#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${ROOT_DIR}/01-infrastructure"
BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
DEFAULT_CADDY_TLS_CA_FILE="${ROOT_DIR}/01-infrastructure/.generated/caddy/certs/weave-local-ca.pem"
NEXTCLOUD_CONTAINER_NAME="${NEXTCLOUD_CONTAINER_NAME:-weave-nextcloud}"
CADDY_TLS_CA_FILE=""

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

normalize_repo_local_cert_path_var() {
  local name="$1"
  local value="${!name:-}"
  local repo_generated_suffix="/weave-workspace/01-infrastructure/.generated/caddy/certs/"

  if [[ -z "${value}" || "${value}" != *"${repo_generated_suffix}"* ]]; then
    return
  fi

  export "${name}=${INFRA_DIR}/.generated/caddy/certs/$(basename -- "${value}")"
}

normalize_repo_local_paths() {
  normalize_repo_local_cert_path_var TF_VAR_caddy_tls_cert_file
  normalize_repo_local_cert_path_var TF_VAR_caddy_tls_key_file
  normalize_repo_local_cert_path_var TF_VAR_caddy_tls_ca_file
}

load_bootstrap_env() {
  if [[ -f "${BOOTSTRAP_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${BOOTSTRAP_ENV_FILE}"
    normalize_repo_local_paths
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
    "${TF_VAR_tenant_domain:?Expected TF_VAR_tenant_domain in env or bootstrap env}" \
    "$(public_port_suffix)"
}

product_public_url() {
  printf '%s://%s%s' \
    "${TF_VAR_public_scheme:-https}" \
    "${TF_VAR_tenant_domain:?Expected TF_VAR_tenant_domain in env or bootstrap env}" \
    "$(public_port_suffix)"
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

curl_json() {
  local url="$1"
  local host_port

  host_port="$(host_port_from_url "${url}")"
  curl --silent --show-error --fail \
    --cacert "${CADDY_TLS_CA_FILE}" \
    --resolve "${host_port}:127.0.0.1" \
    "$url"
}

curl_form() {
  local url="$1"
  shift
  local host_port

  host_port="$(host_port_from_url "${url}")"
  curl --silent --show-error --fail \
    --cacert "${CADDY_TLS_CA_FILE}" \
    --resolve "${host_port}:127.0.0.1" \
    -H 'content-type: application/x-www-form-urlencoded' \
    "$url" "$@"
}

curl_auth_json() {
  local token="$1"
  local url="$2"
  local host_port

  host_port="$(host_port_from_url "${url}")"
  curl --silent --show-error --fail \
    --cacert "${CADDY_TLS_CA_FILE}" \
    --resolve "${host_port}:127.0.0.1" \
    -H "Authorization: Bearer ${token}" \
    "$url"
}

curl_auth_status_to_file() {
  local token="$1"
  local url="$2"
  local output_file="$3"
  local host_port

  host_port="$(host_port_from_url "${url}")"
  curl --silent --show-error \
    --cacert "${CADDY_TLS_CA_FILE}" \
    --resolve "${host_port}:127.0.0.1" \
    -H "Authorization: Bearer ${token}" \
    -o "${output_file}" \
    -w '%{http_code}' \
    "$url"
}

curl_status() {
  local url="$1"
  local host_port

  host_port="$(host_port_from_url "${url}")"
  curl --silent --show-error \
    --cacert "${CADDY_TLS_CA_FILE}" \
    --resolve "${host_port}:127.0.0.1" \
    -o /dev/null \
    -w '%{http_code}' \
    "$url"
}

curl_location() {
  local url="$1"
  local host_port

  host_port="$(host_port_from_url "${url}")"
  curl --silent --show-error \
    --cacert "${CADDY_TLS_CA_FILE}" \
    --resolve "${host_port}:127.0.0.1" \
    -o /dev/null \
    -D - \
    "$url" | grep -im1 '^location:' | cut -d' ' -f2- | tr -d '\r'
}

assert_json() {
  local json="$1"
  local jq_filter="$2"
  local description="$3"

  jq -e "${jq_filter}" >/dev/null <<<"${json}" || fail "Smoke check failed: ${description}"
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
  [[ -n "${value}" ]] || fail "Smoke check failed: weave-backend is missing required ${name} Nextcloud facade configuration"
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
  [[ "${actor_model}" == "backend-service-account" ]] || fail "Smoke check failed: unsupported files actor model ${actor_model}"

  actor_username="$(container_env_value weave-backend WEAVE_NEXTCLOUD_FILES_ACTOR_USERNAME)"
  caldav_username="$(container_env_value weave-backend WEAVE_CALDAV_BACKEND_USERNAME)"
  [[ "${actor_username}" == "${caldav_username}" ]] || fail "Smoke check failed: files and calendar adapters should use the same backend-owned Nextcloud actor username"

  webdav_root="$(container_env_value weave-backend WEAVE_NEXTCLOUD_FILES_WEBDAV_ROOT_PATH)"
  [[ "${webdav_root}" == "/remote.php/dav/files" ]] || fail "Smoke check failed: unexpected files WebDAV root path ${webdav_root}"

  backend_nextcloud_base_url="$(container_env_value weave-backend WEAVE_NEXTCLOUD_BASE_URL)"
  caldav_base_url="$(container_env_value weave-backend WEAVE_CALDAV_BASE_URL)"
  [[ "${caldav_base_url}" == "${backend_nextcloud_base_url}" ]] || fail "Smoke check failed: CalDAV base URL should match the backend Nextcloud adapter base URL"

  caldav_template="$(container_env_value weave-backend WEAVE_CALDAV_CALENDAR_PATH_TEMPLATE)"
  [[ "${caldav_template}" == *"{user}"* ]] || fail "Smoke check failed: CalDAV calendar path template must contain {user}"

  caldav_auth_mode="$(container_env_value weave-backend WEAVE_CALDAV_AUTH_MODE)"
  [[ "${caldav_auth_mode}" == "BASIC" || "${caldav_auth_mode}" == "BEARER" ]] || fail "Smoke check failed: unsupported CalDAV auth mode ${caldav_auth_mode}"

  docker exec --user www-data "${NEXTCLOUD_CONTAINER_NAME}" php occ user:info "${actor_username}" >/dev/null 2>&1 || \
    fail "Smoke check failed: Nextcloud backend actor user is not provisioned"

  if [[ -f "${ROOT_DIR}/.generated/app-config.env" ]]; then
    ! grep -Eq 'WEAVE_NEXTCLOUD_FILES_ACTOR_TOKEN|WEAVE_CALDAV_BACKEND_TOKEN|TF_VAR_nextcloud_backend_actor_token' "${ROOT_DIR}/.generated/app-config.env" || \
      fail "Smoke check failed: no-secret app config exposes backend Nextcloud actor secrets"
  fi
}

probe_authenticated_facade() {
  local name="$1"
  local token="$2"
  local url="$3"
  local body_file
  local status

  body_file="$(mktemp)"
  status="$(curl_auth_status_to_file "${token}" "${url}" "${body_file}" || true)"
  if grep -q 'nextcloud-adapter-not-configured' "${body_file}"; then
    rm -f -- "${body_file}"
    fail "Smoke check failed: ${name} facade reports missing backend-owned Nextcloud actor configuration"
  fi
  rm -f -- "${body_file}"

  if [[ "${status}" == 2* ]]; then
    log "${name} facade answered HTTP ${status}."
  else
    log "${name} facade probe answered HTTP ${status}; actor config is present, but full downstream user/calendar readiness is not gated here."
  fi
}

require_command curl
require_command docker
require_command jq
load_bootstrap_env

CADDY_TLS_CA_FILE="${TF_VAR_caddy_tls_ca_file:-${DEFAULT_CADDY_TLS_CA_FILE}}"
[[ -f "${CADDY_TLS_CA_FILE}" ]] || fail "Expected a trusted Caddy TLS CA file at ${CADDY_TLS_CA_FILE}. Set TF_VAR_caddy_tls_ca_file explicitly or run install.sh first."

WEAVE_API_BASE_URL="${WEAVE_API_BASE_URL:-${WEAVE_BASE_URL:-$(public_url "${TF_VAR_api_subdomain:-api}")/api}}"
WEAVE_BASE_URL="${WEAVE_API_BASE_URL%/}"
WEAVE_OIDC_ISSUER_URL="${WEAVE_OIDC_ISSUER_URL:-$(public_url "${TF_VAR_auth_subdomain:-auth}")/realms/${TF_VAR_tenant_slug:-weave}}"
WEAVE_NEXTCLOUD_BASE_URL="${WEAVE_NEXTCLOUD_BASE_URL:-$(public_url "${TF_VAR_nextcloud_subdomain:-files}")}"
WEAVE_MATRIX_HOMESERVER_URL="${WEAVE_MATRIX_HOMESERVER_URL:-$(public_url "${TF_VAR_matrix_subdomain:-matrix}")}"
: "${WEAVE_OIDC_CLIENT_ID:?Expected WEAVE_OIDC_CLIENT_ID in env or bootstrap env}"
: "${WEAVE_NEXTCLOUD_BASE_URL:?Expected WEAVE_NEXTCLOUD_BASE_URL in env or bootstrap env}"
: "${WEAVE_MATRIX_HOMESERVER_URL:?Expected WEAVE_MATRIX_HOMESERVER_URL in env or bootstrap env}"
: "${WEAVE_TEST_USERNAME:?Expected WEAVE_TEST_USERNAME in env or bootstrap env}"
: "${WEAVE_TEST_PASSWORD:?Expected WEAVE_TEST_PASSWORD in env or bootstrap env}"

log "Checking Keycloak issuer discovery..."
issuer_config="$(curl_json "${WEAVE_OIDC_ISSUER_URL}/.well-known/openid-configuration")"
assert_json "${issuer_config}" ".issuer == \"${WEAVE_OIDC_ISSUER_URL}\"" "Keycloak issuer should match the public contract"
assert_json "${issuer_config}" '.jwks_uri | startswith("http")' "Keycloak discovery should expose a JWKS URI"

token_endpoint="$(jq -r '.token_endpoint' <<<"${issuer_config}")"

log "Checking public backend health..."
backend_health="$(curl_json "${WEAVE_BASE_URL}/health/ready")"
assert_json "${backend_health}" '.status == "up"' "Backend readiness should report up"

log "Checking product shell routes..."
product_status="$(curl_status "$(product_public_url)/")"
[[ "${product_status}" == "200" ]] || fail "Smoke check failed: Weave product gateway should return 200, got ${product_status}"
files_product_status="$(curl_status "$(product_public_url)/files")"
[[ "${files_product_status}" == "200" ]] || fail "Smoke check failed: Weave files product route should return 200, got ${files_product_status}"
calendar_product_status="$(curl_status "$(product_public_url)/calendar")"
[[ "${calendar_product_status}" == "200" ]] || fail "Smoke check failed: Weave calendar product route should return 200, got ${calendar_product_status}"

log "Checking public platform config..."
platform_config="$(curl_json "${WEAVE_BASE_URL}/platform/config")"
assert_json "${platform_config}" ".apiBaseUrl == \"${WEAVE_BASE_URL}\"" "Platform config should expose the canonical public API route"
assert_json "${platform_config}" '.authBaseUrl | contains("auth.")' "Platform config should expose the public auth host"
assert_json "${platform_config}" '.features.chatE2ee == false and .features.matrixFederation == false' "MVP chat security flags should be honest"

platform_status="$(curl_json "${WEAVE_BASE_URL}/platform/status")"
assert_json "${platform_status}" '.backend.status == "up"' "Platform status should report backend up"

log "Minting a real app token through Keycloak..."
token_response="$(curl_form "${token_endpoint}" \
  --data-urlencode grant_type=password \
  --data-urlencode client_id="${WEAVE_OIDC_CLIENT_ID}" \
  --data-urlencode username="${WEAVE_TEST_USERNAME}" \
  --data-urlencode password="${WEAVE_TEST_PASSWORD}" \
  --data-urlencode scope='openid profile email')"
access_token="$(jq -r '.access_token' <<<"${token_response}")"
[[ -n "${access_token}" && "${access_token}" != "null" ]] || fail "Smoke check failed: Keycloak did not return an access token"

log "Checking authenticated backend contract..."
profile_response="$(curl_auth_json "${access_token}" "${WEAVE_BASE_URL}/me")"
assert_json "${profile_response}" ".email == \"${WEAVE_TEST_USERNAME}\"" "Backend should accept a valid app token"
assert_json "${profile_response}" ".audience | index(\"${WEAVE_OIDC_CLIENT_ID}\") != null" "Token audience should include the app client"
assert_json "${profile_response}" '.userId != null and .username != null' "Backend should expose canonical identity fields"

log "Checking backend files/calendar facade actor wiring..."
assert_backend_nextcloud_actor_config
probe_authenticated_facade "Files" "${access_token}" "${WEAVE_BASE_URL}/files"
probe_authenticated_facade "Calendar" "${access_token}" "${WEAVE_BASE_URL}/calendar/events"

log "Checking Nextcloud OIDC bootstrap..."
nextcloud_status="$(curl_json "${WEAVE_NEXTCLOUD_BASE_URL}/status.php")"
assert_json "${nextcloud_status}" '.installed == true' "Nextcloud should be installed"
nextcloud_providers="$(docker exec --user www-data "${NEXTCLOUD_CONTAINER_NAME}" php occ user_oidc:providers)"
assert_json "${nextcloud_providers}" ".identifier == \"keycloak\"" "Nextcloud should expose the Keycloak provider"
assert_json "${nextcloud_providers}" ".clientId == \"nextcloud\"" "Nextcloud provider client ID should stay aligned"
assert_json "${nextcloud_providers}" ".discoveryEndpoint == \"${WEAVE_OIDC_ISSUER_URL}/.well-known/openid-configuration\"" "Nextcloud should point at the public Keycloak discovery URL"
assert_json "${nextcloud_providers}" '.settings.groupProvisioning == true' "Nextcloud group provisioning should remain enabled"
nextcloud_oidc_redirect="$(curl_location "${WEAVE_NEXTCLOUD_BASE_URL}/apps/user_oidc/login/1")"
[[ "${nextcloud_oidc_redirect}" == https://auth* ]] || fail "Smoke check failed: Nextcloud OIDC login should redirect to Auth, got '${nextcloud_oidc_redirect}'"

log "Checking Matrix auth routing and MAS wiring..."
matrix_base_url="${WEAVE_MATRIX_HOMESERVER_URL}"
matrix_versions="$(curl_json "${matrix_base_url}/_matrix/client/versions")"
assert_json "${matrix_versions}" '.versions | length > 0' "Matrix client versions should be reachable"
matrix_client_discovery="$(curl_json "${matrix_base_url}/.well-known/matrix/client")"
assert_json "${matrix_client_discovery}" '."m.homeserver".base_url == "'"${matrix_base_url}"'"' "Matrix client discovery should advertise the public homeserver"
matrix_login="$(curl_json "${matrix_base_url}/_matrix/client/v3/login")"
assert_json "${matrix_login}" '.flows | any(.type == "m.login.sso")' "Matrix login should advertise SSO"
assert_json "${matrix_login}" '.flows | any(."org.matrix.msc3824.delegated_oidc_compatibility" == true)' "Matrix login should stay wired through MAS delegated OIDC"
matrix_auth_metadata="$(curl_json "${matrix_base_url}/_matrix/client/v1/auth_metadata")"
assert_json "${matrix_auth_metadata}" ".issuer == \"${matrix_base_url}/\"" "Matrix OAuth metadata should be served by MAS"
assert_json "${matrix_auth_metadata}" '.authorization_endpoint | contains("/authorize")' "Matrix OAuth metadata should expose the MAS authorization endpoint"
mas_discovery="$(curl_json "${matrix_base_url}/.well-known/openid-configuration")"
assert_json "${mas_discovery}" ".issuer == \"${matrix_base_url}/\"" "MAS issuer should match the public matrix URL"
assert_json "${mas_discovery}" ".authorization_endpoint | contains(\"/authorize\")" "MAS discovery should expose an authorization endpoint"
authorize_status="$(curl_status "${matrix_base_url}/authorize")"
[[ "${authorize_status}" == "400" ]] || fail "Smoke check failed: MAS authorize endpoint should be reachable and reject incomplete requests with 400"

log "Smoke checks passed."
