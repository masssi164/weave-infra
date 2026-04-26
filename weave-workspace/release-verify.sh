#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

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

host_port_from_url() {
  local url="$1"
  local host_port

  host_port="${url#*://}"
  host_port="${host_port%%/*}"
  if [[ "${host_port}" != *:* ]]; then
    case "${url%%://*}" in
      https) host_port="${host_port}:443" ;;
      http) host_port="${host_port}:80" ;;
    esac
  fi

  printf '%s\n' "${host_port}"
}

curl_common_args() {
  local -a args=(--silent --show-error --fail)

  if [[ -n "${WEAVE_TLS_CA_FILE:-}" ]]; then
    args+=(--cacert "${WEAVE_TLS_CA_FILE}")
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
  fi

  curl "${args[@]}" -o /dev/null -w '%{http_code}' "$url"
}

assert_json() {
  local json="$1"
  local jq_filter="$2"
  local description="$3"

  jq -e "${jq_filter}" >/dev/null <<<"${json}" || fail "Release verify failed: ${description}"
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
  [[ -n "${value}" ]] || fail "Release verify failed: weave-backend is missing required ${name} Nextcloud facade configuration"
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
  [[ "${actor_model}" == "backend-service-account" ]] || fail "Release verify failed: unsupported files actor model ${actor_model}"

  actor_username="$(container_env_value weave-backend WEAVE_NEXTCLOUD_FILES_ACTOR_USERNAME)"
  caldav_username="$(container_env_value weave-backend WEAVE_CALDAV_BACKEND_USERNAME)"
  [[ "${actor_username}" == "${caldav_username}" ]] || fail "Release verify failed: files and calendar adapters should use the same backend-owned Nextcloud actor username"

  webdav_root="$(container_env_value weave-backend WEAVE_NEXTCLOUD_FILES_WEBDAV_ROOT_PATH)"
  [[ "${webdav_root}" == "/remote.php/dav/files" ]] || fail "Release verify failed: unexpected files WebDAV root path ${webdav_root}"

  backend_nextcloud_base_url="$(container_env_value weave-backend WEAVE_NEXTCLOUD_BASE_URL)"
  caldav_base_url="$(container_env_value weave-backend WEAVE_CALDAV_BASE_URL)"
  [[ "${caldav_base_url}" == "${backend_nextcloud_base_url}" ]] || fail "Release verify failed: CalDAV base URL should match the backend Nextcloud adapter base URL"

  caldav_template="$(container_env_value weave-backend WEAVE_CALDAV_CALENDAR_PATH_TEMPLATE)"
  [[ "${caldav_template}" == *"{user}"* ]] || fail "Release verify failed: CalDAV calendar path template must contain {user}"

  caldav_auth_mode="$(container_env_value weave-backend WEAVE_CALDAV_AUTH_MODE)"
  [[ "${caldav_auth_mode}" == "BASIC" || "${caldav_auth_mode}" == "BEARER" ]] || fail "Release verify failed: unsupported CalDAV auth mode ${caldav_auth_mode}"

  docker exec --user www-data weave-nextcloud php occ user:info "${actor_username}" >/dev/null 2>&1 || \
    fail "Release verify failed: Nextcloud backend actor user is not provisioned"
}

require_command curl
require_command docker
require_command jq

if [[ -z "${WEAVE_API_BASE_URL:-}" ]]; then
  : "${WEAVE_BASE_URL:?Expected WEAVE_API_BASE_URL or WEAVE_BASE_URL in env}"
  WEAVE_API_BASE_URL="${WEAVE_BASE_URL%/}"
fi
WEAVE_BASE_URL="${WEAVE_API_BASE_URL%/}"
: "${WEAVE_PUBLIC_BASE_URL:=}"
: "${WEAVE_AUTH_BASE_URL:=}"
: "${WEAVE_OIDC_ISSUER_URL:?Expected WEAVE_OIDC_ISSUER_URL in env}"
: "${WEAVE_NEXTCLOUD_BASE_URL:?Expected WEAVE_NEXTCLOUD_BASE_URL in env}"
: "${WEAVE_MATRIX_HOMESERVER_URL:?Expected WEAVE_MATRIX_HOMESERVER_URL in env}"

if [[ -n "${WEAVE_TLS_CA_FILE:-}" ]]; then
  [[ -f "${WEAVE_TLS_CA_FILE}" ]] || fail "WEAVE_TLS_CA_FILE points to a missing file: ${WEAVE_TLS_CA_FILE}"
fi

if [[ -n "${WEAVE_PUBLIC_BASE_URL}" ]]; then
  log "Checking Weave product gateway routes..."
  product_status="$(curl_status "${WEAVE_PUBLIC_BASE_URL}/")"
  [[ "${product_status}" == "200" ]] || fail "Release verify failed: product gateway returned HTTP ${product_status}"

  files_product_status="$(curl_status "${WEAVE_PUBLIC_BASE_URL}/files")"
  [[ "${files_product_status}" == "200" ]] || fail "Release verify failed: product files route returned HTTP ${files_product_status}"

  calendar_product_status="$(curl_status "${WEAVE_PUBLIC_BASE_URL}/calendar")"
  [[ "${calendar_product_status}" == "200" ]] || fail "Release verify failed: product calendar route returned HTTP ${calendar_product_status}"
fi

log "Checking Keycloak discovery..."
issuer_config="$(curl_json "${WEAVE_OIDC_ISSUER_URL}/.well-known/openid-configuration")"
assert_json "${issuer_config}" ".issuer == \"${WEAVE_OIDC_ISSUER_URL}\"" "issuer should match the public OIDC URL"
assert_json "${issuer_config}" '.jwks_uri | startswith("http")' "jwks_uri should be present"

log "Checking backend health through the public API URL..."
backend_health="$(curl_json "${WEAVE_BASE_URL}/health/ready")"
assert_json "${backend_health}" '.status == "up"' "backend readiness should report up"

log "Checking Nextcloud public status..."
nextcloud_status="$(curl_json "${WEAVE_NEXTCLOUD_BASE_URL}/status.php")"
assert_json "${nextcloud_status}" '.installed == true' "Nextcloud should be installed"

assert_backend_nextcloud_actor_config

nextcloud_bearer_validation="$(docker exec --user www-data weave-nextcloud php occ config:system:get user_oidc oidc_provider_bearer_validation 2>/dev/null || true)"
[[ "${nextcloud_bearer_validation}" == "true" ]] || fail "Release verification failed: Nextcloud user_oidc bearer validation is not enabled"

nextcloud_oidc_provider="$(docker exec --user www-data weave-nextcloud php occ user_oidc:provider --output=json keycloak)"
assert_json "${nextcloud_oidc_provider}" '.settings.checkBearer == true or .settings.checkBearer == "1" or .settings.checkBearer == 1' "Nextcloud OIDC provider should validate Bearer tokens"
assert_json "${nextcloud_oidc_provider}" '.settings.bearerProvisioning == true or .settings.bearerProvisioning == "1" or .settings.bearerProvisioning == 1' "Nextcloud OIDC provider should provision Bearer-token users"

log "Checking Matrix delegated auth discovery..."
mas_discovery="$(curl_json "${WEAVE_MATRIX_HOMESERVER_URL}/.well-known/openid-configuration")"
assert_json "${mas_discovery}" ".issuer == \"${WEAVE_MATRIX_HOMESERVER_URL}/\"" "MAS issuer should match the public Matrix URL"
assert_json "${mas_discovery}" '.authorization_endpoint | contains("/authorize")' "MAS should expose an authorization endpoint"

matrix_versions="$(curl_json "${WEAVE_MATRIX_HOMESERVER_URL}/_matrix/client/versions")"
assert_json "${matrix_versions}" '.versions | type == "array"' "Matrix client versions should be served by the public Matrix route"

authorize_status="$(curl_status "${WEAVE_MATRIX_HOMESERVER_URL}/authorize")"
[[ "${authorize_status}" == "400" ]] || fail "Release verify failed: Matrix authorize endpoint should answer with 400 for an incomplete request"

log "Release verification checks passed."
