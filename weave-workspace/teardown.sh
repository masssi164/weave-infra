#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
readonly INFRA_DIR="${ROOT_DIR}/01-infrastructure"
readonly KEYCLOAK_DIR="${ROOT_DIR}/02-keycloak-setup"
readonly BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
readonly RUNNER_BOOTSTRAP_ENV_FILE="/tmp/weave-infra/weave-workspace/.generated/bootstrap.env"
readonly WEAVE_CONTAINERS=(
  weave-proxy
  weave-keycloak
  weave-backend
  weave-mas
  weave-synapse
  weave-nextcloud
  weave-db
)
readonly WEAVE_VOLUMES=(
  weave_caddy_data
  weave_caddy_config
  weave_db_data
  weave_keycloak_data
  weave_nextcloud_data
  weave_synapse_data
)
readonly DESTRUCTIVE_DATA_DOMAINS=(
  "Keycloak identity/session data"
  "Weave backend service data stored in Postgres"
  "Matrix/Synapse database and media state"
  "Nextcloud database, files, and calendar data"
  "Shared Postgres service databases"
  "Caddy/TLS state stored in Docker volumes"
)
readonly BACKUP_GUIDANCE="docs/operator-runbook.md#5-backup-expectations"
readonly LEGACY_CONFIRMATION="weave-delete-local-data"

log() {
  printf '%s\n' "$*"
}

dry_run_enabled() {
  [[ "${WEAVE_TEARDOWN_DRY_RUN:-false}" == "true" ]]
}

required_destructive_confirmation() {
  printf '%s' "${TF_VAR_tenant_slug:-weave}"
}

terraform_destroy() {
  local dir="$1"

  if [[ ! -d "${dir}" ]]; then
    return
  fi

  if dry_run_enabled; then
    log "DRY RUN: would run terraform destroy in ${dir}"
    return
  fi

  terraform -chdir="${dir}" init -input=false >/dev/null 2>&1 || true
  terraform -chdir="${dir}" destroy -refresh=false -input=false -auto-approve || true
}

remove_container() {
  local name="$1"

  if dry_run_enabled; then
    log "DRY RUN: would remove container ${name}"
    return
  fi

  if docker container inspect "${name}" >/dev/null 2>&1; then
    log "Removing container ${name}"
    docker rm -f -v "${name}" >/dev/null 2>&1 || true
  fi
}

remove_volume() {
  local name="$1"

  if dry_run_enabled; then
    log "DRY RUN: would remove volume ${name}"
    return
  fi

  if docker volume inspect "${name}" >/dev/null 2>&1; then
    log "Removing volume ${name}"
    docker volume rm -f "${name}" >/dev/null 2>&1 || true
  fi
}

remove_network() {
  local network_name="${TF_VAR_docker_network_name:-weave_network}"

  if dry_run_enabled; then
    log "DRY RUN: would remove network ${network_name}"
    return
  fi

  if docker network inspect "${network_name}" >/dev/null 2>&1; then
    log "Removing network ${network_name}"
    docker network rm "${network_name}" >/dev/null 2>&1 || true
  fi
}

print_destructive_reset_scope() {
  local required_confirmation
  required_confirmation="$(required_destructive_confirmation)"

  cat >&2 <<EOF
Destructive Weave local/dev reset requested.

Before deleting persistent data, read backup/restore guidance:
  ${BACKUP_GUIDANCE}

Affected data domains:
EOF

  local domain
  for domain in "${DESTRUCTIVE_DATA_DOMAINS[@]}"; do
    printf '  - %s\n' "${domain}" >&2
  done

  cat >&2 <<EOF

Docker volumes scheduled for deletion:
EOF

  local volume
  for volume in "${WEAVE_VOLUMES[@]}"; do
    printf '  - %s\n' "${volume}" >&2
  done

  cat >&2 <<EOF

Generated local secrets/config in .generated/ are not removed by this helper;
back them up separately before deleting them manually.

Required confirmation:
  WEAVE_REMOVE_VOLUMES=true
  WEAVE_CONFIRM_DESTRUCTIVE_RESET=${required_confirmation}
EOF
}

confirm_volume_removal() {
  local required_confirmation
  required_confirmation="$(required_destructive_confirmation)"

  if [[ "${WEAVE_REMOVE_VOLUMES:-false}" != "true" ]]; then
    log "Persistent Docker volumes: preserved. Set WEAVE_REMOVE_VOLUMES=true plus WEAVE_CONFIRM_DESTRUCTIVE_RESET=${required_confirmation} only after taking a backup."
    return 1
  fi

  print_destructive_reset_scope

  if [[ "${WEAVE_CONFIRM_REMOVE_VOLUMES:-}" == "${LEGACY_CONFIRMATION}" && -z "${WEAVE_CONFIRM_DESTRUCTIVE_RESET:-}" ]]; then
    cat >&2 <<EOF

Refusing to remove persistent Weave Docker volumes: the old
WEAVE_CONFIRM_REMOVE_VOLUMES=${LEGACY_CONFIRMATION} confirmation is no longer
accepted. Type the tenant/workspace slug instead.
EOF
    exit 2
  fi

  if [[ "${WEAVE_CONFIRM_DESTRUCTIVE_RESET:-}" == "${required_confirmation}" ]]; then
    log "Destructive reset confirmed for tenant/workspace slug '${required_confirmation}'."
    return 0
  fi

  cat >&2 <<EOF

Refusing to remove persistent Weave Docker volumes without the typed tenant/workspace confirmation.

Container/network cleanup is safe by default and has already been requested. To
also delete local data volumes, rerun with both:

  WEAVE_REMOVE_VOLUMES=true
  WEAVE_CONFIRM_DESTRUCTIVE_RESET=${required_confirmation}

Do not run the destructive form until the backup guidance above has been reviewed.
EOF
  exit 2
}

load_bootstrap_env() {
  local env_file=""

  if [[ -f "${BOOTSTRAP_ENV_FILE}" ]]; then
    env_file="${BOOTSTRAP_ENV_FILE}"
  elif [[ -f "${RUNNER_BOOTSTRAP_ENV_FILE}" ]]; then
    env_file="${RUNNER_BOOTSTRAP_ENV_FILE}"
  fi

  if [[ -n "${env_file}" ]]; then
    # shellcheck disable=SC1090
    source "${env_file}"
  fi
}

require_runtime_commands() {
  if dry_run_enabled; then
    return
  fi

  command -v docker >/dev/null 2>&1 || {
    printf 'Missing required command: docker\n' >&2
    exit 1
  }

  command -v terraform >/dev/null 2>&1 || {
    printf 'Missing required command: terraform\n' >&2
    exit 1
  }
}

main() {
  require_runtime_commands
  load_bootstrap_env

  if [[ "${WEAVE_TERRAFORM_DESTROY:-false}" == "true" ]]; then
    terraform_destroy "${KEYCLOAK_DIR}"
    terraform_destroy "${INFRA_DIR}"
  fi

  local container
  for container in "${WEAVE_CONTAINERS[@]}"; do
    remove_container "${container}"
  done

  remove_network

  if confirm_volume_removal; then
    local volume
    for volume in "${WEAVE_VOLUMES[@]}"; do
      remove_volume "${volume}"
    done
  fi
}

main "$@"
