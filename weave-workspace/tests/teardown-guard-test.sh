#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly TEARDOWN_SCRIPT="${ROOT_DIR}/teardown.sh"

run_case() {
  local name="$1"
  local expected_status="$2"
  shift 2

  local output_file
  output_file="$(mktemp)"

  set +e
  (
    cd "${ROOT_DIR}"
    env -i \
      PATH="${PATH}" \
      HOME="${HOME:-/tmp}" \
      WEAVE_TEARDOWN_DRY_RUN=true \
      TF_VAR_tenant_slug=weave \
      "$@" \
      bash "${TEARDOWN_SCRIPT}"
  ) >"${output_file}" 2>&1
  local status=$?
  set -e

  if [[ "${status}" != "${expected_status}" ]]; then
    printf 'FAIL %s: expected exit %s, got %s\n' "${name}" "${expected_status}" "${status}" >&2
    cat "${output_file}" >&2
    rm -f "${output_file}"
    exit 1
  fi

  printf '%s\n' "${output_file}"
}

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq -- "${expected}" "${file}"; then
    printf 'Expected output to contain: %s\n' "${expected}" >&2
    cat "${file}" >&2
    rm -f "${file}"
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"

  if grep -Fq -- "${unexpected}" "${file}"; then
    printf 'Expected output not to contain: %s\n' "${unexpected}" >&2
    cat "${file}" >&2
    rm -f "${file}"
    exit 1
  fi
}

main() {
  local output

  output="$(run_case "preserves volumes by default" 0)"
  assert_contains "${output}" "Persistent Docker volumes: preserved."
  assert_not_contains "${output}" "DRY RUN: would remove volume weave_synapse_data"
  rm -f "${output}"

  output="$(run_case "refuses missing confirmation" 2 WEAVE_REMOVE_VOLUMES=true)"
  assert_contains "${output}" "Refusing to remove persistent Weave Docker volumes without the typed tenant/workspace confirmation."
  assert_contains "${output}" "docs/operator-runbook.md#5-backup-expectations"
  assert_contains "${output}" "Keycloak identity/session data"
  assert_contains "${output}" "Matrix/Synapse database and media state"
  assert_contains "${output}" "Nextcloud database, files, and calendar data"
  assert_contains "${output}" "WEAVE_CONFIRM_DESTRUCTIVE_RESET=weave"
  assert_not_contains "${output}" "DRY RUN: would remove volume weave_synapse_data"
  rm -f "${output}"

  output="$(run_case "refuses legacy confirmation" 2 WEAVE_REMOVE_VOLUMES=true WEAVE_CONFIRM_REMOVE_VOLUMES=weave-delete-local-data)"
  assert_contains "${output}" "old"
  assert_contains "${output}" "WEAVE_CONFIRM_REMOVE_VOLUMES=weave-delete-local-data"
  assert_contains "${output}" "Type the tenant/workspace slug instead."
  rm -f "${output}"

  output="$(run_case "removes volumes with typed confirmation in dry-run mode" 0 WEAVE_REMOVE_VOLUMES=true WEAVE_CONFIRM_DESTRUCTIVE_RESET=weave)"
  assert_contains "${output}" "Destructive reset confirmed for tenant/workspace slug 'weave'."
  assert_contains "${output}" "DRY RUN: would remove volume weave_synapse_data"
  assert_contains "${output}" "DRY RUN: would remove volume weave_nextcloud_data"
  rm -f "${output}"

  printf 'teardown guard tests passed\n'
}

main "$@"
