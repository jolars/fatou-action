# GitHub Action for fatou

[![CI](https://github.com/jolars/fatou-action/actions/workflows/ci.yml/badge.svg)](https://github.com/jolars/fatou-action/actions/workflows/ci.yml)

A GitHub Action that installs [fatou](https://github.com/jolars/fatou) and runs
formatting and lint checks in CI.

The action installs prebuilt release binaries and supports GitHub-hosted runners
for Linux, macOS, and Windows on both x64 and ARM64. Downloaded binaries are
verified against their published SHA256 checksum and build provenance
attestation, and cached between runs.

## Usage

### Basic

```yaml
name: fatou

on:
  pull_request:
  push:
    branches: [main]

jobs:
  fatou:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: jolars/fatou-action@v1
```

### Pin fatou version

```yaml
- uses: jolars/fatou-action@v1
  with:
    version: v0.7.0
```

### Format only

```yaml
- uses: jolars/fatou-action@v1
  with:
    lint: "false"
```

### Lint only

```yaml
- uses: jolars/fatou-action@v1
  with:
    format: "false"
```

### Run only on a specific path

```yaml
- uses: jolars/fatou-action@v1
  with:
    path: src/
```

### Use a custom config

```yaml
- uses: jolars/fatou-action@v1
  with:
    config: fatou.toml
```

## Inputs

| Input             | Description                                     | Default  |
| ----------------- | ----------------------------------------------- | -------- |
| `path`            | File or directory to check                      | `.`      |
| `version`         | fatou version to install (`latest` or `vX.Y.Z`) | `latest` |
| `format`          | Run `fatou format --check`                      | `true`   |
| `lint`            | Run `fatou lint`                                | `true`   |
| `config`          | Optional path to a `fatou.toml` config file     | `""`     |
| `verify-checksum` | Verify the downloaded asset against its SHA256  | `true`   |

## Outputs

| Output    | Description                 |
| --------- | --------------------------- |
| `version` | Installed fatou CLI version |

## Checksum verification

When `verify-checksum` is `true` (the default), the action downloads the
`.sha256` sidecar published alongside each release asset and verifies the
archive before installing. Releases that predate checksum publishing have no
sidecar; for those the action prints a warning and installs without
verification rather than failing.

Checksums guard against corrupted or truncated downloads; they are not a
substitute for release signing.

## Build provenance

Fatou release archives carry a [build provenance
attestation](https://docs.github.com/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds),
signed via Sigstore and tied to the workflow that built them. Unlike a
checksum, this cannot be forged by an attacker who only controls the release
assets. When the `gh` CLI is available, this action verifies it before
installing; a failing attestation aborts the install, while a missing one
(older releases) or a missing `gh` warns and continues.

To verify by hand:

```bash
gh attestation verify fatou-x86_64-unknown-linux-gnu.tar.gz \
  --repo jolars/fatou
```

Add `--signer-workflow jolars/fatou/.github/workflows/packages.yml` to also
pin the exact workflow that must have produced the artifact.

## Versioning

This action uses semantic versioning based on action API changes:

- Major: breaking changes to action inputs/outputs/behavior
- Minor: backward-compatible features
- Patch: fixes and internal improvements

Use `@v1` for stable major updates, or pin exact tags like `@v1.2.3`.
