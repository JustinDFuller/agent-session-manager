# Design

## Context

Both hooks live in `.githooks/` and are selected for every worktree through `core.hooksPath`, which `make setup-hooks` points at the main checkout. The pre-commit hook runs `swift test`, `swift-format lint`, and `swiftlint` unconditionally. The pre-push hook runs `make test-ui-dev-launch` unconditionally. `scripts/test-git-hooks.sh` runs both hooks against stub tools to prove that disposable fixture repositories never recurse into the hooks. See proposal.md for why these hooks are the only gate for unit and UI tests today.

Existing Makefile targets already cover most cheap checks: `no-code-comments`, `no-fixed-width-prose`, `docs-check`, and `test-ui-dev-launch`. `scripts/check-docs.sh` and `scripts/test-release-publishing.sh` cover documentation, and `.github/scripts/*.test.mjs` hold the CI script tests.

## Goals / Non-Goals

**Goals:**

- One shared runner decides what to run for both hooks so the commit and push behavior cannot drift apart.
- A wrong skip must be impossible to cause by adding a new kind of file.
- The behavior is testable with stub tools, with no real Swift build.

**Non-Goals:**

- A general-purpose hook framework or a new dependency.
- Caching results between runs or parallelizing checks.
- Making `--no-verify` harder or easier to use.

## Decisions

### One runner script, thin hook wrappers

`scripts/git-hook-checks.sh` takes a mode (`pre-commit` or `pre-push`) and owns change detection, classification, ordering, and reporting. `.githooks/pre-commit` and `.githooks/pre-push` keep the existing `cd` to the top level and `unset` of inherited Git variables, then run the runner. Keeping the `unset` line in the wrappers preserves the fixture isolation requirement in native-test-validation.

Alternative: duplicate logic in each hook. Rejected because classification and ordering would diverge.
Alternative: adopt lefthook or the pre-commit framework. Rejected because it adds a tool every contributor and agent must install, for a ruleset this small.

### Changed files per mode

- Commit: `git diff --cached --name-only`.
- Push: read the ref lines Git supplies on standard input, ignore deletions, and for each pushed ref list files from `git log --name-only -m <local-sha> --not --remotes=<remote>`. The `--remotes` exclusion treats every commit the remote already has as checked, which keeps stacked branches and follow-up evidence pushes cheap and counts rewritten commits as new.
- If the remote name is unknown (for example a URL was pushed to), a Git command fails, or the output cannot be read, the change set is marked undetermined and classified as native.

Alternative: compare against the default branch. Rejected because a documentation-only push onto a branch that already has code would still run everything, which is the case that prompted this change.

### Allowlist classification, fail safe

Each path maps to the first matching group; no match means native.

| Group | Paths |
|---|---|
| openspec | `openspec/**` |
| docs | `documentation/**`, root `*.md`, `_config.yml`, `_data/**`, `_layouts/**`, `assets/**`, `Gemfile*`, `favicon.ico`, `CNAME`, `scripts/check-docs*`, `scripts/test-release-publishing.sh` |
| evidence | `screenshots/**`, image and video files, `.claude/skills/**`, `.agents/skills/**` |
| ci-scripts | `.github/scripts/**` |
| hooks | `.githooks/**`, `scripts/git-hook-checks.sh`, `scripts/test-git-hooks.sh` |
| native | everything else, including `Sources/`, `Tests/`, `UITests/`, `Package.*`, `project.yml`, `Makefile`, other `scripts/`, plists, entitlements, lint configuration, and `.github/workflows/**` |

A path can belong to more than one group when it triggers more than one check (for example a hook script is both `hooks` and `native` because the hook tests and the full ladder both apply to a change in the runner). Groups only ever add checks; `native` is the superset.

Alternative: denylist native paths. Rejected because a new source directory would silently skip unit tests, and CI does not backstop them.

### Check ladder

| Order | Check | Runs when | Commit | Push |
|---|---|---|---|---|
| 1 | `make no-code-comments`, `make no-fixed-width-prose` | any change | yes | yes |
| 2 | `openspec validate --all --strict` | openspec | yes | yes |
| 3 | `swift-format lint`, `swiftlint lint --strict` | native | yes | yes |
| 4 | `node --test .github/scripts/*.test.mjs` | ci-scripts | no | yes |
| 5 | `bash scripts/test-git-hooks.sh` | hooks | no | yes |
| 6 | `make docs-check`, `scripts/test-release-publishing.sh` | docs | no | yes |
| 7 | `swift test` | native | no | yes |
| 8 | `make test-ui-dev-launch` | native | no | yes |

The commit column holds only checks that finish in seconds on typical changes. Everything slower waits for push, where the full ladder for the pushed commits runs once instead of once per commit. A failing step exits immediately, so cheaper steps always surface first.

### Reporting

Each tier prints a `==> Running <check>` or `==> Skipping <check> (<reason>)` line, and the runner ends with a one-line summary of the groups it found. The `swift test` step keeps today's behavior of filtering output to errors on failure.

### Testing the runner

`scripts/test-git-hooks.sh` already puts recording stubs for `swift`, `make`, `swift-format`, and `swiftlint` first on `PATH`. The runner is tested the same way, adding stubs for `node` and `openspec` and a throwaway bare remote. Cases cover: documentation-only commit and push skip heavy stubs; a Swift commit runs the fast stubs and not `swift`; an unknown path runs everything; a failing lint stub prevents `swift` from starting; and a follow-up documentation push on an already-pushed native commit runs no heavy stub. The existing recursion cases are updated so their fixture commit stages a native file.

## Risks / Trade-offs

- Broken tests can now be committed locally and are caught at push, not commit → the push gate is unchanged in strength, and the push still runs before anything reaches the remote.
- A stale remote-tracking ref can make the runner see commits as unpushed → it runs extra checks, never fewer.
- A native commit made with `--no-verify` and not yet pushed still counts at the next push → the unpushed range includes it, so it is checked.
- The classification list can go stale as directories are added → unknown paths default to native, and the hook tests assert that default.
- Hooks only take effect after the main checkout updates → recorded in the proposal follow-ups.

## Open Questions

- None that affect the specs, approach, or tasks.
