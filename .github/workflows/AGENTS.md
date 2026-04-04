# Workflows Guide

This directory contains GitHub Actions workflows for repository validation.

## Files

- `ci.yml`: runs Terraform formatting and validation checks plus `bash -n` and `shellcheck` for the bootstrap script on pushes and pull requests.

## Maintenance Notes

- Keep the workflow focused on deterministic repository checks that can run without local Docker state.
- Prefer validating both Terraform stages with `init -backend=false` before adding heavier integration steps.
