# Backend Module Guide

This module owns the local Weave backend runtime consumed by the Caddy product gateway.

## Files

- `main.tf`: Weave backend image, container, healthcheck, OIDC environment, and Docker network aliases.
- `variables.tf`: image, port, hostname, and OIDC contract inputs.
- `outputs.tf`: exported backend container identifier.
