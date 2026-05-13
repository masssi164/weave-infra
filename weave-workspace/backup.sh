#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
DEFAULT_OUTPUT_DIR="${ROOT_DIR}/.generated/backups"
BACKUP_OUTPUT_DIR="${WEAVE_BACKUP_DIR:-${DEFAULT_OUTPUT_DIR}}"
HELPER_IMAGE="${WEAVE_BACKUP_HELPER_IMAGE:-alpine:3.20}"
CREATED_AT="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_BASENAME="weave-backup-${CREATED_AT}"
BACKUP_DIR=""

readonly VOLUME_BACKUPS=(
  "weave_nextcloud_data:nextcloud-data.tgz:Nextcloud files/calendar application data"
  "weave_synapse_data:matrix-synapse-data.tgz:Matrix/Synapse media and local data"
  "weave_caddy_data:caddy-data.tgz:Caddy ACME/TLS runtime data"
  "weave_caddy_config:caddy-config.tgz:Caddy runtime config"
  "weave_keycloak_data:keycloak-data.tgz:Keycloak container-side runtime data"
)

log() {
  printf '%s\n' "$*"
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage: bash weave-workspace/backup.sh [output-dir]

Creates a Release 1 backup artifact set for operator-managed restore rehearsals.
The output contains secrets and production data. It is not a support bundle and must
not be attached to issues or shared with support.

Environment:
  WEAVE_BACKUP_DIR           Output parent directory (default: .generated/backups)
  WEAVE_BACKUP_HELPER_IMAGE  Container image used for read-only volume archives (default: alpine:3.20)
USAGE
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

require_container_running() {
  local name="$1"
  local state

  state="$(docker inspect --format '{{.State.Status}}' "${name}" 2>/dev/null || true)"
  [[ "${state}" == "running" ]] || fail "Required container is not running: ${name}"
}

require_volume() {
  local name="$1"
  docker volume inspect "${name}" >/dev/null 2>&1 || fail "Required Docker volume not found: ${name}"
}

write_manifest_header() {
  cat >"${BACKUP_DIR}/MANIFEST.txt" <<MSG
Weave Release 1 backup
Created UTC: ${CREATED_AT}

SECURITY: This directory contains secrets and user/workspace data. Keep it encrypted
or operator-readable only. Do not attach these artifacts to GitHub issues or support
requests. Use support-bundle.sh for redacted diagnostics.

Restore smoke after a restore or reprovisioning rehearsal:
  bash weave-workspace/restore-smoke.sh ${BACKUP_DIR}

Artifacts:
MSG
}

append_manifest() {
  printf -- '- %s: %s\n' "$1" "$2" >>"${BACKUP_DIR}/MANIFEST.txt"
}

backup_postgres() {
  local db_user="${TF_VAR_db_admin_username:-weave_admin}"
  local db_password="${TF_VAR_db_admin_password:-}"
  local target="${BACKUP_DIR}/postgres.sql"

  [[ -n "${db_password}" ]] || fail "TF_VAR_db_admin_password is required; run install.sh first or provide the generated bootstrap env."
  require_container_running weave-db

  log "Backing up PostgreSQL service databases to postgres.sql"
  docker exec -e "PGPASSWORD=${db_password}" weave-db pg_dumpall -U "${db_user}" >"${target}"
  append_manifest "postgres.sql" "PostgreSQL dump for Keycloak, MAS, Synapse, Nextcloud, and Weave backend service databases"
}

backup_volume() {
  local volume="$1"
  local archive_name="$2"
  local description="$3"

  require_volume "${volume}"
  log "Archiving Docker volume ${volume} to ${archive_name}"
  docker run --rm \
    -v "${volume}:/source:ro" \
    -v "${BACKUP_DIR}:/backup" \
    "${HELPER_IMAGE}" \
    sh -c "tar -C /source -czf /backup/${archive_name} ."
  append_manifest "${archive_name}" "${description} from Docker volume ${volume}"
}

backup_generated_config() {
  local -a generated_paths=()
  local target="${BACKUP_DIR}/generated-config-secrets.tgz"

  [[ -f "${ROOT_DIR}/.generated/bootstrap.env" ]] && generated_paths+=(".generated/bootstrap.env")
  [[ -f "${ROOT_DIR}/.generated/app-config.env" ]] && generated_paths+=(".generated/app-config.env")
  [[ -d "${ROOT_DIR}/.generated/tls" ]] && generated_paths+=(".generated/tls")
  [[ -d "${ROOT_DIR}/01-infrastructure/.generated" ]] && generated_paths+=("01-infrastructure/.generated")
  [[ -d "${ROOT_DIR}/02-keycloak-setup/.generated" ]] && generated_paths+=("02-keycloak-setup/.generated")

  ((${#generated_paths[@]} > 0)) || fail "No generated config/secrets were found under weave-workspace/.generated or Terraform stage .generated directories."

  log "Archiving generated config/secrets metadata to generated-config-secrets.tgz"
  tar -C "${ROOT_DIR}" -czf "${target}" "${generated_paths[@]}"
  append_manifest "generated-config-secrets.tgz" "Generated bootstrap env, no-secret app config, TLS material, and generated Terraform service config needed for restore/reprovisioning"
}

create_backup() {
  local output_dir="$1"
  umask 077
  mkdir -p "${output_dir}"
  BACKUP_DIR="${output_dir}/${BACKUP_BASENAME}"
  mkdir -p "${BACKUP_DIR}"

  write_manifest_header
  backup_postgres

  local entry
  for entry in "${VOLUME_BACKUPS[@]}"; do
    IFS=: read -r volume archive description <<<"${entry}"
    backup_volume "${volume}" "${archive}" "${description}"
  done

  backup_generated_config

  cat >>"${BACKUP_DIR}/MANIFEST.txt" <<MSG

Notes:
- This backup intentionally uses pg_dumpall for PostgreSQL-backed service data instead
  of copying the live postgres data volume.
- Matrix room/event state is in postgres.sql; Matrix media/local files are in
  matrix-synapse-data.tgz.
- Nextcloud metadata is in postgres.sql; file/calendar application data is in
  nextcloud-data.tgz.
- Caddy artifacts are included for ACME/TLS continuity when applicable.
- Generated config/secrets are included because restore/reprovisioning may need them;
  keep this backup private.
MSG

  log "Backup written to ${BACKUP_DIR}"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  require_command docker
  require_command tar
  load_bootstrap_env

  local output_dir="${1:-${BACKUP_OUTPUT_DIR}}"
  create_backup "${output_dir}"
}

main "$@"
