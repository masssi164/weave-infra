#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROVISIONER="${ROOT_DIR}/provision-matrix-default-workspace.sh"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

if grep -q '_synapse/admin/v1/register' "${PROVISIONER}"; then
  fail "Matrix provisioner must not call Synapse shared-secret admin registration on the MAS delegated-auth stack."
fi

grep -q 'manage register-user' "${PROVISIONER}" || fail "Matrix provisioner should register provisioning users through MAS CLI."
grep -q 'manage issue-compatibility-token' "${PROVISIONER}" || fail "Matrix provisioner should issue MAS compatibility tokens for Matrix client API provisioning."
grep -q 'WEAVE_MATRIX_MAS_CONTAINER_NAME' "${PROVISIONER}" || fail "Matrix provisioner should expose an actionable MAS container preflight."

if grep -q -- '--username\|--device-id' "${PROVISIONER}"; then
  fail "Matrix provisioner should use the MAS 1.15 CLI positional username/device arguments."
fi

# shellcheck disable=SC1090,SC1091
source "${PROVISIONER}"
parsed_token="$(printf '%s\n' 'INFO Compatibility token issued: mct_sample compat_session.id=123' | extract_mas_compatibility_token)"
[[ "${parsed_token}" == "mct_sample" ]] || fail "Matrix provisioner should parse MAS compatibility-token CLI output without printing secrets."

printf '%s\n' "Matrix provisioning MAS CLI contract test passed."
