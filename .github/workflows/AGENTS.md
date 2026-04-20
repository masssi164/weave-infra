# Workflows Guide

This directory contains GitHub Actions workflows for repository validation.

## Files

- `ci.yml`: runs Terraform formatting and validation checks plus shell linting, then boots the local stack and executes the release smoke test on pushes and pull requests.

## Maintenance Notes

- Keep the validation job focused on deterministic repository checks that can run without local Docker state.
- Prefer validating both Terraform stages with `init -backend=false` before heavier integration steps.
- The smoke job is allowed to use Docker when it validates release-critical stack contracts end to end.
