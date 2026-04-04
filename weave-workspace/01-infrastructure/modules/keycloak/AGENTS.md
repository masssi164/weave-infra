# Keycloak Module Guide

This module runs the local Keycloak container and exposes it through Traefik labels.

## Files

- `main.tf`: Keycloak image, persistent volume, database wiring, admin bootstrap, and routing labels.
- `variables.tf`: image, storage, database, port, hostname, and admin inputs.
- `outputs.tf`: exported container and volume identifiers.
