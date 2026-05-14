#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/activate-user.sh"

output="$(${SCRIPT} \
  --dry-run \
  --username alice \
  --email alice@example.test \
  --display-name 'Alice Example' \
  --role admin \
  --workspace-group workspace-default \
  --password 'not-secret-for-dry-run')"

grep -Fq 'Weave activation plan' <<<"${output}"
grep -Fq -- '- username: alice' <<<"${output}"
grep -Fq -- '- email: alice@example.test' <<<"${output}"
grep -Fq -- '- role: admin' <<<"${output}"
grep -Fq -- '- group: workspace-default' <<<"${output}"
grep -Fq 'Dry run only: Keycloak was not modified.' <<<"${output}"

if grep -Fq 'not-secret-for-dry-run' <<<"${output}"; then
  echo 'dry-run output leaked the provided password' >&2
  exit 1
fi

if ${SCRIPT} --dry-run --username alice --email alice@example.test --display-name 'Alice Example' --role superuser >/tmp/weave-activate-invalid.out 2>&1; then
  echo 'invalid role was accepted' >&2
  exit 1
fi
grep -Fq "Invalid role 'superuser'" /tmp/weave-activate-invalid.out
rm -f /tmp/weave-activate-invalid.out

printf 'activate-user helper tests passed\n'
