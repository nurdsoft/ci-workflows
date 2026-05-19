# Contributing

Thanks for improving the shared CI/CD library. The workflows and actions here
are consumed by many repositories, so a small, consistent process keeps every
consumer safe.

## Principles

- **Stay generic.** Nothing here may contain project-specific values — identity
  providers, regions, bucket names, URLs, environment or component names. Every
  such value is an input supplied by the caller.
- **Stay backward-compatible.** Consumers pin the major tag (`@v1`). Additive
  changes are fine; anything that would break an existing caller is a breaking
  change — see [Versioning](#versioning).
- **One concern per pull request.** Keep changes focused and reviewable.
- **Document what you change.** Update `README.md` whenever an input, action or
  workflow is added or changed.

## Workflow

1. **Branch** from `main`, named for the change: `feat/...`, `fix/...`,
   `chore/...`, `docs/...`, or `ci/...`.
2. **Commit** using [Conventional Commits](https://www.conventionalcommits.org)
   (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`). The commit history is the
   record of what changed and why.
3. **Test against a real consumer.** Point a consuming repository's workflow at
   your branch or commit SHA — `uses: nurdsoft/ci-workflows/...@<branch-or-sha>`
   — and confirm a run succeeds before requesting review. Workflow and action
   changes cannot be meaningfully tested in isolation.
4. **Open a pull request** into `main`. Describe what changed and how it was
   verified. Request review from a maintainer.
5. **Merge** once approved and checks pass. Squash so each change is one clean
   commit on `main`.

## Versioning

Consumers pin the moving major tag (`@v1`).

- **Additive or fixed** — move the `v1` tag forward to the merge commit.
- **Breaking** — anything that removes or renames an input, or changes behavior
  a caller relies on. Publish it under a new major tag (`v2`) and leave `v1` in
  place for callers that have not migrated.

If you are unsure whether a change is breaking, assume it is and discuss it in
the pull request.
