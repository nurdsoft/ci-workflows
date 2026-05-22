# ci-workflows

Reusable, function-named CI/CD building blocks for Nurdsoft projects.

Each action is named for the **pipeline function** it performs, not a language
or tool — so the implementation underneath is pluggable while the public
interface stays stable. The repo ships three concerns and keeps only the
generic two: it **provisions** (auth, toolchain install) and **orchestrates**
(artifacts, PR comments, notifications); the project-specific **commands** live
behind a runner contract you control (or pass inline via `run`).

## Contents

| Path | Type | Function |
|------|------|----------|
| `.github/workflows/version.yml` | Reusable workflow | Cut a SemVer release |
| `actions/auth`   | Action | Obtain cloud credentials (OIDC) |
| `actions/setup`  | Action | Install runtime + deps (+ EAS login) |
| `actions/verify` | Action | Lint / type-check / test |
| `actions/build`  | Action | Produce a deployable artifact |
| `actions/deploy` | Action | Ship the artifact |
| `actions/plan`   | Action | Preview an infrastructure change |
| `actions/apply`  | Action | Apply an infrastructure change |
| `actions/notify` | Action | Post the pipeline result |

## Design

- **Function-named directories** — swap Node→Bun or GCP→AWS by changing inputs,
  not the directory.
- **No forced Makefile** — phase actions take a `run` command (or a `runner`);
  `make` is only the default our repos opt into (see [Runner contract](#runner-contract)).
- **Provision vs execute vs orchestrate** — credentials and tools are installed
  here; the commands that use them live in the consumer.
- **Reusable workflow for release** — `version.yml` is a workflow (not an
  action) because cutting a release needs its own `contents: write` job.

## Usage

Callers wire the actions into a job graph and supply their own values. Two
illustrative shapes:

**App pipeline — verify, release, build, deploy**

```yaml
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: nurdsoft/ci-workflows/actions/verify@v2

  version:
    needs: [verify]
    uses: nurdsoft/ci-workflows/.github/workflows/version.yml@v2
    permissions: { contents: write }
    with:
      rc-line: "1-rc"          # rc off non-default branches; stable on default

  build:
    needs: [version]
    runs-on: ubuntu-latest
    steps:
      - uses: nurdsoft/ci-workflows/actions/build@v2
        with:
          run: <your build command>     # or rely on `make build`
          output: artifact

  deploy:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - uses: nurdsoft/ci-workflows/actions/deploy@v2
        with:
          run: <your deploy command>    # or rely on `make deploy`
          download-artifact: "true"
          gcp-wif-provider: ${{ secrets.WIF_PROVIDER }}
          gcp-service-account: ${{ secrets.SERVICE_ACCOUNT }}
```

**Infrastructure pipeline — plan then apply the same plan**

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: nurdsoft/ci-workflows/actions/plan@v2
        with:
          env: <env>
          aws-role-arn: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

  apply:
    needs: [plan]
    runs-on: ubuntu-latest
    steps:
      - uses: nurdsoft/ci-workflows/actions/apply@v2
        with:
          env: <env>
          aws-role-arn: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
```

## Runner contract

Phase actions (`build`, `deploy`, `plan`, `apply`) run a command — supply it any
of three ways: pass `run`/`run-*` directly (no Makefile), set `runner` to your
tool (`just`, `task`, `npm run`), or implement the default `make` targets.

| Phase  | Default command(s)                  | Env provided      |
|--------|-------------------------------------|-------------------|
| build  | `make build`                        | ENV, APP_VERSION* |
| deploy | `make deploy`                       | ENV               |
| plan   | `make tf-init`, `make tf-plan` (+ `tf-fmt`/`tf-validate` for terraform) | ENV, TARGET |
| apply  | `make tf-init`, `make tf-apply`     | ENV, TARGET       |

\* `build` exports `APP_VERSION` under the name given by `version-env-var`.

Self-contained — no contract, no Makefile: `auth`, `setup`, `verify`, `notify`,
and the `version.yml` reusable workflow.

## Versioning

Pin to the major tag (`@v2`). Breaking changes ship under a new major; the
previous major stays in place for un-migrated callers. Third-party actions are
SHA-pinned and bumped by Dependabot.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). PRs are linted with `actionlint` (and
shellcheck over composite `run:` blocks) via `.github/workflows/ci.yml`.
