# Workflows Guide

This directory contains GitHub Actions workflows for repository validation.

## Files

- `ci.yml`: runs Terraform formatting and validation checks plus shell linting on pushes and pull requests. Full-stack smoke is manual-only through `workflow_dispatch` with an explicit power/storage confirmation gate.

## Maintenance Notes

- Keep the validation job focused on deterministic repository checks that can run without local Docker state.
- Prefer validating both Terraform stages with `init -backend=false` before heavier integration steps.
- The smoke job is allowed to use Docker when manually dispatched to validate release-critical stack contracts end to end. Do not make it a normal PR/push requirement unless the cross-repo CI/E2E spec changes.
