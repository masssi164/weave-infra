#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
SCRIPT="${ROOT_DIR}/restore-smoke.sh"

backup_dir="$(mktemp -d)"
trap 'rm -rf "${backup_dir}"' EXIT

required_artifacts=(
  MANIFEST.txt
  postgres.sql
  nextcloud-data.tgz
  matrix-synapse-data.tgz
  caddy-data.tgz
  caddy-config.tgz
  keycloak-data.tgz
  generated-config-secrets.tgz
)

for artifact in "${required_artifacts[@]}"; do
  printf 'fixture for %s\n' "${artifact}" >"${backup_dir}/${artifact}"
done

output="$(WEAVE_RESTORE_SMOKE_ARTIFACTS_ONLY=true bash "${SCRIPT}" "${backup_dir}")"
[[ "${output}" == *"Backup artifact presence check passed"* ]] || {
  echo "restore-smoke did not report artifact presence success" >&2
  echo "${output}" >&2
  exit 1
}
[[ "${output}" == *"Service readiness was not checked in artifacts-only mode"* ]] || {
  echo "restore-smoke did not make artifacts-only limits explicit" >&2
  echo "${output}" >&2
  exit 1
}

rm "${backup_dir}/postgres.sql"
if WEAVE_RESTORE_SMOKE_ARTIFACTS_ONLY=true bash "${SCRIPT}" "${backup_dir}" >/tmp/restore-smoke-missing.out 2>&1; then
  echo "restore-smoke accepted a backup directory with a missing postgres.sql" >&2
  exit 1
fi
grep -Fq "Backup artifact is missing or empty" /tmp/restore-smoke-missing.out || {
  echo "restore-smoke missing-artifact failure was not actionable" >&2
  cat /tmp/restore-smoke-missing.out >&2
  exit 1
}

printf 'restore smoke artifact tests passed\n'
