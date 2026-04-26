#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"

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

product_public_url() {
  printf '%s://%s%s' \
    "${TF_VAR_public_scheme:-https}" \
    "${TF_VAR_tenant_domain:?Expected TF_VAR_tenant_domain in env or bootstrap env}" \
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

require_command curl
require_command docker
require_command jq
load_bootstrap_env

: "${WEAVE_BASE_URL:=$(api_public_url)/api}"
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

log "Checking public issuer, API, files, and matrix URLs..."
issuer_config="$(curl_json "${WEAVE_OIDC_ISSUER_URL}/.well-known/openid-configuration")"
assert_json "${issuer_config}" ".issuer == \"${WEAVE_OIDC_ISSUER_URL}\"" "public Keycloak issuer should match the configured release URL"

backend_health="$(curl_json "${WEAVE_BASE_URL}/health/ready")"
assert_json "${backend_health}" '.status == "up"' "public backend readiness should report up"

nextcloud_status="$(curl_json "${WEAVE_NEXTCLOUD_BASE_URL}/status.php")"
assert_json "${nextcloud_status}" '.installed == true' "Nextcloud should be installed"

mas_discovery="$(curl_json "${WEAVE_MATRIX_HOMESERVER_URL}/.well-known/openid-configuration")"
assert_json "${mas_discovery}" ".issuer == \"${WEAVE_MATRIX_HOMESERVER_URL}/\"" "MAS issuer should match the public matrix URL"

matrix_auth_metadata="$(curl_json "${WEAVE_MATRIX_HOMESERVER_URL}/_matrix/client/v1/auth_metadata")"
assert_json "${matrix_auth_metadata}" ".issuer == \"${WEAVE_MATRIX_HOMESERVER_URL}/\"" "Matrix OAuth metadata should be served by MAS"
assert_json "${matrix_auth_metadata}" '.authorization_endpoint | contains("/authorize")' "Matrix OAuth metadata should expose the MAS authorization endpoint"

log "Operator checks passed."
