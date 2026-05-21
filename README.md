# ci-workflows

Reusable CI/CD building blocks for Nurdsoft projects.

This repository is a shared, version-pinned library of GitHub Actions workflows
and composite actions. The goal is straightforward: any project, whatever its
shape or stack, should be able to assemble a complete, best-practice pipeline —
release, build, deploy, infrastructure, notifications — from pieces that are
written once, reviewed once, and maintained in one place.

Keeping that logic here means individual repositories do not reinvent it, drift
apart, or quietly fall behind good practice. A consuming repository wires the
pieces together and supplies its own values; everything in this repository
stays generic and reusable.

## Contents

| Path | Type | Purpose |
| ---- | ---- | ------- |
| `.github/workflows/release.yml` | Reusable workflow | Tag a SemVer release |
| `actions/frontend-build`  | Composite action | Build a frontend project and upload the output |
| `actions/frontend-deploy` | Composite action | Publish the build to a bucket and invalidate the CDN |
| `actions/backend-build`   | Composite action | Build a container image (and optionally push) |
| `actions/backend-deploy`  | Composite action | Deploy a container image to a managed service runtime |
| `actions/infra-plan`      | Composite action | Plan infrastructure changes |
| `actions/infra-apply`     | Composite action | Apply a saved infrastructure plan |
| `actions/mobile-checks`   | Composite action | Install deps and run lint / type-check / tests for an Expo project |
| `actions/mobile-build`    | Composite action | Build an Expo / React Native app with EAS Build |
| `actions/mobile-deploy`   | Composite action | Submit an EAS build to the stores or publish an over-the-air update |
| `actions/announce`        | Composite action | Post a deployment result to Slack |

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

The caller maps its own branches to release behavior.

**Single release branch.** Every push to `main` cuts a stable release with a
changelog:

```yaml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    uses: nurdsoft/ci-workflows/.github/workflows/release.yml@v1
    permissions:
      contents: write
    with:
      changelog: true
```

**Release branch plus feature branches.** The release branch cuts stable
releases; feature branches cut rc prereleases with no changelog:

```yaml
name: Release

on:
  push:
    branches: [main, "feature/**"]

jobs:
  release:
    uses: nurdsoft/ci-workflows/.github/workflows/release.yml@v1
    permissions:
      contents: write
    with:
      maintained-version: ${{ github.ref_name == 'main' && '' || '1-rc' }}
      changelog:          ${{ github.ref_name == 'main' }}
```

go-semantic-release plugin configuration (commit-analyzer rules, etc.) is read
from each repo's own `.semrelrc`.

## Composite actions

The composite actions are the steps of a release pipeline. Each plugs into one
job of the caller's workflow, so the caller keeps a flat, readable run graph and
owns the job DAG (`needs:` / `if:`), triggers and permissions.

### `frontend-build`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `env` | yes | — | Target environment for the build. |
| `node-version` | no | `20` | Node.js version. |
| `app-version` | no | `''` | Version string injected into the build (as the env var named by `version-env-var`). |
| `version-env-var` | no | `NEXT_PUBLIC_APP_VERSION` | Name of the env var that receives `app-version`. |
| `build-output-path` | no | `out` | Build output directory uploaded as the artifact. |
| `artifact-name` | no | `build-output` | Name of the uploaded artifact. |
| `artifact-retention-days` | no | `7` | Artifact retention. |

### `frontend-deploy`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `env` | yes | — | Target environment for the deploy. |
| `wif-provider` | no | `''` | GCP WIF provider resource name. Empty skips GCP auth. |
| `wif-service-account` | no | `''` | Service account impersonated via WIF. Required when `wif-provider` is set. |
| `aws-role-arn` | no | `''` | AWS IAM role to assume via OIDC. Empty skips AWS auth. |
| `aws-region` | no | `''` | AWS region for the assumed role. Required when `aws-role-arn` is set. |
| `artifact-name` | no | `build-output` | Artifact to download. |
| `build-output-path` | no | `out` | Local path the artifact is unpacked to. |
| `app-url` | no | `''` | Public URL shown in the run summary. |
| `app-version` | no | `''` | Version shown in the run summary. |

The caller passes whichever cloud auth applies; the unused auth step is skipped automatically.

### `backend-build`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `tags` | yes | — | Image tags to apply (one per line; each must be a full `registry/image:tag` URI). |
| `push` | no | `false` | Push the image after building. Set `false` for PR validation. |
| `registry` | no | `''` | Container registry hostname for docker login. Required when `push` is true. |
| `dockerfile` | no | `Dockerfile` | Path to the Dockerfile. |
| `context` | no | `.` | Build context directory. |
| `wif-provider` | no | `''` | GCP WIF provider resource name. Empty skips GCP auth. |
| `wif-service-account` | no | `''` | Service account impersonated via WIF. Required when `wif-provider` is set. |
| `aws-role-arn` | no | `''` | AWS IAM role to assume via OIDC. Empty skips AWS auth. |
| `aws-region` | no | `''` | AWS region for the assumed role. |

### `backend-deploy`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `image` | yes | — | Full image URI to deploy, including tag (e.g. `registry/image:1.2.3`). |
| `service-name` | yes | — | Name of the target service. |
| `region` | yes | — | Region the service runs in. |
| `env-secret` | no | `''` | Full resource path of a Secret Manager secret to load as runtime env vars. Empty skips the fetch. |
| `vpc-connector` | no | `''` | VPC connector name to attach to the service. Empty skips. |
| `extra-flags` | no | `''` | Additional deploy flags (one per line). |
| `env-vars-update-strategy` | no | `overwrite` | Strategy for updating env vars (`merge` or `overwrite`). |
| `wif-provider` | no | `''` | GCP WIF provider resource name. |
| `wif-service-account` | no | `''` | Service account impersonated via WIF. Required when `wif-provider` is set. |

Currently targets Google Cloud Run. Other runtimes can be added behind the same action later.

### `infra-plan`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `env` | yes | — | Target environment for the Terraform run. |
| `target` | no | `app` | Terraform target directory under `deploy/`. |
| `tf-version` | no | `1.x` | Terraform version. |
| `wif-provider` | no | `''` | GCP WIF provider resource name. Empty skips GCP auth. |
| `wif-service-account` | no | `''` | Service account impersonated via WIF. Required when `wif-provider` is set. |
| `aws-role-arn` | no | `''` | IAM role to assume via OIDC. Empty skips AWS auth. |
| `aws-region` | no | `''` | Region for the assumed role. |
| `github-token` | no | `''` | Token to post the plan as a PR comment. Empty skips the comment. |
| `plan-artifact-name` | no | `terraform-plan` | Name of the uploaded plan artifact. |
| `plan-extra-paths` | no | `''` | Extra paths (one per line) to ship alongside `plan.tfplan` — e.g. a Lambda module's `builds/` directory. |

On a pull request the plan is posted as a sticky PR comment. On a push the plan
file is uploaded as an artifact for the apply action to consume in the same run.

### `infra-apply`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `env` | yes | — | Target environment for the Terraform run. |
| `target` | no | `app` | Terraform target directory under `deploy/`. |
| `tf-version` | no | `1.x` | Terraform version. |
| `wif-provider` | no | `''` | GCP WIF provider resource name. Empty skips GCP auth. |
| `wif-service-account` | no | `''` | Service account impersonated via WIF. Required when `wif-provider` is set. |
| `aws-role-arn` | no | `''` | IAM role to assume via OIDC. Empty skips AWS auth. |
| `aws-region` | no | `''` | Region for the assumed role. |
| `plan-artifact-name` | no | `terraform-plan` | Plan artifact to download. Must match `infra-plan`. |

### `mobile-checks`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `node-version` | no | `20` | Node.js version. |

Runs `npm ci`, then `tsc --noEmit`, the `lint` script and the `test` script. Lint and test run only if the project defines those scripts (`npm run … --if-present`), and all three checks are informational — they never fail the job. Tests are forced into non-interactive CI mode so a watch-mode default can't hang.

### `mobile-build`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `expo-token` | yes | — | Expo access token with access to the project. |
| `profile` | yes | — | EAS build profile from `eas.json` (e.g. `production`, `preview`). |
| `platform` | no | `all` | Target platform: `android`, `ios`, or `all`. |
| `node-version` | no | `20` | Node.js version. |
| `wait` | no | `true` | Wait for the build to finish. Set `false` to queue and return immediately. |

Runs `eas build` for the given profile and platform. Waits by default so a later `mobile-deploy` (submit) step can pick up the finished build.

### `mobile-deploy`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `expo-token` | yes | — | Expo access token with access to the project. |
| `mode` | yes | — | `submit` (store submission) or `update` (over-the-air update). |
| `profile` | no | `production` | EAS profile for `submit` mode. |
| `platform` | no | `all` | Platform for `submit` mode: `android`, `ios`, or `all`. |
| `branch` | no | `''` | EAS Update branch for `update` mode (required in that mode). |
| `message` | no | `''` | Update message for `update` mode. Defaults to the commit SHA. |
| `node-version` | no | `20` | Node.js version. |

In `submit` mode runs `eas submit --latest` to send the most recent build to the stores. In `update` mode runs `eas update` to publish an over-the-air JS/asset update to the given channel.

### `announce`

| Input | Required | Default | Purpose |
| ----- | -------- | ------- | ------- |
| `result` | yes | — | Deploy result (`success` / `failure`). |
| `webhook-url` | no | `''` | Slack incoming webhook. Empty makes the action a no-op. |
| `label` | no | `Deployment` | Short label for the message. |
| `version` | no | `''` | Version shown in the message. |

Best-effort: a missing webhook never fails the pipeline.

### Usage

Each action is referenced as a single step of a job. Project-specific values
are supplied by the caller (often from its own `env:` block or secrets):

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: nurdsoft/ci-workflows/actions/frontend-build@v1
        with:
          env: <env>
          app-version: ${{ needs.version.outputs.version }}
```

## Versioning

Callers pin to the major tag (`@v1`) for both the reusable workflow and the
composite actions. That tag is moved on each non-breaking release so updates
reach consumers deliberately. A breaking change is published under a new major
tag, leaving `@v1` in place for un-migrated callers.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full
flow. In short: open a pull request with a Conventional Commit title, keep every
change generic and backward-compatible, and validate it against a real consumer
before merge.
