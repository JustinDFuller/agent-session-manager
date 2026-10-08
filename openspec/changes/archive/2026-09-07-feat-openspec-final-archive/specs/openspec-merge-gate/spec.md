## Purpose

The OpenSpec merge gate keeps requirements reviewable throughout a pull-request stack and requires final archival only at the point where the complete implementation and QA result can be finalized.

## ADDED Requirements

### Requirement: Every pull request carries a new shared OpenSpec change set

The repository SHALL require every pull request to carry at least one OpenSpec change that is new to the current stack relative to its trunk. An archived change already present on the trunk SHALL NOT satisfy this requirement, even when the pull request edits or otherwise touches that archived change.

For a stacked pull request, the change names SHALL remain the same across all layers. A non-bottom layer SHALL neither omit a change carried by its immediate base nor introduce a competing OpenSpec change. A standalone pull request SHALL be evaluated as the top layer of a one-pull-request stack.

#### Scenario: Standalone pull request introduces a new archived change

- **WHEN** a standalone pull request introduces a valid archived OpenSpec change whose name is absent from the trunk's archived changes
- **THEN** the OpenSpec check SHALL recognize that change as the pull request's required change set

#### Scenario: Existing archived change is the only OpenSpec content

- **WHEN** a pull request only edits, copies, or relies on an archived change already present on the trunk
- **THEN** the OpenSpec check SHALL fail with a finding that a new change is required

#### Scenario: Bottom stack layer introduces active changes

- **WHEN** the bottom layer of a stack introduces one or more valid active changes absent from the stack trunk
- **THEN** the OpenSpec check SHALL accept those names as the stack's change set

#### Scenario: Higher layer preserves the shared change set

- **WHEN** a higher stack layer carries exactly the active change set present in its immediate base
- **THEN** the OpenSpec check SHALL accept the layer's OpenSpec identity even if the change remains unarchived

#### Scenario: Higher layer changes the shared change set

- **WHEN** a higher stack layer omits an inherited change or introduces a different OpenSpec change
- **THEN** the OpenSpec check SHALL fail and identify the change-set mismatch

### Requirement: Only the current top layer finalizes the change

The OpenSpec check SHALL determine the finalization owner from the current stack state. For a stacked pull request, the top layer SHALL be the layer whose one-based position equals the current stack size. A pull request without stack metadata SHALL be treated as a one-layer stack and SHALL own finalization.

Non-top stack layers SHALL be allowed to retain active changes and unchecked tasks while implementation or QA proceeds, but SHALL NOT archive the shared change. The top layer and every standalone pull request SHALL require the shared change set to be archived, task-complete, and free of active changes.

#### Scenario: Non-top implementation layer remains active

- **WHEN** a non-top stack layer contains the shared valid active change with one or more unchecked tasks
- **THEN** the OpenSpec check SHALL pass its phase-specific state requirements and SHALL not require archival in that layer

#### Scenario: Non-top layer archives early

- **WHEN** a non-top stack layer archives the shared change before the top layer
- **THEN** the OpenSpec check SHALL fail and direct archival to the final top layer

#### Scenario: Top layer archives the shared change

- **WHEN** the current stack position equals the current stack size and the candidate archives exactly the shared change set with every task complete
- **THEN** the OpenSpec check SHALL pass the phase-specific archive requirements

#### Scenario: Stack shrinks after a lower merge

- **WHEN** lower pull requests merge and GitHub updates the remaining pull requests' positions and stack size
- **THEN** the OpenSpec check SHALL assign finalization to the new current top without relying on the original stack length or original pull-request number

#### Scenario: Top layer is a one-pull-request stack

- **WHEN** a stack has one remaining pull request with position one and size one
- **THEN** the OpenSpec check SHALL require that pull request to archive the complete shared change set

### Requirement: The archive pull request is a standalone finalization step

The finalization pull request SHALL contain only the OpenSpec changes needed to move the shared active change set into the archive and synchronize the corresponding main specifications. It SHALL NOT combine implementation, QA, or unrelated repository changes with archival.

#### Scenario: Archive-only finalization is submitted

- **WHEN** the top pull request's direct diff contains only the exact shared OpenSpec archive transition and corresponding main-specification updates
- **THEN** the OpenSpec check SHALL accept it as a standalone archive pull request

#### Scenario: Archive pull request includes implementation work

- **WHEN** the top pull request's direct diff includes source, tests, QA changes, documentation unrelated to the archive, or another non-OpenSpec path
- **THEN** the OpenSpec check SHALL fail and identify that finalization must be isolated

#### Scenario: Finalization follows an active change already on the trunk

- **WHEN** lower stack layers have merged and the current trunk temporarily contains the shared active change
- **THEN** the top pull request SHALL be allowed to archive that exact active change, while an existing archived change with no matching active-to-archived transition SHALL remain insufficient

### Requirement: OpenSpec artifacts and enforcement remain valid and protected

The OpenSpec check SHALL require the repository's spec-driven artifacts, reject specification shortcuts, require synchronized main specifications for archived changes, and run strict OpenSpec validation. The required check SHALL run for every relevant pull-request update, including drafts and stack transitions, from base-branch-owned enforcement logic against an immutable candidate revision.

#### Scenario: Required artifact or strict validation is invalid

- **WHEN** a relevant change is missing required artifacts, uses `skip_specs: true`, lacks a synchronized main specification, or fails strict OpenSpec validation
- **THEN** the OpenSpec check SHALL fail with an actionable finding

#### Scenario: Non-top active artifacts are structurally valid

- **WHEN** a non-top layer has complete valid planning artifacts but its task checklist is not yet complete
- **THEN** strict artifact validation SHALL run and pass without converting the incomplete task checklist into a finalization failure

#### Scenario: Candidate attempts to replace enforcement

- **WHEN** the pull request modifies the workflow or validator used by the gate
- **THEN** the required check SHALL continue using the protected base-branch enforcement source and SHALL not execute candidate-controlled enforcement code

#### Scenario: Required status is missing or failing

- **WHEN** the stable OpenSpec check has not passed for the current pull-request revision
- **THEN** the repository's `main` ruleset SHALL prevent the pull request or stack from merging
