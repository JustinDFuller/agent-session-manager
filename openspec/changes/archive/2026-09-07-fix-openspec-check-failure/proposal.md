## Why

The base-owned OpenSpec workflow checks out its enforcement source under `enforcement-source/` but runs the validator test from the workspace root. Test 20 reads the validator and workflow using workspace-relative paths, so the base-owned test fails with `ENOENT` before any candidate OpenSpec validation runs.

The fix is needed on the default branch because pull-request checks intentionally source the test and validator from that branch; changing only a checked pull-request candidate cannot repair its own enforcement check.

## What Changes

- Make the enforcement regression test resolve its validator and workflow fixtures relative to the test module instead of the process working directory.
- Add a delta requirement to the OpenSpec merge-gate capability covering working-directory-independent base-owned regression tests.
- Preserve the existing base-branch-owned workflow, immutable candidate checkout, stack validation, and validator semantics.
- Verify the test from both the repository root and a workflow-shaped workspace containing only `enforcement-source/`.

Deliberately out of scope:

- Changing OpenSpec merge-gate rules, stack metadata, or candidate validation behavior.
- Changing the workflow checkout layout or adding a workflow `working-directory` override.
- Reworking or rebasing the currently failing pull-request stack.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `openspec-merge-gate`: Require the base-owned validator regression test to pass when invoked from the workflow workspace root with enforcement files checked out under `enforcement-source/`.

## Impact

The affected files are `.github/scripts/openspec-merge-gate.test.mjs` and the change delta under `specs/openspec-merge-gate/`. No public API, application runtime code, dependency, or production data is affected. The correction must reach the default branch before the affected pull-request checks are rerun.
