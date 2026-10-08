# no-code-comments Specification

## Purpose
The no-code-comments capability keeps executable and configuration files focused on behavior while preserving Markdown and repository communication channels for rationale, history, and usage guidance.

## Requirements

### Requirement: Tracked code and configuration contain no explanatory comments

The repository SHALL contain no explanatory comments in tracked non-Markdown source, test, script, build, CI, hook, or configuration files. This SHALL include line comments, block comments, documentation comments, section comments, and comment annotations supported by the file format.

Executable shebangs and the required first-line SwiftPM tools-version directive SHALL be treated as machine directives and SHALL remain allowed. Comment-like text inside strings, URLs, generated values, or executable data SHALL not be treated as a comment.

#### Scenario: A tracked code comment is present

- **WHEN** a tracked non-Markdown code or configuration file contains an explanatory comment
- **THEN** the no-code-comments validation SHALL fail and identify the file and location

#### Scenario: Markdown contains explanatory prose

- **WHEN** a Markdown file contains prose, examples, or Markdown syntax
- **THEN** the no-code-comments validation SHALL not report that content as a code comment

#### Scenario: A required machine directive is present

- **WHEN** a supported script contains its interpreter shebang or `Package.swift` begins with the required SwiftPM tools-version directive
- **THEN** the no-code-comments validation SHALL allow the directive

#### Scenario: Comment-like text is executable data

- **WHEN** a non-Markdown file contains comment-like characters inside a string, URL, raw string, multiline string, CSS color, or other executable data
- **THEN** the no-code-comments validation SHALL not report that text as a comment

### Requirement: Local validation reports violations deterministically

The repository SHALL provide a local validation command that scans the complete tracked candidate tree and exits successfully only when no in-scope comments are found. A failure SHALL report each violation with a repository-relative path and source location so it can be corrected without guessing.

#### Scenario: The tracked tree is clean

- **WHEN** the local validation command scans a candidate tree with no in-scope comments
- **THEN** it SHALL exit successfully and report a passing result

#### Scenario: The tracked tree contains one or more violations

- **WHEN** the local validation command scans a candidate tree containing in-scope comments
- **THEN** it SHALL exit unsuccessfully and report every detected violation with its path and location

#### Scenario: The candidate adds a new supported file

- **WHEN** a tracked pull request adds a supported non-Markdown source or configuration file
- **THEN** the complete-tree scan SHALL include that file without requiring a manually maintained file list

### Requirement: Pull requests receive a strict protected check

The repository SHALL run a stable `no-code-comments` status check for every relevant pull-request revision, including drafts, ready-for-review transitions, and every layer of a formal stacked pull request. The check SHALL evaluate the immutable pull-request candidate using enforcement logic from the protected base branch and SHALL use read-only permissions.

#### Scenario: A pull request contains a code comment

- **WHEN** the immutable pull-request candidate contains an in-scope comment
- **THEN** the `no-code-comments` check SHALL fail with the reported violation locations

#### Scenario: A pull request contains no code comments

- **WHEN** the immutable pull-request candidate passes the complete-tree validation
- **THEN** the `no-code-comments` check SHALL pass

#### Scenario: A candidate changes the enforcement files

- **WHEN** a pull request modifies the no-code-comments workflow or validator
- **THEN** the check SHALL continue to use the protected base-branch enforcement source for that run

#### Scenario: A higher stacked layer is otherwise valid

- **WHEN** a higher stacked pull-request layer passes the no-code-comments validation
- **THEN** the same strict check SHALL pass for that layer without using a relaxed stack-specific path

### Requirement: Repository guidance names approved explanation channels

The repository SHALL provide agent guidance that directs contributors to use pull-request descriptions for change rationale, commit messages for historical changes, Markdown documentation or skills for usage guidance, and simpler code before adding explanatory prose elsewhere.

#### Scenario: An agent needs to explain a change

- **WHEN** an agent consults the repository guidance before editing code
- **THEN** it SHALL find the no-code-comments rule and the approved alternative location for the explanation

#### Scenario: An agent encounters confusing implementation logic

- **WHEN** existing code is difficult to understand
- **THEN** the guidance SHALL direct the agent to simplify the code first and reserve remaining explanation for the pull-request description

### Requirement: The default branch can require the status check

The repository SHALL document the manual repository-owner action required to add the stable `no-code-comments` status to the default branch ruleset. Once that external rule is configured, a pull request SHALL not be eligible to merge through the default branch without a passing current `no-code-comments` result.

#### Scenario: The required status is failing or absent

- **WHEN** the default branch ruleset requires `no-code-comments` and the current pull request result is failing, skipped, or absent
- **THEN** the pull request SHALL remain blocked from merging through the default branch

#### Scenario: The required status passes

- **WHEN** the default branch ruleset requires `no-code-comments` and the current pull request has a passing result
- **THEN** the pull request SHALL satisfy the no-code-comments merge prerequisite subject to the repository's other rules
