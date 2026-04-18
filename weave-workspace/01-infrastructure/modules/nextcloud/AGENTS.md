# Nextcloud Module Guide

This module owns the local Nextcloud runtime behind the Caddy reverse proxy.

## Files

- `main.tf`: Nextcloud image, persistent volume, database wiring, admin bootstrap, proxy trust, and local CA mount.
- `variables.tf`: image, storage, database, hostname, URL, proxy trust, TLS CA mount, and admin inputs.
- `outputs.tf`: exported container and volume identifiers.
