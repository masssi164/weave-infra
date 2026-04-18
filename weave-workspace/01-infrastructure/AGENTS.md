# Infrastructure Stage Guide

This stage owns Docker networking, generated runtime config files, local containers, and the shared PostgreSQL bootstrap that creates one database per service.

## Files

- `main.tf`: root orchestration, per-service database bootstrap, generated file creation, module composition, Weave backend wiring, and state-preserving `moved` blocks.
- `variables.tf`: public input contract for the infrastructure stage.
- `outputs.tf`: exported service names, URLs, and hostnames.
- `.terraform.lock.hcl`: pinned provider selections for reproducible init behavior.
- `templates/Caddyfile.tpl`: Caddy reverse proxy and TLS routing template.
- `templates/mas-config.yaml.tpl`: Matrix Authentication Service config template.
- `templates/homeserver.yaml.tpl`: Synapse delegated-auth config template.
- `modules/AGENTS.md`: map of child modules and their responsibilities.

## Child Module Responsibilities

- `modules/postgres`: shared PostgreSQL container and volume; root bootstrap logic creates the service databases inside it.
- `modules/reverse-proxy`: Caddy edge container with local TLS cert mounts.
- `modules/keycloak`: Keycloak container and storage.
- `modules/backend`: Weave backend container, OIDC environment, healthcheck, and Caddy routing.
- `modules/matrix`: MAS and Synapse containers plus local CA trust for MAS.
- `modules/nextcloud`: Nextcloud container and storage.
