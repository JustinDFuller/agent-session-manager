# Manual validation

These runs used the real hooks from this branch (`git -c core.hooksPath=<clone>/.githooks`) in a scratch clone with a local bare repository as the remote, on macOS, with the real `swift-format`, `swiftlint`, `swift test`, `make docs-check`, and `xcodebuild`. Nothing is stubbed. Timings come from the shell `time` builtin.

## 1. Markdown-only commit and push

Commit finished in 0.43 seconds. Push finished in 2.3 seconds, including the documentation build.

```
$ git commit (markdown only)
==> Changed file groups: docs
==> Running comment and prose checks...
no-code-comments: no violations found
fixed-width-prose: no violations found
==> Skipping OpenSpec validation (no OpenSpec changes)
==> Skipping format and lint (no native changes)
==> Skipping CI script tests (no CI script changes)
==> Skipping hook tests (no hook changes)
==> Skipping documentation build (runs on push)
==> Skipping unit tests (no native changes)
==> Skipping UI smoke tests (no native changes)
==> All applicable checks passed.
git -c core.hooksPath=$H commit -q -m "docs: qa note"  0.19s user 0.06s system 59% cpu 0.430 total
```

Push (second attempt, with Homebrew Ruby first on PATH; see the note below):

```
$ git push (markdown only, Homebrew Ruby first on PATH)
==> Changed file groups: docs
==> Running comment and prose checks...
no-code-comments: no violations found
fixed-width-prose: no violations found
==> Skipping OpenSpec validation (no OpenSpec changes)
==> Skipping format and lint (no native changes)
==> Skipping CI script tests (no CI script changes)
==> Skipping hook tests (no hook changes)
==> Running documentation build...
Diátaxis documentation taxonomy passed (28 public pages).

Documentation build and internal-link checks passed.
Release publication contract passed.
==> Skipping unit tests (no native changes)
==> Skipping UI smoke tests (no native changes)
==> All applicable checks passed.
git -c core.hooksPath=$H push -q origin qa  1.13s user 0.50s system 71% cpu 2.266 total
```

Note: the first push attempt failed in `scripts/test-release-publishing.sh` because the shell used for the run found macOS system Ruby 2.6 (LibreSSL) before Homebrew Ruby, and that script needs a newer OpenSSL. CI uses Ruby 3.3. The hook reported `==> documentation build failed` and rejected the push, which is the intended failure behavior. This is an existing property of the script and not a change in this work.

## 2. Swift change with a deliberate format violation

The commit stopped at format and lint after 2.9 seconds. `swiftlint`, `swift test`, and UI smoke tests never started.

```
$ git commit (Swift file with a format violation)
==> Changed file groups: native
==> Running comment and prose checks...
no-code-comments: no violations found
fixed-width-prose: no violations found
==> Skipping OpenSpec validation (no OpenSpec changes)
==> Running format and lint...
Sources/QAHookProbe.swift:2:7: error: [Spacing] remove 2 spaces
Sources/QAHookProbe.swift:2:21: error: [Spacing] add 1 space
Sources/QAHookProbe.swift:2:33: error: [Spacing] add 1 space
==> format and lint failed
git -c core.hooksPath=$H commit -q -m "feat: format violation"  2.79s user 0.10s system 100% cpu 2.870 total
commit exit status: 1
```

## 3. Clean Swift change

The commit ran only the fast tier and finished in 3.6 seconds, with unit and UI tests reported as "runs on push".

```
$ git commit (clean Swift change)
==> Changed file groups: native
==> Running comment and prose checks...
no-code-comments: no violations found
fixed-width-prose: no violations found
==> Skipping OpenSpec validation (no OpenSpec changes)
==> Running format and lint...
==> Skipping CI script tests (no CI script changes)
==> Skipping hook tests (no hook changes)
==> Skipping documentation build (no documentation changes)
==> Skipping unit tests (runs on push)
==> Skipping UI smoke tests (runs on push)
==> All applicable checks passed.
git -c core.hooksPath=$H commit -q -m "feat: clean swift probe"  5.85s user 0.32s system 171% cpu 3.594 total
commit exit status: 0
Done linting! Found 0 violations, 0 serious in 249 files.
```

This push took 15 minutes because the scratch clone built the app and the UI test bundle from scratch. It ran the ladder in order: comment and prose checks, format and lint, then the real `swift test` suite (passed), then UI smoke tests.

```
$ git push (clean Swift change; full ladder)
==> Changed file groups: native
==> Running comment and prose checks...
==> Skipping OpenSpec validation (no OpenSpec changes)
==> Running format and lint...
==> Skipping CI script tests (no CI script changes)
==> Skipping hook tests (no hook changes)
==> Skipping documentation build (no documentation changes)
==> Running unit tests...
Test Suite 'All tests' passed at 2026-10-14 08:04:21.680.
==> Running UI smoke tests...
	 Executed 2 tests, with 2 failures (0 unexpected) in 128.733 (128.735) seconds
	 Executed 8 tests, with 8 failures (0 unexpected) in 505.580 (505.586) seconds
	 Executed 10 tests, with 10 failures (0 unexpected) in 634.312 (634.322) seconds
	 Executed 10 tests, with 10 failures (0 unexpected) in 634.312 (634.323) seconds
==> UI smoke tests failed
git -c core.hooksPath=$H push -q origin qa  564.58s user 95.15s system 72% cpu 15:09.65 total
push exit status: 1
```

The UI smoke tests started and then failed in this automation environment with `Failed to activate application 'com.justinfuller.agent-session-manager.xcode-dev'` for every test, so the push was rejected with `==> UI smoke tests failed`. This environment cannot bring the app to the foreground. The failure is not caused by the hooks: the runner started the UI smoke step only after `swift test` passed, reported the failing check by name, and exited nonzero. A passing UI smoke run needs a desktop session and has to be confirmed by running `make test-ui-dev-launch` from a normal terminal.

## 4. Follow-up markdown push on a branch whose Swift change is already on the remote

The Swift commit was pushed with `--no-verify` first, to stand in for a push that had already reached the remote. The follow-up push finished in 1.7 seconds and skipped unit and UI tests as "no native changes".

```
$ git push (markdown-only follow-up on a branch whose Swift change is already on the remote)
==> Changed file groups: docs
==> Running comment and prose checks...
no-code-comments: no violations found
fixed-width-prose: no violations found
==> Skipping OpenSpec validation (no OpenSpec changes)
==> Skipping format and lint (no native changes)
==> Skipping CI script tests (no CI script changes)
==> Skipping hook tests (no hook changes)
==> Running documentation build...
Diátaxis documentation taxonomy passed (28 public pages).

Documentation build and internal-link checks passed.
Release publication contract passed.
==> Skipping unit tests (no native changes)
==> Skipping UI smoke tests (no native changes)
==> All applicable checks passed.
git -c core.hooksPath=$H push -q origin qa  1.03s user 0.44s system 84% cpu 1.743 total
```
