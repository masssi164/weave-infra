# Matrix default workspace provisioning

`weave-workspace/install.sh` runs `weave-workspace/provision-matrix-default-workspace.sh` after Synapse is ready. The script is idempotent: it resolves the stable Matrix aliases first, creates only missing structures, and then reapplies the expected space parent/child state and power levels.

## Stable aliases and names

For the default local tenant (`matrix.weave.local`):

| Structure | Name | Alias |
|---|---|---|
| Workspace space | `Weave Workspace` | `#weave-workspace:matrix.weave.local` |
| Announcements room | `announcements` | `#announcements:matrix.weave.local` |
| General room | `general` | `#general:matrix.weave.local` |
| Help room | `help` | `#help:matrix.weave.local` |

For a non-local tenant, replace `matrix.weave.local` with `matrix.<tenant_domain>` or the configured `TF_VAR_matrix_subdomain`.`TF_VAR_tenant_domain` value.

## Access policy in this slice

- The configured local/dev owner/admin Matrix account localpart defaults to `TF_VAR_keycloak_admin_username` (`admin`) and is joined to the workspace space plus all default rooms.
- `announcements` keeps `events_default=50`, so normal members cannot post by default; owner/admin can post.
- `general` and `help` keep normal member posting enabled.
- When `TF_VAR_create_test_user=true`, the local smoke-test Matrix member (`test`) is created and joined to `announcements`, `general`, and `help` so smoke/E2E can verify the default member path. To avoid Synapse's cold-stack invite rate limit, provisioning briefly opens each default room for that member's Client-Server API join and immediately restores the invite-only policy.
- Guest auto-join is intentionally disabled. Guests require an explicit invite/resource permission until role-driven Matrix membership automation lands.
- Full owner/admin/member/guest synchronization from Keycloak roles remains a follow-up; this slice only pre-provisions the local/dev default structures and optional smoke-test member.

## Provisioning credential path

The current Synapse/MAS stack delegates Matrix authentication to Matrix Authentication Service (MAS), so the default workspace provisioner does **not** use Synapse shared-secret admin registration. Instead, `provision-matrix-default-workspace.sh` preflights the running MAS container, registers the local provisioning users with `mas-cli`, reconciles admin policy for existing users on reruns, issues MAS compatibility tokens, and validates each token against Synapse `/_matrix/client/v3/account/whoami` before any Matrix Client-Server API room creation.

The generated MAS config disables password authentication (`passwords.enabled=false`). Provisioning therefore creates MAS users without `--password`/`set-password`; the room setup path authenticates only through compatibility tokens stored in the private generated bootstrap environment. MAS CLI user arguments are Matrix localparts/usernames such as `admin`, not full MXIDs such as `@admin:matrix.weave.local`.

By default the MAS container is `weave-mas`. Override `WEAVE_MATRIX_MAS_CONTAINER_NAME` only if the deployment intentionally uses a different container name. If MAS is not running, the image does not provide `mas-cli`, or Synapse rejects a freshly issued compatibility token, provisioning fails before room creation with an actionable error. Matrix API calls also retry transient rate-limit/service-unavailable responses.

## Secret handling

The script stores MAS compatibility access tokens only in the private `weave-workspace/.generated/bootstrap.env` file. It does not print Matrix access tokens. `support-bundle.sh` does not include these private values and its redaction check treats token/secret/password patterns as failures.

## Verification

After install:

```bash
cd weave-workspace
./operator-check.sh
TF_VAR_create_test_user=true ./smoke-test.sh
```

`operator-check.sh` verifies the stable aliases resolve. `smoke-test.sh` also verifies that the default rooms are attached to the workspace space and that `announcements` posting is owner/admin-limited by default.
