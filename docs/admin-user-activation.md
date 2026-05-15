# Local/Dev Admin User Activation Helper

The operator baseline needs a support-safe way for an operator to activate a Weave user without editing Keycloak internals by hand. The helper is intentionally local/dev oriented and maps directly to the current backend product-profile contract:

- MVP realm roles: `owner`, `admin`, `member`, `guest`
- default role-mapped group claims: `workspace-owners`, `workspace-admins`, `workspace-members`, `workspace-guests`
- backend verification path: `/api/me` or the app first-run/profile status surfaces

## Prerequisites

Run the local stack install first so `weave-workspace/.generated/bootstrap.env` contains the Keycloak admin URL and credentials:

```bash
cd weave-workspace
./install.sh
```

The helper loads `.generated/bootstrap.env` automatically. If you are running it from a different shell, ensure these values are available:

- `TF_VAR_keycloak_admin_username`
- `TF_VAR_keycloak_admin_password`
- `TF_VAR_public_scheme`
- `TF_VAR_tenant_domain`
- optional `TF_VAR_auth_subdomain`, `TF_VAR_proxy_host_port`, `TF_VAR_caddy_tls_ca_file`, `WEAVE_TLS_CA_FILE`

## Dry-run the activation plan

```bash
cd weave-workspace
./activate-user.sh \
  --dry-run \
  --username alice \
  --email alice@example.test \
  --display-name 'Alice Example' \
  --role admin
```

The dry run prints the realm, username, email, display name, role, role-mapped default group, and password mode. It does not print the password and does not contact Keycloak.

Guests are mapped to `workspace-guests`, not member/admin groups. Override `--workspace-group` only for an intentional local/dev policy test.

## Activate a user

```bash
cd weave-workspace
./activate-user.sh \
  --username alice \
  --email alice@example.test \
  --display-name 'Alice Example' \
  --role member
```

If `--password` is omitted, the helper generates a local/dev initial password and prints it once as intentional operator output. By default the password is temporary so the user must change it at first login. Use `--permanent-password` only for disposable local/dev test accounts.

## What the helper changes

The helper uses the Keycloak admin API to:

1. ensure the selected MVP realm role exists;
2. ensure the workspace group exists;
3. create or update the user;
4. set the initial password;
5. assign the role and group.

It does not create separate Matrix or Nextcloud accounts. Those modules remain behind Weave/Keycloak SSO and the existing provisioning contracts.

## Verify activation

After sign-in, verify the user through the app profile/status screen or backend facade:

```bash
curl -sS "$WEAVE_API_BASE_URL/me" \
  -H "Authorization: Bearer <user access token>" | jq .
```

Expected evidence:

- `roles` includes the selected MVP role;
- `groups` includes the role-mapped default group (`workspace-guests` for guest, `workspace-members` for member, etc.) unless a different `--workspace-group` was used;
- profile display name/email match the activated user.

## Release boundary

This is an operator helper, not the final product admin UI/API. The operator baseline may use it for local/dev owner/admin activation evidence. A later product admin flow should replace this script for non-technical workspace administrators.
