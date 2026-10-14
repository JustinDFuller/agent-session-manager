# Tasks

## 1. Runner and change detection

- [x] 1.1 Add `scripts/git-hook-checks.sh` with `pre-commit` and `pre-push` modes, change detection for staged files and unpushed commits, and the allowlist classification that defaults unknown paths and detection errors to native; verify with fixture-repository cases in `scripts/test-git-hooks.sh` covering documentation-only, Swift, unknown-path, nothing-to-push, branch deletion, and undetermined-change inputs
- [x] 1.2 Replace `.githooks/pre-commit` and `.githooks/pre-push` with thin wrappers that keep the top-level `cd` and the inherited Git variable isolation (done in the runner after the changed files are read); verify `bash scripts/test-git-hooks.sh` still proves no recursion through command-line and environment hook configuration, with the fixture commit staging a native file

## 2. Check ladder

- [x] 2.1 Implement the ordered ladder with fail-fast, the per-tier run and skip lines, and the commit and push columns from design.md; verify with stub-based cases that a failing `swiftlint` stub prevents the `swift` stub from starting and that skip lines name their reason
- [x] 2.2 Add the previously CI-only checks (comment and prose checks, `openspec validate`, CI script tests, hook tests, documentation build) to the ladder; verify each runs only for its group by asserting stub invocations per changed-file category
- [x] 2.3 Scope pushes to commits not on the remote using a throwaway bare remote; verify a documentation-only follow-up push after a pushed native commit invokes no heavy stub, and a force-pushed rewrite of that native commit does

## 3. Documentation and CI

- [x] 3.1 Add `scripts/git-hook-checks.sh` to the path filters in `.github/workflows/git-hooks.yml`; verify the filter list contains it
- [x] 3.2 Update the hook descriptions in `AGENTS.md` and any public documentation page that mentions the hooks, following the Diataxis skill; verify `make docs-check` and `scripts/test-release-publishing.sh` pass

## 4. Integration

- [x] 4.1 Install the new hooks in this worktree against a local bare remote and run a markdown-only commit and push, a Swift change with a deliberate formatting violation, a clean Swift push, and a follow-up markdown-only push; verify with recorded timings and terminal output that the markdown pushes finish in seconds, the formatting violation stops before `swift test`, and the clean Swift push runs the full ladder in order
- [x] 4.2 Run the OpenSpec validation commands the hook uses (`--archived`, `--changes --strict`, `--specs`) and `make no-code-comments no-fixed-width-prose`; verify both pass
