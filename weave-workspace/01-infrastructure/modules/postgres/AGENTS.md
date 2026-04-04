# Postgres Module Guide

This module owns the shared PostgreSQL runtime used by Keycloak, MAS, Synapse, and Nextcloud.

## Files

- `main.tf`: PostgreSQL image, persistent volume, and container lifecycle.
- `variables.tf`: image, network, bootstrap database, and administrator credential inputs.
- `outputs.tf`: exported container and volume identifiers for sibling modules.

## Maintenance Notes

- Per-service roles and databases are created by the root stage bootstrap in `01-infrastructure/main.tf`, not inside this child module.
