#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
APP_CONFIG_ENV_FILE="${ROOT_DIR}/.generated/app-config.env"

log() {
  printf '%s\n' "$*"
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

load_bootstrap_env() {
  if [[ -f "${BOOTSTRAP_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${BOOTSTRAP_ENV_FILE}"
  fi
}

public_port_suffix() {
  local scheme="${TF_VAR_public_scheme:-https}"
  local port="${TF_VAR_proxy_host_port:-443}"

  if [[ "${scheme}" == "http" && "${port}" == "80" ]] || [[ "${scheme}" == "https" && "${port}" == "443" ]]; then
    printf ''
    return
  fi

  printf ':%s' "${port}"
}

public_url() {
  local subdomain="$1"
  printf '%s://%s.%s%s' \
    "${TF_VAR_public_scheme:-https}" \
    "${subdomain}" \
    "${TF_VAR_tenant_domain:-weave.local}" \
    "$(public_port_suffix)"
}

product_public_url() {
  printf '%s://%s%s' \
    "${TF_VAR_public_scheme:-https}" \
    "${TF_VAR_tenant_domain:-weave.local}" \
    "$(public_port_suffix)"
}

api_public_url() {
  public_url "${TF_VAR_api_subdomain:-api}"
}

curl_common_args() {
  local -a args=(--silent --show-error --fail)

  if [[ -n "${WEAVE_TLS_CA_FILE:-}" ]]; then
    args+=(--cacert "${WEAVE_TLS_CA_FILE}")
  elif [[ -n "${TF_VAR_caddy_tls_ca_file:-}" && -f "${TF_VAR_caddy_tls_ca_file}" ]]; then
    args+=(--cacert "${TF_VAR_caddy_tls_ca_file}")
  fi

  printf '%s\0' "${args[@]}"
}

curl_json() {
  local url="$1"
  local -a args=()

  while IFS= read -r -d '' arg; do
    args+=("${arg}")
  done < <(curl_common_args)

  curl "${args[@]}" "$url"
}

curl_status() {
  local url="$1"
  local -a args=(--silent --show-error)

  if [[ -n "${WEAVE_TLS_CA_FILE:-}" ]]; then
    args+=(--cacert "${WEAVE_TLS_CA_FILE}")
  elif [[ -n "${TF_VAR_caddy_tls_ca_file:-}" && -f "${TF_VAR_caddy_tls_ca_file}" ]]; then
    args+=(--cacert "${TF_VAR_caddy_tls_ca_file}")
  fi

  curl "${args[@]}" -o /dev/null -w '%{http_code}' "$url"
}

assert_container_running() {
  local name="$1"
  local state

  state="$(docker inspect --format '{{.State.Status}}' "${name}" 2>/dev/null || true)"
  [[ "${state}" == "running" ]] || fail "Operator check failed: container ${name} is not running"
}

assert_http_200() {
  local name="$1"
  local url="$2"
  local status

  status="$(curl --silent --show-error -o /dev/null -w '%{http_code}' "$url" || true)"
  [[ "${status}" == "200" ]] || fail "Operator check failed: ${name} returned HTTP ${status} at ${url}"
}

assert_json() {
  local json="$1"
  local jq_filter="$2"
  local description="$3"

  jq -e "${jq_filter}" >/dev/null <<<"${json}" || fail "Operator check failed: ${description}"
}

container_env_value() {
  local container="$1"
  local name="$2"

  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${container}" 2>/dev/null |
    awk -v name="${name}" 'index($0, name "=") == 1 { print substr($0, length(name) + 2); found = 1 } END { if (!found) exit 1 }'
}

assert_backend_env_present() {
  local name="$1"
  local value

  value="$(container_env_value weave-backend "${name}" || true)"
  [[ -n "${value}" ]] || fail "Operator check failed: weave-backend is missing required ${name} Nextcloud facade configuration"
}

assert_backend_nextcloud_actor_config() {
  local actor_username
  local actor_model
  local webdav_root
  local backend_nextcloud_base_url
  local caldav_base_url
  local caldav_template
  local caldav_auth_mode
  local caldav_username
  local name

  log "Checking backend-owned Nextcloud actor configuration..."
  for name in \
    WEAVE_NEXTCLOUD_BASE_URL \
    WEAVE_NEXTCLOUD_FILES_ACTOR_MODEL \
    WEAVE_NEXTCLOUD_FILES_ACTOR_USERNAME \
    WEAVE_NEXTCLOUD_FILES_ACTOR_TOKEN \
    WEAVE_NEXTCLOUD_FILES_WEBDAV_ROOT_PATH \
    WEAVE_CALDAV_BASE_URL \
    WEAVE_CALDAV_CALENDAR_PATH_TEMPLATE \
    WEAVE_CALDAV_AUTH_MODE \
    WEAVE_CALDAV_BACKEND_USERNAME \
    WEAVE_CALDAV_BACKEND_TOKEN \
    WEAVE_CALDAV_REQUEST_TIMEOUT_SECONDS; do
    assert_backend_env_present "${name}"
  done

  actor_model="$(container_env_value weave-backend WEAVE_NEXTCLOUD_FILES_ACTOR_MODEL)"
  [[ "${actor_model}" == "backend-service-account" ]] || fail "Operator check failed: unsupported files actor model ${actor_model}"

  actor_username="$(container_env_value weave-backend WEAVE_NEXTCLOUD_FILES_ACTOR_USERNAME)"
  caldav_username="$(container_env_value weave-backend WEAVE_CALDAV_BACKEND_USERNAME)"
  [[ "${actor_username}" == "${caldav_username}" ]] || fail "Operator check failed: files and calendar adapters should use the same backend-owned Nextcloud actor username"

  webdav_root="$(container_env_value weave-backend WEAVE_NEXTCLOUD_FILES_WEBDAV_ROOT_PATH)"
  [[ "${webdav_root}" == "/remote.php/dav/files" ]] || fail "Operator check failed: unexpected files WebDAV root path ${webdav_root}"

  backend_nextcloud_base_url="$(container_env_value weave-backend WEAVE_NEXTCLOUD_BASE_URL)"
  caldav_base_url="$(container_env_value weave-backend WEAVE_CALDAV_BASE_URL)"
  [[ "${caldav_base_url}" == "${backend_nextcloud_base_url}" ]] || fail "Operator check failed: CalDAV base URL should match the backend Nextcloud adapter base URL"

  caldav_template="$(container_env_value weave-backend WEAVE_CALDAV_CALENDAR_PATH_TEMPLATE)"
  [[ "${caldav_template}" == *"{user}"* ]] || fail "Operator check failed: CalDAV calendar path template must contain {user}"

  caldav_auth_mode="$(container_env_value weave-backend WEAVE_CALDAV_AUTH_MODE)"
  [[ "${caldav_auth_mode}" == "BASIC" || "${caldav_auth_mode}" == "BEARER" ]] || fail "Operator check failed: unsupported CalDAV auth mode ${caldav_auth_mode}"

  docker exec --user www-data weave-nextcloud php occ user:info "${actor_username}" >/dev/null 2>&1 || \
    fail "Operator check failed: Nextcloud backend actor user is not provisioned"

  if [[ -f "${APP_CONFIG_ENV_FILE}" ]]; then
    ! grep -Eq 'WEAVE_NEXTCLOUD_FILES_ACTOR_TOKEN|WEAVE_CALDAV_BACKEND_TOKEN|TF_VAR_nextcloud_backend_actor_token' "${APP_CONFIG_ENV_FILE}" || \
      fail "Operator check failed: no-secret app config exposes backend Nextcloud actor secrets"
  fi
}

require_command curl
require_command docker
require_command jq
load_bootstrap_env

: "${WEAVE_BASE_URL:=$(api_public_url)/api}"
: "${WEAVE_PUBLIC_BASE_URL:=$(product_public_url)}"
: "${WEAVE_OIDC_ISSUER_URL:=$(public_url "${TF_VAR_auth_subdomain:-auth}")/realms/${TF_VAR_tenant_slug:-weave}}"
: "${WEAVE_NEXTCLOUD_BASE_URL:=$(public_url "${TF_VAR_nextcloud_subdomain:-files}")}"
: "${WEAVE_MATRIX_HOMESERVER_URL:=$(public_url "${TF_VAR_matrix_subdomain:-matrix}")}"

log "Checking core containers..."
for container in weave-proxy weave-keycloak weave-backend weave-mas weave-synapse weave-nextcloud weave-db; do
  assert_container_running "${container}"
done

log "Checking loopback health endpoints..."
assert_http_200 "Keycloak management" "http://127.0.0.1:${TF_VAR_keycloak_management_host_port:-49000}/health/ready"
assert_http_200 "Weave backend" "http://127.0.0.1:${TF_VAR_backend_host_port:-48084}/actuator/health"
assert_http_200 "MAS" "http://127.0.0.1:${TF_VAR_mas_host_port:-48082}/health"
assert_http_200 "Synapse" "http://127.0.0.1:${TF_VAR_synapse_host_port:-48008}/_matrix/client/versions"

log "Checking public product, issuer, API, files, and matrix routes..."
product_status="$(curl_status "${WEAVE_PUBLIC_BASE_URL}/")"
[[ "${product_status}" == "200" ]] || fail "Operator check failed: Weave product gateway returned HTTP ${product_status} at ${WEAVE_PUBLIC_BASE_URL}/"

files_product_status="$(curl_status "${WEAVE_PUBLIC_BASE_URL}/files")"
[[ "${files_product_status}" == "200" ]] || fail "Operator check failed: Weave product files route returned HTTP ${files_product_status} at ${WEAVE_PUBLIC_BASE_URL}/files"

calendar_product_status="$(curl_status "${WEAVE_PUBLIC_BASE_URL}/calendar")"
[[ "${calendar_product_status}" == "200" ]] || fail "Operator check failed: Weave product calendar route returned HTTP ${calendar_product_status} at ${WEAVE_PUBLIC_BASE_URL}/calendar"

issuer_config="$(curl_json "${WEAVE_OIDC_ISSUER_URL}/.well-known/openid-configuration")"
assert_json "${issuer_config}" ".issuer == \"${WEAVE_OIDC_ISSUER_URL}\"" "public Keycloak issuer should match the configured release URL"

backend_health="$(curl_json "${WEAVE_BASE_URL}/health/ready")"
assert_json "${backend_health}" '.status == "up"' "public backend readiness should report up"

nextcloud_status="$(curl_json "${WEAVE_NEXTCLOUD_BASE_URL}/status.php")"
assert_json "${nextcloud_status}" '.installed == true' "Nextcloud should be installed"

assert_backend_nextcloud_actor_config

nextcloud_bearer_validation="$(docker exec --user www-data weave-nextcloud php occ config:system:get user_oidc oidc_provider_bearer_validation 2>/dev/null || true)"
[[ "${nextcloud_bearer_validation}" == "true" ]] || fail "Operator check failed: Nextcloud user_oidc bearer validation is not enabled"

nextcloud_oidc_provider="$(docker exec --user www-data weave-nextcloud php occ user_oidc:provider --output=json keycloak)"
assert_json "${nextcloud_oidc_provider}" '.settings.checkBearer == true or .settings.checkBearer == "1" or .settings.checkBearer == 1' "Nextcloud OIDC provider should validate Bearer tokens"
assert_json "${nextcloud_oidc_provider}" '.settings.bearerProvisioning == true or .settings.bearerProvisioning == "1" or .settings.bearerProvisioning == 1' "Nextcloud OIDC provider should provision Bearer-token users"

mas_discovery="$(curl_json "${WEAVE_MATRIX_HOMESERVER_URL}/.well-known/openid-configuration")"
assert_json "${mas_discovery}" ".issuer == \"${WEAVE_MATRIX_HOMESERVER_URL}/\"" "MAS issuer should match the public matrix URL"

matrix_versions="$(curl_json "${WEAVE_MATRIX_HOMESERVER_URL}/_matrix/client/versions")"
assert_json "${matrix_versions}" '.versions | type == "array"' "public Matrix client versions route should be served by Synapse"

matrix_auth_metadata="$(curl_json "${WEAVE_MATRIX_HOMESERVER_URL}/_matrix/client/v1/auth_metadata")"
assert_json "${matrix_auth_metadata}" ".issuer == \"${WEAVE_MATRIX_HOMESERVER_URL}/\"" "Matrix OAuth metadata should be served by MAS"
assert_json "${matrix_auth_metadata}" '.authorization_endpoint | contains("/authorize")' "Matrix OAuth metadata should expose the MAS authorization endpoint"

log "Operator checks passed."
