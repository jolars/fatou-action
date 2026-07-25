# AGENTS.md

Guidance for agentic coding assistants in `fatou-action`.

## Scope

- Repo type: composite GitHub Action.
- Purpose: install `fatou` and run format/lint checks.
- Primary files: `action.yml`, `scripts/install-fatou.sh`, `scripts/install-fatou.ps1`.
- CI coverage: Linux/macOS/Windows on x64 and ARM64.

## Repository Map

- `action.yml`: action API (inputs/outputs) and execution steps.
- `scripts/install-fatou.sh`: Unix installer (verifies checksum + provenance).
- `scripts/install-fatou.ps1`: Windows installer (verifies checksum + provenance).
- `.github/workflows/ci.yml`: lint, integration tests, and the versionary release job.
- `.github/workflows/update-major-minor-tags.yml`: release tag maintenance.
- `fixtures/ok.jl`, `fixtures/bad.jl`: expected pass/fail fixtures.
- `versionary.jsonc`: versionary release config (`simple` strategy).
- `version.txt`: the current version, managed by versionary.

## Tooling Assumptions

- No `package.json`, `Makefile`, or Python project files.
- No compile/build artifact pipeline; tests are workflow-driven.
- Installer smoke checks require network access.

## Lint and Validation

Run from repo root.

The `lint` job in `ci.yml` runs all of these; run them locally before pushing.

- Shell syntax: `sh -n scripts/install-fatou.sh`
- ShellCheck: `shellcheck scripts/install-fatou.sh`
- PowerShell parse check:
  `pwsh -NoLogo -NoProfile -Command "[void][ScriptBlock]::Create((Get-Content -Raw 'scripts/install-fatou.ps1'))"`
- Workflow lint: `actionlint`

## Test

- Main workflow: `.github/workflows/ci.yml`.
  - `test-pass` should succeed with `fixtures/ok.jl`.
  - `test-fail` should fail with `fixtures/bad.jl` (failure is asserted).
- Focused Unix smoke check without CI:
  - `tmpdir="$(mktemp -d)" && FATOU_INSTALL_DIR="$tmpdir" FATOU_VERIFY_CHECKSUM=false bash scripts/install-fatou.sh && "$tmpdir/fatou" --version`

## Code Style Guidelines

- Preserve Unix/Windows behavior parity; keep OS conditionals explicit.
- YAML: 2-space indent, kebab-case input names, string booleans (`"true"`/`"false"`).
- Shell: POSIX `sh`, prologue `#!/usr/bin/env sh` + `set -eu`, `case` for OS/arch
  branching, quote expansions, HTTPS-only downloads, `trap` cleanup.
- PowerShell: `$ErrorActionPreference = 'Stop'`, camelCase names, explicit
  cmdlets, `try/finally` cleanup, throw on unsupported architecture.
- Env vars: `FATOU_*` (UPPER_SNAKE_CASE).
- Update `README.md` when behavior or the input/output API changes.
- Use Conventional Commits (`feat:`, `fix:`, `chore:`).

## Security

- Download artifacts only over HTTPS from GitHub Releases.
- Verify downloads against the published `.sha256` sidecar; a mismatch aborts,
  a missing sidecar (older releases) warns and continues.
- Verify build provenance with `gh attestation verify` when `gh` is available;
  a failing attestation aborts, a missing one or missing `gh` warns.
- Never log secrets/tokens.
- Treat release/tag automation edits as high risk.
