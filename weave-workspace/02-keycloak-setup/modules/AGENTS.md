# Keycloak Setup Modules Guide

## Modules

- `tenant-identity/`
  - `AGENTS.md`: module summary and ownership notes.
  - `main.tf`: tenant realm, optional integration test user, OIDC clients, Weave workspace scope and audience mapper, and the Nextcloud group mapper.
  - `variables.tf`: public URLs, shared client-secret inputs, and optional test user flag.
  - `outputs.tf`: realm, Weave, Nextcloud client, and optional test user outputs returned to the root stage.
