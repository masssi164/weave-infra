#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
readonly INFRA_DIR="${ROOT_DIR}/01-infrastructure"
readonly KEYCLOAK_DIR="${ROOT_DIR}/02-keycloak-setup"
readonly BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
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

log() {
  printf '%s\n' "$*"
}

terraform_destroy() {
  local dir="$1"

  if [[ ! -d "${dir}" ]]; then
    return
  fi

  terraform -chdir="${dir}" init -input=false >/dev/null 2>&1 || true
  terraform -chdir="${dir}" destroy -refresh=false -input=false -auto-approve || true
}

remove_container() {
  local name="$1"

  if docker container inspect "${name}" >/dev/null 2>&1; then
    log "Removing container ${name}"
    docker rm -f -v "${name}" >/dev/null 2>&1 || true
  fi
}

remove_volume() {
  local name="$1"

  if docker volume inspect "${name}" >/dev/null 2>&1; then
    log "Removing volume ${name}"
    docker volume rm -f "${name}" >/dev/null 2>&1 || true
  fi
}

remove_network() {
  local network_name="${TF_VAR_docker_network_name:-weave_network}"

  if docker network inspect "${network_name}" >/dev/null 2>&1; then
    log "Removing network ${network_name}"
    docker network rm "${network_name}" >/dev/null 2>&1 || true
  fi
}

main() {
  command -v docker >/dev/null 2>&1 || {
    printf 'Missing required command: docker\n' >&2
    exit 1
  }
  command -v terraform >/dev/null 2>&1 || {
    printf 'Missing required command: terraform\n' >&2
    exit 1
  }

  if [[ -f "${BOOTSTRAP_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${BOOTSTRAP_ENV_FILE}"
  fi

  terraform_destroy "${KEYCLOAK_DIR}"
  terraform_destroy "${INFRA_DIR}"

  local container
  for container in "${WEAVE_CONTAINERS[@]}"; do
    remove_container "${container}"
  done

  remove_network

  if [[ "${WEAVE_REMOVE_VOLUMES:-false}" == "true" ]]; then
    local volume
    for volume in "${WEAVE_VOLUMES[@]}"; do
      remove_volume "${volume}"
    done
  fi
}

main "$@"
