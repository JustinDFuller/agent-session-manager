## Context

The existing `.github/workflows/unit-tests.yml` runs `swift test --enable-code-coverage` on macOS 15, but it does not export or expose a readable coverage report. SwiftPM and LLVM output can include package dependencies, so the report must be filtered to repository sources. The repository wants ordinary CI output and a downloadable artifact rather than GitHub's separately billed native Code Quality coverage service. The existing `ENABLE_MACOSX_JOBS` policy gate remains authoritative.

## Goals / Non-Goals

Goals:

- Reuse the existing unit-test execution so coverage does not require a second macOS test run.
- Produce a source-filtered coverage summary and LCOV artifact for main pushes, pull requests, and manual runs.
- Validate the report deterministically and reject dependency or build paths.
- Preserve fork safety, read-only permissions, and honest reporting when macOS jobs are disabled.

Non-goals:

- Adding UI-test or screenshot coverage.
- GitHub Code Quality or a hosted coverage service.
- Coverage thresholds or branch-protection changes.
- New package dependencies or application runtime changes.

## Decisions

### Extend the existing unit-test workflow

Add reporting to `.github/workflows/unit-tests.yml` rather than running a second macOS test job. Retain manual dispatch, add pushes to `main`, and preserve the `vars.ENABLE_MACOSX_JOBS == 'true'` gate. The LCOV file is uploaded only after tests and report validation succeed.

### Measure the pull-request head commit

Checkout `ref: ${{ github.event.pull_request.head.sha || github.sha }}`. Pull requests therefore measure the submitted head commit, while pushes and manual runs measure the workflow SHA.

### Export filtered LCOV directly with LLVM

After `swift test --enable-code-coverage`, locate the test executable from SwiftPM's build output instead of hardcoding a toolchain-specific path. Run `llvm-cov export --format=lcov --instr-profile=...` against the test executable and the repository source roots `Sources/AgentSessionManager` and `Sources/AgentSessionManagerMCPBridgeCore`. Validate that the report is nonempty and every `SF:` path is within those roots; reject `.build/checkouts` and other build paths. Run `llvm-cov report` to print the line-coverage summary. Store the validated report at a stable path such as `.build/coverage/unit-test-coverage.info`.

Direct LCOV keeps the output readable and avoids a converter or third-party service. Replacing the existing SwiftPM test path with Xcode result-bundle coverage would add an unrelated UI/build-system migration.

### Use a standard Actions artifact

Upload the LCOV file with `actions/upload-artifact@v7` under a stable name such as `unit-test-coverage`. This is an ordinary workflow artifact and does not require a Code Quality permission, a hosted service, or repository write access. The workflow permissions remain limited to `contents: read`.

### Protect fork pull requests

The standard artifact is compatible with fork pull requests without repository write access. Pull requests still use the existing read-only workflow permissions, and a disabled macOS job remains skipped rather than being described as a successful coverage measurement.

## Risks / Trade-offs

- Toolchain-specific executable and profile paths require deriving locations from SwiftPM output and validating them locally and in hosted CI.
- An incorrect source filter could hide coverage, so the validator rejects every `SF:` path outside the two allowed repository source roots.
- When macOS jobs are disabled, coverage remains skipped and is not reported as a successful measurement.
- Standard artifacts are downloadable rather than an inline PR coverage comparison, which is an accepted trade-off for avoiding the separately billed native service.
