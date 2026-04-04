# Reverse Proxy Module Guide

This module owns the Traefik edge container for local hostname-based routing.

## Files

- `main.tf`: Traefik image, Docker socket mount, published port, and container.
- `variables.tf`: network, image, and host-port inputs.
- `outputs.tf`: exported proxy container identifier.
