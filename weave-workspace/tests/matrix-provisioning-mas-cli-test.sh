#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROVISIONER="${ROOT_DIR}/provision-matrix-default-workspace.sh"
PROVISIONER_CODE="$(grep -v '^[[:space:]]*#' "${PROVISIONER}")"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

if grep -q '_synapse/admin/v1/register' <<<"${PROVISIONER_CODE}"; then
  fail "Matrix provisioner must not call Synapse shared-secret admin registration on the MAS delegated-auth stack."
fi

grep -q 'manage register-user' <<<"${PROVISIONER_CODE}" || fail "Matrix provisioner should register provisioning users through MAS CLI."
grep -q 'manage issue-compatibility-token' <<<"${PROVISIONER_CODE}" || fail "Matrix provisioner should issue MAS compatibility tokens for Matrix client API provisioning."
grep -q 'WEAVE_MATRIX_MAS_CONTAINER_NAME' <<<"${PROVISIONER_CODE}" || fail "Matrix provisioner should expose an actionable MAS container preflight."

if grep -q -- '--username\|--device-id' <<<"${PROVISIONER_CODE}"; then
  fail "Matrix provisioner should use the MAS 1.15 CLI positional username/device arguments."
fi

if grep -q 'manage set-password\|--password\|--ignore-password-complexity\|--ignore-complexity' <<<"${PROVISIONER_CODE}"; then
  fail "Matrix provisioner must not use MAS password commands because generated MAS config disables password authentication."
fi

# shellcheck disable=SC1090,SC1091
source "${PROVISIONER}"
parsed_token="$(printf '%s\n' 'INFO Compatibility token issued: mct_sample compat_session.id=123' | extract_mas_compatibility_token)"
[[ "${parsed_token}" == "mct_sample" ]] || fail "Matrix provisioner should parse MAS compatibility-token CLI output without printing secrets."

run_register_flow() {
  local mode="$1"
  local expected_token="$2"
  local calls_file token

  calls_file="$(mktemp)"

  # shellcheck disable=SC2329 # register_matrix_user invokes this mock indirectly.
  mas_cli() {
    printf '%s\n' "$*" >>"${calls_file}"
    case "$1 $2" in
      'manage register-user')
        case "${mode}" in
          fresh)
            printf '%s\n' 'User registered'
            return 0
            ;;
          existing)
            printf '%s\n' 'Error: User already exists'
            return 1
            ;;
          broken)
            printf '%s\n' 'Error: password manager is disabled'
            return 1
            ;;
        esac
        ;;
      'manage promote-admin'|'manage demote-admin')
        printf '%s\n' 'Admin policy reconciled'
        return 0
        ;;
      'manage issue-compatibility-token')
        printf 'Compatibility token issued: %s\n' "${expected_token}"
        return 0
        ;;
    esac

    printf 'Unexpected MAS CLI call: %s\n' "$*" >&2
    return 1
  }

  token="$(register_matrix_user '@admin:matrix.weave.local' true)"
  [[ "${token}" == "${expected_token}" ]] || fail "Matrix provisioner should return the compatibility token from MAS CLI."

  if grep -q -- '--password\|set-password\|@admin:matrix.weave.local' "${calls_file}"; then
    fail "Matrix provisioner should call MAS with password-free username/localpart semantics."
  fi

  if [[ "${mode}" == "fresh" ]] && grep -q 'promote-admin' "${calls_file}"; then
    fail "Matrix provisioner should trust --admin on a fresh MAS user instead of promoting a user that was not created."
  fi

  if [[ "${mode}" == "existing" ]] && ! grep -q 'promote-admin admin' "${calls_file}"; then
    fail "Matrix provisioner should reconcile admin policy for existing MAS users on idempotent reruns."
  fi

  rm -f -- "${calls_file}"
}

run_register_flow fresh mct_fresh
run_register_flow existing mct_existing

# shellcheck disable=SC2329 # register_matrix_user invokes this mock indirectly.
mas_cli() {
  if [[ "$1 $2" == 'manage register-user' ]]; then
    printf '%s\n' 'Error: password manager is disabled'
    return 1
  fi

  printf 'Unexpected MAS CLI call after failed registration: %s\n' "$*" >&2
  return 1
}

if (register_matrix_user broken true) >/tmp/weave-mas-broken.out 2>/tmp/weave-mas-broken.err; then
  fail "Matrix provisioner should fail immediately when MAS registration fails for a reason other than an existing user."
fi
grep -q 'could not register MAS user' /tmp/weave-mas-broken.err || fail "Matrix provisioner should report the MAS registration failure instead of cascading into User not found."
rm -f /tmp/weave-mas-broken.out /tmp/weave-mas-broken.err

printf '%s\n' "Matrix provisioning MAS CLI contract test passed."
