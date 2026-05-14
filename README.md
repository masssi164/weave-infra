# Weave Infrastructure

[![CI](https://github.com/masssi164/weave-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/masssi164/weave-infra/actions/workflows/ci.yml)

`weave-infra` is the Docker/Terraform infrastructure for a self-hosted Weave stack. Its Release 1 job is to give operators a repeatable single-host path for identity, chat, files/calendar foundations, backend API routing, local HTTPS, verification, backups, and support diagnostics.

Weave's north star is broader than this repository: accessibility-first collaboration, data sovereignty, open/self-hosted control, a credible migration path from Teams/Slack-style workspaces, and a future Weaver intelligence layer for assistants, agents, automation, and connectors. This repo provides the operator substrate for that vision; it does not pretend Release 1 is the finished product.

## Release 1 scope

Release 1 targets a single Linux host with public DNS, public HTTPS, Docker Engine, Terraform, pinned images, explicit operator-managed secrets, and persistence/backups owned by the operator.

The stack provisions and configures:

- Caddy as the public HTTPS gateway
- Keycloak realm, clients, scopes, and first-party Weave app contract
- Matrix/Synapse with Matrix Authentication Service delegated auth
- Nextcloud technical/admin/protocol surface for files and calendar backing services
- `weave-backend` behind the canonical `api.<tenant_domain>/api` route
- PostgreSQL runtime databases and persisted Docker volumes
- default Matrix workspace rooms for the MVP collaboration slice
- install, teardown, release verification, operator checks, backup/restore smoke, and support-bundle scripts

Release 1 is **not** yet the full Teams/Slack replacement, multi-host HA platform, managed SaaS installer, automatic offsite backup system, or Weaver intelligence layer. Those are future product and operations tracks.

## Quick start: local/dev stack

Add local host entries before opening browser-facing URLs:

```text
127.0.0.1 weave.local api.weave.local auth.weave.local files.weave.local matrix.weave.local
```

Then bootstrap the stack:

```bash
cd weave-workspace
./install.sh
```

`install.sh` defaults to a shared-host-safe isolated port block, runs preflight checks, generates missing local secrets and TLS material, applies both Terraform stages, waits for backend readiness, and bootstraps the Nextcloud `user_oidc` app. Generated local inputs are persisted in `weave-workspace/.generated/bootstrap.env`; a no-secrets app summary is written to `weave-workspace/.generated/app-config.env`.

For deeper local details, TLS trust, port modes, smoke-test inputs, and the native app contract, see [docs/local-bootstrap.md](docs/local-bootstrap.md).

## Quick start: Release 1 operator path

Use the single-host guide and env template as the starting point for a real deployment:

- [docs/release-1-single-host.md](docs/release-1-single-host.md): target shape, public contract, required inputs, TLS/image/persistence expectations, and verify flow
- [weave-workspace/release.env.example](weave-workspace/release.env.example): operator-facing environment template
- [docs/operator-runbook.md](docs/operator-runbook.md): install/upgrade, rotation, backup, restore, destructive reset, and triage guidance
- [docs/calendar-caldav-external-clients.md](docs/calendar-caldav-external-clients.md): CalDAV discovery, safe external-client credential path, and blocked private-calendar/profile flows

After installation, run public and host-local verification from the operator env:

```bash
bash weave-workspace/release-verify.sh
bash weave-workspace/operator-check.sh
```

## Public contract

Default local names resolve to loopback; non-local installs derive the same pattern from `<tenant_domain>`:

- `https://<tenant_domain>`: Weave product gateway, including `/files` and `/calendar` product routes
- `https://api.<tenant_domain>/api`: canonical backend API origin
- `https://auth.<tenant_domain>`: Keycloak
- `https://matrix.<tenant_domain>`: Matrix/Synapse and MAS behind the matrix hostname
- `https://files.<tenant_domain>`: raw Nextcloud technical/admin/protocol fallback

The product should prefer Weave routes and backend APIs where they exist. Raw Nextcloud remains a technical/admin/protocol fallback, not the primary customer-facing files/calendar UX.

The first Calendar facade slice uses the backend-owned Nextcloud actor's own `personal` CalDAV collection as a Weave-managed workspace calendar. A backend service account cannot read every user's private Nextcloud calendar merely by targeting `/calendars/{user}/personal/`; private user calendars require a later explicit sharing, provisioning, or delegated-token contract.

## Repo compass

- `README.md`: product/operator overview and entry points.
- `AGENTS.md`: repository navigation notes for maintainers.
- `Makefile`: local helper targets such as `make dev-hosts` and `make smoke`.
- `.github/workflows/ci.yml`: Terraform/shell validation plus manual full-stack smoke.
- `KEYCLOAK_CONTRACT.md`: realm, client, scope, claim, and audience contract.
- `docs/local-bootstrap.md`: local port modes, TLS trust, integration test inputs, and native app contract.
- `docs/release-1-single-host.md`: Release 1 single-host deployment target.
- `docs/operator-runbook.md`: operations, backup/restore, rotation, and triage guidance.
- `docs/matrix-default-workspace.md`: default Matrix space/room provisioning.
- `docs/calendar-caldav-external-clients.md`: CalDAV discovery, revocable client credentials, and fail-closed Calendar profile boundaries.
- `weave-workspace/install.sh`: end-to-end bootstrap for local and single-host runs.
- `weave-workspace/teardown.sh`: non-destructive cleanup by default; destructive volume reset requires explicit confirmation.
- `weave-workspace/release-verify.sh`: public endpoint verification for non-local Release 1 installs.
- `weave-workspace/operator-check.sh`: host-local container and health checks.
- `weave-workspace/backup.sh`, `restore-smoke.sh`, `support-bundle.sh`: minimum operator support and recovery helpers.
- `weave-workspace/01-infrastructure`: Docker runtime, generated config, and service modules.
- `weave-workspace/02-keycloak-setup`: Keycloak tenant configuration stage.

## Validation

Repository-safe validation used by CI:

```bash
terraform -chdir=weave-workspace/01-infrastructure validate
terraform -chdir=weave-workspace/02-keycloak-setup validate
terraform -chdir=weave-workspace/01-infrastructure plan -refresh=false
bash -n weave-workspace/install.sh
```

Local/full-stack validation when Docker and the optional test user flow are available:

```bash
TF_VAR_create_test_user=true bash weave-workspace/install.sh
bash weave-workspace/smoke-test.sh
```

GitHub Actions runs deterministic repository checks on pushes and pull requests. The Docker-backed full-stack smoke job is manual-only (`workflow_dispatch`) and asks the dispatcher to confirm the solar/storage/power budget before it starts.

## Operator safety notes

- `teardown.sh` is non-destructive by default: it removes Weave containers/network but preserves persistent Docker volumes and generated local secrets/config.
- Destructive local reset requires both `WEAVE_REMOVE_VOLUMES=true` and `WEAVE_CONFIRM_DESTRUCTIVE_RESET=<tenant/workspace slug>`.
- Create an operator-owned backup before destructive maintenance:

```sh
bash weave-workspace/backup.sh /var/backups/weave
```

- Run restore smoke after restoring or cleanly reprovisioning from backup artifacts:

```sh
bash weave-workspace/restore-smoke.sh /var/backups/weave/<weave-backup-timestamp>
```

For Release 1 recovery evidence on the dedicated runner, manually dispatch the `CI` workflow with `confirm_power_budget_ok=true` and `run_restore_smoke=true`. That creates private backup artifacts on the runner and runs `restore-smoke.sh` without uploading secrets.

- Create a redacted diagnostics bundle before sharing logs manually:

```sh
bash weave-workspace/support-bundle.sh
```

Support bundles are not backups. Keep backup artifacts private; they contain databases, volume archives, and generated config/secrets.
