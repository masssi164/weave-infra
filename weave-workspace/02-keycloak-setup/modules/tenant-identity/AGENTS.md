# Tenant Identity Module Guide

This module owns tenant-specific Keycloak configuration after the server is already running.

## Files

- `main.tf`: tenant realm, OIDC client definitions, Weave workspace scope and audience mapper, and the Nextcloud group membership mapper.
- `variables.tf`: tenant slug, public URLs, and shared secret inputs.
- `outputs.tf`: realm and Nextcloud client outputs returned to the stage root.
