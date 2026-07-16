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
| `.github/workflows/version.yml` | Reusable workflow | Cut a SemVer release — detects RC line, cuts the release, and creates the next RC baseline automatically |
| `actions/auth`   | Action | Obtain cloud credentials (OIDC) |
| `actions/setup`  | Action | Install runtime + deps (+ EAS login) |
| `actions/verify` | Action | Lint / type-check / test |
| `actions/build`  | Action | Produce a deployable artifact — static or Docker image |
| `actions/deploy` | Action | Ship the artifact — static site, Cloud Run service, or Cloud Run job (+ optional Cloud Scheduler) |
| `actions/plan`   | Action | Preview an infrastructure change |
| `actions/apply`  | Action | Apply an infrastructure change |
| `actions/notify` | Action | Post the pipeline result as a rich Slack card |
| `actions/enforce` | Action | Merge-time gate — revert a merge whose PR had an empty description and return `block` (+ alert content) so the caller stands its release down |

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

**App pipeline — static site (verify, release, build, deploy)**

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

**App pipeline — Docker + Cloud Run (release, build, deploy)**

Activated by passing `image-name` to `build` and `cloudrun-service` to `deploy`. The static-build and static-deploy steps are skipped automatically — existing callers are unaffected.

```yaml
jobs:
  version:
    uses: nurdsoft/ci-workflows/.github/workflows/version.yml@v2
    permissions: { contents: write }

  build:
    needs: [version]
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: nurdsoft/ci-workflows/actions/build@v2
        with:
          gcp-wif-provider: ${{ secrets.GCP_WIF_PROVIDER }}
          gcp-service-account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
          gcp-project-id: ${{ secrets.GCP_PROJECT_ID }}
          gcp-region: ${{ secrets.GCP_REGION }}
          gcp-repository: ${{ secrets.GCP_REPOSITORY }}
          image-name: ${{ secrets.IMAGE_NAME }}
          gcp-secret-name: ${{ secrets.GCP_SECRET_NAME }}   # fetched → .env.production at build time

  deploy:
    needs: [build]
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: nurdsoft/ci-workflows/actions/deploy@v2
        with:
          gcp-wif-provider: ${{ secrets.GCP_WIF_PROVIDER }}
          gcp-service-account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
          gcp-project-id: ${{ secrets.GCP_PROJECT_ID }}
          gcp-region: ${{ secrets.GCP_REGION }}
          gcp-repository: ${{ secrets.GCP_REPOSITORY }}
          image-name: ${{ secrets.IMAGE_NAME }}
          cloudrun-service: ${{ secrets.CLOUDRUN_SERVICE_NAME }}
          gcp-secret-name: ${{ secrets.GCP_SECRET_NAME }}   # fetched → injected as Cloud Run env vars
          cloudrun-flags: "--allow-unauthenticated --ingress=internal-and-cloud-load-balancing"
```

**App pipeline — GHCR pull + retag + Cloud Run (pre-built image)**

For services whose Docker image is built and published to GHCR by a separate process (e.g. a commerce platform). Activated by passing `ghcr-image` to `build` alongside `image-name`. The action pulls the pre-built image, re-tags it for GCP Artifact Registry (SHA + latest), and pushes it — no Dockerfile or build-time secrets required. Takes priority over the Docker build+push path.

```yaml
jobs:
  version:
    uses: nurdsoft/ci-workflows/.github/workflows/version.yml@v2
    permissions: { contents: write }

  build:
    needs: [version]
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: nurdsoft/ci-workflows/actions/build@v2
        with:
          gcp-wif-provider: ${{ secrets.GCP_WIF_PROVIDER }}
          gcp-service-account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
          gcp-project-id: ${{ secrets.GCP_PROJECT_ID }}
          gcp-region: ${{ secrets.GCP_REGION }}
          gcp-repository: ${{ secrets.GCP_REGISTRY }}
          image-name: ${{ vars.SERVICE_NAME }}
          ghcr-image: ghcr.io/org/repo:latest   # source image; triggers pull+retag path

  deploy:
    needs: [build]
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: nurdsoft/ci-workflows/actions/deploy@v2
        with:
          gcp-wif-provider: ${{ secrets.GCP_WIF_PROVIDER }}
          gcp-service-account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
          gcp-project-id: ${{ secrets.GCP_PROJECT_ID }}
          gcp-region: ${{ secrets.GCP_REGION }}
          gcp-repository: ${{ secrets.GCP_REGISTRY }}
          image-name: ${{ vars.SERVICE_NAME }}
          cloudrun-service: ${{ vars.SERVICE_NAME }}
          gcp-secret-name: ${{ secrets.GCP_SECRET_NAME }}
          cloudrun-flags: >-
            --vpc-connector="${{ secrets.GCP_VPC_CONNECTOR }}"
            --ingress=internal-and-cloud-load-balancing
```

**App pipeline — Docker + Cloud Run job with Cloud Scheduler**

Activated by passing `cloudrun-job` to `deploy` instead of `cloudrun-service`. Optionally reconciles a Cloud Scheduler trigger (created if missing, updated if existing) when `scheduler-name` and `schedule-time` are set.

```yaml
jobs:
  version:
    uses: nurdsoft/ci-workflows/.github/workflows/version.yml@v2
    permissions: { contents: write }

  build:
    needs: [version]
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: nurdsoft/ci-workflows/actions/build@v2
        with:
          gcp-wif-provider: ${{ secrets.GCP_WIF_PROVIDER }}
          gcp-service-account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
          gcp-project-id: ${{ secrets.GCP_PROJECT_ID }}
          gcp-region: ${{ secrets.GCP_REGION }}
          gcp-repository: ${{ secrets.GCP_REPOSITORY }}
          image-name: ${{ secrets.IMAGE_NAME }}
          gcp-secret-name: ${{ secrets.GCP_SECRET_NAME }}

  deploy-job:
    needs: [build]
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - uses: nurdsoft/ci-workflows/actions/deploy@v2
        with:
          gcp-wif-provider: ${{ secrets.GCP_WIF_PROVIDER }}
          gcp-service-account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
          gcp-project-id: ${{ secrets.GCP_PROJECT_ID }}
          gcp-region: ${{ secrets.GCP_REGION }}
          gcp-repository: ${{ secrets.GCP_REPOSITORY }}
          image-name: ${{ secrets.IMAGE_NAME }}
          cloudrun-job: ${{ secrets.CLOUDRUN_JOB_NAME }}
          gcp-secret-name: ${{ secrets.GCP_SECRET_NAME }}
          cloudrun-flags: >-
            --command="/app/server"
            --args="worker"
            --vpc-connector=${{ secrets.VPC_CONNECTOR }}
          scheduler-name: my-job-scheduler-trigger   # omit to skip scheduler management
          schedule-time: "0 * * * *"                 # cron expression — hourly
```

**Cloud Scheduler IAM prerequisite**

When `scheduler-name` and `schedule-time` are set, the deploy step creates a Cloud Scheduler trigger that invokes the Cloud Run job as the deploy SA. For the scheduler to impersonate that SA, the Cloud Scheduler service agent `service-<PROJECT_NUMBER>@gcp-sa-cloudscheduler.iam.gserviceaccount.com` must hold `roles/iam.serviceAccountTokenCreator` on the deploy SA. Existing projects with prior Cloud Scheduler usage already have this binding; new consumers must add it explicitly — without it the trigger is created successfully but never fires.

```bash
gcloud iam service-accounts add-iam-policy-binding "<DEPLOY_SA_EMAIL>" \
  --member="serviceAccount:service-<PROJECT_NUMBER>@gcp-sa-cloudscheduler.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
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

## version.yml — inputs

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `changelog-on-default` | boolean | `true` | Generate + commit `CHANGELOG.md` on the default branch (stable releases). |
| `changelog-on-rc` | boolean | `false` | Generate + commit `CHANGELOG.md` on RC (non-default) branches. Set to `true` if you want a running changelog on `dev` as well. |
| `rc-branch` | string | `dev` | Branch where RC releases are cut. Used to create the next RC baseline after a stable release. |
| `semrel-version` | string | `v2.31.0` | go-semantic-release binary version. |
| `semrel-sha256` | string | `''` | Expected SHA-256 of the binary for integrity verification. Empty skips the check (logs a warning). |

**Changelog behaviour**

| Branch | `changelog-on-default` | `changelog-on-rc` | Result |
|--------|------------------------|-------------------|--------|
| `main` | `true` | any | `CHANGELOG.md` generated and committed on every stable release |
| `dev` | any | `true` | `CHANGELOG.md` generated and committed on every RC release |
| `dev` | any | `false` (default) | No changelog on dev — commit step is skipped entirely |

Example — changelog on both branches:

```yaml
version:
  uses: nurdsoft/ci-workflows/.github/workflows/version.yml@v3
  permissions: { contents: write }
  with:
    changelog-on-default: true
    changelog-on-rc: true
```

## enforce — inputs & outputs

Merge-time gate that enforces non-empty PR descriptions. Call it as the **first
step** of a job at the top of your pipeline, gated to the branch you protect.
On a push whose merge commit traces to a PR with an empty (or whitespace-only)
body, it reverts the merge on that branch, edits the PR to explain, and returns
`block=true`; downstream jobs read `needs.<guard-job>.outputs.block != 'true'`
and stand down. A PR-fetch API error fails **safe** (skips, never
false-reverts); a rejected push or a revert conflict keeps `block=true` and
reports "revert by hand".

It reverts a merge commit via `git revert -m 1` and a squash/rebase merge via
the `before..HEAD` range, so all three GitHub merge styles are fully undone.

Because it's a composite action, the alert is posted in the **same job**: the
Slack webhook (typically an environment-scoped secret) resolves inline, so no
separate output-threaded alert job is needed. It emits the alert content as
step outputs; feed those directly into a `notify` step in the same job.

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `label` | string | no | `Service` | Short name shown in the alert header the caller renders (e.g. `Backend`, `Web`). |
| `github-token` | string | no | `${{ github.token }}` | Token used to read the PR, push the revert, and edit the PR body. Override with a GitHub-App token for cross-org. |

| Output | Description |
|--------|-------------|
| `block` | `'true'` when the merge was reverted and the caller's release must stand down. |
| `outcome` | Empty when nothing was done; else `reverted` \| `push_failed` \| `conflict`. Gate the notify step on `outcome != ''`. |
| `header` | Alert header line for the caller's Slack card. |
| `color` | Alert colour bar (hex) for the caller's Slack card. |
| `reason` | Alert status line for the caller's Slack card. |

Grant `contents: write` + `pull-requests: write` on the calling job. To surface
the alert on Slack, add a follow-up step in the same job (the environment-scoped
webhook resolves directly there) that renders the card via `notify` from the
guard's outputs. Expose `block` as a job-level output so downstream jobs can
gate on it.

```yaml
jobs:
  guard:
    if: github.event_name == 'push' && github.ref_name == 'dev'
    runs-on: ubuntu-latest
    environment: dev                              # so ${{ secrets.SLACK_WEBHOOK_URL }} resolves
    permissions: { contents: write, pull-requests: write }
    outputs:
      block: ${{ steps.g.outputs.block }}
    steps:
      - id: g
        uses: nurdsoft/ci-workflows/actions/enforce@v3
        with:
          label: Backend

      # Alert on Slack when the guard acted; on a clean merge this step skips.
      # Best-effort — a missing/failed webhook never fails the job.
      - if: ${{ steps.g.outputs.outcome != '' }}
        uses: nurdsoft/ci-workflows/actions/notify@v3
        with:
          result: failure
          webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
          label: Backend
          header: ${{ steps.g.outputs.header }}
          color:  ${{ steps.g.outputs.color }}
          status: ${{ steps.g.outputs.reason }}

  release:
    needs: [guard]
    # !cancelled() so a skipped guard (e.g. non-dev push) doesn't skip release;
    # block=true stands it down; a guard that *failed* fails closed.
    if: ${{ !cancelled() && needs.guard.result != 'failure' && needs.guard.outputs.block != 'true' }}
    # ...
```

## notify — inputs

Posts a rich Slack card for a pipeline result: a green/red header
(`<label> — succeeded|failed`), a Version field, and the **PR** this deploy
traces to (title + clickable `owner/repo#NN`). With no PR it falls back to the
**commit** (subject + clickable short SHA), and with neither to a single-line
text message. A context line shows the author, the UTC build date
(`YYYY.MM.DD`), and a link to the run. The build date is stamped by the action
so the deploy date reads unambiguously rather than being inferred from Slack's
local-timezone message timestamp.
Best-effort: an empty `webhook-url` is a no-op that still succeeds, and a failed
post never fails the pipeline.

The `header`, `color`, and `status` inputs turn the same card into a general
**alert** (e.g. a revert or guard notice) instead of a deploy result: supply a
custom title and color bar, and the first field becomes **Status** instead of
**Version**. The PR/commit resolution, body, and context line are unchanged, so
the card still shows the PR (or commit) that `target-sha` traces to. Omit all
three and the card is exactly the deploy-result card above.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `result` | yes | — | `success` / `failure` — e.g. a deploy job's `result`. Anything other than `success` renders as failed. |
| `webhook-url` | no | `''` | Slack incoming webhook URL. Empty makes the action a no-op. |
| `label` | no | `Deployment` | Short label for the card header (app / component name). |
| `version` | no | `''` | Version string shown in the Version field (`n/a` if empty). |
| `header` | no | `''` | Full header line, verbatim, overriding the default `<emoji> <label> — <status>`. May contain Slack emoji shortcodes. |
| `color` | no | `''` | Attachment bar color (hex) overriding the result-derived green/red. |
| `status` | no | `''` | When set, the first field renders as **Status** with this text in place of the **Version** field. |
| `channel` | no | `slack` | Chat channel; only `slack` is implemented today. |
| `github-token` | no | `${{ github.token }}` | Token used to read the PR/commit. The default job token covers a same-repo deploy; for a cross-org deploy pass a token minted in the caller from a GitHub App with read access to `target-repo`. |
| `target-repo` | no | `${{ github.repository }}` | `owner/repo` whose PR/commit the card describes. Override for a cross-repo deploy. |
| `target-sha` | no | `${{ github.sha }}` | Exact built/deployed commit SHA used to resolve the PR/commit. |

Example — same-repo deploy (token/target default to this repo):

```yaml
  announce:
    needs: deploy
    if: ${{ always() && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    permissions: { contents: read, pull-requests: read }
    steps:
      - uses: nurdsoft/ci-workflows/actions/notify@v3
        with:
          result: ${{ needs.deploy.result }}
          label: "Backend (${{ github.ref_name == 'prod' && 'Prod' || 'Dev' }})"
          version: ${{ needs.deploy.outputs.version }}
          webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
```

Example — cross-org deploy (card describes a PR/commit in another repo):

```yaml
      - uses: actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547  # v1.12.0
        id: app-token
        with:
          app-id: ${{ vars.READ_APP_ID }}
          private-key: ${{ secrets.READ_APP_KEY }}
          owner: other-org
          repositories: other-repo
      - uses: nurdsoft/ci-workflows/actions/notify@v3
        with:
          result: ${{ needs.deploy.result }}
          label: "Web (Prod)"
          version: ${{ needs.build.outputs.app_version }}
          webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
          github-token: ${{ steps.app-token.outputs.token }}
          target-repo: other-org/other-repo
          target-sha: ${{ needs.build.outputs.app_sha }}
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

> **Docker / Cloud Run path**: when `image-name` (build) or `cloudrun-service` / `cloudrun-job` (deploy) is set,
> the runner contract is bypassed entirely — the action handles auth, build, and deploy
> against GCP Artifact Registry and Cloud Run directly. No Makefile targets required.
>
> **Cloud Run job path**: when `cloudrun-job` (deploy) is set instead of `cloudrun-service`, the action
> deploys a Cloud Run job and optionally reconciles a Cloud Scheduler trigger (created if missing,
> updated if existing). Pass `scheduler-name` and `schedule-time` to enable scheduling; omit both to skip it.
>
> **GHCR pull + retag path**: when `ghcr-image` (build) is also set, the action pulls the
> pre-built image from GHCR and re-tags it for Artifact Registry instead of building from
> source. No Dockerfile or build-time secrets needed.

## Versioning

Pin to the major tag (`@v2`). Breaking changes ship under a new major; the
previous major stays in place for un-migrated callers. Third-party actions are
SHA-pinned and bumped by Dependabot.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). PRs are linted with `actionlint` (and
shellcheck over composite `run:` blocks) via `.github/workflows/ci.yml`.
