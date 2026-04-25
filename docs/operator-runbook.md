# Release 1 operator runbook

This is the minimum operator layer for `weave-infra` Release 1.
It is meant to remove the remaining tribal knowledge around install, verify, recovery, and routine maintenance.

## 1. Before install

Prepare these explicitly:

- DNS for `<tenant_domain>` for the Weave product gateway
- DNS for `auth.<tenant_domain>`
- DNS for `matrix.<tenant_domain>`
- DNS for `files.<tenant_domain>` as the canonical Nextcloud URL
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
- after a backend image change, verify `/actuator/health` through both `release-verify.sh` and `operator-check.sh`

## 4. Routine verification

Use these in order:

1. `bash weave-workspace/release-verify.sh`
2. `bash weave-workspace/operator-check.sh`
3. `docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep '^weave-'`

What `operator-check.sh` adds beyond `release-verify.sh`:

- confirms the core containers exist and are running
- checks loopback health endpoints for Keycloak, MAS, Synapse, and backend
- checks the public origins through the configured release URLs

## 5. Backup expectations

Release 1 does not ship automated backup jobs, so operators must run explicit backups.
Minimum backup set:

- PostgreSQL data from container `weave-db`
- Nextcloud app data volume `weave_nextcloud_data`
- Caddy data volume `weave_caddy_data` when ACME state matters

Example host-local backup commands:

```bash
mkdir -p /var/backups/weave
stamp="$(date +%Y%m%d-%H%M%S)"
docker exec weave-db pg_dumpall -U "$TF_VAR_db_admin_username" > "/var/backups/weave/postgres-${stamp}.sql"
docker run --rm \
  -v weave_nextcloud_data:/source:ro \
  -v /var/backups/weave:/backup \
  alpine sh -c "tar -C /source -czf /backup/nextcloud-data-${stamp}.tgz ."
```

Minimum expectation before calling the stack release-ready:

- backups run on a schedule owned by the operator
- at least one recent backup is stored off-host or on snapshot-backed storage
- one restore rehearsal has been performed and written down

## 6. Restore outline

For a host-level restore or failed upgrade rollback:

1. stop further writes to the stack
2. restore the release env file and TLS material
3. restore the Postgres dump
4. restore Nextcloud data volume contents if needed
5. run `bash weave-workspace/install.sh`
6. run `bash weave-workspace/release-verify.sh`
7. run `bash weave-workspace/operator-check.sh`

If the deployment is badly wedged but data is safe, prefer a clean host plus restored data over ad-hoc container surgery.

## 7. Minimum observability and triage

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

Escalate quickly when any of these fail:

- Keycloak discovery does not match the public issuer URL
- backend health is not `UP`
- Nextcloud `status.php` is not installed/healthy
- Matrix delegated auth discovery or `/authorize` is unavailable

## 8. Known Release 1 limits

These are still intentionally out of scope for this repo slice:

- automated backup scheduling
- secret manager integration
- HA or zero-downtime upgrades
- centralized metrics or alert routing
- fully declarative Nextcloud bootstrap beyond the supported `install.sh` path
