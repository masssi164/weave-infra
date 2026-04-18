# Keycloak Module Guide

This module runs the local Keycloak container behind the Caddy reverse proxy.

## Files

- `main.tf`: Keycloak image, persistent volume, database wiring, admin bootstrap, and public URL wiring.
- `variables.tf`: image, storage, database, port, hostname, and admin inputs.
- `outputs.tf`: exported container and volume identifiers.
