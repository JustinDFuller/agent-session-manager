## Why

The current required OpenSpec gate makes the base pull request responsible for completing and archiving the change. That conflicts with a protected, no-force-push workflow and prevents a stacked sequence from progressing naturally through implementation and QA before finalization.

The workflow needs to preserve strict OpenSpec coverage while making the current top pull request the finalization point, including after GitHub collapses a stack as lower pull requests merge.

## What Changes

- Replace base-pull-request archive ownership with dynamic top-of-stack archive ownership using GitHub's current stack position and size.
- Require standalone pull requests and the current top stack pull request to introduce a new OpenSpec change and finish it with complete tasks, synchronized main specifications, and no active change remaining.
- Allow non-top stack pull requests to carry the same valid active change set while implementation and QA proceed; unchecked tasks and active changes are allowed until the archive pull request.
- Prove that the change set is new relative to the stack trunk, so an existing archived change cannot satisfy the requirement, while preserving identity when lower pull requests have temporarily landed on `main`.
- Require the final archive pull request to be standalone: its direct change is limited to archiving the exact active change set and synchronizing its main specifications.
- Update the base-owned CI validator, workflow, regression tests, guide comment, and OpenSpec documentation to describe and enforce the new lifecycle.
- Document and verify the external `main` ruleset configuration that blocks force pushes and requires the stable `openspec-check` status; do not make CI mutate repository administration settings.

## Capabilities

### New Capabilities

- `openspec-merge-gate`: Enforces OpenSpec presence, shared change identity, phase-aware completion, and final archival across standalone and stacked pull requests.

### Modified Capabilities

- None

## Impact

- GitHub Actions workflow and base-branch-owned validator under `.github/`.
- Validator regression tests covering stack phases, stack collapse, new-change proof, and archive-only finalization.
- `openspec/README.md`, `openspec/config.yaml`, and the informational guide comment's workflow guidance.
- External `main` ruleset verification for required checks and non-fast-forward protection.

### Deliberately out of scope

- Changes to the OpenSpec schema, pinned CLI version, or application runtime behavior.
- Enforcing a minimum four-pull-request stack; four is the intended decomposition, but standalone and shorter stacks remain supported.
- Automatic archiving, rebasing, force pushing, or mutation of GitHub rulesets by CI.
