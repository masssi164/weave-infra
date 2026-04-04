#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${ROOT_DIR}/01-infrastructure"
KEYCLOAK_DIR="${ROOT_DIR}/02-keycloak-setup"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ensure_var() {
  local name="$1"
  local default_value="$2"
  if [[ -z "${!name:-}" ]]; then
    export "${name}=${default_value}"
  fi
}

generate_base64_secret() {
  local bytes="$1"
  openssl rand -base64 "${bytes}" | tr -d '\n'
}

generate_hex_secret() {
  local bytes="$1"
  openssl rand -hex "${bytes}"
}

ensure_secret() {
  local name="$1"
  local value="$2"
  if [[ -z "${!name:-}" ]]; then
    export "${name}=${value}"
  fi
}

ensure_mas_signing_key() {
  if [[ -n "${TF_VAR_mas_signing_key_pem:-}" ]]; then
    return
  fi

  local key_file
  key_file="$(mktemp)"
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${key_file}" >/dev/null 2>&1
  export TF_VAR_mas_signing_key_pem
  TF_VAR_mas_signing_key_pem="$(<"${key_file}")"
  rm -f "${key_file}"
}

wait_for_keycloak() {
  local attempts=120
  local sleep_seconds=5
  local url="http://localhost:${TF_VAR_keycloak_host_port:-8080}/health/ready"

  for ((i = 1; i <= attempts; i++)); do
    if [[ "$(curl -s -o /dev/null -w "%{http_code}" "${url}" || true)" == "200" ]]; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  echo "Keycloak never became ready at ${url}" >&2
  return 1
}

wait_for_nextcloud() {
  local attempts=120
  local sleep_seconds=5

  for ((i = 1; i <= attempts; i++)); do
    if docker exec --user www-data weave-nextcloud php occ status >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  echo "Nextcloud did not finish bootstrapping in time." >&2
  return 1
}

occ() {
  docker exec --user www-data weave-nextcloud php occ "$@"
}

require_command curl
require_command docker
require_command gh
require_command openssl
require_command terraform

mkdir -p \
  "${INFRA_DIR}/.generated/db" \
  "${INFRA_DIR}/.generated/mas" \
  "${INFRA_DIR}/.generated/synapse"

ensure_var TF_VAR_tenant_slug "weave"
ensure_var TF_VAR_tenant_domain "weave.local"
ensure_var TF_VAR_public_scheme "http"
ensure_var TF_VAR_proxy_host_port "8090"
ensure_var TF_VAR_keycloak_admin_username "admin"
ensure_var TF_VAR_db_admin_username "weave_admin"
ensure_var TF_VAR_keycloak_db_username "keycloak"
ensure_var TF_VAR_mas_db_username "mas"
ensure_var TF_VAR_synapse_db_username "synapse"
ensure_var TF_VAR_nextcloud_db_username "nextcloud"
ensure_var TF_VAR_nextcloud_admin_username "admin"

ensure_secret TF_VAR_db_admin_password "$(generate_base64_secret 24)"
ensure_secret TF_VAR_keycloak_admin_password "$(generate_base64_secret 24)"
ensure_secret TF_VAR_keycloak_db_password "$(generate_base64_secret 24)"
ensure_secret TF_VAR_mas_db_password "$(generate_base64_secret 24)"
ensure_secret TF_VAR_synapse_db_password "$(generate_base64_secret 24)"
ensure_secret TF_VAR_nextcloud_db_password "$(generate_base64_secret 24)"
ensure_secret TF_VAR_nextcloud_admin_password "$(generate_base64_secret 24)"
ensure_secret TF_VAR_matrix_mas_client_secret "$(generate_base64_secret 32)"
ensure_secret TF_VAR_mas_encryption_secret "$(generate_hex_secret 32)"
ensure_secret TF_VAR_mas_matrix_secret "$(generate_base64_secret 32)"
ensure_secret TF_VAR_synapse_registration_shared_secret "$(generate_base64_secret 32)"
ensure_secret TF_VAR_synapse_macaroon_secret_key "$(generate_base64_secret 32)"
ensure_secret TF_VAR_synapse_form_secret "$(generate_base64_secret 32)"
ensure_mas_signing_key

terraform -chdir="${INFRA_DIR}" init
terraform -chdir="${INFRA_DIR}" apply -auto-approve

wait_for_keycloak

terraform -chdir="${KEYCLOAK_DIR}" init
terraform -chdir="${KEYCLOAK_DIR}" apply -auto-approve

wait_for_nextcloud

issuer_url="$(terraform -chdir="${KEYCLOAK_DIR}" output -raw keycloak_issuer_url)"
nextcloud_client_secret="$(terraform -chdir="${KEYCLOAK_DIR}" output -raw nextcloud_client_secret)"
nextcloud_base_url="${TF_VAR_public_scheme}://files.${TF_VAR_tenant_domain}"

if [[ "${TF_VAR_proxy_host_port}" != "80" && "${TF_VAR_proxy_host_port}" != "443" ]]; then
  nextcloud_base_url="${nextcloud_base_url}:${TF_VAR_proxy_host_port}"
fi

occ app:install user_oidc || true
occ app:enable user_oidc

if [[ "${TF_VAR_public_scheme}" == "http" ]]; then
  occ config:app:set --type=boolean --value=1 user_oidc allow_insecure_http
fi

occ user_oidc:provider keycloak \
  --clientid="nextcloud" \
  --clientsecret="${nextcloud_client_secret}" \
  --discoveryuri="${issuer_url}/.well-known/openid-configuration" \
  --group-provisioning=1

echo
echo "Add these host entries before using the browser-facing URLs:"
echo "127.0.0.1 auth.${TF_VAR_tenant_domain} mas.${TF_VAR_tenant_domain} matrix.${TF_VAR_tenant_domain} files.${TF_VAR_tenant_domain}"
echo
echo "Keycloak admin: ${TF_VAR_keycloak_admin_username} / ${TF_VAR_keycloak_admin_password}"
echo "Nextcloud admin: ${TF_VAR_nextcloud_admin_username} / ${TF_VAR_nextcloud_admin_password}"
echo "Nextcloud URL: ${nextcloud_base_url}"
