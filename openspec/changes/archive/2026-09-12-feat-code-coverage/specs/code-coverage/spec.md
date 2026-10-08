## Purpose

Expose repository unit-test line coverage through ordinary CI output and a downloadable artifact without covering dependencies or requiring a hosted coverage service.

## ADDED Requirements

### Requirement: Repository unit coverage is generated for reviewable commits

When macOS CI jobs are enabled, the unit-test workflow MUST run the repository unit-test suite with coverage enabled for pull requests targeting the default branch, pushes to the default branch, and manual dispatches. The resulting LCOV report MUST include only repository source files and MUST exclude package checkouts, generated files, and build artifacts.

#### Scenario: Default-branch baseline coverage

- **WHEN** a commit is pushed to `main` and macOS CI jobs are enabled
- **THEN** the unit-test workflow produces a repository-only LCOV coverage report and prints a line-coverage summary

#### Scenario: Pull-request coverage

- **WHEN** a pull request targeting `main` runs with macOS CI jobs enabled
- **THEN** the unit-test workflow produces a repository-only LCOV coverage report for the pull-request head commit and prints a line-coverage summary

#### Scenario: Disabled macOS policy

- **WHEN** macOS CI jobs are disabled by repository policy
- **THEN** the coverage-producing job is skipped and the workflow does not claim that coverage was generated or uploaded

### Requirement: Coverage is retained as a standard CI artifact

After successful unit tests and report validation, the workflow MUST upload the filtered LCOV report as a standard GitHub Actions artifact with a stable artifact name. The workflow MUST NOT require GitHub Code Quality permissions or call a native coverage-upload service.

#### Scenario: Pull-request artifact

- **WHEN** a pull request completes its coverage-producing unit-test job successfully
- **THEN** the workflow retains a downloadable LCOV artifact containing the repository coverage report

#### Scenario: Manual diagnostic artifact

- **WHEN** a manually dispatched coverage-producing unit-test job completes successfully
- **THEN** the workflow retains the same downloadable LCOV artifact without publishing it to a hosted coverage service

### Requirement: Coverage output is safe for all pull requests

The workflow MUST run coverage tests for fork pull requests under the existing pull-request permissions and MUST NOT require repository write or Code Quality permissions to retain the standard artifact. The workflow MUST grant no permissions beyond repository read access needed by checkout and testing.

#### Scenario: Fork pull request

- **WHEN** a fork pull request runs the coverage workflow
- **THEN** tests may execute according to the existing macOS policy and the artifact step uses only the standard Actions artifact service without attempting a repository or Code Quality write

#### Scenario: Least-privilege permissions

- **WHEN** the coverage workflow is inspected
- **THEN** its permissions are limited to repository read access and do not include `code-quality: write`

### Requirement: Invalid coverage output fails visibly

The coverage workflow MUST fail when LLVM cannot produce a non-empty report, when the report contains disallowed source paths, or when the artifact step cannot retain the report. It MUST NOT silently present a missing, malformed, dependency-only, or stale report as successful coverage.

#### Scenario: Invalid source coverage

- **WHEN** the LLVM report is missing, empty, malformed, or contains a dependency or build path
- **THEN** the validation step fails and the artifact step does not report successful coverage

#### Scenario: Artifact failure

- **WHEN** the standard artifact upload fails
- **THEN** the coverage step fails and the workflow exposes the failure in its result

### Requirement: Coverage reporting does not enforce a threshold

The coverage workflow MUST report measured coverage without failing solely because the percentage is below a configured minimum, and it MUST NOT change merge protection or required-check policy as part of this capability.

#### Scenario: Low measured coverage

- **WHEN** tests pass and the generated report contains a low line-coverage percentage
- **THEN** the summary and artifact are still eligible for publication and no threshold failure is raised
