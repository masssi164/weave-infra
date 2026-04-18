# Backend Module Guide

This module owns the local Weave backend runtime and its Traefik integration.

## Files

- `main.tf`: Weave backend image, container, healthcheck, OIDC environment, and Traefik labels.
- `variables.tf`: image, port, hostname, and OIDC contract inputs.
- `outputs.tf`: exported backend container identifier.
