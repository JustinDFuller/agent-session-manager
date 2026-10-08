## Why

The repository already measures Swift unit-test coverage in CI, but it does not expose a readable summary or retain the generated report for review. A regular CI coverage step will make coverage available without opting into GitHub's separately billed native coverage service.

## What Changes

- Extend the existing macOS unit-test workflow to generate a filtered LCOV report directly from LLVM coverage output.
- Run the coverage-producing unit-test workflow on pull requests, pushes to `main`, and the existing manual dispatch, while preserving the existing macOS-job policy gate.
- Print a normal LLVM line-coverage summary in CI and upload the filtered LCOV report as a standard GitHub Actions artifact.
- Add workflow validation for report existence, source filtering, triggers, checkout, permissions, and artifact publication.
- Do not enforce a minimum coverage threshold in this change.

## Capabilities

### New Capabilities

- `code-coverage`: Expose repository unit-test line coverage as ordinary CI output and a downloadable Actions artifact.

### Modified Capabilities

None.

## Impact

The implementation will affect the unit-test GitHub Actions workflow and add local/CI validation for the generated LCOV report. It will use the existing SwiftPM test target, LLVM tools, and macOS runner; it will not change application APIs, production runtime behavior, UI tests, or package dependencies.

## Deliberately Out of Scope

- UI-test or screenshot coverage.
- GitHub Code Quality/native coverage uploads, Codecov, Coveralls, or another hosted coverage service.
- Coverage thresholds, merge blocking, or quality-gate policy changes.
- Coverage for Swift package dependencies or generated/build files.
