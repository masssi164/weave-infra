#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
DEFAULT_OUTPUT_DIR="${ROOT_DIR}/.generated/support-bundles"
SUPPORT_BUNDLE_OUTPUT_DIR="${WEAVE_SUPPORT_BUNDLE_DIR:-${DEFAULT_OUTPUT_DIR}}"
TAIL_LINES="${WEAVE_SUPPORT_BUNDLE_LOG_LINES:-200}"
RUN_CHECKS="${WEAVE_SUPPORT_BUNDLE_RUN_CHECKS:-false}"
CREATED_AT="$(date -u +%Y%m%dT%H%M%SZ)"
BUNDLE_BASENAME="weave-support-${CREATED_AT}"
WORK_DIR=""

readonly DEFAULT_CONTAINERS=(
  weave-proxy
  weave-keycloak
  weave-backend
  weave-mas
  weave-synapse
  weave-nextcloud
  weave-db
)

readonly PUBLIC_ENV_KEYS=(
  TF_VAR_tenant_domain
  TF_VAR_tenant_slug
  TF_VAR_public_scheme
  TF_VAR_auth_subdomain
  TF_VAR_api_subdomain
  TF_VAR_matrix_subdomain
  TF_VAR_nextcloud_subdomain
  TF_VAR_proxy_host_port
  TF_VAR_backend_host_port
  TF_VAR_keycloak_management_host_port
  TF_VAR_mas_host_port
  TF_VAR_synapse_host_port
  TF_VAR_weave_backend_image
  TF_VAR_synapse_image
  TF_VAR_mas_image
  TF_VAR_create_test_user
  WEAVE_PUBLIC_BASE_URL
  WEAVE_API_BASE_URL
  WEAVE_BASE_URL
  WEAVE_AUTH_BASE_URL
  WEAVE_OIDC_ISSUER_URL
  WEAVE_OIDC_CLIENT_ID
  WEAVE_NEXTCLOUD_BASE_URL
  WEAVE_MATRIX_HOMESERVER_URL
  WEAVE_TLS_CA_FILE
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
Usage: bash weave-workspace/support-bundle.sh [output-dir]

Creates a redacted support bundle for Release 1 diagnostics.
The bundle is a triage artifact, not a backup.

Environment:
  WEAVE_SUPPORT_BUNDLE_DIR         Output directory (default: .generated/support-bundles)
  WEAVE_SUPPORT_BUNDLE_LOG_LINES   Docker log tail per service (default: 200)
  WEAVE_SUPPORT_BUNDLE_RUN_CHECKS  true to run operator-check and release-verify (default: false)
USAGE
}

cleanup() {
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

redact_stream() {
  perl -0pe '
    s/-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----/<redacted-private-key>/gs;
    s/(Authorization:\s*)(Bearer|Basic)\s+[^\r\n]+/${1}<redacted>/gi;
    s/((?:Set-)?Cookie:\s*)[^\r\n]+/${1}<redacted>/gi;
    s/((?:password|passwd|token|secret|private[_-]?key|signing[_-]?key|credential|authorization|cookie)\s*[=:]\s*)([^\s\r\n"'"'"']+)/${1}<redacted>/gi;
    s/("(?:password|passwd|token|secret|privateKey|signingKey|credential|authorization|cookie)"\s*:\s*")[^"]+/${1}<redacted>/gi;
  '
}

scan_for_unredacted_secrets() {
  local path="$1"
  local findings=""

  findings="$(grep -RInE \
    'BEGIN (RSA |EC |OPENSSH |)?PRIVATE KEY|Authorization:[[:space:]]+(Bearer|Basic)[[:space:]]+[^<[:space:]]|Cookie:[[:space:]]+[^<[:space:]]|Set-Cookie:[[:space:]]+[^<[:space:]]|([A-Za-z0-9_]*(PASSWORD|TOKEN|SECRET|PRIVATE_KEY|SIGNING_KEY|CREDENTIAL)[A-Za-z0-9_]*[=:][[:space:]]*[^<[:space:]]+)' \
    "${path}" 2>/dev/null || true)"

  if [[ -n "${findings}" ]]; then
    printf 'Support bundle redaction check failed. Possible secret material remains:\n%s\n' "${findings}" >&2
    return 1
  fi
}

write_text_file() {
  local relative_path="$1"
  local target="${WORK_DIR}/${relative_path}"
  mkdir -p "$(dirname -- "${target}")"
  cat >"${target}"
}

collect_command_output() {
  local relative_path="$1"
  shift
  local target="${WORK_DIR}/${relative_path}"
  mkdir -p "$(dirname -- "${target}")"

  {
    printf '$'
    local arg
    for arg in "$@"; do
      printf ' %q' "${arg}"
    done
    printf '\n\n'
    set +e
    "$@"
    local status=$?
    set -e
    printf '\n[exit status: %s]\n' "${status}"
  } 2>&1 | redact_stream >"${target}"
}

collect_if_command_exists() {
  local command_name="$1"
  local relative_path="$2"
  shift 2

  if command -v "${command_name}" >/dev/null 2>&1; then
    collect_command_output "${relative_path}" "$@"
  else
    write_text_file "${relative_path}" <<MSG
Skipped: missing command ${command_name}
MSG
  fi
}

collect_public_env_from_file() {
  local source_file="$1"
  local target_file="$2"
  local key

  if [[ ! -f "${source_file}" ]]; then
    printf 'Skipped: file not found: %s\n' "${source_file}" >>"${target_file}"
    return
  fi

  printf '# %s\n' "${source_file}" >>"${target_file}"
  for key in "${PUBLIC_ENV_KEYS[@]}"; do
    grep -E "^(export[[:space:]]+)?${key}=" "${source_file}" >>"${target_file}" || true
  done
  printf '\n' >>"${target_file}"
}

collect_public_env() {
  local target="${WORK_DIR}/config/public-env-summary.env"
  mkdir -p "$(dirname -- "${target}")"
  : >"${target}"

  collect_public_env_from_file "${ROOT_DIR}/.generated/bootstrap.env" "${target}"
  collect_public_env_from_file "${ROOT_DIR}/.generated/app-config.env" "${target}"

  {
    printf '# current process public env\n'
    local key
    for key in "${PUBLIC_ENV_KEYS[@]}"; do
      if [[ -n "${!key:-}" ]]; then
        printf '%s=%q\n' "${key}" "${!key}"
      fi
    done
  } >>"${target}"

  redact_stream <"${target}" >"${target}.redacted"
  mv "${target}.redacted" "${target}"
}

collect_recent_artifacts() {
  local target_dir="${WORK_DIR}/recent-artifacts"
  mkdir -p "${target_dir}"

  if [[ ! -d "${ROOT_DIR}/.generated" ]]; then
    printf 'Skipped: no .generated directory exists.\n' >"${target_dir}/README.txt"
    return
  fi

  find "${ROOT_DIR}/.generated" -maxdepth 2 -type f \
    \( -iname '*smoke*.log' -o -iname '*smoke*.txt' -o -iname '*operator*.log' -o -iname '*operator*.txt' -o -iname '*verify*.log' -o -iname '*verify*.txt' \) \
    -print0 | while IFS= read -r -d '' artifact; do
      local name
      name="$(basename -- "${artifact}")"
      redact_stream <"${artifact}" >"${target_dir}/${name}"
    done

  if [[ -z "$(find "${target_dir}" -type f ! -name README.txt -print -quit)" ]]; then
    printf 'No recent smoke/operator/release-verify text artifacts were found under .generated.\n' >"${target_dir}/README.txt"
  fi
}

collect_logs() {
  local container
  mkdir -p "${WORK_DIR}/logs"

  if ! command -v docker >/dev/null 2>&1; then
    printf 'Skipped: missing command docker\n' >"${WORK_DIR}/logs/README.txt"
    return
  fi

  for container in "${DEFAULT_CONTAINERS[@]}"; do
    collect_command_output "logs/${container}.log" docker logs --tail "${TAIL_LINES}" "${container}"
  done
}

collect_optional_checks() {
  mkdir -p "${WORK_DIR}/checks"

  if [[ "${RUN_CHECKS}" != "true" ]]; then
    cat >"${WORK_DIR}/checks/README.txt" <<MSG
operator-check.sh and release-verify.sh were not run.
Set WEAVE_SUPPORT_BUNDLE_RUN_CHECKS=true to include fresh check output in the bundle.
MSG
    return
  fi

  collect_command_output "checks/operator-check.txt" bash "${ROOT_DIR}/operator-check.sh"
  collect_command_output "checks/release-verify.txt" bash "${ROOT_DIR}/release-verify.sh"
}

create_bundle() {
  local output_dir="$1"
  mkdir -p "${output_dir}"
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${BUNDLE_BASENAME}.XXXXXX")"
  mkdir -p "${WORK_DIR}"

  cat >"${WORK_DIR}/README.txt" <<MSG
Weave Release 1 support bundle
Created UTC: ${CREATED_AT}

This bundle is for support-safe diagnostics only. It is not a backup and cannot restore
Postgres databases, Matrix media, Nextcloud files/calendar data, Caddy ACME state, or
generated secrets. Use docs/operator-runbook.md#5-backup-expectations for backups.

Before sharing externally, review the bundle contents. The script redacts common secret
patterns and refuses obvious leftovers, but operators remain responsible for checking
site-specific logs.
MSG

  collect_public_env
  collect_if_command_exists uname host/uname.txt uname -a
  collect_if_command_exists df host/disk.txt df -h
  collect_if_command_exists docker docker/containers.txt docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}'
  collect_if_command_exists docker docker/volumes.txt docker volume ls
  collect_if_command_exists docker docker/system-df.txt docker system df
  collect_logs
  collect_optional_checks
  collect_recent_artifacts

  scan_for_unredacted_secrets "${WORK_DIR}"

  local archive="${output_dir}/${BUNDLE_BASENAME}.tar.gz"
  tar -C "$(dirname -- "${WORK_DIR}")" -czf "${archive}" "$(basename -- "${WORK_DIR}")"
  log "Support bundle written to ${archive}"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ "${TAIL_LINES}" =~ ^[0-9]+$ ]]; then
    :
  else
    fail "WEAVE_SUPPORT_BUNDLE_LOG_LINES must be numeric"
  fi

  local output_dir="${1:-${SUPPORT_BUNDLE_OUTPUT_DIR}}"
  create_bundle "${output_dir}"
}

main "$@"
