# Keycloak Contract

This is the local identity contract for the Weave self-hosted development stack.

## Realm

- Realm name: `weave`
- Default public issuer URI: `http://auth.weave.local:8090/realms/weave`
- Terraform source: `weave-workspace/02-keycloak-setup/modules/tenant-identity`

The issuer URI follows the infrastructure inputs:

- `tenant_slug`: realm name, default `weave`
- `auth_subdomain`: default `auth`
- `tenant_domain`: default `weave.local`
- `public_scheme`: default `http`
- `proxy_host_port`: default `8090`

## Clients

### Weave Mobile App

- Keycloak display name: `weave-app`
- OIDC client ID: `com.massimotter.weave`
- Access type: public
- OAuth flow: authorization code
- PKCE: required, `S256`
- Sign-in redirect URI: `com.massimotter.weave:/oauthredirect`
- Post-logout redirect URI: `com.massimotter.weave:/logout`
- Optional API scope: `weave:workspace`

The Flutter app must request `openid profile email weave:workspace` when it needs API tokens for the backend.

### Weave Backend

- Keycloak client ID: `weave-backend`
- Access type: bearer-only
- Expected token audience: `weave-backend`
- Backend environment:
  - `WEAVE_OIDC_ISSUER_URI=http://auth.weave.local:8090/realms/weave`
  - `WEAVE_OIDC_REQUIRED_AUDIENCE=weave-backend`
- Public API URL: `http://api.weave.local:8090`
- Direct health URL: `http://127.0.0.1:8084/actuator/health`

### Matrix Authentication Service

- Client ID: `matrix-mas`
- Access type: confidential
- Redirect URI: `http://mas.weave.local:8090/upstream/callback/01JQ7N9R4QK6W3M5X8Y2ZC1DHF`
- Web origins: `+`

### Nextcloud

- Client ID: `nextcloud`
- Access type: confidential
- Redirect URI: `http://nextcloud.weave.local:8090/*`
- Post-logout redirect URI: `http://nextcloud.weave.local:8090/*`
- Backchannel logout URL: `http://nextcloud.weave.local:8090/index.php/apps/user_oidc/backchannel-logout/keycloak`
- Token claims include `groups` for Nextcloud group provisioning.

## Client Scopes

### `weave:workspace`

- Type: OpenID client scope
- `include_in_token_scope`: true
- Assigned to `com.massimotter.weave` as an optional scope
- Purpose: API access scope for Weave workspace operations

The scope carries an audience mapper:

- Mapper name: `weave-backend-audience`
- Mapper type: OIDC audience protocol mapper
- Included client audience: `weave-backend`
- Added to access token: true
- Added to ID token: false

## Token Claims

A mobile access token requested with `weave:workspace` must include:

- `iss`: `http://auth.weave.local:8090/realms/weave`
- `azp`: `com.massimotter.weave`
- `aud`: includes `weave-backend`
- `scope`: includes `openid`, requested profile scopes, and `weave:workspace`

The backend accepts the token only when:

- the issuer matches `WEAVE_OIDC_ISSUER_URI`
- the `aud` claim includes `WEAVE_OIDC_REQUIRED_AUDIENCE`

## Terraform Outputs

The Keycloak setup stage exports:

- `keycloak_realm_name`
- `keycloak_issuer_url`
- `weave_app_client_id`
- `weave_app_redirect_uris`
- `weave_app_post_logout_redirect_uris`
- `weave_app_optional_scopes`
- `weave_workspace_scope_name`
- `weave_backend_client_id`
- `weave_backend_audience`
- `nextcloud_client_id`
- `nextcloud_client_secret`

The infrastructure stage exports:

- `weave_backend_oidc_issuer_uri`
- `weave_backend_required_audience`
- `public_urls.api`
- `service_names.backend`
