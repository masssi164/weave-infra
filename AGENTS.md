# Repository Guide

This repository contains one runnable workspace under `weave-workspace/`.

## Files

- `.gitignore`: ignores Terraform state, generated runtime assets, and local work directories.
- `README.md`: operator-focused overview and bootstrap instructions.
- `.github/AGENTS.md`: GitHub automation and workflow navigation notes.
- `weave-workspace/AGENTS.md`: workspace-level navigation guide.

## Working Model

- Treat `01-infrastructure` and `02-keycloak-setup` as separate Terraform states.
- Keep generated runtime artifacts inside each stage’s `.generated/` directory.
- Prefer extending existing child modules before adding more logic to a root `main.tf`.
- Keep PostgreSQL changes at the shared-instance level in `01-infrastructure`; service isolation is handled with one database per service, not with cross-service schema juggling.
