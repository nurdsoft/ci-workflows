# ci-workflows

Shared reusable GitHub Actions workflows for Nurdsoft projects.

## `release.yml` — SemVer release pipeline

A generic, environment-agnostic reusable workflow that tags a commit with
Semantic Versioning via [go-semantic-release](https://github.com/go-semantic-release/semantic-release).
It does not build, test, or deploy, and it has no knowledge of any branch or
environment. The calling repo decides, per branch, what each run should do.

### Inputs

| Input                | Required | Default     | Purpose |
| -------------------- | -------- | ----------- | ------- |
| `maintained-version` | no       | `''`        | rc prerelease line (e.g. `1-rc`). Empty produces a stable release. |
| `changelog`          | no       | `false`     | Generate `CHANGELOG.md` and commit it back to the branch. |
| `semrel-version`     | no       | `v2.31.0`   | go-semantic-release binary version. |

### Usage

The caller maps its own branches to release behavior. Example for a repo whose
production branch is `prod` and integration branch is `dev`:

```yaml
name: Release

on:
  push:
    branches: [dev, prod]

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release:
    uses: nurdsoft/ci-workflows/.github/workflows/release.yml@v1
    permissions:
      contents: write
    with:
      maintained-version: ${{ github.ref_name == 'prod' && '' || '1-rc' }}
      changelog:          ${{ github.ref_name == 'prod' }}
```

A push to `prod` produces a stable release with a changelog; a push to any other
listed branch produces an rc prerelease. go-semantic-release plugin
configuration (commit-analyzer rules, etc.) is read from each repo's own
`.semrelrc`.

### Versioning

Callers pin to the major tag (`@v1`). That tag is moved on each release so
updates reach consumers deliberately.
