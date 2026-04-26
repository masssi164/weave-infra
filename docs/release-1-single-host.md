# Release 1 single-host deployment path

This is the first non-local deployment target for Weave Release 1.
It is intentionally narrower than a future HA or Kubernetes story.

## Target shape

Release 1 runs on one Linux host with Docker Engine, Terraform, public DNS, and publicly trusted TLS certificates.
The host is the operator boundary.

Services on the host:

- Caddy as the public HTTPS entry point
- Keycloak for OIDC
- Matrix Synapse plus MAS
- Nextcloud
- Weave backend
- one PostgreSQL container with separate per-service databases

## Public contract

Operators should expose these HTTPS origins:

- `https://<tenant_domain>` for the Weave product gateway plus `/files` and `/calendar` product routes
- `https://api.<tenant_domain>/api` for the canonical Weave backend API
- `https://auth.<tenant_domain>`
- `https://matrix.<tenant_domain>`
- `https://files.<tenant_domain>` as the raw Nextcloud technical/admin/protocol fallback for WebDAV, CalDAV, OCS, discovery, and admin access

For the current preferred contract, use:

- `https://weave.example`
- `https://api.weave.example/api`
- `https://auth.weave.example`
- `https://matrix.weave.example`
- `https://files.weave.example`

Do not expose public aliases for older Keycloak, Nextcloud, or product-gateway API routes. Keep backend, mobile, Caddy, and operator docs aligned to the canonical public contract above.

## Required operator inputs

Set these explicitly before the first apply:

- `TF_VAR_tenant_domain`
- `TF_VAR_auth_subdomain`
- `TF_VAR_api_subdomain`
- `TF_VAR_matrix_subdomain`
- `TF_VAR_nextcloud_subdomain`
- `TF_VAR_public_scheme=https`
- `TF_VAR_caddy_tls_cert_file`
- `TF_VAR_caddy_tls_key_file`
- `TF_VAR_caddy_tls_ca_file` only when you use a private CA
- `TF_VAR_weave_backend_image`
- all admin, database, and MAS secrets consumed by `install.sh`

Start from `weave-workspace/release.env.example`, copy it to a local untracked file, then replace every placeholder.

## TLS source

Release 1 should use publicly trusted certificates, for example Let's Encrypt or a certificate issued by your edge platform.
Do not rely on the generated local CA flow outside development.

Recommended pattern:

1. issue a SAN certificate for the five canonical public hostnames
2. place the cert and key on the host with restrictive permissions
3. set `TF_VAR_caddy_tls_cert_file` and `TF_VAR_caddy_tls_key_file` to those absolute paths
4. leave `TF_VAR_caddy_tls_ca_file` unset unless your issuer is private and clients must trust an extra CA

## Image source

Release 1 should pin images, not rely on floating local defaults.

Minimum expectation:

- pin `TF_VAR_weave_backend_image` to a version or immutable digest
- pin Terraform-managed service images when the module variables expose them
- keep the default `TF_VAR_mas_image` unless an override has been validated against the generated `synapse_modern` config and localpart conflict policy
- keep `TF_VAR_synapse_image` on Synapse 1.136.0 or later so Matrix Authentication Service delegated auth can call the homeserver MAS API
- record the chosen image set in the deployment change or release note

## Persistence expectations

These paths or named volumes are release data and must survive host replacement or operator error:

- PostgreSQL data volume for Keycloak, MAS, Synapse, and Nextcloud databases
- Nextcloud application data volume
- Caddy data volume when using ACME-managed certificates
- generated Matrix or MAS signing material if stored outside the database

Before go-live, decide whether persistence is:

- host-local disk with host snapshots, or
- attached volume plus backup export, or
- remote snapshot-capable storage

What matters is that the choice is explicit and tested.

## Install flow

1. provision DNS for the public hostnames
2. copy a filled-in release env file onto the host
3. stage TLS material on disk
4. export the `TF_VAR_*` values from the env file
5. run `bash weave-workspace/install.sh`
6. run `bash weave-workspace/release-verify.sh`
7. if local-only test-user bootstrap was enabled accidentally, disable it and re-apply before production use

## Verify after install

Use `weave-workspace/release-verify.sh` with:

- `WEAVE_BASE_URL`
- `WEAVE_PUBLIC_BASE_URL`
- `WEAVE_OIDC_ISSUER_URL`
- `WEAVE_NEXTCLOUD_BASE_URL`
- `WEAVE_MATRIX_HOMESERVER_URL`
- optional `WEAVE_TLS_CA_FILE` when a private CA is required

The script checks:

- Keycloak discovery on the public issuer URL
- Weave product gateway plus `/files` and `/calendar` product routes when `WEAVE_PUBLIC_BASE_URL` is set
- backend health through the public API origin
- Nextcloud install status through the raw technical/admin/protocol fallback files origin
- Matrix delegated auth discovery, client versions, and `/authorize` reachability

## Operational minimums

At minimum, operators need:

- a secret inventory and rotation plan
- backup and restore procedure for Postgres and Nextcloud data
- image upgrade procedure with a rollback point
- a post-deploy verification step using `release-verify.sh`
- a host-local verification step using `operator-check.sh`
- a note explaining whether test users are forbidden or temporarily enabled in the environment

Use `docs/operator-runbook.md` as the concrete Release 1 runbook for install, verification, rotation, backup, restore, and first-line triage.

## Not the Release 1 story yet

This slice does not yet provide:

- automated backup or restore jobs
- secret manager integration
- zero-downtime upgrades or HA
- public monitoring, metrics, or alert routing
- a fully declarative Nextcloud OIDC bootstrap path
