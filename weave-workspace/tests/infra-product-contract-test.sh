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

for file in "${backend_main}" "${infra_main}" "${install_script}" "${keycloak_main}" "${release_env}" "${admin_doc}" "${caldav_doc}"; do
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

printf '%s\n' 'infra product contract tests passed'
