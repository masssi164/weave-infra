# Calendar CalDAV external clients

Release 2 exposes Calendar through the Weave backend facade first. Native CalDAV clients are allowed only through secret-free discovery metadata plus user-owned, revocable credentials.

## Public discovery route

- Public CalDAV/WebDAV base: `https://files.<tenant-domain>/remote.php/dav`.
- Local default: `https://files.weave.local/remote.php/dav`.
- Caddy forwards the whole `files.<tenant-domain>` host to Nextcloud, so no dedicated Caddy path rule is required for `/remote.php/dav`.
- `smoke-test.sh` and `release-verify.sh` probe `PROPFIND /remote.php/dav` without credentials and accept:
  - `401` as the expected protected discovery endpoint, or
  - `207` if a test stack has already supplied ambient credentials.
- `404`, connection failures, or product-domain `/calendar` responses are failures because external clients would not reach Nextcloud discovery.

## Credential path

Supported safe path for external clients:

- Users create or receive a per-client Nextcloud Login Flow/app-password credential.
- Users can revoke that app password/client from Nextcloud security settings.
- Weave backend-generated setup metadata may show host, SSL, principal URL, display label, and username.
- Weave must not embed backend actor credentials, primary user passwords, bearer tokens, or static long-lived secrets in client-facing profiles, URLs, logs, app config, or support bundles.

Blocked until a dedicated access model is implemented:

- Private `{user}` calendar path templates in backend CalDAV config.
- Password-bearing Apple `.mobileconfig` profiles.
- Read-only ICS/webcal feed URLs with non-revocable tokens.
- Any flow that hands the backend-owned Nextcloud actor password/app token to the user or to a generated profile.

## Operator checks

- `WEAVE_NEXTCLOUD_BASE_URL` should point to the technical Nextcloud host (`https://files...`), not the Weave product `/calendar` route.
- Backend CalDAV adapter variables should target the backend actor workspace calendar only:
  - `WEAVE_CALDAV_BASE_URL=$WEAVE_NEXTCLOUD_BASE_URL`
  - `WEAVE_CALDAV_CALENDAR_PATH_TEMPLATE=/remote.php/dav/calendars/<backend-actor>/personal/`
  - `WEAVE_CALDAV_AUTH_MODE=BASIC` (or `BEARER` only when explicitly tested)
- Generated no-secret app config must not include `WEAVE_CALDAV_BACKEND_TOKEN`, `WEAVE_NEXTCLOUD_FILES_ACTOR_TOKEN`, or `TF_VAR_nextcloud_backend_actor_token`.
