#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
readonly INFRA_DIR="${ROOT_DIR}/01-infrastructure"
readonly KEYCLOAK_DIR="${ROOT_DIR}/02-keycloak-setup"
readonly BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
readonly RUNNER_BOOTSTRAP_ENV_FILE="/tmp/weave-infra/weave-workspace/.generated/bootstrap.env"
readonly TEARDOWN_SCRIPT="${ROOT_DIR}/teardown.sh"
readonly LOOPBACK_HOST="127.0.0.1"
readonly TEST_USER_EMAIL="test@weave.local"
readonly PERSISTED_TF_VARS=(
  TF_VAR_docker_host
  TF_VAR_docker_network_name
  TF_VAR_tenant_slug
  TF_VAR_tenant_domain
  TF_VAR_create_test_user
  TF_VAR_test_user_password
  TF_VAR_auth_subdomain
  TF_VAR_matrix_subdomain
  TF_VAR_nextcloud_subdomain
  TF_VAR_api_subdomain
  TF_VAR_public_scheme
  TF_VAR_proxy_host_port
  TF_VAR_proxy_http_host_port
  TF_VAR_keycloak_host_port
  TF_VAR_keycloak_management_host_port
  TF_VAR_mas_host_port
  TF_VAR_synapse_host_port
  TF_VAR_nextcloud_host_port
  TF_VAR_nextcloud_trusted_proxies
  TF_VAR_caddy_tls_cert_file
  TF_VAR_caddy_tls_key_file
  TF_VAR_caddy_tls_ca_file
  TF_VAR_backend_host_port
  TF_VAR_backend_container_port
  TF_VAR_weave_backend_image
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

load_persisted_env() {
  if [[ ! -f "${BOOTSTRAP_ENV_FILE}" ]]; then
    return
  fi

  local var
  local index
  local preset_names_joined=""
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
  normalize_repo_local_paths

  for ((index = 0; index < ${#preset_names[@]}; index++)); do
    export "${preset_names[$index]}=${preset_values[$index]}"
  done

  if (( ${#preset_names[@]} > 0 )); then
    preset_names_joined=" ${preset_names[*]} "
  fi

  # Preserve compatibility with older bootstrap environments that used
  # TF_VAR_files_subdomain before the contract was renamed.
  if [[ ! "${preset_names_joined}" =~ " TF_VAR_nextcloud_subdomain " ]] &&
    [[ -n "${TF_VAR_files_subdomain:-}" ]]; then
    export TF_VAR_nextcloud_subdomain="${TF_VAR_files_subdomain}"
    unset TF_VAR_files_subdomain
  fi

  # Migrate the legacy default Nextcloud hostname from files.<tenant_domain>
  # to nextcloud.<tenant_domain> unless the caller already set a value.
  if [[ ! "${preset_names_joined}" =~ " TF_VAR_nextcloud_subdomain " ]] &&
    [[ "${TF_VAR_nextcloud_subdomain:-}" == "files" ]]; then
    export TF_VAR_nextcloud_subdomain="nextcloud"
  fi

  # Migrate the old Keycloak default from auth.<tenant_domain> to
  # keycloak.<tenant_domain> unless the caller already set a value.
  if [[ ! "${preset_names_joined}" =~ " TF_VAR_auth_subdomain " ]] &&
    [[ "${TF_VAR_auth_subdomain:-}" == "auth" ]]; then
    export TF_VAR_auth_subdomain="keycloak"
  fi
}

persist_bootstrap_env() {
  local var

  mkdir -p "$(dirname -- "${BOOTSTRAP_ENV_FILE}")" "$(dirname -- "${RUNNER_BOOTSTRAP_ENV_FILE}")"
  : > "${BOOTSTRAP_ENV_FILE}"
  chmod 600 "${BOOTSTRAP_ENV_FILE}"

  for var in "${PERSISTED_TF_VARS[@]}"; do
    if [[ "${!var+x}" == "x" ]]; then
      printf 'export %s=%q\n' "${var}" "${!var}" >> "${BOOTSTRAP_ENV_FILE}"
    fi
  done

  if create_test_user_enabled; then
    {
      printf 'export WEAVE_BASE_URL=%q\n' "$(integration_test_base_url)"
      printf 'export WEAVE_OIDC_ISSUER_URL=%q\n' "$(integration_test_oidc_issuer_url)"
      printf 'export WEAVE_OIDC_CLIENT_ID=%q\n' "weave-app"
      printf 'export WEAVE_TEST_USERNAME=%q\n' "${TEST_USER_EMAIL}"
      printf 'export WEAVE_TEST_PASSWORD=%q\n' "${TF_VAR_test_user_password}"
    } >> "${BOOTSTRAP_ENV_FILE}"
  fi

  cp "${BOOTSTRAP_ENV_FILE}" "${RUNNER_BOOTSTRAP_ENV_FILE}"
  chmod 600 "${RUNNER_BOOTSTRAP_ENV_FILE}"
}

ensure_mas_signing_key() {
  if [[ -n "${TF_VAR_mas_signing_key_pem:-}" ]]; then
    export TF_VAR_mas_signing_key_pem
    return
  fi

  local key_file
  key_file="$(mktemp)"

  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${key_file}" >/dev/null 2>&1
  TF_VAR_mas_signing_key_pem="$(<"${key_file}")"
  export TF_VAR_mas_signing_key_pem
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

wait_for_keycloak_admin_login() {
  local attempts="${1:-60}"
  local sleep_seconds="${2:-2}"
  local token_url="http://${LOOPBACK_HOST}:${TF_VAR_keycloak_host_port}/realms/master/protocol/openid-connect/token"
  local response

  for ((i = 1; i <= attempts; i++)); do
    response="$(curl -sS -X POST "${token_url}"       -H 'Content-Type: application/x-www-form-urlencoded'       --data-urlencode 'client_id=admin-cli'       --data-urlencode "username=${TF_VAR_keycloak_admin_username}"       --data-urlencode "password=${TF_VAR_keycloak_admin_password}"       --data-urlencode 'grant_type=password' || true)"
    if [[ "${response}" == *'"access_token"'* ]]; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  fail "Keycloak admin login never became ready at ${token_url} for user ${TF_VAR_keycloak_admin_username}"
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

ensure_terraform_network_state() {
  local existing_network_id=""

  if terraform -chdir="${INFRA_DIR}" state show docker_network.weave_network >/dev/null 2>&1; then
    return
  fi

  if docker network inspect "${TF_VAR_docker_network_name}" >/dev/null 2>&1; then
    existing_network_id="$(docker network inspect --format '{{.ID}}' "${TF_VAR_docker_network_name}")"
    log "Importing existing Docker network ${TF_VAR_docker_network_name} into Terraform state..."
    terraform -chdir="${INFRA_DIR}" import -input=false docker_network.weave_network "${existing_network_id}"
  fi
}

terraform_output_raw() {
  local dir="$1"
  local name="$2"

  terraform -chdir="${dir}" output -raw "${name}"
}

refresh_backend_container_if_image_changed() {
  local desired_image="${TF_VAR_weave_backend_image:-}"
  local desired_image_id
  local current_image_id

  if [[ -z "${desired_image}" ]]; then
    return
  fi

  if ! docker image inspect "${desired_image}" >/dev/null 2>&1; then
    return
  fi

  if ! docker container inspect weave-backend >/dev/null 2>&1; then
    log "Recreating missing Weave backend container for image ${desired_image}..."
    terraform -chdir="${INFRA_DIR}" init -input=false
    terraform -chdir="${INFRA_DIR}" apply -input=false -auto-approve
    return
  fi

  desired_image_id="$(docker image inspect --format '{{.Id}}' "${desired_image}")"
  current_image_id="$(docker inspect --format '{{.Image}}' weave-backend)"

  if [[ "${desired_image_id}" == "${current_image_id}" ]]; then
    return
  fi

  log "Refreshing Weave backend container to match image ${desired_image}..."
  docker rm -f weave-backend >/dev/null
  terraform -chdir="${INFRA_DIR}" init -input=false
  terraform -chdir="${INFRA_DIR}" apply -input=false -auto-approve
}

ensure_postgres_bootstrap_applied() {
  local sql_file="${INFRA_DIR}/.generated/db/001-init.sql"

  log "Ensuring PostgreSQL bootstrap state is applied..."

  for _attempt in $(seq 1 30); do
    if docker exec weave-db pg_isready -U "${TF_VAR_db_admin_username}" -d postgres >/dev/null 2>&1; then
      docker exec -e PGPASSWORD="${TF_VAR_db_admin_password}" -i weave-db \
        psql -v ON_ERROR_STOP=1 -U "${TF_VAR_db_admin_username}" -d postgres < "${sql_file}"
      return 0
    fi
    sleep 2
  done

  fail "PostgreSQL bootstrap did not become ready in time for SQL initialization."
}

public_port_suffix() {
  if [[ "${TF_VAR_public_scheme}" == "http" && "${TF_VAR_proxy_host_port}" == "80" ]] ||
    [[ "${TF_VAR_public_scheme}" == "https" && "${TF_VAR_proxy_host_port}" == "443" ]]; then
    printf ''
  else
    printf ':%s' "${TF_VAR_proxy_host_port}"
  fi
}

public_host() {
  local subdomain="$1"
  printf '%s.%s' "${subdomain}" "${TF_VAR_tenant_domain}"
}

create_test_user_enabled() {
  case "${TF_VAR_create_test_user:-false}" in
    true | TRUE | True | 1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

integration_test_base_url() {
  printf '%s://%s%s' "${TF_VAR_public_scheme}" "$(public_host "${TF_VAR_api_subdomain}")" "$(public_port_suffix)"
}

integration_test_oidc_issuer_url() {
  printf '%s://%s%s/realms/%s' "${TF_VAR_public_scheme}" "$(public_host "${TF_VAR_auth_subdomain}")" "$(public_port_suffix)" "${TF_VAR_tenant_slug}"
}

ensure_generated_directories() {
  mkdir -p \
    "${ROOT_DIR}/.generated" \
    "${INFRA_DIR}/.generated/db" \
    "${INFRA_DIR}/.generated/caddy/certs" \
    "${INFRA_DIR}/.generated/mas" \
    "${INFRA_DIR}/.generated/synapse"
}

maybe_prepare_runner_hygiene() {
  if [[ "${WEAVE_RUNNER_HYGIENE:-false}" != "true" ]]; then
    return
  fi

  if [[ ! -x "${TEARDOWN_SCRIPT}" && ! -f "${TEARDOWN_SCRIPT}" ]]; then
    fail "Expected teardown helper at ${TEARDOWN_SCRIPT}"
  fi

  log "Running shared-host hygiene cleanup before bootstrap..."
  WEAVE_REMOVE_VOLUMES="${WEAVE_REMOVE_VOLUMES:-false}" bash "${TEARDOWN_SCRIPT}"
}

cleanup_partial_weave_containers() {
  local name
  local state
  local removed_any=false
  local containers=(
    weave-proxy
    weave-db
    weave-keycloak
    weave-backend
    weave-mas
    weave-synapse
    weave-nextcloud
  )

  for name in "${containers[@]}"; do
    if ! docker container inspect "${name}" >/dev/null 2>&1; then
      continue
    fi

    state="$(docker inspect --format '{{.State.Status}}' "${name}" 2>/dev/null || true)"
    case "${state}" in
      created|dead|exited)
        log "Removing leftover ${state} container ${name} before bootstrap..."
        docker rm -f "${name}" >/dev/null
        removed_any=true
        ;;
    esac
  done

  if [[ "${removed_any}" == true ]]; then
    log "Removed stale partial Weave containers."
  fi
}

ensure_default_inputs() {
  local defaults=(
    "TF_VAR_docker_network_name=weave_network"
    "TF_VAR_tenant_slug=weave"
    "TF_VAR_tenant_domain=weave.local"
    "TF_VAR_auth_subdomain=keycloak"
    "TF_VAR_matrix_subdomain=matrix"
    "TF_VAR_nextcloud_subdomain=nextcloud"
    "TF_VAR_api_subdomain=api"
    "TF_VAR_public_scheme=https"
    "TF_VAR_proxy_host_port=44443"
    "TF_VAR_proxy_http_host_port=44080"
    "TF_VAR_keycloak_host_port=48080"
    "TF_VAR_keycloak_management_host_port=49000"
    "TF_VAR_mas_host_port=48082"
    "TF_VAR_synapse_host_port=48008"
    "TF_VAR_nextcloud_host_port=48083"
    "TF_VAR_nextcloud_trusted_proxies=172.16.0.0/12"
    "TF_VAR_backend_host_port=48084"
    "TF_VAR_backend_container_port=8080"
    "TF_VAR_weave_backend_image=ghcr.io/masssi164/weave-backend:latest"
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

  set_default_var TF_VAR_caddy_tls_cert_file "${INFRA_DIR}/.generated/caddy/certs/weave.local.pem"
  set_default_var TF_VAR_caddy_tls_key_file "${INFRA_DIR}/.generated/caddy/certs/weave.local-key.pem"
  set_default_var TF_VAR_caddy_tls_ca_file "${INFRA_DIR}/.generated/caddy/certs/weave-local-ca.pem"
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
  if create_test_user_enabled; then
    set_default_secret TF_VAR_test_user_password "$(random_base64 16)"
  fi
  ensure_mas_signing_key
  export TF_VAR_mas_signing_key_pem
}

certificate_alt_names() {
  local index=1
  local host
  local hosts=(
    "$(public_host "${TF_VAR_auth_subdomain}")"
    "$(public_host "${TF_VAR_nextcloud_subdomain}")"
    "$(public_host "${TF_VAR_matrix_subdomain}")"
    "$(public_host "${TF_VAR_api_subdomain}")"
  )

  for host in "${hosts[@]}"; do
    printf 'DNS.%d = %s\n' "${index}" "${host}"
    index=$((index + 1))
  done
}

ensure_local_tls_certificates() {
  local cert_file="${TF_VAR_caddy_tls_cert_file}"
  local key_file="${TF_VAR_caddy_tls_key_file}"
  local ca_file="${TF_VAR_caddy_tls_ca_file}"
  local cert_dir
  local key_dir
  local ca_dir
  local ca_key_file
  local csr_file
  local ext_file

  if [[ -f "${cert_file}" && -f "${key_file}" && -f "${ca_file}" ]]; then
    return
  fi

  if [[ -f "${cert_file}" || -f "${key_file}" ]] &&
    [[ ! -f "${cert_file}" || ! -f "${key_file}" || ! -f "${ca_file}" ]]; then
    fail "Local TLS cert, key, and CA files must all exist together. Check TF_VAR_caddy_tls_cert_file, TF_VAR_caddy_tls_key_file, and TF_VAR_caddy_tls_ca_file."
  fi

  cert_dir="$(dirname -- "${cert_file}")"
  key_dir="$(dirname -- "${key_file}")"
  ca_dir="$(dirname -- "${ca_file}")"
  ca_key_file="${ca_file%.*}-key.pem"

  if [[ "${cert_dir}" != "${key_dir}" && "${cert_dir}" != "${ca_dir}" ]]; then
    fail "Caddy TLS cert, key, and CA files must be in the same directory so the Docker cert mount contains all three files."
  fi

  mkdir -p "${cert_dir}" "${key_dir}" "${ca_dir}"

  if [[ -f "${ca_file}" && ! -f "${ca_key_file}" ]]; then
    fail "Existing local CA certificate found at ${ca_file}, but the CA private key is missing at ${ca_key_file}. Provide a matching leaf cert/key or restore the CA key."
  fi

  if [[ ! -f "${ca_file}" ]]; then
    openssl genrsa -out "${ca_key_file}" 4096
    chmod 600 "${ca_key_file}"
    openssl req -x509 -new -nodes \
      -key "${ca_key_file}" \
      -sha256 \
      -days 3650 \
      -out "${ca_file}" \
      -subj "/CN=Weave Local Development CA"
    chmod 644 "${ca_file}"
  fi

  csr_file="$(mktemp)"
  ext_file="$(mktemp)"

  openssl genrsa -out "${key_file}" 2048
  chmod 600 "${key_file}"
  openssl req -new \
    -key "${key_file}" \
    -out "${csr_file}" \
    -subj "/CN=$(public_host "${TF_VAR_auth_subdomain}")"

  {
    printf '%s\n' "authorityKeyIdentifier=keyid,issuer"
    printf '%s\n' "basicConstraints=CA:FALSE"
    printf '%s\n' "keyUsage = digitalSignature, keyEncipherment"
    printf '%s\n' "extendedKeyUsage = serverAuth"
    printf '%s\n' "subjectAltName = @alt_names"
    printf '%s\n' ""
    printf '%s\n' "[alt_names]"
    certificate_alt_names
  } > "${ext_file}"

  openssl x509 -req \
    -in "${csr_file}" \
    -CA "${ca_file}" \
    -CAkey "${ca_key_file}" \
    -CAcreateserial \
    -out "${cert_file}" \
    -days 825 \
    -sha256 \
    -extfile "${ext_file}"
  chmod 644 "${cert_file}"

  rm -f -- "${csr_file}" "${ext_file}"
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

install_nextcloud_tls_ca() {
  local ca_filename

  ca_filename="$(basename -- "${TF_VAR_caddy_tls_ca_file}")"
  docker exec --user 0 weave-nextcloud \
    install -m 0644 "/certs/${ca_filename}" "/usr/local/share/ca-certificates/weave-local-ca.crt"
  docker exec --user 0 weave-nextcloud update-ca-certificates
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

  # The OIDC provider is reached via the local reverse proxy hostname on the Docker network.
  # Nextcloud blocks RFC1918 / local-address targets by default, which breaks discovery in local dev.
  occ config:system:set allow_local_remote_servers --type=bool --value=true
  occ config:app:set --type=boolean --value="${allow_insecure_http}" user_oidc allow_insecure_http
  # The Weave app signs in with the browser-grade weave-app OIDC client and then reuses
  # that session token for API/WebDAV access. Nextcloud therefore must validate bearer
  # tokens from the configured provider and allow the local app audience instead of
  # falling back to its interactive login/v2 app-password flow during E2E.
  occ config:system:set user_oidc selfencoded_bearer_validation_audience_check --type=boolean --value=false
  occ config:system:set user_oidc userinfo_bearer_validation --type=boolean --value=true
  occ user_oidc:provider keycloak \
    --clientid="${nextcloud_client_id}" \
    --clientsecret="${nextcloud_client_secret}" \
    --discoveryuri="${issuer_url}/.well-known/openid-configuration" \
    --group-provisioning=1 \
    --check-bearer=1 \
    --bearer-provisioning=1
}

print_summary() {
  local suffix
  local backend_url
  local issuer_url
  local nextcloud_url
  local weave_client_id

  suffix="$(public_port_suffix)"
  nextcloud_url="${TF_VAR_public_scheme}://$(public_host "${TF_VAR_nextcloud_subdomain}")${suffix}"
  backend_url="${TF_VAR_public_scheme}://$(public_host "${TF_VAR_api_subdomain}")${suffix}"
  issuer_url="$(integration_test_oidc_issuer_url)"
  weave_client_id="$(terraform_output_raw "${KEYCLOAK_DIR}" weave_app_client_id)"

  log
  log "Add these host entries before using the browser-facing URLs:"
  log "127.0.0.1 $(public_host "${TF_VAR_auth_subdomain}") $(public_host "${TF_VAR_nextcloud_subdomain}") $(public_host "${TF_VAR_matrix_subdomain}") $(public_host "${TF_VAR_api_subdomain}")"
  log
  log "Trust this local TLS CA certificate on the host before opening browser URLs:"
  log "${TF_VAR_caddy_tls_ca_file}"
  log
  log "Weave app client ID: ${weave_client_id}"
  log "Weave app sign-in redirect: com.massimotter.weave:/oauthredirect"
  log "Weave app post-logout redirect: com.massimotter.weave:/logout"
  log "Keycloak admin: ${TF_VAR_keycloak_admin_username} / ${TF_VAR_keycloak_admin_password}"
  log "Nextcloud admin: ${TF_VAR_nextcloud_admin_username} / ${TF_VAR_nextcloud_admin_password}"
  log "Nextcloud URL: ${nextcloud_url}"
  log "Weave backend URL: ${backend_url}"
  log "Weave backend health: http://${LOOPBACK_HOST}:${TF_VAR_backend_host_port}/actuator/health"

  if create_test_user_enabled; then
    log "Test user: ${TEST_USER_EMAIL} / ${TF_VAR_test_user_password}"
    log "Integration test env: WEAVE_BASE_URL=${backend_url} WEAVE_OIDC_ISSUER_URL=${issuer_url} WEAVE_OIDC_CLIENT_ID=${weave_client_id} WEAVE_TEST_USERNAME=${TEST_USER_EMAIL} WEAVE_TEST_PASSWORD=${TF_VAR_test_user_password}"
  fi
}

main() {
  require_command curl
  require_command docker
  require_command openssl
  require_command terraform

  ensure_generated_directories
  load_persisted_env
  ensure_default_inputs
  maybe_prepare_runner_hygiene
  cleanup_partial_weave_containers
  ensure_docker_provider_inputs
  ensure_generated_secrets
  ensure_local_tls_certificates
  persist_bootstrap_env
  ensure_terraform_network_state

  log "Applying infrastructure module..."
  terraform_apply "${INFRA_DIR}"
  ensure_postgres_bootstrap_applied
  refresh_backend_container_if_image_changed

  log "Waiting for Keycloak management readiness..."
  wait_for_http_200 "Keycloak management" "http://${LOOPBACK_HOST}:${TF_VAR_keycloak_management_host_port}/health/ready"

  log "Waiting for Keycloak admin login readiness..."
  wait_for_keycloak_admin_login 90 2

  log "Applying Keycloak configuration module..."
  terraform_apply "${KEYCLOAK_DIR}"

  log "Waiting for Weave backend readiness..."
  wait_for_http_200 "Weave backend" "http://${LOOPBACK_HOST}:${TF_VAR_backend_host_port}/actuator/health"

  log "Waiting for Matrix Authentication Service readiness..."
  wait_for_http_200 "Matrix Authentication Service" "http://${LOOPBACK_HOST}:${TF_VAR_mas_host_port}/health"

  log "Waiting for Synapse readiness..."
  wait_for_http_200 "Synapse" "http://${LOOPBACK_HOST}:${TF_VAR_synapse_host_port}/_matrix/client/versions"

  log "Waiting for Nextcloud OCC availability..."
  wait_for_nextcloud 120 5

  log "Installing and configuring Nextcloud..."
  ensure_nextcloud_installed
  install_nextcloud_tls_ca
  configure_nextcloud_base_url

  log "Configuring Nextcloud OIDC provider..."
  configure_nextcloud_oidc

  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
