## 1. LLVM Coverage Reporting

- [x] 1.1 Add workflow commands to locate the SwiftPM test executable and profile, export filtered LCOV, print the LLVM line-coverage summary, and fail on an empty report; verify a coverage-enabled local test run.
- [x] 1.2 Add report validation tests for covered output, multiple files, dependency and build-path exclusion, malformed or empty reports, and both allowed repository source roots; verify the validation suite.

## 2. GitHub Actions Integration

- [x] 2.1 Update the unit-test workflow for pushes to `main`, default-branch pull requests, and manual dispatch; checkout the reviewed commit, preserve the macOS policy gate, and keep permissions at `contents: read`; verify the workflow structure.
- [x] 2.2 Upload the validated LCOV report with `actions/upload-artifact@v7` using a stable artifact name and print the summary; verify there is no native Code Quality action or elevated permission.
- [x] 2.3 Preserve fork behavior and the disabled-macOS policy; standard artifacts may retain successful fork reports without repository or Code Quality write access, while disabled jobs remain skipped; verify the permission behavior.

## 3. End-to-End Validation

- [x] 3.1 Run `swift test --triple "$(uname -m)-apple-macosx14.0" --enable-code-coverage`, export and filter the report, and print the summary; verify source-only paths and a nonempty LCOV artifact.
- [x] 3.2 Run `make no-code-comments`, `make no-fixed-width-prose`, `openspec validate feat-code-coverage --type change --strict`, the workflow and report validation tests, and `git diff --check`; verify all pass without application code changes.
