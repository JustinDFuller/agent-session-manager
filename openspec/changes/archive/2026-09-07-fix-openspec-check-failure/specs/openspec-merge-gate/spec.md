## MODIFIED Requirements

### Requirement: OpenSpec artifacts and enforcement remain valid and protected

The OpenSpec check SHALL require the repository's spec-driven artifacts, reject specification shortcuts, require synchronized main specifications for archived changes, and run strict OpenSpec validation. The required check SHALL run for every relevant pull-request update, including drafts and stack transitions, from base-branch-owned enforcement logic against an immutable candidate revision. The base-owned enforcement test suite SHALL resolve enforcement files independently of the invoking working directory so it remains valid when the default branch is checked out under `enforcement-source/` and the test is invoked from the workflow workspace root.

#### Scenario: Required artifact or strict validation is invalid

- **WHEN** a relevant change is missing required artifacts, uses `skip_specs: true`, lacks a synchronized main specification, or fails strict OpenSpec validation
- **THEN** the OpenSpec check SHALL fail with an actionable finding

#### Scenario: Base-owned enforcement test runs from the workflow workspace root

- **WHEN** the base-owned workflow checks out its enforcement source under `enforcement-source/` and invokes the validator test from the workspace root
- **THEN** the test suite SHALL locate its validator and workflow inputs and complete without a working-directory-dependent `ENOENT` failure

#### Scenario: Non-top active artifacts are structurally valid

- **WHEN** a non-top layer has complete valid planning artifacts but its task checklist is not yet complete
- **THEN** strict artifact validation SHALL run and pass without converting the incomplete task checklist into a finalization failure

#### Scenario: Candidate attempts to replace enforcement

- **WHEN** the pull request modifies the workflow or validator used by the gate
- **THEN** the required check SHALL continue using the protected base-branch enforcement source and SHALL not execute candidate-controlled enforcement code

#### Scenario: Required status is missing or failing

- **WHEN** the stable OpenSpec check has not passed for the current pull-request revision
- **THEN** the repository's `main` ruleset SHALL prevent the pull request or stack from merging
