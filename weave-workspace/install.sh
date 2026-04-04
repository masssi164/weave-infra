#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly INFRA_DIR="${ROOT_DIR}/01-infrastructure"
readonly KEYCLOAK_DIR="${ROOT_DIR}/02-keycloak-setup"

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

set_default_var() {
  local name="$1"
  local value="$2"

  if [[ -z "${!name:-}" ]]; then
    export "${name}=${value}"
  fi
}

set_default_secret() {
  local name="$1"
  local value="$2"

  if [[ -z "${!name:-}" ]]; then
    export "${name}=${value}"
  fi
}

random_base64() {
  local bytes="$1"
  openssl rand -base64 "${bytes}" | tr -d '\n'
}

random_hex() {
  local bytes="$1"
  openssl rand -hex "${bytes}"
}

ensure_mas_signing_key() {
  if [[ -n "${TF_VAR_mas_signing_key_pem:-}" ]]; then
    return
  fi

  local key_file
  key_file="$(mktemp)"
  trap 'rm -f "${key_file}"' RETURN

  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${key_file}" >/dev/null 2>&1
  export TF_VAR_mas_signing_key_pem
  TF_VAR_mas_signing_key_pem="$(<"${key_file}")"
}

wait_for_http_200() {
  local name="$1"
  local url="$2"
  local attempts="${3:-120}"
  local sleep_seconds="${4:-5}"
  local status_code

  for ((i = 1; i <= attempts; i++)); do
    status_code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" || true)"
    if [[ "${status_code}" == "200" ]]; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  fail "${name} never became ready at ${url}"
}

wait_for_nextcloud() {
  local attempts="${1:-120}"
  local sleep_seconds="${2:-5}"

  for ((i = 1; i <= attempts; i++)); do
    if docker exec --user www-data weave-nextcloud php occ status >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  fail "Nextcloud did not finish bootstrapping in time."
}

occ() {
  docker exec --user www-data weave-nextcloud php occ "$@"
}

terraform_apply() {
  local dir="$1"

  terraform -chdir="${dir}" init -input=false
  terraform -chdir="${dir}" apply -input=false -auto-approve
}

terraform_output_raw() {
  local dir="$1"
  local name="$2"

  terraform -chdir="${dir}" output -raw "${name}"
}

public_port_suffix() {
  if [[ "${TF_VAR_proxy_host_port}" == "80" || "${TF_VAR_proxy_host_port}" == "443" ]]; then
    printf ''
  else
    printf ':%s' "${TF_VAR_proxy_host_port}"
  fi
}

public_host() {
  local subdomain="$1"
  printf '%s.%s' "${subdomain}" "${TF_VAR_tenant_domain}"
}

ensure_generated_directories() {
  mkdir -p \
    "${INFRA_DIR}/.generated/db" \
    "${INFRA_DIR}/.generated/mas" \
    "${INFRA_DIR}/.generated/synapse"
}

ensure_default_inputs() {
  local defaults=(
    "TF_VAR_tenant_slug=weave"
    "TF_VAR_tenant_domain=weave.local"
    "TF_VAR_auth_subdomain=auth"
    "TF_VAR_mas_subdomain=mas"
    "TF_VAR_matrix_subdomain=matrix"
    "TF_VAR_files_subdomain=files"
    "TF_VAR_public_scheme=http"
    "TF_VAR_proxy_host_port=8090"
    "TF_VAR_keycloak_host_port=8080"
    "TF_VAR_keycloak_admin_username=admin"
    "TF_VAR_db_admin_username=weave_admin"
    "TF_VAR_keycloak_db_username=keycloak"
    "TF_VAR_mas_db_username=mas"
    "TF_VAR_synapse_db_username=synapse"
    "TF_VAR_nextcloud_db_username=nextcloud"
    "TF_VAR_nextcloud_admin_username=admin"
  )

  local entry
  for entry in "${defaults[@]}"; do
    set_default_var "${entry%%=*}" "${entry#*=}"
  done
}

ensure_generated_secrets() {
  set_default_secret TF_VAR_db_admin_password "$(random_base64 24)"
  set_default_secret TF_VAR_keycloak_admin_password "$(random_base64 24)"
  set_default_secret TF_VAR_keycloak_db_password "$(random_base64 24)"
  set_default_secret TF_VAR_mas_db_password "$(random_base64 24)"
  set_default_secret TF_VAR_synapse_db_password "$(random_base64 24)"
  set_default_secret TF_VAR_nextcloud_db_password "$(random_base64 24)"
  set_default_secret TF_VAR_nextcloud_admin_password "$(random_base64 24)"
  set_default_secret TF_VAR_matrix_mas_client_secret "$(random_base64 32)"
  set_default_secret TF_VAR_mas_encryption_secret "$(random_hex 32)"
  set_default_secret TF_VAR_mas_matrix_secret "$(random_base64 32)"
  set_default_secret TF_VAR_synapse_registration_shared_secret "$(random_base64 32)"
  set_default_secret TF_VAR_synapse_macaroon_secret_key "$(random_base64 32)"
  set_default_secret TF_VAR_synapse_form_secret "$(random_base64 32)"
  ensure_mas_signing_key
}

configure_nextcloud_oidc() {
  local issuer_url
  local nextcloud_client_secret
  local allow_insecure_http

  issuer_url="$(terraform_output_raw "${KEYCLOAK_DIR}" keycloak_issuer_url)"
  nextcloud_client_secret="$(terraform_output_raw "${KEYCLOAK_DIR}" nextcloud_client_secret)"

  if ! occ app:enable user_oidc >/dev/null 2>&1; then
    occ app:install user_oidc
    occ app:enable user_oidc
  fi

  allow_insecure_http=0
  if [[ "${TF_VAR_public_scheme}" == "http" ]]; then
    allow_insecure_http=1
  fi

  occ config:app:set --type=boolean --value="${allow_insecure_http}" user_oidc allow_insecure_http
  occ user_oidc:provider keycloak \
    --clientid="nextcloud" \
    --clientsecret="${nextcloud_client_secret}" \
    --discoveryuri="${issuer_url}/.well-known/openid-configuration" \
    --group-provisioning=1
}

print_summary() {
  local suffix
  local nextcloud_url

  suffix="$(public_port_suffix)"
  nextcloud_url="${TF_VAR_public_scheme}://$(public_host "${TF_VAR_files_subdomain}")${suffix}"

  log
  log "Add these host entries before using the browser-facing URLs:"
  log "127.0.0.1 $(public_host "${TF_VAR_auth_subdomain}") $(public_host "${TF_VAR_mas_subdomain}") $(public_host "${TF_VAR_matrix_subdomain}") $(public_host "${TF_VAR_files_subdomain}")"
  log
  log "Keycloak admin: ${TF_VAR_keycloak_admin_username} / ${TF_VAR_keycloak_admin_password}"
  log "Nextcloud admin: ${TF_VAR_nextcloud_admin_username} / ${TF_VAR_nextcloud_admin_password}"
  log "Nextcloud URL: ${nextcloud_url}"
}

main() {
  require_command curl
  require_command docker
  require_command openssl
  require_command terraform

  ensure_generated_directories
  ensure_default_inputs
  ensure_generated_secrets

  log "Applying infrastructure module..."
  terraform_apply "${INFRA_DIR}"

  log "Waiting for Keycloak readiness..."
  wait_for_http_200 "Keycloak" "http://localhost:${TF_VAR_keycloak_host_port}/health/ready"

  log "Applying Keycloak configuration module..."
  terraform_apply "${KEYCLOAK_DIR}"

  log "Waiting for Nextcloud OCC availability..."
  wait_for_nextcloud

  log "Configuring Nextcloud OIDC provider..."
  configure_nextcloud_oidc

  print_summary
}

main "$@"
