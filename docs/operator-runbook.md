# Release 1 operator runbook

This is the minimum operator layer for `weave-infra` Release 1.
It is meant to remove the remaining tribal knowledge around install, verify, recovery, and routine maintenance.

## 1. Before install

Prepare these explicitly:

- DNS for `<tenant_domain>` for the Weave product gateway
- DNS for `auth.<tenant_domain>`
- DNS for `matrix.<tenant_domain>`
- DNS for `files.<tenant_domain>` as the raw Nextcloud technical/admin/protocol fallback
- a filled, private copy of `weave-workspace/release.env.example`
- pinned image references, especially `TF_VAR_weave_backend_image`
- TLS certificate and key readable by the operator account
- backup location for Postgres dumps and Nextcloud data exports

Recommended file permissions on the host:

- release env file: `chmod 600`
- TLS private key: `chmod 600`
- backup exports: operator-readable only

## 2. Secrets inventory and rotation

Release 1 secrets are file-managed, not generated on the fly.
At minimum track ownership and rotation dates for:

- `TF_VAR_db_admin_password`
- `TF_VAR_keycloak_admin_password`
- `TF_VAR_keycloak_db_password`
- `TF_VAR_mas_db_password`
- `TF_VAR_synapse_db_password`
- `TF_VAR_nextcloud_db_password`
- `TF_VAR_nextcloud_admin_password`
- `TF_VAR_nextcloud_backend_actor_token`
- `TF_VAR_matrix_mas_client_secret`
- `TF_VAR_mas_encryption_secret`
- `TF_VAR_mas_signing_key_pem`
- `TF_VAR_mas_matrix_secret`
- `TF_VAR_synapse_registration_shared_secret`
- `TF_VAR_synapse_macaroon_secret_key`
- `TF_VAR_synapse_form_secret`

Rotation guidance:

1. update the private env file
2. re-export the `TF_VAR_*` values
3. run `bash weave-workspace/install.sh`
4. run `bash weave-workspace/release-verify.sh`
5. if the rotated secret affects sign-in, also test a fresh login manually

Treat `TF_VAR_mas_signing_key_pem` as a durable signing secret. Rotating it is possible, but it is a higher-risk maintenance event and should be paired with a recovery window and explicit client revalidation.

## 3. Install and upgrade flow

```bash
cd weave-infra
set -a
source ./weave-workspace/release.env.private
set +a
bash weave-workspace/install.sh
bash weave-workspace/release-verify.sh
bash weave-workspace/operator-check.sh
```

Notes:

- `install.sh` is the supported apply path for both first install and repeat apply
- keep `TF_VAR_create_test_user=false` for release environments
- use pinned images, not `:latest`
- after a backend image change, verify `/api/health/ready` and the backend-owned Nextcloud actor checks through both `release-verify.sh` and `operator-check.sh`

## 4. Routine verification

Use these in order:

1. `bash weave-workspace/release-verify.sh`
2. `bash weave-workspace/operator-check.sh`
3. `docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep '^weave-'`

What `operator-check.sh` adds beyond `release-verify.sh`:

- confirms the core containers exist and are running
- checks loopback health endpoints for Keycloak, MAS, Synapse, and backend
- checks the public product, backend, auth, Matrix, and raw Nextcloud fallback routes through the configured release URLs
- checks that the default Matrix workspace aliases resolve (`#weave-workspace`, `#announcements`, `#general`, and `#help` on the configured Matrix homeserver)
- checks that `weave-backend` has the required server-side Files/Calendar Nextcloud actor env and that the actor user exists in Nextcloud
- treats the actor's own `personal` CalDAV collection as the first Weave-managed workspace calendar; user-private calendars require future explicit sharing/provisioning before they are safe to expose through the backend facade

The default Matrix workspace is provisioned by `weave-workspace/provision-matrix-default-workspace.sh` during install. See `docs/matrix-default-workspace.md` for aliases, the owner/admin-limited `announcements` policy, and current member/guest automation limits.

## 5. Backup expectations

Release 1 does not ship scheduled backup jobs, but it does provide a manually runnable backup helper for operator-owned backup storage:

```bash
bash weave-workspace/backup.sh /var/backups/weave
```

The helper writes one timestamped directory and sets restrictive file permissions. Treat that directory as secret production data, not as a support artifact. It includes:

- `postgres.sql`: PostgreSQL-backed service data for Keycloak, MAS, Synapse, Nextcloud, and Weave backend databases from container `weave-db`
- `nextcloud-data.tgz`: Nextcloud files/calendar application data from Docker volume `weave_nextcloud_data`
- `matrix-synapse-data.tgz`: Matrix/Synapse media and local data from Docker volume `weave_synapse_data`
- `caddy-data.tgz` and `caddy-config.tgz`: Caddy ACME/TLS state and runtime config when local Caddy owns certificates
- `keycloak-data.tgz`: Keycloak container-side runtime data from Docker volume `weave_keycloak_data`
- `generated-config-secrets.tgz`: generated bootstrap env, no-secret app config, TLS material, and generated Terraform service config needed to restore or reprovision without inventing credentials
- `MANIFEST.txt`: artifact list and restore-smoke reminder

Support bundles are **not** backups. `support-bundle.sh` deliberately excludes raw databases, Matrix media, Nextcloud files/calendar data, Caddy ACME state, and generated secrets.

Minimum expectation before calling the stack release-ready:

- backups run on a schedule owned by the operator
- at least one recent backup is stored off-host or on snapshot-backed storage
- one restore rehearsal has been performed and written down
- the restore rehearsal ends with `bash weave-workspace/restore-smoke.sh <backup-dir>`

## 6. Restore outline and smoke

For a host-level restore or failed upgrade rollback:

1. stop further writes to the stack
2. restore the release env file, generated config/secrets, and TLS material from `generated-config-secrets.tgz`
3. restore the Postgres dump from `postgres.sql`
4. restore `weave_nextcloud_data`, `weave_synapse_data`, Caddy volumes, and Keycloak runtime volume from their `.tgz` archives when those volumes are part of the deployment
5. run `bash weave-workspace/install.sh` to reconcile containers and generated config
6. run `bash weave-workspace/restore-smoke.sh <backup-dir>`

`restore-smoke.sh` is safe to run after a restore or clean reprovisioning rehearsal. It never deletes volumes and does not perform the restore itself. When a backup directory is provided it first checks for the expected backup artifacts, then reuses `operator-check.sh` to verify backend readiness, Keycloak discovery, Matrix client versions and MAS discovery, default Matrix room aliases, and raw Nextcloud readiness. If the restored Matrix database is intentionally empty but generated Matrix bootstrap secrets are available, run:

```bash
WEAVE_RESTORE_SMOKE_REPROVISION_MATRIX=true bash weave-workspace/restore-smoke.sh <backup-dir>
```

That option re-runs the idempotent default Matrix workspace provisioner before the checks. If the deployment is badly wedged but data is safe, prefer a clean host plus restored data over ad-hoc container surgery.

## 7. Stop, clean rebuild, and destructive reset

Use the least destructive action that solves the problem:

1. **Stop/restart containers:** use normal Docker or Terraform apply workflows when you only need a service restart. Persistent Docker volumes and generated secrets stay intact.
2. **Clean rebuild:** run `bash weave-workspace/teardown.sh`, then `bash weave-workspace/install.sh`. This removes Weave containers and the Docker network so Terraform can recreate them, but it preserves persistent volumes and `.generated/` secrets/config by default.
3. **Destructive local reset:** only after a backup, run `WEAVE_REMOVE_VOLUMES=true WEAVE_CONFIRM_DESTRUCTIVE_RESET=<tenant_slug> bash weave-workspace/teardown.sh`. For the default local tenant, `<tenant_slug>` is `weave`.

The destructive path prints the backup guidance, affected data domains, and exact Docker volumes before deleting anything. It deletes persistent Docker volumes for Keycloak identity/session data, backend/Postgres data, Matrix/Synapse database and media, Nextcloud database/files/calendar data, shared Postgres databases, and Caddy/TLS state. It does not delete `.generated/` files; copy or remove those intentionally as a separate operator step.

The old `WEAVE_CONFIRM_REMOVE_VOLUMES=weave-delete-local-data` token is deliberately rejected so operators type the tenant/workspace slug instead of copying a generic phrase.

## 8. Minimum observability and triage

Useful commands:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker logs --tail=100 weave-backend
docker logs --tail=100 weave-keycloak
docker logs --tail=100 weave-mas
docker logs --tail=100 weave-synapse
docker logs --tail=100 weave-nextcloud
bash weave-workspace/operator-check.sh
bash weave-workspace/release-verify.sh
```

For support requests, prefer a redacted support bundle over hand-copying raw logs:

```bash
bash weave-workspace/support-bundle.sh
```

Set `WEAVE_SUPPORT_BUNDLE_RUN_CHECKS=true` when you want the bundle to include fresh `operator-check.sh` and `release-verify.sh` output. The bundle includes public URL/config summaries, container status, recent service logs, disk/volume summaries, and recent smoke/operator/verify artifacts found under `.generated`. It is a diagnostics artifact only: it is **not** a backup and cannot restore Postgres databases, Matrix media, Nextcloud files/calendar data, Caddy ACME state, or generated secrets. Review the archive before sharing externally.

Escalate quickly when any of these fail:

- Keycloak discovery does not match the public issuer URL
- backend readiness is not `up`
- Nextcloud `status.php` is not installed/healthy
- Matrix delegated auth discovery, client versions, or `/authorize` is unavailable

## 9. Known Release 1 limits

These are still intentionally out of scope for this repo slice:

- automated backup scheduling
- secret manager integration
- HA or zero-downtime upgrades
- centralized metrics or alert routing
- fully declarative Nextcloud bootstrap beyond the supported `install.sh` path
