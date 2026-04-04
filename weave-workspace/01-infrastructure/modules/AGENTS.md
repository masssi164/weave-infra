# Infrastructure Modules Guide

These child modules keep the root stage orchestration-only.

## Modules

- `postgres/`
  - `AGENTS.md`: module summary and ownership notes.
  - `main.tf`: PostgreSQL image, volume, and container.
  - `variables.tf`: database bootstrap and init SQL inputs.
  - `outputs.tf`: container and volume identifiers.
- `reverse-proxy/`
  - `AGENTS.md`: module summary and ownership notes.
  - `main.tf`: Traefik image and container.
  - `variables.tf`: proxy inputs.
  - `outputs.tf`: container identifier.
- `keycloak/`
  - `AGENTS.md`: module summary and ownership notes.
  - `main.tf`: Keycloak image, volume, container, and Traefik labels.
  - `variables.tf`: database, hostname, and admin inputs.
  - `outputs.tf`: container and volume identifiers.
- `matrix/`
  - `AGENTS.md`: module summary and ownership notes.
  - `main.tf`: MAS and Synapse images, Synapse volume, containers, and edge routing labels.
  - `variables.tf`: generated-file paths, ports, and hostnames.
  - `outputs.tf`: Matrix container and volume identifiers.
- `nextcloud/`
  - `AGENTS.md`: module summary and ownership notes.
  - `main.tf`: Nextcloud image, volume, container, and Traefik labels.
  - `variables.tf`: database, hostname, and admin inputs.
  - `outputs.tf`: container and volume identifiers.
