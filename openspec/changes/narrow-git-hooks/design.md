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

`scripts/git-hook-checks.sh` takes a mode (`pre-commit` or `pre-push`) and owns change detection, classification, ordering, and reporting. `.githooks/pre-commit` and `.githooks/pre-push` keep the existing `cd` to the top level, then run the runner. The runner reads the changed files first and only then unsets the inherited Git variables (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR`, `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`), because `GIT_INDEX_FILE` selects the temporary index when `git commit <paths>` runs the hook. Unsetting before every check preserves the fixture isolation requirement in native-test-validation.

The wrapper resolves the runner relative to the hooks' own checkout rather than the current worktree, so the hooks and the runner always version together and a branch that predates the runner still finds it. The checks themselves still run against the current worktree's files and Makefile.

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
| docs | `documentation/**`, root `*.md`, `_config.yml`, `_data/**`, `_layouts/**`, `assets/**`, `Gemfile*`, `favicon.ico`, `CNAME`, `scripts/check-docs.sh`, `scripts/check-docs-taxonomy.rb`, `scripts/test-release-publishing.sh` |
| evidence | `screenshots/**`, `.claude/skills/**`, `.agents/skills/**` |
| ci-scripts | `.github/scripts/**` |
| hooks | `.githooks/**`, `scripts/git-hook-checks.sh`, `scripts/test-git-hooks.sh` |
| native | everything else, including `Sources/`, `Tests/`, `UITests/`, `Package.*`, `project.yml`, `Makefile`, other `scripts/`, plists, entitlements, lint configuration, and `.github/workflows/**` |

A path can belong to more than one group when it triggers more than one check (for example a hook script is both `hooks` and `native` because the hook tests and the full ladder both apply to a change in the runner). Groups only ever add checks; `native` is the superset.

Alternative: denylist native paths. Rejected because a new source directory would silently skip unit tests, and CI does not backstop them.

### Check ladder

| Order | Check | Runs when | Commit | Push |
|---|---|---|---|---|
| 1 | `make no-code-comments`, `make no-fixed-width-prose` | any change | yes | yes |
| 2 | `openspec validate --archived`, `--changes --strict`, `--specs` | openspec | yes | yes |
| 3 | `swift-format lint`, `swiftlint lint --strict` | native | yes | yes |
| 4 | `node --test .github/scripts/*.test.mjs` | ci-scripts | no | yes |
| 5 | `bash scripts/test-git-hooks.sh` | hooks | no | yes |
| 6 | `make docs-check`, `scripts/test-release-publishing.sh` | docs | no | yes |
| 7 | `swift test` | native | no | yes |
| 8 | `make test-ui-dev-launch` | native | no | yes |

The OpenSpec step validates archived changes, active changes (strict), and main specs (non-strict) separately instead of `--all --strict`, because newer local CLI versions flag long requirements in existing main specs that the CI-pinned version accepts. An image or video outside `screenshots/` is not treated as evidence: under `documentation/` or `assets/` it counts as documentation, and elsewhere, for example under `Sources/`, it is native because it can change the app.

The commit column holds only checks that finish in seconds on typical changes. Everything slower waits for push, where the full ladder for the pushed commits runs once instead of once per commit. A failing step exits immediately, so cheaper steps always surface first.

### Reporting

Each tier prints a `==> Running <check>` or `==> Skipping <check> (<reason>)` line, the runner prints the file groups it found before running anything, and it ends with a line saying every applicable check passed. The `swift test` step keeps today's behavior of filtering output to errors on failure.

### Testing the runner

`scripts/test-git-hooks.sh` already puts recording stubs for `swift`, `make`, `swift-format`, and `swiftlint` first on `PATH`. The runner is tested the same way, adding stubs for `node` and `openspec` and a throwaway bare remote. An empty change set (an empty commit, or a push with nothing new) runs no checks and says so. The fixture repository has a configured remote named `origin`, and one case pushes to a bare path to prove the undetermined fallback. Cases cover: documentation-only commit and push skip heavy stubs; a Swift commit runs the fast stubs and not `swift`; an unknown path runs everything; a failing lint stub prevents `swift` from starting; and a follow-up documentation push on an already-pushed native commit runs no heavy stub. The existing recursion cases are updated so their fixture commit stages a native file.

## Risks / Trade-offs

- Broken tests can now be committed locally and are caught at push, not commit → the push gate is unchanged in strength, and the push still runs before anything reaches the remote.
- A stale remote-tracking ref can make the runner see commits as unpushed → it runs extra checks, never fewer.
- A native commit made with `--no-verify` and not yet pushed still counts at the next push → the unpushed range includes it, so it is checked.
- The classification list can go stale as directories are added → unknown paths default to native, and the hook tests assert that default.
- A commit that exists only on the remote (made by automation, the GitHub web interface, or another machine) counts as already checked once it is fetched, so a later documentation-only push on top of it skips native checks → accepted, because the confirmed scope is commits not yet on the remote; CI does not run unit tests, so such commits were never checked locally either way.
- A merge of already-pushed commits into a branch re-runs native checks, because merge commits are compared with their first parent → this over-checks, never under-checks.
- Checks run against the checked-out working tree, as the previous hooks did, not against the pushed commits → unchanged behavior.
- Hooks only take effect after the main checkout updates → recorded in the proposal follow-ups.
- A worktree whose branch predates the Makefile targets and scripts the runner calls (for example `make no-code-comments`) cannot commit until it rebases onto the merged change → accepted, because skipping a missing check would fail open; rebasing is the fix.
- Documentation-only pushes now depend on Ruby, Bundler, Jekyll, and Node being on `PATH`, and the runner reports a missing tool only as the failed check → accepted, and AGENTS.md notes the Homebrew Ruby requirement.
- Files under `.agents/skills/` count as evidence even when they are shell scripts, because no hook check runs them today → add a group for them if one is ever wired in.

## Open Questions

- None that affect the specs, approach, or tasks.
