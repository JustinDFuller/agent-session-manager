# Proposal

## Why

The repository's Git hooks run the full unit suite on every commit and the full native UI smoke suite on every push, no matter what changed. Pushing a markdown file of QA evidence costs the same minutes as pushing a Swift change. The slowest check also runs first, so a formatting mistake surfaces only after the unit suite passes, and several cheap checks that CI enforces (no code comments, fixed-width prose, OpenSpec validation, documentation build) never run locally at all.

Unit and UI tests do not run in GitHub Actions while the `ENABLE_MACOSX_JOBS` variable is `false`, so these hooks are currently the only place those tests run. Any narrowing must therefore skip heavy checks only when it can prove the change cannot affect them.

## What Changes

- Replace the always-run commit and push hooks with a shared runner that classifies changed files and runs only the checks that apply, cheapest first, stopping at the first failure.
- Commits run only fast checks against the staged files. Heavy checks (`swift test`, native UI smoke tests) move to push.
- Pushes evaluate only the commits that are not yet on the remote, so follow-up pushes of evidence or documentation to an already-pushed code branch stay fast.
- Classification is allowlist-based and fails safe: any path not known to be non-native, and any failure to determine the changed files, runs the full set of checks.
- Add checks that CI enforces but the hooks never ran: no code comments, fixed-width prose, OpenSpec validation, CI script tests, hook fixture tests, and the documentation build.
- Print which checks ran and which were skipped, with the reason, so a skip is never silent.
- Update the pre-push native validation requirement so native launch validation runs when the pushed commits include native changes, rather than on every push.

Out of scope:

- Changing which checks CI runs, or re-enabling macOS jobs in CI.
- Adding new test suites or changing the content of existing tests.
- Changing how hooks are installed (`make setup-hooks` and the shared hooks path stay as they are).
- Bypass flags or environment variables to skip hooks; `git --no-verify` remains the only escape hatch.

## Capabilities

### New Capabilities

- `git-hook-validation`: Which local checks run at commit and push, how changed files are classified, the order checks run in, and how skips are reported.

### Modified Capabilities

- `native-test-validation`: The pre-push native validation scenario now applies when the pushed commits include native changes. The hook fixture isolation requirement is unchanged.

## Impact

- `.githooks/pre-commit` and `.githooks/pre-push` become thin wrappers around a new shared runner script under `scripts/`.
- `scripts/test-git-hooks.sh` gains cases for classification, fail-fast ordering, and push scoping, and its existing recursion checks keep working.
- `.github/workflows/git-hooks.yml` path filters include the new runner.
- `AGENTS.md` and any public documentation page that describes the hooks are updated.
- Every worktree shares the main checkout's `.githooks`, so the new behavior takes effect only after this change is merged and the main checkout is updated.

## Follow-ups after merge

- Pull the merged change into the main checkout so every worktree picks up the new hooks.
