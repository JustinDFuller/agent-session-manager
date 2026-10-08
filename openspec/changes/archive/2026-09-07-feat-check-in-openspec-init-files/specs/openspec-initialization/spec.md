# OpenSpec repository initialization

## Purpose

The repository SHALL expose the initialized OpenSpec workflow and directory structure needed for contributors and supported coding agents to create, review, validate, and archive changes.

## ADDED Requirements

### Requirement: Workflow skills are available to supported agents

The repository SHALL include the generated OpenSpec workflow skills for exploring, proposing, applying, archiving, syncing, updating, and verifying changes under `.agents/skills/`.

#### Scenario: Agent discovers the OpenSpec workflows

- **WHEN** a supported coding agent loads the repository's available skills
- **THEN** it SHALL find a valid skill directory and `SKILL.md` for each of the seven OpenSpec workflows
- **AND** each skill SHALL identify the OpenSpec CLI as its required command surface

### Requirement: OpenSpec planning roots are initialized

The repository SHALL contain dedicated roots for active changes, archived changes, and main specifications, including the initialized archive and specification directory markers.

#### Scenario: Contributor starts a repository-local OpenSpec workflow

- **WHEN** the contributor runs the OpenSpec CLI from the repository
- **THEN** the CLI SHALL resolve the repository's `openspec/` root and configured `spec-driven` schema
- **AND** the repository SHALL provide locations for active changes, archived changes, and main specifications

### Requirement: Repository initialization preserves curated configuration

The initialized workflow SHALL use the repository's curated `openspec/config.yaml` and SHALL not replace it with profile-generated defaults.

#### Scenario: OpenSpec is initialized or updated

- **WHEN** initialization or update output is reviewed for check-in
- **THEN** the curated repository configuration SHALL remain intact
- **AND** generated workflow files SHALL be checked in alongside the repository configuration without overwriting it
