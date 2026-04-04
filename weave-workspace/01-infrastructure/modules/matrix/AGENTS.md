# Matrix Module Guide

This module owns Matrix Authentication Service and Synapse, including the Traefik routing rules that split browser auth paths from Matrix APIs.

## Files

- `main.tf`: MAS and Synapse images, Synapse volume, generated config uploads, containers, and routing labels.
- `variables.tf`: ports, hostnames, generated-file paths, and image inputs.
- `outputs.tf`: exported MAS and Synapse container identifiers plus Synapse storage metadata.
