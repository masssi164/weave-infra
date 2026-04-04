# Keycloak Setup Modules Guide

## Modules

- `tenant-identity/`
  - `AGENTS.md`: module summary and ownership notes.
  - `main.tf`: tenant realm, OIDC clients, and the Nextcloud group mapper.
  - `variables.tf`: public URLs and shared client-secret inputs.
  - `outputs.tf`: realm and Nextcloud client outputs returned to the root stage.
