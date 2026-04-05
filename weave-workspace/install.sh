#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
readonly INFRA_DIR="${ROOT_DIR}/01-infrastructure"
readonly KEYCLOAK_DIR="${ROOT_DIR}/02-keycloak-setup"
readonly BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
readonly LOOPBACK_HOST="127.0.0.1"
readonly PERSISTED_TF_VARS=(
  TF_VAR_docker_host
  TF_VAR_docker_network_name
  TF_VAR_tenant_slug
  TF_VAR_tenant_domain
  TF_VAR_auth_subdomain
  TF_VAR_mas_subdomain
  TF_VAR_matrix_subdomain
  TF_VAR_nextcloud_subdomain
  TF_VAR_api_subdomain
  TF_VAR_public_scheme
  TF_VAR_proxy_host_port
  TF_VAR_keycloak_host_port
  TF_VAR_mas_host_port
  TF_VAR_synapse_host_port
  TF_VAR_nextcloud_host_port
  TF_VAR_synapse_uid
  TF_VAR_synapse_gid
  TF_VAR_db_name
  TF_VAR_db_admin_username
  TF_VAR_db_admin_password
  TF_VAR_keycloak_admin_username
  TF_VAR_keycloak_admin_password
  TF_VAR_keycloak_db_username
  TF_VAR_keycloak_db_password
  TF_VAR_mas_db_username
  TF_VAR_mas_db_password
  TF_VAR_synapse_db_username
  TF_VAR_synapse_db_password
  TF_VAR_nextcloud_db_username
  TF_VAR_nextcloud_db_password
  TF_VAR_nextcloud_admin_username
  TF_VAR_nextcloud_admin_password
  TF_VAR_matrix_mas_client_secret
  TF_VAR_mas_encryption_secret
  TF_VAR_mas_signing_key_pem
  TF_VAR_mas_matrix_secret
  TF_VAR_synapse_registration_shared_secret
  TF_VAR_synapse_macaroon_secret_key
  TF_VAR_synapse_form_secret
)

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

detect_docker_host() {
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    printf '%s\n' "${DOCKER_HOST}"
    return
  fi

  docker context inspect "$(docker context show)" --format '{{ (index .Endpoints "docker").Host }}'
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

load_persisted_env() {
  if [[ ! -f "${BOOTSTRAP_ENV_FILE}" ]]; then
    return
  fi

  local var
  local index
  local -a preset_names=()
  local -a preset_values=()

  for var in "${PERSISTED_TF_VARS[@]}"; do
    if [[ "${!var+x}" == "x" ]]; then
      preset_names+=("${var}")
      preset_values+=("${!var}")
    fi
  done

  # shellcheck disable=SC1090
  source "${BOOTSTRAP_ENV_FILE}"

  for ((index = 0; index < ${#preset_names[@]}; index++)); do
    export "${preset_names[$index]}=${preset_values[$index]}"
  done

  # Preserve compatibility with older bootstrap environments that used
  # TF_VAR_files_subdomain before the contract was renamed.
  if [[ ! " ${preset_names[*]} " =~ " TF_VAR_nextcloud_subdomain " ]] &&
    [[ -n "${TF_VAR_files_subdomain:-}" ]]; then
    export TF_VAR_nextcloud_subdomain="${TF_VAR_files_subdomain}"
  fi

  # Migrate the legacy default Nextcloud hostname from files.<tenant_domain>
  # to nextcloud.<tenant_domain> unless the caller already set a value.
  if [[ ! " ${preset_names[*]} " =~ " TF_VAR_nextcloud_subdomain " ]] &&
    [[ "${TF_VAR_nextcloud_subdomain:-}" == "files" ]]; then
    export TF_VAR_nextcloud_subdomain="nextcloud"
  fi
}

persist_bootstrap_env() {
  local var

  : > "${BOOTSTRAP_ENV_FILE}"
  chmod 600 "${BOOTSTRAP_ENV_FILE}"

  for var in "${PERSISTED_TF_VARS[@]}"; do
    if [[ "${!var+x}" == "x" ]]; then
      printf 'export %s=%q\n' "${var}" "${!var}" >> "${BOOTSTRAP_ENV_FILE}"
    fi
  done
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
  rm -f -- "${key_file}"
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
    if docker exec --user www-data weave-nextcloud php occ status --output=json >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  fail "Nextcloud did not finish bootstrapping in time."
}

occ() {
  docker exec --user www-data weave-nextcloud php occ "$@"
}

nextcloud_is_installed() {
  occ status --output=json 2>/dev/null | grep -q '"installed":true'
}

terraform_apply() {
  local dir="$1"

  terraform -chdir="${dir}" init -input=false
  terraform -chdir="${dir}" apply -refresh=false -input=false -auto-approve
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
    "${ROOT_DIR}/.generated" \
    "${INFRA_DIR}/.generated/db" \
    "${INFRA_DIR}/.generated/mas" \
    "${INFRA_DIR}/.generated/synapse"
}

ensure_default_inputs() {
  local defaults=(
    "TF_VAR_docker_network_name=weave_network"
    "TF_VAR_tenant_slug=weave"
    "TF_VAR_tenant_domain=weave.local"
    "TF_VAR_auth_subdomain=auth"
    "TF_VAR_mas_subdomain=mas"
    "TF_VAR_matrix_subdomain=matrix"
    "TF_VAR_nextcloud_subdomain=nextcloud"
    "TF_VAR_api_subdomain=api"
    "TF_VAR_public_scheme=http"
    "TF_VAR_proxy_host_port=8090"
    "TF_VAR_keycloak_host_port=8080"
    "TF_VAR_mas_host_port=8082"
    "TF_VAR_synapse_host_port=8008"
    "TF_VAR_nextcloud_host_port=8083"
    "TF_VAR_synapse_uid=991"
    "TF_VAR_synapse_gid=991"
    "TF_VAR_db_name=weave"
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

ensure_docker_provider_inputs() {
  if [[ -z "${TF_VAR_docker_host:-}" ]]; then
    export TF_VAR_docker_host
    TF_VAR_docker_host="$(detect_docker_host)"
  fi
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

ensure_nextcloud_installed() {
  local nextcloud_database_name

  if nextcloud_is_installed; then
    return
  fi

  nextcloud_database_name="$(terraform_output_raw "${INFRA_DIR}" nextcloud_database_name)"

  occ maintenance:install \
    --database=pgsql \
    --database-host="weave-db" \
    --database-name="${nextcloud_database_name}" \
    --database-user="${TF_VAR_nextcloud_db_username}" \
    --database-pass="${TF_VAR_nextcloud_db_password}" \
    --admin-user="${TF_VAR_nextcloud_admin_username}" \
    --admin-pass="${TF_VAR_nextcloud_admin_password}"
}

configure_nextcloud_base_url() {
  local nextcloud_host
  local nextcloud_url

  nextcloud_host="$(public_host "${TF_VAR_nextcloud_subdomain}")"
  nextcloud_url="${TF_VAR_public_scheme}://${nextcloud_host}$(public_port_suffix)"

  occ config:system:set trusted_domains 0 --value="${nextcloud_host}"
  occ config:system:set trusted_domains 1 --value="localhost"
  occ config:system:set trusted_domains 2 --value="127.0.0.1"
  occ config:system:set overwritehost --value="${nextcloud_host}$(public_port_suffix)"
  occ config:system:set overwrite.cli.url --value="${nextcloud_url}"
  occ config:system:set overwriteprotocol --value="${TF_VAR_public_scheme}"
}

configure_nextcloud_oidc() {
  local issuer_url
  local nextcloud_client_id
  local nextcloud_client_secret
  local allow_insecure_http

  issuer_url="$(terraform_output_raw "${KEYCLOAK_DIR}" keycloak_issuer_url)"
  nextcloud_client_id="$(terraform_output_raw "${KEYCLOAK_DIR}" nextcloud_client_id)"
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
    --clientid="${nextcloud_client_id}" \
    --clientsecret="${nextcloud_client_secret}" \
    --discoveryuri="${issuer_url}/.well-known/openid-configuration" \
    --group-provisioning=1
}

print_summary() {
  local suffix
  local backend_url
  local nextcloud_url
  local weave_client_id

  suffix="$(public_port_suffix)"
  nextcloud_url="${TF_VAR_public_scheme}://$(public_host "${TF_VAR_nextcloud_subdomain}")${suffix}"
  backend_url="${TF_VAR_public_scheme}://$(public_host "${TF_VAR_api_subdomain}")${suffix}"
  weave_client_id="$(terraform_output_raw "${KEYCLOAK_DIR}" weave_app_client_id)"

  log
  log "Add these host entries before using the browser-facing URLs:"
  log "127.0.0.1 $(public_host "${TF_VAR_auth_subdomain}") $(public_host "${TF_VAR_mas_subdomain}") $(public_host "${TF_VAR_matrix_subdomain}") $(public_host "${TF_VAR_nextcloud_subdomain}") $(public_host "${TF_VAR_api_subdomain}")"
  log
  log "Weave app client ID: ${weave_client_id}"
  log "Weave app sign-in redirect: com.massimotter.weave:/oauthredirect"
  log "Weave app post-logout redirect: com.massimotter.weave:/logout"
  log "Keycloak admin: ${TF_VAR_keycloak_admin_username} / ${TF_VAR_keycloak_admin_password}"
  log "Nextcloud admin: ${TF_VAR_nextcloud_admin_username} / ${TF_VAR_nextcloud_admin_password}"
  log "Nextcloud URL: ${nextcloud_url}"
  log "Reserved backend URL: ${backend_url}"
}

main() {
  require_command curl
  require_command docker
  require_command openssl
  require_command terraform

  ensure_generated_directories
  load_persisted_env
  ensure_default_inputs
  ensure_docker_provider_inputs
  ensure_generated_secrets
  persist_bootstrap_env

  log "Applying infrastructure module..."
  terraform_apply "${INFRA_DIR}"

  log "Waiting for Keycloak readiness..."
  wait_for_http_200 "Keycloak" "http://${LOOPBACK_HOST}:${TF_VAR_keycloak_host_port}/health/ready"

  log "Applying Keycloak configuration module..."
  terraform_apply "${KEYCLOAK_DIR}"

  log "Waiting for Matrix Authentication Service readiness..."
  wait_for_http_200 "Matrix Authentication Service" "http://${LOOPBACK_HOST}:${TF_VAR_mas_host_port}/health"

  log "Waiting for Synapse readiness..."
  wait_for_http_200 "Synapse" "http://${LOOPBACK_HOST}:${TF_VAR_synapse_host_port}/_matrix/client/versions"

  log "Waiting for Nextcloud OCC availability..."
  wait_for_nextcloud 120 5

  log "Installing and configuring Nextcloud..."
  ensure_nextcloud_installed
  configure_nextcloud_base_url

  log "Configuring Nextcloud OIDC provider..."
  configure_nextcloud_oidc

  print_summary
}

main "$@"
