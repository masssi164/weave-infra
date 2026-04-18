# Reverse Proxy Module Guide

This module owns the Caddy edge container for local HTTPS hostname-based routing.

## Files

- `main.tf`: Caddy image, Caddyfile mount, TLS cert directory mount, runtime volumes, published HTTP/HTTPS ports, and container.
- `variables.tf`: network, image, host-port, Caddyfile, TLS cert, and hostname inputs.
- `outputs.tf`: exported proxy container and volume identifiers.
