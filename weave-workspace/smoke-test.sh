#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
NEXTCLOUD_CONTAINER_NAME="${NEXTCLOUD_CONTAINER_NAME:-weave-nextcloud}"

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
    --cacert "${TF_VAR_caddy_tls_ca_file}" \
    --resolve "${host_port}:127.0.0.1" \
    "$url"
}

curl_form() {
  local url="$1"
  shift
  local host_port

  host_port="$(host_port_from_url "${url}")"
  curl --silent --show-error --fail \
    --cacert "${TF_VAR_caddy_tls_ca_file}" \
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
    --cacert "${TF_VAR_caddy_tls_ca_file}" \
    --resolve "${host_port}:127.0.0.1" \
    -H "Authorization: Bearer ${token}" \
    "$url"
}

curl_status() {
  local url="$1"
  local host_port

  host_port="$(host_port_from_url "${url}")"
  curl --silent --show-error \
    --cacert "${TF_VAR_caddy_tls_ca_file}" \
    --resolve "${host_port}:127.0.0.1" \
    -o /dev/null \
    -w '%{http_code}' \
    "$url"
}

assert_json() {
  local json="$1"
  local jq_filter="$2"
  local description="$3"

  jq -e "${jq_filter}" >/dev/null <<<"${json}" || fail "Smoke check failed: ${description}"
}

require_command curl
require_command docker
require_command jq
load_bootstrap_env

: "${TF_VAR_caddy_tls_ca_file:?Expected TF_VAR_caddy_tls_ca_file in env or bootstrap env}"
: "${WEAVE_BASE_URL:?Expected WEAVE_BASE_URL in env or bootstrap env}"
: "${WEAVE_OIDC_ISSUER_URL:?Expected WEAVE_OIDC_ISSUER_URL in env or bootstrap env}"
: "${WEAVE_OIDC_CLIENT_ID:?Expected WEAVE_OIDC_CLIENT_ID in env or bootstrap env}"
: "${WEAVE_TEST_USERNAME:?Expected WEAVE_TEST_USERNAME in env or bootstrap env}"
: "${WEAVE_TEST_PASSWORD:?Expected WEAVE_TEST_PASSWORD in env or bootstrap env}"

log "Checking Keycloak issuer discovery..."
issuer_config="$(curl_json "${WEAVE_OIDC_ISSUER_URL}/.well-known/openid-configuration")"
assert_json "${issuer_config}" ".issuer == \"${WEAVE_OIDC_ISSUER_URL}\"" "Keycloak issuer should match the public contract"
assert_json "${issuer_config}" '.jwks_uri | startswith("http")' "Keycloak discovery should expose a JWKS URI"

token_endpoint="$(jq -r '.token_endpoint' <<<"${issuer_config}")"

log "Checking public backend health..."
backend_health="$(curl_json "${WEAVE_BASE_URL}/actuator/health")"
assert_json "${backend_health}" '.status == "UP"' "Backend health should report UP"

log "Minting a real app token through Keycloak..."
token_response="$(curl_form "${token_endpoint}" \
  --data-urlencode grant_type=password \
  --data-urlencode client_id="${WEAVE_OIDC_CLIENT_ID}" \
  --data-urlencode username="${WEAVE_TEST_USERNAME}" \
  --data-urlencode password="${WEAVE_TEST_PASSWORD}" \
  --data-urlencode scope='openid profile email weave:workspace')"
access_token="$(jq -r '.access_token' <<<"${token_response}")"
[[ -n "${access_token}" && "${access_token}" != "null" ]] || fail "Smoke check failed: Keycloak did not return an access token"

log "Checking authenticated backend contract..."
profile_response="$(curl_auth_json "${access_token}" "${WEAVE_BASE_URL}/api/v1/me")"
assert_json "${profile_response}" ".email == \"${WEAVE_TEST_USERNAME}\"" "Backend should accept a valid app token"
assert_json "${profile_response}" ".audience | index(\"${WEAVE_OIDC_CLIENT_ID}\") != null" "Token audience should include the app client"

capabilities_response="$(curl_auth_json "${access_token}" "${WEAVE_BASE_URL}/api/v1/workspace/capabilities")"
assert_json "${capabilities_response}" '.files.enabled == true and .chat.enabled == true' "Release capabilities should stay enabled"

log "Checking Nextcloud OIDC bootstrap..."
nextcloud_status="$(curl_json "$(public_url "${TF_VAR_nextcloud_subdomain:-nextcloud}")/status.php")"
assert_json "${nextcloud_status}" '.installed == true' "Nextcloud should be installed"
nextcloud_providers="$(docker exec --user www-data "${NEXTCLOUD_CONTAINER_NAME}" php occ user_oidc:providers)"
assert_json "${nextcloud_providers}" ".identifier == \"keycloak\"" "Nextcloud should expose the Keycloak provider"
assert_json "${nextcloud_providers}" ".clientId == \"nextcloud\"" "Nextcloud provider client ID should stay aligned"
assert_json "${nextcloud_providers}" ".discoveryEndpoint == \"${WEAVE_OIDC_ISSUER_URL}/.well-known/openid-configuration\"" "Nextcloud should point at the public Keycloak discovery URL"
assert_json "${nextcloud_providers}" '.settings.groupProvisioning == true' "Nextcloud group provisioning should remain enabled"

log "Checking Matrix auth routing and MAS wiring..."
matrix_base_url="$(public_url "${TF_VAR_matrix_subdomain:-matrix}")"
matrix_login="$(curl_json "${matrix_base_url}/_matrix/client/v3/login")"
assert_json "${matrix_login}" '.flows | any(.type == "m.login.sso")' "Matrix login should advertise SSO"
assert_json "${matrix_login}" '.flows | any(."org.matrix.msc3824.delegated_oidc_compatibility" == true)' "Matrix login should stay wired through MAS delegated OIDC"
mas_discovery="$(curl_json "${matrix_base_url}/.well-known/openid-configuration")"
assert_json "${mas_discovery}" ".issuer == \"${matrix_base_url}/\"" "MAS issuer should match the public matrix URL"
assert_json "${mas_discovery}" ".authorization_endpoint | contains(\"/authorize\")" "MAS discovery should expose an authorization endpoint"
authorize_status="$(curl_status "${matrix_base_url}/authorize")"
[[ "${authorize_status}" == "400" ]] || fail "Smoke check failed: MAS authorize endpoint should be reachable and reject incomplete requests with 400"

log "Smoke checks passed."
