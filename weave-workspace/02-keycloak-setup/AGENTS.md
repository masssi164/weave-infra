# Keycloak Setup Stage Guide

This stage owns tenant-level identity configuration after Keycloak is already running.

## Files

- `main.tf`: provider configuration, derived URLs, child module call, and `moved` blocks.
- `variables.tf`: public input contract for the Keycloak setup stage.
- `outputs.tf`: realm and client outputs consumed by operators and `install.sh`.
- `.terraform.lock.hcl`: pinned provider selections for reproducible init behavior.
- `modules/AGENTS.md`: map of the child module used by this stage.

## Responsibility Boundary

- This stage configures Keycloak only.
- It does not mutate Docker resources or rerender infrastructure assets.
- Nextcloud app bootstrap remains in `install.sh`, using outputs from this stage.
