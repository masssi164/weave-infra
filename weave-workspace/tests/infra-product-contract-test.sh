#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd -- "${ROOT_DIR}/.." && pwd)"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "${needle}" "${file}" || fail "Expected ${file} to contain: ${needle}"
}

assert_file_absent() {
  local file="$1"
  local needle="$2"
  ! grep -Fq -- "${needle}" "${file}" || fail "Did not expect ${file} to contain: ${needle}"
}

backend_main="${ROOT_DIR}/01-infrastructure/modules/backend/main.tf"
infra_main="${ROOT_DIR}/01-infrastructure/main.tf"
install_script="${ROOT_DIR}/install.sh"
keycloak_main="${ROOT_DIR}/02-keycloak-setup/modules/tenant-identity/main.tf"
release_env="${ROOT_DIR}/release.env.example"
admin_doc="${REPO_DIR}/docs/admin-user-activation.md"
caldav_doc="${REPO_DIR}/docs/calendar-caldav-external-clients.md"
connector_doc="${REPO_DIR}/docs/connector-runtime-guardrails.md"
caddy_template="${ROOT_DIR}/01-infrastructure/templates/Caddyfile.tpl"

for file in "${backend_main}" "${infra_main}" "${install_script}" "${keycloak_main}" "${release_env}" "${admin_doc}" "${caldav_doc}" "${connector_doc}" "${caddy_template}"; do
  [[ -f "${file}" ]] || fail "Missing expected contract file: ${file}"
done

# CalDAV external-client metadata must stay public/no-secret and fail-closed.
assert_file_contains "${backend_main}" 'WEAVE_CALDAV_EXTERNAL_DISCOVERY_URL=${var.caldav_external_discovery_url}'
assert_file_contains "${backend_main}" 'WEAVE_CALDAV_EXTERNAL_CREDENTIAL_MODE=${var.caldav_external_credential_mode}'
assert_file_contains "${backend_main}" 'WEAVE_CALDAV_EXTERNAL_PROFILE_PASSWORD_MODE=${var.caldav_external_profile_password_mode}'
assert_file_contains "${backend_main}" 'WEAVE_CALDAV_EXTERNAL_PRIVATE_USER_CALENDARS=${var.caldav_external_private_user_calendars}'
assert_file_contains "${infra_main}" 'caldav_external_discovery_url'
assert_file_contains "${infra_main}" 'nextcloud-login-flow-app-password'
assert_file_contains "${infra_main}" 'caldav_external_profile_password_mode  = "omit"'
assert_file_contains "${infra_main}" 'caldav_external_private_user_calendars = "disabled"'
assert_file_contains "${install_script}" 'WEAVE_CALDAV_EXTERNAL_DISCOVERY_URL'
assert_file_contains "${install_script}" 'WEAVE_CALDAV_EXTERNAL_PROFILE_PASSWORD_MODE'
assert_file_contains "${release_env}" 'WEAVE_CALDAV_EXTERNAL_DISCOVERY_URL=https://files.weave.example/remote.php/dav'
assert_file_absent "${caldav_doc}" 'WEAVE_CALDAV_BACKEND_TOKEN='
assert_file_absent "${release_env}" 'WEAVE_CALDAV_BACKEND_TOKEN='

# Keycloak must declare product roles/groups, and guest must remain distinct from member/admin.
for role in owner admin member guest; do
  grep -Eq "^[[:space:]]+${role}[[:space:]]+=" "${keycloak_main}" || fail "Expected Keycloak product role/group entry for: ${role}"
done
assert_file_contains "${keycloak_main}" 'workspace-guests'
assert_file_contains "${keycloak_main}" 'keycloak_group_roles'
assert_file_contains "${keycloak_main}" 'keycloak_user_roles'
assert_file_contains "${admin_doc}" 'Guests are mapped to `workspace-guests`, not member/admin groups.'

# Connector/interop runtime guardrails must default closed and keep public provider callbacks blocked.
assert_file_contains "${backend_main}" 'WEAVE_INTEROP_ENABLED=${var.interop_enabled}'
assert_file_contains "${backend_main}" 'WEAVE_INTEROP_SLACK_ENABLED=${var.interop_slack_enabled}'
assert_file_contains "${backend_main}" 'WEAVE_INTEROP_TEAMS_ENABLED=${var.interop_teams_enabled}'
assert_file_contains "${backend_main}" 'WEAVE_CONNECTORS_PUBLIC_SDK_ENABLED=${var.connectors_public_sdk_enabled}'
assert_file_contains "${infra_main}" 'connector_provider_callbacks_exposed ? ""'
assert_file_contains "${infra_main}" 'interop_enabled                        = false'
assert_file_contains "${infra_main}" 'interop_slack_enabled                  = false'
assert_file_contains "${infra_main}" 'connectors_public_sdk_enabled          = false'
assert_file_contains "${caddy_template}" 'connector_provider_callbacks_guard'
assert_file_contains "${connector_doc}" 'provider callback routes such as Slack OAuth and event ingestion are blocked at Caddy with `404`'
assert_file_contains "${connector_doc}" 'do not commit demo OAuth secrets, webhook signing secrets, bot tokens, access tokens, or refresh tokens'

printf '%s\n' 'infra product contract tests passed'
