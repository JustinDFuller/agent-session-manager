# Spec Delta

## Purpose

Local Git hooks give fast, trustworthy feedback by running only the checks that apply to the changes being committed or pushed, cheapest first, without ever skipping a check that could catch a real problem.

## ADDED Requirements

### Requirement: Commits run only fast checks

The pre-commit hook SHALL evaluate the staged files and run only the lightweight checks that apply to them. It SHALL NOT run the unit test suite or the native UI tests.

#### Scenario: Documentation-only commit

- **WHEN** a developer commits only files that are not native source or configuration
- **THEN** the commit completes after the applicable lightweight checks without running Swift formatting, linting, unit tests, or native UI tests

#### Scenario: Swift source commit

- **WHEN** a developer commits a change to Swift source
- **THEN** the commit runs the comment, prose, formatting, and lint checks and does not run the unit test suite

### Requirement: Pushes check only commits not yet on the remote

The pre-push hook SHALL evaluate only the commits being pushed that the destination remote does not already have, and SHALL run every check that applies to the files those commits changed.

#### Scenario: Evidence added to a branch that already has code

- **WHEN** a developer pushes a new commit containing only documentation or evidence files to a branch whose native changes are already on the remote
- **THEN** the push skips the unit test suite and native UI tests

#### Scenario: Push contains native changes

- **WHEN** a developer pushes a commit that changes native source or configuration
- **THEN** the push runs the unit test suite and native UI tests after the lighter checks pass

#### Scenario: Nothing new to push

- **WHEN** a developer pushes refs whose commits the remote already has, or deletes a remote branch
- **THEN** the push runs no checks

#### Scenario: Rewritten history

- **WHEN** a developer force-pushes rewritten commits
- **THEN** every rewritten commit the remote does not have counts as new and its changed files determine which checks run

### Requirement: Unrecognized changes run every check

The hooks SHALL treat a changed path as non-native only when it matches a known non-native category. A path that matches no known category, or a failure to determine the changed files, SHALL run every check that the hook would run for native changes.

#### Scenario: Unknown file type

- **WHEN** a commit or push includes a file whose path matches no known non-native category
- **THEN** the hook runs the same checks it would run for a Swift change

#### Scenario: Changed files cannot be determined

- **WHEN** the hook cannot determine which files changed
- **THEN** the hook runs every check that applies to native changes instead of skipping any

### Requirement: Checks run cheapest first and stop at the first failure

The hooks SHALL run applicable checks in order of increasing cost, with comment and prose checks first, then OpenSpec validation, formatting and lint, CI script and hook tests, the documentation build, the unit test suite, and finally the native UI tests. The hook SHALL stop at the first failing check and SHALL NOT start a more expensive check after a failure.

#### Scenario: Formatting failure on a code push

- **WHEN** a pushed Swift change violates the formatting rules
- **THEN** the push fails at the formatting check and the unit test suite never starts

#### Scenario: All checks pass

- **WHEN** every applicable check passes
- **THEN** the hook allows the commit or push

### Requirement: Checks that CI enforces also run locally

The hooks SHALL run the comment prohibition and fixed-width prose checks for every evaluated change. They SHALL run OpenSpec validation when OpenSpec files changed, the CI script tests when those scripts changed, the hook tests when hook files changed, and the documentation build when documentation or site files changed.

#### Scenario: OpenSpec file edited

- **WHEN** a commit changes a file under the OpenSpec directory
- **THEN** the hook validates the OpenSpec changes and rejects the commit if validation fails

#### Scenario: Documentation page edited at push

- **WHEN** a push includes a change to a public documentation page
- **THEN** the push runs the documentation build and link check

#### Scenario: Hook file edited at push

- **WHEN** a push includes a change to a hook file or its runner
- **THEN** the push runs the hook fixture tests

### Requirement: Hooks report what ran and what was skipped

The hooks SHALL print each check they run and each check they skip, and SHALL state why each skipped check did not apply.

#### Scenario: Skipped checks are visible

- **WHEN** a hook skips the unit test suite because no native files changed
- **THEN** the output names the skipped check and says no native changes were found

#### Scenario: Failure names the failing check

- **WHEN** a check fails
- **THEN** the output names the failing check and the failure details before the hook exits with an error
