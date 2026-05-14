#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
readonly BOOTSTRAP_ENV_FILE="${ROOT_DIR}/.generated/bootstrap.env"
readonly LOOPBACK_HOST="127.0.0.1"

log() {
  printf '%s\n' "$*"
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

safe_tail() {
  local file="$1"
  tail -n 20 "${file}" 2>/dev/null | sed -E 's/(Compatibility token issued: )[[:graph:]]+/\1[redacted]/g; s/(access_token[=:] ?)[[:graph:]]+/\1[redacted]/gi; s/(token[=:] ?)[[:graph:]]+/\1[redacted]/gi; s/(password[=:] ?)[[:graph:]]+/\1[redacted]/gi'
}

load_bootstrap_env() {
  if [[ -f "${BOOTSTRAP_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${BOOTSTRAP_ENV_FILE}"
  fi
}

set_default_var() {
  local name="$1"
  local value="$2"

  if [[ -z "${!name:-}" ]]; then
    export "${name}=${value}"
  fi
}

public_port_suffix() {
  local scheme="${TF_VAR_public_scheme:-https}"
  local port="${TF_VAR_proxy_host_port:-443}"

  if [[ "${scheme}" == "http" && "${port}" == "80" ]] || [[ "${scheme}" == "https" && "${port}" == "443" ]]; then
    printf ''
    return
  fi

  printf ':%s' "${port}"
}

public_host() {
  local subdomain="$1"
  if [[ -z "${subdomain}" ]]; then
    printf '%s\n' "${TF_VAR_tenant_domain:?Expected TF_VAR_tenant_domain}"
    return
  fi
  printf '%s.%s\n' "${subdomain}" "${TF_VAR_tenant_domain:?Expected TF_VAR_tenant_domain}"
}

url_encode() {
  local value="$1"
  python3 - "$value" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=''))
PY
}

json_string() {
  local value="$1"
  python3 - "$value" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
}

json_get() {
  local filter="$1"
  python3 -c "import json,sys; data=json.load(sys.stdin); value=${filter}; print('' if value is None else value)"
}

mas_cli_username() {
  local value="$1"

  value="${value#@}"
  value="${value%%:*}"
  [[ -n "${value}" ]] || fail "Matrix provisioning failed: MAS username/localpart cannot be empty."
  printf '%s\n' "${value}"
}

matrix_user_id() {
  local localpart
  localpart="$(mas_cli_username "$1")"
  printf '@%s:%s\n' "${localpart}" "${MATRIX_HOMESERVER_NAME}"
}

upsert_bootstrap_var() {
  local name="$1"
  local value="$2"
  local tmp_file

  mkdir -p "$(dirname -- "${BOOTSTRAP_ENV_FILE}")"
  touch "${BOOTSTRAP_ENV_FILE}"
  chmod 600 "${BOOTSTRAP_ENV_FILE}"
  tmp_file="$(mktemp)"
  grep -v -E "^export[[:space:]]+${name}=" "${BOOTSTRAP_ENV_FILE}" >"${tmp_file}" || true
  printf 'export %s=%q\n' "${name}" "${value}" >>"${tmp_file}"
  cat "${tmp_file}" >"${BOOTSTRAP_ENV_FILE}"
  rm -f -- "${tmp_file}"
}

api_request_once() {
  local method="$1"
  local path="$2"
  local token="${3:-}"
  local body="${4:-}"
  local output_file="$5"
  local -a args=(--silent --show-error --output "${output_file}" --write-out '%{http_code}' -X "${method}")

  if [[ -n "${token}" ]]; then
    args+=(-H "Authorization: Bearer ${token}")
  fi
  if [[ -n "${body}" ]]; then
    args+=(-H 'Content-Type: application/json' --data "${body}")
  fi

  curl "${args[@]}" "${MATRIX_INTERNAL_URL}${path}"
}

api_request() {
  local method="$1"
  local path="$2"
  local token="${3:-}"
  local body="${4:-}"
  local output_file="$5"
  local attempts="${WEAVE_MATRIX_API_RETRY_ATTEMPTS:-6}"
  local delay="${WEAVE_MATRIX_API_RETRY_DELAY_SECONDS:-2}"
  local attempt status

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    status="$(api_request_once "${method}" "${path}" "${token}" "${body}" "${output_file}" || true)"
    case "${status}" in
      429|502|503|504)
        if ((attempt < attempts)); then
          sleep "${delay}"
          continue
        fi
        ;;
    esac

    printf '%s\n' "${status}"
    return 0
  done

  printf '%s\n' "${status:-000}"
}

mas_cli() {
  docker exec "${WEAVE_MATRIX_MAS_CONTAINER_NAME}" mas-cli --config /config/config.yaml "$@"
}

ensure_mas_cli_available() {
  require_command docker

  if ! docker inspect -f '{{.State.Running}}' "${WEAVE_MATRIX_MAS_CONTAINER_NAME}" >/dev/null 2>&1; then
    fail "Matrix provisioning failed: MAS container '${WEAVE_MATRIX_MAS_CONTAINER_NAME}' is not running. Run install.sh until Matrix Authentication Service is healthy, or set WEAVE_MATRIX_MAS_CONTAINER_NAME to the running MAS container name."
  fi

  if [[ "$(docker inspect -f '{{.State.Running}}' "${WEAVE_MATRIX_MAS_CONTAINER_NAME}" 2>/dev/null)" != "true" ]]; then
    fail "Matrix provisioning failed: MAS container '${WEAVE_MATRIX_MAS_CONTAINER_NAME}' is not running. Start the stack and rerun provision-matrix-default-workspace.sh."
  fi

  if ! docker exec "${WEAVE_MATRIX_MAS_CONTAINER_NAME}" mas-cli --config /config/config.yaml --help >/dev/null 2>&1; then
    fail "Matrix provisioning failed: MAS CLI is unavailable in container '${WEAVE_MATRIX_MAS_CONTAINER_NAME}'. The current Synapse/MAS stack requires mas-cli to register provisioning users and issue compatibility tokens; check the MAS image and config mount."
  fi
}

expect_success() {
  local status="$1"
  local description="$3"

  : "$2"
  case "${status}" in
    200|201) return 0 ;;
  esac

  fail "Matrix provisioning failed: ${description} returned HTTP ${status}"
}

validate_token() {
  local token="$1"
  local expected_user_id="$2"
  local response_file status user_id

  response_file="$(mktemp)"
  status="$(api_request GET '/_matrix/client/v3/account/whoami' "${token}" '' "${response_file}" || true)"
  if [[ "${status}" != "200" ]]; then
    rm -f -- "${response_file}"
    return 1
  fi

  user_id="$(json_get "data.get('user_id')" <"${response_file}")"
  rm -f -- "${response_file}"
  [[ "${user_id}" == "${expected_user_id}" ]]
}

wait_for_valid_token() {
  local token="$1"
  local expected_user_id="$2"
  local username="$3"

  if try_wait_for_valid_token "${token}" "${expected_user_id}"; then
    return 0
  fi

  fail "Matrix provisioning failed: MAS compatibility token for '${username}' was rejected by Synapse whoami after ${WEAVE_MATRIX_TOKEN_VALIDATION_ATTEMPTS:-12} attempt(s). Check the MAS/Synapse delegated-auth shared secret, homeserver name '${MATRIX_HOMESERVER_NAME}', and compatibility-token scopes."
}

try_wait_for_valid_token() {
  local token="$1"
  local expected_user_id="$2"
  local attempts="${WEAVE_MATRIX_TOKEN_VALIDATION_ATTEMPTS:-12}"
  local delay="${WEAVE_MATRIX_TOKEN_VALIDATION_DELAY_SECONDS:-1}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if validate_token "${token}" "${expected_user_id}"; then
      return 0
    fi

    if ((attempt < attempts)); then
      sleep "${delay}"
    fi
  done

  return 1
}

extract_mas_compatibility_token() {
  python3 -c '
import re
import sys

text = sys.stdin.read()
# MAS compatibility access tokens are either new-format mct_<30 chars>_<crc>
# tokens or legacy Synapse-style syt_* tokens. Match only token-shaped values so
# trailing log fields/punctuation do not get persisted and later fail as inactive.
token_pattern = r"(?:mct_[A-Za-z0-9]{30}_[A-Za-z0-9]{6}|syt_[^\s\"'"'"'<>]+)"
labelled = re.search(r"Compatibility token issued:\s*[\"'"'"']?(" + token_pattern + r")", text)
if labelled:
    print(labelled.group(1).rstrip(".,;:"))
    raise SystemExit(0)

matches = re.findall(token_pattern, text)
if len(matches) == 1:
    print(matches[0].rstrip(".,;:"))
    raise SystemExit(0)

raise SystemExit(1)
'
}

mas_cli_output_indicates_existing_user() {
  local file="$1"
  grep -Eiq 'user already exists|username already exists|already exists' "${file}"
}

wait_for_mas_registration_device_sync() {
  local username="$1"
  local seconds="${WEAVE_MATRIX_MAS_REGISTRATION_SETTLE_SECONDS:-3}"

  [[ "${seconds}" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "Matrix provisioning failed: WEAVE_MATRIX_MAS_REGISTRATION_SETTLE_SECONDS must be numeric."
  if [[ "${seconds}" == "0" || "${seconds}" == "0.0" ]]; then
    return 0
  fi

  # MAS registers users asynchronously in Synapse and then syncs the user's
  # device list. Issuing a compatibility token before that background sync can
  # create a Synapse device that the pending sync immediately deletes, leaving
  # Synapse to reject the fresh token as inactive. Let the fresh-user sync settle
  # before minting the token used for Matrix client API provisioning.
  log "Waiting ${seconds}s for MAS to finish Synapse user/device sync for '${username}'..." >&2
  sleep "${seconds}"
}

register_matrix_user() {
  local localpart="$1"
  local admin_flag="$2"
  local username response_file token user_existed
  local -a register_args issue_args admin_args

  username="$(mas_cli_username "${localpart}")"
  response_file="$(mktemp)"
  user_existed=false

  # MAS password authentication is intentionally disabled in the generated config.
  # The provisioning path only needs a MAS user row plus a compatibility token, so
  # do not pass --password or run set-password: MAS 1.15 rejects those operations
  # when passwords.enabled=false, leaving no user for later admin/token commands.
  register_args=(manage register-user "${username}" --yes)
  if [[ "${admin_flag}" == "true" ]]; then
    register_args+=(--admin)
    admin_args=(manage promote-admin "${username}")
    issue_args=(manage issue-compatibility-token "${username}" --yes-i-want-to-grant-synapse-admin-privileges)
  else
    register_args+=(--no-admin)
    admin_args=(manage demote-admin "${username}")
    issue_args=(manage issue-compatibility-token "${username}")
  fi

  if ! mas_cli "${register_args[@]}" >"${response_file}" 2>&1; then
    if mas_cli_output_indicates_existing_user "${response_file}"; then
      user_existed=true
    else
      fail "Matrix provisioning failed: could not register MAS user '${username}'. Last MAS CLI output: $(safe_tail "${response_file}")"
    fi
  fi

  # New users receive the requested admin flag during registration. Existing users
  # need their policy reconciled explicitly so reruns remain idempotent.
  if [[ "${admin_flag}" == "true" && "${user_existed}" == "true" ]] && ! mas_cli "${admin_args[@]}" >"${response_file}" 2>&1; then
    fail "Matrix provisioning failed: could not apply MAS admin policy for '${username}'. Last MAS CLI output: $(safe_tail "${response_file}")"
  elif [[ "${admin_flag}" != "true" && "${user_existed}" == "true" ]]; then
    mas_cli "${admin_args[@]}" >"${response_file}" 2>&1 || true
  fi

  if [[ "${user_existed}" != "true" ]]; then
    wait_for_mas_registration_device_sync "${username}"
  fi

  if ! mas_cli "${issue_args[@]}" >"${response_file}" 2>&1; then
    fail "Matrix provisioning failed: could not issue a MAS compatibility token for '${username}'. Last MAS CLI output: $(safe_tail "${response_file}")"
  fi

  token="$(extract_mas_compatibility_token <"${response_file}" || true)"
  rm -f -- "${response_file}"
  [[ -n "${token}" ]] || fail "Matrix provisioning failed: MAS CLI did not return a compatibility token for '${username}'"
  printf '%s\n' "${token}"
}

ensure_matrix_user_token() {
  local localpart="$1"
  local token_var="$2"
  local admin_flag="$3"
  local token expected_user_id issue_attempt issue_attempts

  localpart="$(mas_cli_username "${localpart}")"
  expected_user_id="$(matrix_user_id "${localpart}")"
  token="${!token_var:-}"
  if [[ -n "${token}" ]] && validate_token "${token}" "${expected_user_id}"; then
    return 0
  fi

  issue_attempts="${WEAVE_MATRIX_TOKEN_ISSUE_ATTEMPTS:-2}"
  [[ "${issue_attempts}" =~ ^[0-9]+$ && "${issue_attempts}" -gt 0 ]] || fail "Matrix provisioning failed: WEAVE_MATRIX_TOKEN_ISSUE_ATTEMPTS must be a positive integer."

  for ((issue_attempt = 1; issue_attempt <= issue_attempts; issue_attempt++)); do
    token="$(register_matrix_user "${localpart}" "${admin_flag}")"
    if try_wait_for_valid_token "${token}" "${expected_user_id}"; then
      export "${token_var}=${token}"
      upsert_bootstrap_var "${token_var}" "${token}"
      return 0
    fi

    if ((issue_attempt < issue_attempts)); then
      log "MAS compatibility token for '${localpart}' was inactive after validation; reissuing after MAS device sync settles..." >&2
      sleep "${WEAVE_MATRIX_TOKEN_VALIDATION_DELAY_SECONDS:-1}"
    fi
  done

  fail "Matrix provisioning failed: MAS compatibility token for '${localpart}' was rejected by Synapse whoami after ${WEAVE_MATRIX_TOKEN_VALIDATION_ATTEMPTS:-12} attempt(s). Check the MAS/Synapse delegated-auth shared secret, homeserver name '${MATRIX_HOMESERVER_NAME}', and compatibility-token scopes."
}

resolve_room_alias() {
  local alias="$1"
  local response_file status room_id

  response_file="$(mktemp)"
  status="$(api_request GET "/_matrix/client/v3/directory/room/$(url_encode "${alias}")" "${WEAVE_MATRIX_PROVISIONER_ACCESS_TOKEN}" '' "${response_file}" || true)"
  if [[ "${status}" == "200" ]]; then
    room_id="$(json_get "data.get('room_id')" <"${response_file}")"
    rm -f -- "${response_file}"
    printf '%s\n' "${room_id}"
    return 0
  fi
  rm -f -- "${response_file}"
  return 1
}

power_levels_json() {
  local room_kind="$1"
  local admin_user_id
  admin_user_id="$(matrix_user_id "${WEAVE_MATRIX_PROVISIONER_LOCALPART}")"
  python3 - "${room_kind}" "${admin_user_id}" <<'PY'
import json
import sys
room_kind, admin_user_id = sys.argv[1:]
content = {
    'users': {admin_user_id: 100},
    'users_default': 0,
    'state_default': 50,
    'invite': 50,
    'kick': 50,
    'ban': 50,
    'redact': 50,
}
if room_kind == 'announcements':
    content['events_default'] = 50
    content['events'] = {'m.room.message': 50}
else:
    content['events_default'] = 0
print(json.dumps(content, separators=(',', ':')))
PY
}

create_room_json() {
  local alias_localpart="$1"
  local name="$2"
  local topic="$3"
  local room_kind="$4"
  local creation_type="$5"
  local power_levels

  power_levels="$(power_levels_json "${room_kind}")"
  python3 - "${alias_localpart}" "${name}" "${topic}" "${creation_type}" "${power_levels}" <<'PY'
import json
import sys
alias_localpart, name, topic, creation_type, power_levels_raw = sys.argv[1:]
initial_state = [
    {'type': 'm.room.join_rules', 'state_key': '', 'content': {'join_rule': 'invite'}},
    {'type': 'm.room.guest_access', 'state_key': '', 'content': {'guest_access': 'forbidden'}},
    {'type': 'm.room.history_visibility', 'state_key': '', 'content': {'history_visibility': 'shared'}},
    {'type': 'm.room.power_levels', 'state_key': '', 'content': json.loads(power_levels_raw)},
]
payload = {
    'visibility': 'private',
    'room_alias_name': alias_localpart,
    'name': name,
    'topic': topic,
    'initial_state': initial_state,
}
if creation_type:
    payload['creation_content'] = {'type': creation_type}
print(json.dumps(payload, separators=(',', ':')))
PY
}

ensure_room() {
  local alias_localpart="$1"
  local name="$2"
  local topic="$3"
  local room_kind="$4"
  local creation_type="${5:-}"
  local alias room_id response_file status body state_body

  alias="#${alias_localpart}:${MATRIX_HOMESERVER_NAME}"
  if room_id="$(resolve_room_alias "${alias}")"; then
    printf '%s\n' "- Reusing ${name}: ${alias}" >&2
  else
    response_file="$(mktemp)"
    body="$(create_room_json "${alias_localpart}" "${name}" "${topic}" "${room_kind}" "${creation_type}")"
    status="$(api_request POST '/_matrix/client/v3/createRoom' "${WEAVE_MATRIX_PROVISIONER_ACCESS_TOKEN}" "${body}" "${response_file}" || true)"
    if [[ "${status}" == "200" || "${status}" == "201" ]]; then
      room_id="$(json_get "data.get('room_id')" <"${response_file}")"
      printf '%s\n' "- Created ${name}: ${alias}" >&2
    elif room_id="$(resolve_room_alias "${alias}")"; then
      printf '%s\n' "- Reusing ${name}: ${alias}" >&2
    else
      fail "Matrix provisioning failed: creating ${name} returned HTTP ${status}"
    fi
    rm -f -- "${response_file}"
  fi

  state_body="$(power_levels_json "${room_kind}")"
  response_file="$(mktemp)"
  status="$(api_request PUT "/_matrix/client/v3/rooms/$(url_encode "${room_id}")/state/m.room.power_levels/" "${WEAVE_MATRIX_PROVISIONER_ACCESS_TOKEN}" "${state_body}" "${response_file}" || true)"
  expect_success "${status}" "${response_file}" "power-level update for ${name}"
  rm -f -- "${response_file}"

  printf '%s\n' "${room_id}"
}

put_space_state() {
  local room_id="$1"
  local event_type="$2"
  local state_key="$3"
  local body="$4"
  local response_file status

  response_file="$(mktemp)"
  status="$(api_request PUT "/_matrix/client/v3/rooms/$(url_encode "${room_id}")/state/${event_type}/$(url_encode "${state_key}")" "${WEAVE_MATRIX_PROVISIONER_ACCESS_TOKEN}" "${body}" "${response_file}" || true)"
  expect_success "${status}" "${response_file}" "space state update ${event_type}"
  rm -f -- "${response_file}"
}

attach_room_to_space() {
  local space_id="$1"
  local room_id="$2"
  local order="$3"
  local child_body parent_body

  child_body="$(python3 - "${MATRIX_HOMESERVER_NAME}" "${order}" <<'PY'
import json
import sys
server, order = sys.argv[1:]
print(json.dumps({'via': [server], 'suggested': True, 'order': order}, separators=(',', ':')))
PY
)"
  parent_body="$(python3 - "${MATRIX_HOMESERVER_NAME}" <<'PY'
import json
import sys
server = sys.argv[1]
print(json.dumps({'via': [server], 'canonical': True}, separators=(',', ':')))
PY
)"

  put_space_state "${space_id}" 'm.space.child' "${room_id}" "${child_body}"
  put_space_state "${room_id}" 'm.space.parent' "${space_id}" "${parent_body}"
}

room_member_membership() {
  local room_id="$1"
  local member_user_id="$2"
  local response_file status membership

  response_file="$(mktemp)"
  status="$(api_request GET "/_matrix/client/v3/rooms/$(url_encode "${room_id}")/state/m.room.member/$(url_encode "${member_user_id}")" "${WEAVE_MATRIX_PROVISIONER_ACCESS_TOKEN}" '' "${response_file}" || true)"
  if [[ "${status}" == "200" ]]; then
    membership="$(json_get "data.get('membership')" <"${response_file}")"
    rm -f -- "${response_file}"
    printf '%s\n' "${membership}"
    return 0
  fi

  rm -f -- "${response_file}"
  printf ''
}

set_room_join_rule() {
  local room_id="$1"
  local join_rule="$2"
  local body

  body="$(python3 - "${join_rule}" <<'PY'
import json
import sys
print(json.dumps({'join_rule': sys.argv[1]}, separators=(',', ':')))
PY
)"
  put_space_state "${room_id}" 'm.room.join_rules' '' "${body}"
}

join_room_as_member_request() {
  local room_id="$1"
  local member_token="$2"
  local output_file="$3"

  api_request POST "/_matrix/client/v3/join/$(url_encode "${room_id}")" "${member_token}" '{}' "${output_file}"
}

join_room_as_member() {
  local room_id="$1"
  local member_token="$2"
  local response_file status

  response_file="$(mktemp)"
  status="$(join_room_as_member_request "${room_id}" "${member_token}" "${response_file}" || true)"
  expect_success "${status}" "${response_file}" "joining default member to room"
  rm -f -- "${response_file}"
}

invite_and_join_member() {
  local room_id="$1"
  local member_user_id member_token membership response_file status

  if [[ "${WEAVE_MATRIX_PROVISION_TEST_MEMBER:-false}" != "true" ]]; then
    return 0
  fi

  member_user_id="$(matrix_user_id "${WEAVE_MATRIX_DEFAULT_MEMBER_LOCALPART}")"
  member_token="${WEAVE_MATRIX_DEFAULT_MEMBER_ACCESS_TOKEN:-}"
  [[ -n "${member_token}" ]] || return 0

  membership="$(room_member_membership "${room_id}" "${member_user_id}")"
  if [[ "${membership}" == "join" ]]; then
    return 0
  fi

  if [[ "${membership}" == "invite" ]]; then
    join_room_as_member "${room_id}" "${member_token}"
    return 0
  fi

  # Synapse's invite endpoint is heavily rate-limited on a cold local stack. For
  # the optional smoke-test member only, briefly open the pre-provisioned room,
  # let the member join through the normal Client-Server API, and restore the
  # MVP default invite-only policy immediately afterwards.
  set_room_join_rule "${room_id}" public
  response_file="$(mktemp)"
  status="$(join_room_as_member_request "${room_id}" "${member_token}" "${response_file}" || true)"
  set_room_join_rule "${room_id}" invite
  expect_success "${status}" "${response_file}" "joining default member to room"
  rm -f -- "${response_file}"
}

write_app_config_defaults() {
  local app_config_file="${ROOT_DIR}/.generated/app-config.env"

  if [[ ! -f "${app_config_file}" ]]; then
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  grep -v -E '^export[[:space:]]+WEAVE_MATRIX_DEFAULT_(SPACE_ALIAS|ANNOUNCEMENTS_ALIAS|GENERAL_ALIAS|HELP_ALIAS|ACCESS_POLICY)=' "${app_config_file}" >"${tmp_file}" || true
  {
    printf 'export WEAVE_MATRIX_DEFAULT_SPACE_ALIAS=%q\n' "#${WEAVE_MATRIX_WORKSPACE_ALIAS_LOCALPART}:${MATRIX_HOMESERVER_NAME}"
    printf 'export WEAVE_MATRIX_DEFAULT_ANNOUNCEMENTS_ALIAS=%q\n' "#${WEAVE_MATRIX_ANNOUNCEMENTS_ALIAS_LOCALPART}:${MATRIX_HOMESERVER_NAME}"
    printf 'export WEAVE_MATRIX_DEFAULT_GENERAL_ALIAS=%q\n' "#${WEAVE_MATRIX_GENERAL_ALIAS_LOCALPART}:${MATRIX_HOMESERVER_NAME}"
    printf 'export WEAVE_MATRIX_DEFAULT_HELP_ALIAS=%q\n' "#${WEAVE_MATRIX_HELP_ALIAS_LOCALPART}:${MATRIX_HOMESERVER_NAME}"
    printf 'export WEAVE_MATRIX_DEFAULT_ACCESS_POLICY=%q\n' "owner-admin-preprovisioned; optional local test member joined when TF_VAR_create_test_user=true; guest auto-join disabled"
  } >>"${tmp_file}"
  cat "${tmp_file}" >"${app_config_file}"
  rm -f -- "${tmp_file}"
}

main() {
  require_command curl
  require_command docker
  require_command python3

  load_bootstrap_env
  set_default_var TF_VAR_tenant_slug weave
  set_default_var TF_VAR_tenant_domain weave.local
  set_default_var TF_VAR_matrix_subdomain matrix
  set_default_var TF_VAR_public_scheme https
  set_default_var TF_VAR_proxy_host_port 44443
  set_default_var TF_VAR_synapse_host_port 48008
  set_default_var TF_VAR_keycloak_admin_username admin
  set_default_var WEAVE_MATRIX_MAS_CONTAINER_NAME weave-mas

  MATRIX_HOMESERVER_NAME="$(public_host "${TF_VAR_matrix_subdomain:-matrix}")"
  readonly MATRIX_HOMESERVER_NAME
  MATRIX_INTERNAL_URL="${WEAVE_MATRIX_PROVISIONING_URL:-http://${LOOPBACK_HOST}:${TF_VAR_synapse_host_port}}"
  readonly MATRIX_INTERNAL_URL

  set_default_var WEAVE_MATRIX_PROVISIONER_LOCALPART "${TF_VAR_keycloak_admin_username:-admin}"
  set_default_var WEAVE_MATRIX_WORKSPACE_ALIAS_LOCALPART weave-workspace
  set_default_var WEAVE_MATRIX_WORKSPACE_NAME "Weave Workspace"
  set_default_var WEAVE_MATRIX_ANNOUNCEMENTS_ALIAS_LOCALPART announcements
  set_default_var WEAVE_MATRIX_GENERAL_ALIAS_LOCALPART general
  set_default_var WEAVE_MATRIX_HELP_ALIAS_LOCALPART help
  set_default_var WEAVE_MATRIX_DEFAULT_MEMBER_LOCALPART test

  ensure_mas_cli_available

  upsert_bootstrap_var WEAVE_MATRIX_MAS_CONTAINER_NAME "${WEAVE_MATRIX_MAS_CONTAINER_NAME}"
  upsert_bootstrap_var WEAVE_MATRIX_PROVISIONER_LOCALPART "${WEAVE_MATRIX_PROVISIONER_LOCALPART}"
  upsert_bootstrap_var WEAVE_MATRIX_WORKSPACE_ALIAS_LOCALPART "${WEAVE_MATRIX_WORKSPACE_ALIAS_LOCALPART}"
  upsert_bootstrap_var WEAVE_MATRIX_WORKSPACE_NAME "${WEAVE_MATRIX_WORKSPACE_NAME}"
  upsert_bootstrap_var WEAVE_MATRIX_ANNOUNCEMENTS_ALIAS_LOCALPART "${WEAVE_MATRIX_ANNOUNCEMENTS_ALIAS_LOCALPART}"
  upsert_bootstrap_var WEAVE_MATRIX_GENERAL_ALIAS_LOCALPART "${WEAVE_MATRIX_GENERAL_ALIAS_LOCALPART}"
  upsert_bootstrap_var WEAVE_MATRIX_HELP_ALIAS_LOCALPART "${WEAVE_MATRIX_HELP_ALIAS_LOCALPART}"

  if [[ "${TF_VAR_create_test_user:-false}" == "true" ]]; then
    export WEAVE_MATRIX_PROVISION_TEST_MEMBER=true
    upsert_bootstrap_var WEAVE_MATRIX_DEFAULT_MEMBER_LOCALPART "${WEAVE_MATRIX_DEFAULT_MEMBER_LOCALPART}"
  fi

  log "Provisioning default Matrix workspace structures at ${MATRIX_INTERNAL_URL}..."
  ensure_matrix_user_token "${WEAVE_MATRIX_PROVISIONER_LOCALPART}" WEAVE_MATRIX_PROVISIONER_ACCESS_TOKEN true

  if [[ "${WEAVE_MATRIX_PROVISION_TEST_MEMBER:-false}" == "true" ]]; then
    ensure_matrix_user_token "${WEAVE_MATRIX_DEFAULT_MEMBER_LOCALPART}" WEAVE_MATRIX_DEFAULT_MEMBER_ACCESS_TOKEN false
  fi

  workspace_id="$(ensure_room \
    "${WEAVE_MATRIX_WORKSPACE_ALIAS_LOCALPART}" \
    "${WEAVE_MATRIX_WORKSPACE_NAME}" \
    'Default Weave workspace space.' \
    space \
    'm.space')"
  announcements_id="$(ensure_room \
    "${WEAVE_MATRIX_ANNOUNCEMENTS_ALIAS_LOCALPART}" \
    announcements \
    'Owner/admin broadcast posts for the Weave workspace.' \
    announcements)"
  general_id="$(ensure_room \
    "${WEAVE_MATRIX_GENERAL_ALIAS_LOCALPART}" \
    general \
    'Default team discussion for the Weave workspace.' \
    room)"
  help_id="$(ensure_room \
    "${WEAVE_MATRIX_HELP_ALIAS_LOCALPART}" \
    help \
    'Setup and support questions for the Weave workspace.' \
    room)"

  attach_room_to_space "${workspace_id}" "${announcements_id}" 'a'
  attach_room_to_space "${workspace_id}" "${general_id}" 'b'
  attach_room_to_space "${workspace_id}" "${help_id}" 'c'

  invite_and_join_member "${announcements_id}"
  invite_and_join_member "${general_id}"
  invite_and_join_member "${help_id}"

  upsert_bootstrap_var WEAVE_MATRIX_DEFAULT_SPACE_ID "${workspace_id}"
  upsert_bootstrap_var WEAVE_MATRIX_DEFAULT_ANNOUNCEMENTS_ID "${announcements_id}"
  upsert_bootstrap_var WEAVE_MATRIX_DEFAULT_GENERAL_ID "${general_id}"
  upsert_bootstrap_var WEAVE_MATRIX_DEFAULT_HELP_ID "${help_id}"
  write_app_config_defaults

  log "Default Matrix workspace is ready."
  log "- Space alias: #${WEAVE_MATRIX_WORKSPACE_ALIAS_LOCALPART}:${MATRIX_HOMESERVER_NAME}"
  log "- Room aliases: #${WEAVE_MATRIX_ANNOUNCEMENTS_ALIAS_LOCALPART}:${MATRIX_HOMESERVER_NAME}, #${WEAVE_MATRIX_GENERAL_ALIAS_LOCALPART}:${MATRIX_HOMESERVER_NAME}, #${WEAVE_MATRIX_HELP_ALIAS_LOCALPART}:${MATRIX_HOMESERVER_NAME}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
