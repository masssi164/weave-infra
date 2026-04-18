# Tenant Identity Module Guide

This module owns tenant-specific Keycloak configuration after the server is already running.

## Files

- `main.tf`: tenant realm, optional integration test user, OIDC client definitions, Weave workspace scope and audience mapper, and the Nextcloud group membership mapper.
- `variables.tf`: tenant slug, public URLs, shared secret inputs, and optional test user flag.
- `outputs.tf`: realm, client, and optional test user outputs returned to the stage root.
