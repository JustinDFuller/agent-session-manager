# fixed-width-prose Specification

## Purpose

The fixed-width prose capability keeps repository communication readable by preventing agents and contributors from inserting formatting-driven line breaks inside logical prose blocks.

## Requirements

### Requirement: Prose blocks use one physical line

The repository SHALL treat each logical paragraph, list item, blockquote paragraph, and pull-request description paragraph as one physical line of prose. A non-empty continuation line within one such logical block SHALL be reported as a violation regardless of its width. Commit-message prose SHALL follow the same authoring rule as guidance, but commit messages SHALL not be a hard-blocking scan input.

#### Scenario: Wrapped Markdown paragraph

- **WHEN** a tracked Markdown file contains one paragraph split across two non-empty physical lines
- **THEN** the prose check SHALL fail and report the continuation location

#### Scenario: Single-line Markdown paragraph

- **WHEN** a tracked Markdown paragraph is contained on one physical line
- **THEN** the prose check SHALL accept it

#### Scenario: Separate Markdown paragraphs

- **WHEN** two prose paragraphs are separated by a blank line
- **THEN** the prose check SHALL evaluate them as separate blocks and SHALL not report the paragraph boundary

#### Scenario: Wrapped list item

- **WHEN** one Markdown list item continues onto another non-empty physical line
- **THEN** the prose check SHALL fail and report the continuation location

### Requirement: Structural Markdown remains line-oriented

The prose check SHALL not report violations for fenced code, indented code, tables, YAML front matter, headings, thematic breaks, raw HTML blocks, or separate list items that use one physical line each.

#### Scenario: Fenced code example

- **WHEN** a fenced code block contains multiple physical lines
- **THEN** the prose check SHALL accept those lines

#### Scenario: Markdown table

- **WHEN** a Markdown table contains one physical line per row
- **THEN** the prose check SHALL accept the table rows

#### Scenario: Document front matter

- **WHEN** YAML front matter contains multiple physical lines before the document body
- **THEN** the prose check SHALL accept the front matter

#### Scenario: Raw HTML block

- **WHEN** a Markdown file contains a raw HTML block whose syntax spans multiple physical lines
- **THEN** the prose check SHALL accept the HTML block

### Requirement: Pull-request descriptions are checked and commit bodies receive guidance

The repository SHALL apply the same prose rule to the current pull-request description. A violation SHALL fail the prose check and identify its source and location. Repository guidance SHALL strongly require one-line logical prose in commit bodies, but commit bodies SHALL not be a hard-blocking CI input because force-pushes are prohibited and a pushed commit message cannot be removed from the pull request's commit set without rewriting history.

#### Scenario: Wrapped pull-request description

- **WHEN** a pull-request description contains a logical paragraph split across physical lines
- **THEN** the prose check SHALL fail with a pull-request-description finding

#### Scenario: Wrapped commit body receives guidance

- **WHEN** a commit body contains a logical paragraph split across physical lines
- **THEN** authoring guidance SHALL identify the commit body as non-conforming, but the prose check SHALL not fail solely because of that commit body

#### Scenario: Clean communication channels

- **WHEN** the pull-request description contains only accepted one-line prose blocks and structural content
- **THEN** the prose check SHALL accept them

### Requirement: CI enforcement is fail-closed

The repository SHALL run the prose check for every relevant pull-request revision, including draft and stacked pull requests, and SHALL fail the check whenever any scanned source violates the rule. Enforcement SHALL evaluate the immutable candidate revision using trusted base-branch enforcement logic and SHALL not execute validator or workflow code supplied by the candidate revision.

#### Scenario: Draft pull request contains a violation

- **WHEN** a draft pull request contains a wrapped Markdown paragraph or pull-request paragraph
- **THEN** the prose check SHALL fail rather than downgrade the finding to a notice

#### Scenario: Higher stacked pull request contains a violation

- **WHEN** a higher layer of a pull-request stack contains a wrapped prose block in its candidate tree or communication channels
- **THEN** the prose check SHALL fail for that layer

#### Scenario: Candidate changes the validator

- **WHEN** a pull request modifies the prose validator or its workflow to weaken enforcement
- **THEN** the check SHALL continue using trusted base-branch enforcement logic and SHALL evaluate the candidate without executing the modified enforcement code

### Requirement: The complete tracked Markdown corpus is covered

The prose check SHALL scan every tracked Markdown-family file in the candidate tree, not only files changed by the current pull request. A clean repository SHALL contain no reported fixed-width prose violations after the migration. Commit bodies are intentionally outside this hard-blocking corpus and are covered by authoring guidance instead.

#### Scenario: Existing file is unchanged by the pull request

- **WHEN** an unchanged tracked Markdown file contains a fixed-width prose violation
- **THEN** the full-tree prose check SHALL fail

#### Scenario: New Markdown file is added

- **WHEN** a pull request adds a tracked Markdown-family file containing a wrapped prose block
- **THEN** the prose check SHALL fail and identify the added file

#### Scenario: Migrated repository is scanned

- **WHEN** every tracked Markdown-family file and all pull-request communication channels satisfy the rule
- **THEN** the prose check SHALL pass with no findings
