# Nextcloud Module Guide

This module owns the local Nextcloud runtime and its Traefik integration.

## Files

- `main.tf`: Nextcloud image, persistent volume, database wiring, admin bootstrap, and routing labels.
- `variables.tf`: image, storage, database, hostname, URL, and admin inputs.
- `outputs.tf`: exported container and volume identifiers.
