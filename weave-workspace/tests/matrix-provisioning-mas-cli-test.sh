#!/usr/bin/env bash
# shellcheck shell=bash
# Mocked functions in this contract test are invoked indirectly by sourced production functions.
# shellcheck disable=SC2317

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

if grep -q '/invite' <<<"${PROVISIONER_CODE}"; then
  fail "Matrix provisioner should avoid the heavily rate-limited invite endpoint for local smoke-test member joins."
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

run_token_validation_flow() {
  bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090,SC1091
    source "$1"
    calls_file="$(mktemp)"
    MATRIX_HOMESERVER_NAME=matrix.weave.local
    WEAVE_MATRIX_TOKEN_VALIDATION_ATTEMPTS=1
    token_var=STALE_MATRIX_TOKEN
    export STALE_MATRIX_TOKEN=mct_stale

    validate_token() {
      printf "validate %s %s\n" "$1" "$2" >>"${calls_file}"
      [[ "$1" == "mct_replacement" && "$2" == "@admin:matrix.weave.local" ]]
    }

    register_matrix_user() {
      printf "register %s %s\n" "$1" "$2" >>"${calls_file}"
      printf "%s\n" "mct_replacement"
    }

    upsert_bootstrap_var() {
      printf "upsert %s\n" "$1" >>"${calls_file}"
    }

    ensure_matrix_user_token "@admin:matrix.weave.local" "${token_var}" true
    [[ "${STALE_MATRIX_TOKEN}" == "mct_replacement" ]] || fail "Matrix provisioner should replace persisted compatibility tokens that Synapse rejects."
    grep -q "validate mct_stale @admin:matrix.weave.local" "${calls_file}" || fail "Matrix provisioner should validate persisted tokens with Synapse whoami."
    grep -q "validate mct_replacement @admin:matrix.weave.local" "${calls_file}" || fail "Matrix provisioner should validate newly-issued MAS compatibility tokens before Matrix room creation."
    grep -q "upsert STALE_MATRIX_TOKEN" "${calls_file}" || fail "Matrix provisioner should persist the validated replacement compatibility token."

    rm -f -- "${calls_file}"
  ' _ "${PROVISIONER}"
}

run_token_validation_flow

MATRIX_HOMESERVER_NAME=matrix.weave.local \
WEAVE_MATRIX_TOKEN_VALIDATION_ATTEMPTS=1 \
WEAVE_MATRIX_TOKEN_VALIDATION_DELAY_SECONDS=0 \
bash -c '
  set -euo pipefail
  # shellcheck disable=SC1090,SC1091
  source "$1"
  validate_token() { return 1; }
  register_matrix_user() { printf "%s\n" mct_invalid; }
  upsert_bootstrap_var() { :; }
  ensure_matrix_user_token admin INVALID_MATRIX_TOKEN true
' _ "${PROVISIONER}" >/tmp/weave-mas-invalid-token.out 2>/tmp/weave-mas-invalid-token.err && \
  fail "Matrix provisioner should fail before room creation when Synapse rejects a freshly issued MAS compatibility token."
grep -q 'rejected by Synapse whoami' /tmp/weave-mas-invalid-token.err || fail "Matrix provisioner should surface a token-validation error instead of a later Matrix API 401."
rm -f /tmp/weave-mas-invalid-token.out /tmp/weave-mas-invalid-token.err

run_matrix_api_retry_flow() {
  bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090,SC1091
    source "$1"
    calls_file="$(mktemp)"
    MATRIX_INTERNAL_URL=http://127.0.0.1:48008
    WEAVE_MATRIX_API_RETRY_ATTEMPTS=2
    WEAVE_MATRIX_API_RETRY_DELAY_SECONDS=0

    api_request_once() {
      printf "call\n" >>"${calls_file}"
      if [[ "$(wc -l <"${calls_file}" | tr -d " ")" == "1" ]]; then
        printf "%s\n" "429"
      else
        printf "%s\n" "200"
      fi
    }

    status="$(api_request GET /_matrix/client/v3/account/whoami mct_token "" /tmp/weave-matrix-api-retry.json)"
    [[ "${status}" == "200" ]] || fail "Matrix provisioner should retry transient Matrix API 429 responses."
    [[ "$(wc -l <"${calls_file}" | tr -d " ")" == "2" ]] || fail "Matrix provisioner should retry Matrix API requests exactly when rate-limited."

    rm -f -- "${calls_file}" /tmp/weave-matrix-api-retry.json
  ' _ "${PROVISIONER}"
}

run_matrix_api_retry_flow

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
