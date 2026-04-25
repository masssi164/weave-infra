# Weave Infrastructure

Terraform code for a Weave stack split into two stages:

- `weave-workspace/01-infrastructure` provisions Docker networking, runtime assets, and containers.
- `weave-workspace/02-keycloak-setup` configures the tenant realm and OIDC clients after Keycloak is reachable.

Both stages now follow a thin-root pattern:

- root modules own provider setup, shared locals, generated files, and cross-module composition
- child modules own single service domains with explicit inputs and outputs
- `moved` blocks preserve state continuity from the earlier flat layout
- one shared PostgreSQL container now hosts the Weave runtime databases, with Nextcloud kept in the persisted `nextcloud` schema inside the shared `weave` database for release-safe local continuity
- Caddy terminates local HTTPS for the public service hostnames with a local CA certificate

## Quick Start

Add local host entries before opening any browser-facing URL:

```text
127.0.0.1 weave.local auth.weave.local files.weave.local matrix.weave.local
```

```bash
cd weave-workspace
./install.sh
```

Run `make dev-hosts` from the repository root to print the default `/etc/hosts` line.

`install.sh` now defaults to a shared-host-safe isolated port block, generates secrets and local TLS certificates when they are not already exported as `TF_VAR_*`, applies both Terraform stages in order, waits for readiness, and bootstraps the Nextcloud `user_oidc` app.

For repeatable local runs, generated bootstrap inputs are persisted in `weave-workspace/.generated/bootstrap.env`, mirrored to `/tmp/weave-infra/weave-workspace/.generated/bootstrap.env` for the self-hosted GitHub runner flow, and reused on subsequent installs unless you override them explicitly with environment variables.

The installer probes local services through `127.0.0.1` rather than bare `localhost` so Docker port checks stay reliable on hosts where IPv6 loopback behaves differently.

## Port Modes

There are now two supported port modes:

- canonical single-stack ports: `80`, `443`, `8080`, `8082`, `8008`, `8083`, `8084`
- required shared-host isolation block: `44080`, `44443`, `48080`, `48082`, `48008`, `48083`, `48084`

Use the canonical ports only when Weave owns the machine's standard local ports. On any shared Docker host or self-hosted runner, use the isolated block. `install.sh` defaults to the isolated block, and `.env.example` shows both modes explicitly.

If you need a completely clean rerun on a shared host, use the runner-hygiene helper before or after bootstrap:

```bash
cd weave-workspace
WEAVE_RUNNER_HYGIENE=true ./install.sh
# or
bash ./teardown.sh
```

Set `WEAVE_REMOVE_VOLUMES=true` when you also want to remove persisted Docker volumes such as `weave_synapse_data`.

## TLS Setup

The public local contract is HTTPS on these hostnames:

- `https://auth.weave.local`
- `https://files.weave.local` as the raw Nextcloud fallback
- `https://matrix.weave.local`
- `https://weave.local/api`
- `https://weave.local/files`
- `https://weave.local/calendar`

Use the generated local CA path printed by `install.sh`, or pre-create mkcert certificates before running the installer.

Generated-CA flow:

1. Add the host entries shown in Quick Start to `/etc/hosts`.
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
  weave.local auth.weave.local files.weave.local matrix.weave.local
cp "$(mkcert -CAROOT)/rootCA.pem" 01-infrastructure/.generated/caddy/certs/weave-local-ca.pem
./install.sh
```

Caddy is managed by the Terraform infrastructure stage. `weave-workspace/docker-compose.yml` mirrors the same Caddy service and mounts the generated Caddyfile plus cert directory for proxy-only iteration against an existing `weave_network`.

## Layout

- `README.md`: top-level usage, local bootstrap, and Release 1 operator summary.
- `AGENTS.md`: repository navigation notes for future maintainers.
- `Makefile`: small local operator helpers such as `make dev-hosts`.
- `.github/workflows/ci.yml`: GitHub Actions workflow for validation checks plus full-stack smoke coverage.
- `docs/release-1-single-host.md`: Release 1 single-host deployment target, required inputs, and operator expectations.
- `weave-workspace/install.sh`: end-to-end bootstrap runbook for both local and single-host deployments.
- `weave-workspace/teardown.sh`: shared-host cleanup helper for Terraform state drift and stale Docker resources.
- `weave-workspace/smoke-test.sh`: local full-stack smoke test that requires the optional test user flow.
- `weave-workspace/release-verify.sh`: public endpoint verification script for non-local Release 1 installs.
- `weave-workspace/operator-check.sh`: host-local operational check for core containers plus loopback/public health.
- `weave-workspace/release.env.example`: operator-facing env template for single-host Release 1 deployments.
- `docs/operator-runbook.md`: install, verify, rotate, backup, restore, and triage guidance for Release 1 operators.
- `weave-workspace/.env.example`: hostname, port, and Caddy mount defaults for local operators.
- `weave-workspace/docker-compose.yml`: Caddy service definition for proxy-only iteration.
- `weave-workspace/01-infrastructure`: Docker and generated runtime configuration stage.
- `weave-workspace/02-keycloak-setup`: Keycloak identity configuration stage.
- `*/AGENTS.md`: directory-level maintenance summaries for faster onboarding.

The infrastructure stage currently materializes these PostgreSQL databases inside the shared `weave-db` instance:

- `<db_name>_keycloak`
- `<db_name>_mas`
- `<db_name>_synapse`
- `<db_name>` (Nextcloud stores its tables in schema `nextcloud` here)

The Weave backend is deployed as `weave-backend`, routed through `<tenant_domain>/api`, and configured with the public tenant Keycloak issuer, an internal Docker-network JWKS URI, a required `weave-app` token audience, and expected client ID `weave-app`. Override `TF_VAR_weave_backend_image` when using a backend image other than the default `ghcr.io/masssi164/weave-backend:latest`.

The Matrix stack uses Matrix Authentication Service delegated auth through MAS' modern Synapse adapter. Keep the default MAS image unless an override has been checked against the generated `synapse_modern` config and `on_conflict: set` localpart policy. Keep `TF_VAR_synapse_image` on Synapse 1.136.0 or later so MAS can provision and link users through the homeserver MAS API.

If that backend image is private in GHCR, authenticate the Docker client before running `install.sh` or `smoke-test.sh`. The consumer side should use an explicit `docker login ghcr.io` step or a CI login action rather than relying on an ambient cached session.

## Release 1 target

The first non-local Release 1 target is a single Linux host with public DNS, public HTTPS, Docker Engine, Terraform, and operator-managed secrets.

That target is documented in `docs/release-1-single-host.md` and is intentionally distinct from the local developer flow:

- local development may use generated secrets, a generated local CA, and an optional test user
- Release 1 should use explicit secrets, publicly trusted certificates, pinned images, and `TF_VAR_create_test_user=false`
- local smoke coverage depends on the test user contract, while release verification uses public endpoint checks only

Use `weave-workspace/release.env.example` as the starting point for a real deployment env file.

## Validation

Current validation flow:

- `terraform -chdir=weave-workspace/01-infrastructure validate`
- `terraform -chdir=weave-workspace/02-keycloak-setup validate`
- `terraform -chdir=weave-workspace/01-infrastructure plan -refresh=false`
- `bash -n weave-workspace/install.sh`
- `bash weave-workspace/install.sh`
- `bash weave-workspace/smoke-test.sh`

GitHub Actions now runs both repository-safe validation and a Docker-backed full-stack smoke job on pushes and pull requests through `.github/workflows/ci.yml`.

For non-local Release 1 installs, run:

```bash
bash weave-workspace/release-verify.sh
bash weave-workspace/operator-check.sh
```

with `WEAVE_BASE_URL`, `WEAVE_OIDC_ISSUER_URL`, `WEAVE_NEXTCLOUD_URL`, and `WEAVE_MATRIX_URL` exported from your operator env file.

`release-verify.sh` confirms the public Release 1 contract. `operator-check.sh` adds host-local checks for the managed containers plus loopback service health so operators can distinguish public routing failures from service failures.

## Local Hostnames

The stack expects these names to resolve to `127.0.0.1`:

- `<tenant_domain>` for the Weave product gateway
- `auth.<tenant_domain>`
- `matrix.<tenant_domain>`
- `files.<tenant_domain>` for the raw Nextcloud fallback

Default `/etc/hosts` line:

```text
127.0.0.1 weave.local auth.weave.local files.weave.local matrix.weave.local
```

MAS is served behind the matrix hostname; no separate `mas.<tenant_domain>` entry is needed.

## Operator runbook

For the Release 1 operator layer, including secrets rotation expectations, backup scope, restore order, and routine triage commands, use `docs/operator-runbook.md`.

## Integration Tests

Integration tests should call the backend through the Caddy proxy URL, not the direct backend container port. For the default local stack:

```bash
export WEAVE_BASE_URL=https://weave.local/api
export WEAVE_OIDC_ISSUER_URL=https://auth.weave.local/realms/weave
export WEAVE_OIDC_CLIENT_ID=weave-app
export WEAVE_TEST_USERNAME=test@weave.local
export WEAVE_TEST_PASSWORD='<generated — see install.sh output or bootstrap.env>'
```

`WEAVE_BASE_URL` must match the Caddy product API route under `<tenant_domain>/api`, and `WEAVE_OIDC_ISSUER_URL` must match the public Keycloak issuer used in access tokens. When `TF_VAR_create_test_user=true`, `install.sh` also writes these `WEAVE_*` values to `weave-workspace/.generated/bootstrap.env`.

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

## Native App Contract

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
- public readiness endpoint: `https://weave.local/api/health/ready`
- direct health endpoint: `http://127.0.0.1:8084/actuator/health`

See `KEYCLOAK_CONTRACT.md` for the full realm, client, scope, claim, and audience contract.
