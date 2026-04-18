# Weave Infrastructure

Terraform code for a local Weave development stack split into two stages:

- `weave-workspace/01-infrastructure` provisions Docker networking, runtime assets, and containers.
- `weave-workspace/02-keycloak-setup` configures the tenant realm and OIDC clients after Keycloak is reachable.

Both stages now follow a thin-root pattern:

- root modules own provider setup, shared locals, generated files, and cross-module composition
- child modules own single service domains with explicit inputs and outputs
- `moved` blocks preserve state continuity from the earlier flat layout
- one shared PostgreSQL container now hosts separate per-service databases, which keeps MAS on `public` tables and gives Synapse its required `C` collation database
- Caddy terminates local HTTPS for the public service hostnames with a local CA certificate

## Quick Start

Add local host entries before opening any browser-facing URL:

```text
127.0.0.1 keycloak.weave.local nextcloud.weave.local matrix.weave.local api.weave.local
```

```bash
cd weave-workspace
./install.sh
```

Run `make dev-hosts` from the repository root to print the default `/etc/hosts` line.

`install.sh` supplies sensible local defaults, generates secrets and local TLS certificates when they are not already exported as `TF_VAR_*`, applies both Terraform stages in order, waits for readiness, and bootstraps the Nextcloud `user_oidc` app.

For repeatable local runs, generated bootstrap inputs are persisted in `weave-workspace/.generated/bootstrap.env` and reused on subsequent installs unless you override them explicitly with environment variables.

The installer probes local services through `127.0.0.1` rather than bare `localhost` so Docker port checks stay reliable on hosts where IPv6 loopback behaves differently.

## TLS Setup

The public local contract is HTTPS on these hostnames:

- `https://keycloak.weave.local`
- `https://nextcloud.weave.local`
- `https://matrix.weave.local`
- `https://api.weave.local`

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
  keycloak.weave.local nextcloud.weave.local matrix.weave.local api.weave.local
cp "$(mkcert -CAROOT)/rootCA.pem" 01-infrastructure/.generated/caddy/certs/weave-local-ca.pem
./install.sh
```

Caddy is managed by the Terraform infrastructure stage. `weave-workspace/docker-compose.yml` mirrors the same Caddy service and mounts the generated Caddyfile plus cert directory for proxy-only iteration against an existing `weave_network`.

## Layout

- `README.md`: top-level usage and architecture summary.
- `AGENTS.md`: repository navigation notes for future maintainers.
- `Makefile`: small local operator helpers such as `make dev-hosts`.
- `.github/workflows/ci.yml`: GitHub Actions workflow for validation checks.
- `weave-workspace/install.sh`: end-to-end local bootstrap runbook.
- `weave-workspace/.env.example`: hostname, port, and Caddy mount defaults for local operators.
- `weave-workspace/docker-compose.yml`: Caddy service definition for proxy-only iteration.
- `weave-workspace/01-infrastructure`: Docker and generated runtime configuration stage.
- `weave-workspace/02-keycloak-setup`: Keycloak identity configuration stage.
- `*/AGENTS.md`: directory-level maintenance summaries for faster onboarding.

The infrastructure stage currently materializes these PostgreSQL databases inside the shared `weave-db` instance:

- `<db_name>_keycloak`
- `<db_name>_mas`
- `<db_name>_synapse`
- `<db_name>_nextcloud`

The Weave backend is deployed as `weave-backend`, routed at `api.<tenant_domain>`, and configured with the public tenant Keycloak issuer, an internal Docker-network JWKS URI, a required `weave-app` token audience, and expected client ID `weave-app`. Override `TF_VAR_weave_backend_image` when using a backend image other than the default `ghcr.io/masssi164/weave-backend:latest`.

## Validation

Current validation flow:

- `terraform -chdir=weave-workspace/01-infrastructure validate`
- `terraform -chdir=weave-workspace/02-keycloak-setup validate`
- `terraform -chdir=weave-workspace/01-infrastructure plan -refresh=false`
- `bash -n weave-workspace/install.sh`
- `bash weave-workspace/install.sh`

GitHub Actions runs repository-safe validation on pushes and pull requests through `.github/workflows/ci.yml`.

## Local Hostnames

The stack expects these names to resolve to `127.0.0.1`:

- `keycloak.<tenant_domain>`
- `matrix.<tenant_domain>`
- `nextcloud.<tenant_domain>`
- `api.<tenant_domain>`

Default `/etc/hosts` line:

```text
127.0.0.1 keycloak.weave.local nextcloud.weave.local matrix.weave.local api.weave.local
```

MAS is served behind the matrix hostname; no separate `mas.<tenant_domain>` entry is needed.

## Integration Tests

Integration tests should call the backend through the Caddy proxy URL, not the direct backend container port. For the default local stack:

```bash
export WEAVE_BASE_URL=https://api.weave.local
export WEAVE_OIDC_ISSUER_URL=https://keycloak.weave.local/realms/weave
export WEAVE_OIDC_CLIENT_ID=weave-app
export WEAVE_TEST_USERNAME=test@weave.local
export WEAVE_TEST_PASSWORD='<generated — see install.sh output or bootstrap.env>'
```

`WEAVE_BASE_URL` must match the Caddy proxy URL for `api.<tenant_domain>`, and `WEAVE_OIDC_ISSUER_URL` must match the public Keycloak issuer used in access tokens. When `TF_VAR_create_test_user=true`, `install.sh` also writes these `WEAVE_*` values to `weave-workspace/.generated/bootstrap.env`.

The test user is disabled by default. Enable it only for local integration testing:

```bash
cd weave-workspace
TF_VAR_create_test_user=true ./install.sh
```

## Native App Contract

The default Keycloak client contract for the Weave mobile app is:

- Keycloak display name: `weave-app`
- OIDC client ID: `weave-app`
- sign-in redirect URI: `com.massimotter.weave:/oauthredirect`
- post-logout redirect URI: `com.massimotter.weave:/logout`
- optional API scope: `weave:workspace`
- Resource Owner Password Grant: disabled by default, enabled only when `TF_VAR_create_test_user=true`

The backend resource server contract is:

- issuer URI: `https://keycloak.weave.local/realms/weave`
- JWKS URI: `http://weave-keycloak:8080/realms/weave/protocol/openid-connect/certs`
- required audience: `weave-app`
- expected client ID / authorized party: `weave-app`
- health endpoint: `http://127.0.0.1:8084/actuator/health`

See `KEYCLOAK_CONTRACT.md` for the full realm, client, scope, claim, and audience contract.
