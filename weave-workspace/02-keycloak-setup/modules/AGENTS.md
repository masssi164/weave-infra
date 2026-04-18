# Keycloak Setup Modules Guide

## Modules

- `tenant-identity/`
  - `AGENTS.md`: module summary and ownership notes.
  - `main.tf`: tenant realm, OIDC clients, Weave workspace scope and audience mapper, and the Nextcloud group mapper.
  - `variables.tf`: public URLs and shared client-secret inputs.
  - `outputs.tf`: realm, Weave, and Nextcloud client outputs returned to the root stage.
