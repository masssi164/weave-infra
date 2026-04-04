# Infrastructure Stage Guide

This stage owns Docker networking, generated runtime config files, local containers, and the shared PostgreSQL bootstrap that creates one database per service.

## Files

- `main.tf`: root orchestration, per-service database bootstrap, generated file creation, module composition, and state-preserving `moved` blocks.
- `variables.tf`: public input contract for the infrastructure stage.
- `outputs.tf`: exported service names, URLs, and hostnames.
- `.terraform.lock.hcl`: pinned provider selections for reproducible init behavior.
- `templates/mas-config.yaml.tpl`: Matrix Authentication Service config template.
- `templates/homeserver.yaml.tpl`: Synapse delegated-auth config template.
- `modules/AGENTS.md`: map of child modules and their responsibilities.

## Child Module Responsibilities

- `modules/postgres`: shared PostgreSQL container and volume; root bootstrap logic creates the service databases inside it.
- `modules/reverse-proxy`: Traefik edge container.
- `modules/keycloak`: Keycloak container and storage.
- `modules/matrix`: MAS and Synapse containers plus routing labels.
- `modules/nextcloud`: Nextcloud container and storage.
