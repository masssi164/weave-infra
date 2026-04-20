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
  local -a args=()

  while IFS= read -r -d '' arg; do
    args+=("${arg}")
  done < <(curl_common_args)

  curl "${args[@]}" -o /dev/null -w '%{http_code}' "$url"
}

assert_json() {
  local json="$1"
  local jq_filter="$2"
  local description="$3"

  jq -e "${jq_filter}" >/dev/null <<<"${json}" || fail "Release verify failed: ${description}"
}

require_command curl
require_command jq

: "${WEAVE_BASE_URL:?Expected WEAVE_BASE_URL in env}"
: "${WEAVE_OIDC_ISSUER_URL:?Expected WEAVE_OIDC_ISSUER_URL in env}"
: "${WEAVE_NEXTCLOUD_URL:?Expected WEAVE_NEXTCLOUD_URL in env}"
: "${WEAVE_MATRIX_URL:?Expected WEAVE_MATRIX_URL in env}"

if [[ -n "${WEAVE_TLS_CA_FILE:-}" ]]; then
  [[ -f "${WEAVE_TLS_CA_FILE}" ]] || fail "WEAVE_TLS_CA_FILE points to a missing file: ${WEAVE_TLS_CA_FILE}"
fi

log "Checking Keycloak discovery..."
issuer_config="$(curl_json "${WEAVE_OIDC_ISSUER_URL}/.well-known/openid-configuration")"
assert_json "${issuer_config}" ".issuer == \"${WEAVE_OIDC_ISSUER_URL}\"" "issuer should match the public OIDC URL"
assert_json "${issuer_config}" '.jwks_uri | startswith("http")' "jwks_uri should be present"

log "Checking backend health through the public API URL..."
backend_health="$(curl_json "${WEAVE_BASE_URL}/actuator/health")"
assert_json "${backend_health}" '.status == "UP"' "backend health should report UP"

log "Checking Nextcloud public status..."
nextcloud_status="$(curl_json "${WEAVE_NEXTCLOUD_URL}/status.php")"
assert_json "${nextcloud_status}" '.installed == true' "Nextcloud should be installed"

log "Checking Matrix delegated auth discovery..."
mas_discovery="$(curl_json "${WEAVE_MATRIX_URL}/.well-known/openid-configuration")"
assert_json "${mas_discovery}" ".issuer == \"${WEAVE_MATRIX_URL}/\"" "MAS issuer should match the public Matrix URL"
assert_json "${mas_discovery}" '.authorization_endpoint | contains("/authorize")' "MAS should expose an authorization endpoint"

authorize_status="$(curl_status "${WEAVE_MATRIX_URL}/authorize")"
[[ "${authorize_status}" == "400" ]] || fail "Release verify failed: Matrix authorize endpoint should answer with 400 for an incomplete request"

log "Release verification checks passed."
