# Matrix Module Guide

This module owns Matrix Authentication Service and Synapse. Public Matrix routing is handled by the generated Caddyfile.

## Files

- `main.tf`: MAS and Synapse images, Synapse volume, generated config uploads, containers, and MAS local CA trust.
- `variables.tf`: ports, hostname, generated-file paths, TLS CA mount, and image inputs.
- `outputs.tf`: exported MAS and Synapse container identifiers plus Synapse storage metadata.
