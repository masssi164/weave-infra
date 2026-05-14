#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"

TENANT_REALM="${TF_VAR_tenant_slug:-weave}"
USERNAME=""
EMAIL=""
DISPLAY_NAME=""
ROLE="member"
WORKSPACE_GROUP="workspace-default"
INITIAL_PASSWORD=""
TEMPORARY_PASSWORD="true"
DRY_RUN="false"

log() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./activate-user.sh --username USERNAME --email EMAIL --display-name NAME --role owner|admin|member|guest [options]

Local/dev owner/admin helper for activating a Weave user in Keycloak.

Required:
  --username VALUE        Keycloak username / preferred username.
  --email VALUE           User email address.
  --display-name VALUE    Display name shown in Weave profile/onboarding.
  --role VALUE            MVP product role: owner, admin, member, or guest.

Options:
  --workspace-group VALUE Group claim to assign; default: workspace-default.
  --password VALUE        Initial password. If omitted, a local/dev password is generated.
  --permanent-password    Mark the initial password as non-temporary. Default is temporary.
  --tenant-realm VALUE    Keycloak realm. Default: TF_VAR_tenant_slug or weave.
  --dry-run               Validate and print the support-safe plan without contacting Keycloak.
  -h, --help              Show this help.

The helper loads weave-workspace/.generated/bootstrap.env when present and uses:
  TF_VAR_keycloak_admin_username
  TF_VAR_keycloak_admin_password
  TF_VAR_public_scheme / TF_VAR_tenant_domain / TF_VAR_auth_subdomain / TF_VAR_proxy_host_port
  TF_VAR_caddy_tls_ca_file or WEAVE_TLS_CA_FILE when local TLS needs a custom CA.
EOF
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

keycloak_public_url() {
  printf '%s://%s.%s%s' \
    "${TF_VAR_public_scheme:-https}" \
    "${TF_VAR_auth_subdomain:-auth}" \
    "${TF_VAR_tenant_domain:-weave.local}" \
    "$(public_port_suffix)"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --username) USERNAME="${2:-}"; shift 2 ;;
      --email) EMAIL="${2:-}"; shift 2 ;;
      --display-name) DISPLAY_NAME="${2:-}"; shift 2 ;;
      --role) ROLE="${2:-}"; shift 2 ;;
      --workspace-group) WORKSPACE_GROUP="${2:-}"; shift 2 ;;
      --password) INITIAL_PASSWORD="${2:-}"; shift 2 ;;
      --permanent-password) TEMPORARY_PASSWORD="false"; shift ;;
      --tenant-realm) TENANT_REALM="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown argument: $1" ;;
    esac
  done
}

validate_role() {
  case "${ROLE}" in
    owner|admin|member|guest) ;;
    *) fail "Invalid role '${ROLE}'. Expected one of: owner, admin, member, guest." ;;
  esac
}

validate_inputs() {
  [[ -n "${USERNAME}" ]] || fail "--username is required"
  [[ -n "${EMAIL}" ]] || fail "--email is required"
  [[ -n "${DISPLAY_NAME}" ]] || fail "--display-name is required"
  [[ -n "${WORKSPACE_GROUP}" ]] || fail "--workspace-group must not be empty"
  [[ -n "${TENANT_REALM}" ]] || fail "--tenant-realm must not be empty"
  validate_role
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 | tr -d '\n'
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

curl_args() {
  local -a args=(--silent --show-error --fail-with-body)
  if [[ -n "${WEAVE_TLS_CA_FILE:-}" ]]; then
    args+=(--cacert "${WEAVE_TLS_CA_FILE}")
  elif [[ -n "${TF_VAR_caddy_tls_ca_file:-}" && -f "${TF_VAR_caddy_tls_ca_file}" ]]; then
    args+=(--cacert "${TF_VAR_caddy_tls_ca_file}")
  fi
  printf '%s\0' "${args[@]}"
}

curl_keycloak() {
  local method="$1"
  local url="$2"
  local token="${3:-}"
  local body="${4:-}"
  local -a args=()
  while IFS= read -r -d '' arg; do args+=("${arg}"); done < <(curl_args)
  args+=(-X "${method}")
  [[ -n "${token}" ]] && args+=(-H "Authorization: Bearer ${token}")
  if [[ -n "${body}" ]]; then
    args+=(-H 'Content-Type: application/json' --data "${body}")
  fi
  curl "${args[@]}" "${url}"
}

admin_token() {
  local token_url
  token_url="$(keycloak_public_url)/realms/master/protocol/openid-connect/token"
  local -a args=()
  while IFS= read -r -d '' arg; do args+=("${arg}"); done < <(curl_args)
  curl "${args[@]}" -X POST "${token_url}" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'client_id=admin-cli' \
    --data-urlencode "username=${TF_VAR_keycloak_admin_username:-admin}" \
    --data-urlencode "password=${TF_VAR_keycloak_admin_password:-}" \
    --data-urlencode 'grant_type=password' |
    jq -r '.access_token // empty'
}

ensure_realm_role() {
  local base_url="$1" token="$2" role_name="$3"
  local encoded_role
  encoded_role="$(jq -nr --arg value "${role_name}" '$value|@uri')"
  if ! curl_keycloak GET "${base_url}/roles/${encoded_role}" "${token}" >/dev/null 2>&1; then
    curl_keycloak POST "${base_url}/roles" "${token}" "$(jq -n --arg name "${role_name}" '{name: $name, description: "Weave MVP product role"}')" >/dev/null
  fi
  curl_keycloak GET "${base_url}/roles/${encoded_role}" "${token}"
}

ensure_group_id() {
  local base_url="$1" token="$2" group_name="$3"
  local encoded_group groups group_id
  encoded_group="$(jq -nr --arg value "${group_name}" '$value|@uri')"
  groups="$(curl_keycloak GET "${base_url}/groups?search=${encoded_group}&exact=true" "${token}")"
  group_id="$(jq -r --arg name "${group_name}" '.[] | select(.name == $name) | .id' <<<"${groups}" | head -n 1)"
  if [[ -z "${group_id}" ]]; then
    curl_keycloak POST "${base_url}/groups" "${token}" "$(jq -n --arg name "${group_name}" '{name: $name}')" >/dev/null
    groups="$(curl_keycloak GET "${base_url}/groups?search=${encoded_group}&exact=true" "${token}")"
    group_id="$(jq -r --arg name "${group_name}" '.[] | select(.name == $name) | .id' <<<"${groups}" | head -n 1)"
  fi
  [[ -n "${group_id}" ]] || fail "Could not create or locate Keycloak group '${group_name}'"
  printf '%s\n' "${group_id}"
}

upsert_user() {
  local base_url="$1" token="$2" password="$3"
  local encoded_username users user_id payload first_name last_name
  encoded_username="$(jq -nr --arg value "${USERNAME}" '$value|@uri')"
  users="$(curl_keycloak GET "${base_url}/users?username=${encoded_username}&exact=true" "${token}")"
  user_id="$(jq -r --arg username "${USERNAME}" '.[] | select(.username == $username) | .id' <<<"${users}" | head -n 1)"

  first_name="${DISPLAY_NAME%% *}"
  if [[ "${DISPLAY_NAME}" == *' '* ]]; then
    last_name="${DISPLAY_NAME#* }"
  else
    last_name=""
  fi

  payload="$(jq -n \
    --arg username "${USERNAME}" \
    --arg email "${EMAIL}" \
    --arg firstName "${first_name}" \
    --arg lastName "${last_name}" \
    '{username: $username, email: $email, firstName: $firstName, lastName: $lastName, enabled: true, emailVerified: true}')"

  if [[ -z "${user_id}" ]]; then
    curl_keycloak POST "${base_url}/users" "${token}" "${payload}" >/dev/null
    users="$(curl_keycloak GET "${base_url}/users?username=${encoded_username}&exact=true" "${token}")"
    user_id="$(jq -r --arg username "${USERNAME}" '.[] | select(.username == $username) | .id' <<<"${users}" | head -n 1)"
  else
    curl_keycloak PUT "${base_url}/users/${user_id}" "${token}" "${payload}" >/dev/null
  fi

  [[ -n "${user_id}" ]] || fail "Could not create or locate Keycloak user '${USERNAME}'"

  curl_keycloak PUT "${base_url}/users/${user_id}/reset-password" "${token}" \
    "$(jq -n --arg value "${password}" --argjson temporary "${TEMPORARY_PASSWORD}" '{type: "password", value: $value, temporary: $temporary}')" >/dev/null

  printf '%s\n' "${user_id}"
}

main() {
  load_bootstrap_env
  parse_args "$@"
  validate_inputs

  local generated_password="false"
  if [[ -z "${INITIAL_PASSWORD}" ]]; then
    INITIAL_PASSWORD="$(generate_password)"
    generated_password="true"
  fi

  log "Weave activation plan"
  log "- realm: ${TENANT_REALM}"
  log "- username: ${USERNAME}"
  log "- email: ${EMAIL}"
  log "- display name: ${DISPLAY_NAME}"
  log "- role: ${ROLE}"
  log "- group: ${WORKSPACE_GROUP}"
  log "- password: $([[ "${generated_password}" == "true" ]] && printf 'generated local/dev initial password' || printf 'provided by operator')"
  log "- password mode: $([[ "${TEMPORARY_PASSWORD}" == "true" ]] && printf 'temporary' || printf 'permanent')"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "Dry run only: Keycloak was not modified."
    return 0
  fi

  require_command curl
  require_command jq

  [[ -n "${TF_VAR_keycloak_admin_password:-}" ]] || fail "TF_VAR_keycloak_admin_password is required; run install.sh first or source .generated/bootstrap.env."

  local token
  token="$(admin_token)"
  [[ -n "${token}" ]] || fail "Could not obtain a Keycloak admin token for $(keycloak_public_url)."

  local base_url role_json group_id user_id
  base_url="$(keycloak_public_url)/admin/realms/${TENANT_REALM}"
  role_json="$(ensure_realm_role "${base_url}" "${token}" "${ROLE}")"
  group_id="$(ensure_group_id "${base_url}" "${token}" "${WORKSPACE_GROUP}")"
  user_id="$(upsert_user "${base_url}" "${token}" "${INITIAL_PASSWORD}")"

  curl_keycloak POST "${base_url}/users/${user_id}/role-mappings/realm" "${token}" "$(jq -n --argjson role "${role_json}" '[$role]')" >/dev/null
  curl_keycloak PUT "${base_url}/users/${user_id}/groups/${group_id}" "${token}" >/dev/null

  log "Activation complete."
  log "- User can sign in at $(keycloak_public_url) and should receive realm role '${ROLE}' plus group '${WORKSPACE_GROUP}'."
  log "- Verify through the backend facade with /api/me or the app first-run profile/status screen."
  log "- Initial password for this local/dev activation: ${INITIAL_PASSWORD}"
}

main "$@"
