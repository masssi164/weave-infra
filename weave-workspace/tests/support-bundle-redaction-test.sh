#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
readonly SCRIPT="${ROOT_DIR}/support-bundle.sh"

output_dir="$(mktemp -d)"
work_home="$(mktemp -d)"
bootstrap_env="${ROOT_DIR}/.generated/bootstrap.env"
app_config_env="${ROOT_DIR}/.generated/app-config.env"
bootstrap_backup=""
app_config_backup=""

backup_file() {
  local source="$1"
  if [[ -f "${source}" ]]; then
    local backup
    backup="$(mktemp)"
    cp "${source}" "${backup}"
    printf '%s\n' "${backup}"
  fi
}

bootstrap_backup="$(backup_file "${bootstrap_env}")"
app_config_backup="$(backup_file "${app_config_env}")"

restore_file() {
  local backup="$1"
  local target="$2"
  if [[ -n "${backup}" && -f "${backup}" ]]; then
    mkdir -p "$(dirname -- "${target}")"
    cp "${backup}" "${target}"
    rm -f "${backup}"
  else
    rm -f "${target}"
  fi
}

cleanup() {
  restore_file "${bootstrap_backup}" "${bootstrap_env}"
  restore_file "${app_config_backup}" "${app_config_env}"
  rm -rf "${output_dir}" "${work_home}"
}
trap cleanup EXIT

mkdir -p "${ROOT_DIR}/.generated"
cat >"${bootstrap_env}" <<'ENV'
TF_VAR_tenant_domain=weave.local
TF_VAR_public_scheme=https
TF_VAR_keycloak_admin_password=super-secret-admin
TF_VAR_nextcloud_backend_actor_token=super-secret-token
TF_VAR_interop_slack_signing_secret=slack-signing-secret
WEAVE_API_BASE_URL=https://api.weave.local/api
WEAVE_OIDC_ISSUER_URL=https://auth.weave.local/realms/weave
ENV
cat >"${app_config_env}" <<'ENV'
WEAVE_PUBLIC_BASE_URL=https://weave.local
WEAVE_NEXTCLOUD_BASE_URL=https://files.weave.local
WEAVE_CALDAV_BACKEND_TOKEN=calendar-token
WEAVE_INTEROP_SLACK_TOKEN_REF=slack-token-ref
WEAVE_INTEROP_SLACK_CLIENT_SECRET_REF=slack-client-secret-ref
ENV

(
  cd "${ROOT_DIR}"
  env -i \
    PATH="${PATH}" \
    HOME="${work_home}" \
    WEAVE_SUPPORT_BUNDLE_LOG_LINES=1 \
    WEAVE_SUPPORT_BUNDLE_RUN_CHECKS=false \
    bash "${SCRIPT}" "${output_dir}"
)

archive="$(find "${output_dir}" -name 'weave-support-*.tar.gz' -print -quit)"
[[ -n "${archive}" ]] || { echo "support bundle archive was not created" >&2; exit 1; }

tar -xzf "${archive}" -C "${output_dir}"
extracted="$(find "${output_dir}" -maxdepth 1 -type d -name 'weave-support-*' -print -quit)"
[[ -n "${extracted}" ]] || { echo "support bundle archive did not extract" >&2; exit 1; }

grep -Fq 'This bundle is for support-safe diagnostics only. It is not a backup' "${extracted}/README.txt"
grep -Fq 'TF_VAR_tenant_domain=weave.local' "${extracted}/config/public-env-summary.env"
grep -Fq 'WEAVE_API_BASE_URL=https://api.weave.local/api' "${extracted}/config/public-env-summary.env"

if grep -R -Fq 'super-secret' "${extracted}" || grep -R -Fq 'calendar-token' "${extracted}" || grep -R -Fq 'slack-signing-secret' "${extracted}" || grep -R -Fq 'slack-client-secret-ref' "${extracted}"; then
  echo "support bundle leaked a test secret" >&2
  grep -R -n -E 'super-secret|calendar-token|slack-signing-secret|slack-client-secret-ref' "${extracted}" >&2 || true
  exit 1
fi

if grep -R -Eq 'PASSWORD=|TOKEN=|SECRET=' "${extracted}/config/public-env-summary.env"; then
  echo "support bundle public env summary included secret keys" >&2
  cat "${extracted}/config/public-env-summary.env" >&2
  exit 1
fi

printf 'support bundle redaction tests passed\n'
