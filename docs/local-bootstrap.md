# Local bootstrap and app contract

This guide contains the local/dev details that used to make the top-level README intimidating: ports, TLS trust, generated env files, integration test inputs, and the native app/backend contract.

## Hostnames

Default local `/etc/hosts` line:

```text
127.0.0.1 weave.local api.weave.local auth.weave.local files.weave.local matrix.weave.local
```

Run this from the repository root to print the current default line:

```bash
make dev-hosts
```

MAS is served behind the matrix hostname; no separate `mas.<tenant_domain>` entry is needed.

## Port modes

There are two supported local port modes:

- canonical single-stack ports: `80`, `443`, `8080`, `8082`, `8008`, `8083`, `8084`
- shared-host isolation block: `44080`, `44443`, `48080`, `48082`, `48008`, `48083`, `48084`

Use canonical ports only when Weave owns the machine's standard local ports. On a shared Docker host or self-hosted runner, use the isolated block. `install.sh` defaults to the isolated block, and `.env.example` shows both modes explicitly.

If you need a clean non-destructive rerun on a shared host:

```bash
cd weave-workspace
WEAVE_RUNNER_HYGIENE=true ./install.sh
# or
bash ./teardown.sh
```

A destructive reset requires explicit opt-in and the tenant/workspace slug. For the default local tenant, read [operator-runbook.md#5-backup-expectations](operator-runbook.md#5-backup-expectations) first, then run only if data loss is intended:

```bash
cd weave-workspace
WEAVE_REMOVE_VOLUMES=true \
WEAVE_CONFIRM_DESTRUCTIVE_RESET=weave \
bash ./teardown.sh
```

Before deleting volumes, the helper lists the affected data domains: Keycloak identity/session data, backend/Postgres data, Matrix/Synapse database and media, Nextcloud database/files/calendar data, Caddy/TLS state, and exact Docker volumes. Generated `.generated/` secrets/config are not removed by the helper; back them up or delete them manually only when intended.

## TLS setup

The public local contract is HTTPS on these hostnames:

- `https://weave.local` as the Weave product gateway
- `https://weave.local/files` and `https://weave.local/calendar` as Weave product routes
- `https://api.weave.local/api` as the canonical backend API
- `https://auth.weave.local`
- `https://matrix.weave.local`
- `https://files.weave.local` as raw Nextcloud technical/admin/protocol fallback

Generated-CA flow:

1. Add the host entries shown above to `/etc/hosts`.
2. Run `cd weave-workspace && ./install.sh`.
3. Trust `weave-workspace/01-infrastructure/.generated/caddy/certs/weave-local-ca.pem` in the host operating system or browser trust store.
4. Reopen the browser after trusting the CA.

mkcert flow:

```bash
cd weave-workspace
mkdir -p 01-infrastructure/.generated/caddy/certs
mkcert -install
mkcert \
  -cert-file 01-infrastructure/.generated/caddy/certs/weave.local.pem \
  -key-file 01-infrastructure/.generated/caddy/certs/weave.local-key.pem \
  weave.local api.weave.local auth.weave.local files.weave.local matrix.weave.local
cp "$(mkcert -CAROOT)/rootCA.pem" 01-infrastructure/.generated/caddy/certs/weave-local-ca.pem
./install.sh
```

Caddy is managed by the Terraform infrastructure stage. `weave-workspace/docker-compose.yml` mirrors the same Caddy service and mounts the generated Caddyfile plus cert directory for proxy-only iteration against an existing `weave_network`.

## Generated local env files

`install.sh` writes two generated env files:

- `weave-workspace/.generated/bootstrap.env`: private local bootstrap values and secrets. Use only for local backend/server-side runs that need those secrets.
- `weave-workspace/.generated/app-config.env`: no-secrets app/runtime summary. It includes product gateway, backend API, auth issuer, Matrix homeserver, Weave product files/calendar routes, and a clearly labeled `WEAVE_NEXTCLOUD_TECHNICAL_BASE_URL` for raw Nextcloud admin/protocol fallback only.

Do not attach `bootstrap.env` to support issues or logs.

## Integration tests

Integration tests should call the backend through the Caddy proxy URL, not the direct backend container port. For the default local stack:

```bash
export WEAVE_API_BASE_URL=https://api.weave.local/api
export WEAVE_BASE_URL=https://api.weave.local/api
export WEAVE_OIDC_ISSUER_URL=https://auth.weave.local/realms/weave
export WEAVE_OIDC_CLIENT_ID=weave-app
export WEAVE_TEST_USERNAME=test@weave.local
export WEAVE_TEST_PASSWORD='<generated — see install.sh output or bootstrap.env>'
```

`WEAVE_API_BASE_URL` (mirrored as legacy-compatible `WEAVE_BASE_URL`) must match the canonical Caddy API route under `api.<tenant_domain>/api`. `WEAVE_OIDC_ISSUER_URL` must match the public Keycloak issuer used in access tokens. When `TF_VAR_create_test_user=true`, `install.sh` also writes these `WEAVE_*` values to `weave-workspace/.generated/bootstrap.env`.

The test user is disabled by default. Enable it only for local integration testing and smoke validation:

```bash
cd weave-workspace
TF_VAR_create_test_user=true ./install.sh
./smoke-test.sh
```

Or from the repository root:

```bash
TF_VAR_create_test_user=true bash weave-workspace/install.sh
make smoke
```

## Native app contract

The default Keycloak client contract for the Weave mobile app is:

- Keycloak display name: `weave-app`
- OIDC client ID: `weave-app`
- sign-in redirect URI: `com.massimotter.weave:/oauthredirect`
- post-logout redirect URI: `com.massimotter.weave:/logout`
- default API scope: `weave:workspace`
- Resource Owner Password Grant: disabled by default, enabled only when `TF_VAR_create_test_user=true`

The backend resource server contract is:

- issuer URI: `https://auth.weave.local/realms/weave`
- JWKS URI: `http://weave-keycloak:8080/realms/weave/protocol/openid-connect/certs`
- required audience: `weave-app`
- expected client ID / authorized party: `weave-app`
- public readiness endpoint: `https://api.weave.local/api/health/ready`
- direct readiness endpoint: `http://127.0.0.1:8084/api/health/ready`

See [../KEYCLOAK_CONTRACT.md](../KEYCLOAK_CONTRACT.md) for the full realm, client, scope, claim, and audience contract.
