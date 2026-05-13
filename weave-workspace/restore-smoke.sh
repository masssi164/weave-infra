#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
REPROVISION_MATRIX="${WEAVE_RESTORE_SMOKE_REPROVISION_MATRIX:-false}"

log() {
  printf '%s\n' "$*"
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: bash weave-workspace/restore-smoke.sh [backup-dir]

Verifies a stack after an operator restore or clean reprovisioning rehearsal.
This script does not restore data and never deletes volumes. It checks the same
minimum recovery contract that issue #36 requires: backend readiness, Keycloak
discovery, Matrix client versions and MAS discovery, default Matrix room aliases,
and raw Nextcloud readiness.

Arguments:
  backup-dir  Optional directory created by backup.sh. When provided, restore-smoke
              checks that the expected backup artifacts are present before probing
              the running stack.

Environment:
  WEAVE_RESTORE_SMOKE_REPROVISION_MATRIX=true  Re-run the idempotent Matrix default
                                               workspace provisioner before checks.
USAGE
}

require_artifact() {
  local backup_dir="$1"
  local name="$2"
  [[ -s "${backup_dir}/${name}" ]] || fail "Backup artifact is missing or empty: ${backup_dir}/${name}"
}

check_backup_dir() {
  local backup_dir="$1"

  [[ -d "${backup_dir}" ]] || fail "Backup directory not found: ${backup_dir}"
  require_artifact "${backup_dir}" MANIFEST.txt
  require_artifact "${backup_dir}" postgres.sql
  require_artifact "${backup_dir}" nextcloud-data.tgz
  require_artifact "${backup_dir}" matrix-synapse-data.tgz
  require_artifact "${backup_dir}" caddy-data.tgz
  require_artifact "${backup_dir}" caddy-config.tgz
  require_artifact "${backup_dir}" keycloak-data.tgz
  require_artifact "${backup_dir}" generated-config-secrets.tgz

  log "Backup artifact presence check passed for ${backup_dir}"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  local backup_dir="${1:-}"
  if [[ -n "${backup_dir}" ]]; then
    check_backup_dir "${backup_dir}"
  fi

  if [[ "${REPROVISION_MATRIX}" == "true" ]]; then
    log "Re-running idempotent Matrix default workspace provisioner before restore smoke..."
    bash "${ROOT_DIR}/provision-matrix-default-workspace.sh"
  fi

  log "Running recovery readiness checks with operator-check.sh..."
  bash "${ROOT_DIR}/operator-check.sh"

  log "Restore smoke passed: backend, Keycloak, Matrix/MAS, default Matrix rooms, and raw Nextcloud checks are healthy."
}

main "$@"
