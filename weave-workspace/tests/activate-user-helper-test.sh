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
  --password 'not-secret-for-dry-run')"

grep -Fq 'Weave activation plan' <<<"${output}"
grep -Fq -- '- username: alice' <<<"${output}"
grep -Fq -- '- email: alice@example.test' <<<"${output}"
grep -Fq -- '- role: admin' <<<"${output}"
grep -Fq -- '- group: workspace-admins' <<<"${output}"
grep -Fq 'Dry run only: Keycloak was not modified.' <<<"${output}"

if grep -Fq 'not-secret-for-dry-run' <<<"${output}"; then
  echo 'dry-run output leaked the provided password' >&2
  exit 1
fi


guest_output="$(${SCRIPT} \
  --dry-run \
  --username guest1 \
  --email guest1@example.test \
  --display-name 'Guest Example' \
  --role guest)"

grep -Fq -- '- role: guest' <<<"${guest_output}"
grep -Fq -- '- group: workspace-guests' <<<"${guest_output}"
if grep -Eq -- '- (role|group): .*workspace-(members|admins)|- role: (member|admin)' <<<"${guest_output}"; then
  echo 'guest dry-run received member/admin role or group' >&2
  exit 1
fi

if ${SCRIPT} --dry-run --username alice --email alice@example.test --display-name 'Alice Example' --role superuser >/tmp/weave-activate-invalid.out 2>&1; then
  echo 'invalid role was accepted' >&2
  exit 1
fi
grep -Fq "Invalid role 'superuser'" /tmp/weave-activate-invalid.out
rm -f /tmp/weave-activate-invalid.out

printf 'activate-user helper tests passed\n'
