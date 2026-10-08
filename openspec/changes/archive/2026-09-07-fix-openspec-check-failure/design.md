## Context

The workflow checks out the default branch into `enforcement-source/` and invokes `node --test enforcement-source/.github/scripts/openspec-merge-gate.test.mjs` from the GitHub workspace root. The test module imports its validator through a module-relative path, but test 20 reads the validator and workflow text using paths relative to `process.cwd()`.

## Goals / Non-Goals

**Goals:**

- Make the enforcement test independent of the directory from which Node launches it.
- Preserve the existing workflow invocation and base-branch-owned enforcement boundary.
- Make the workflow-shaped invocation a required regression check.

**Non-Goals:**

- Changing validator logic, OpenSpec rules, stack handling, or GitHub Actions checkout behavior.
- Adding dependencies or changing application runtime code.

## Decisions

- Resolve both inspected files with `new URL(..., import.meta.url)` and pass those URLs directly to `fs.readFileSync`. This follows the test module’s own location and works when the module is nested under `enforcement-source/`.
- Keep the existing workflow command unchanged. Changing the command’s working directory would hide the test’s invocation fragility and could affect other workflow steps.
- Validate both invocation shapes: the normal repository-root command and a temporary workspace that contains only `enforcement-source/.github/...`, matching the base-owned CI checkout layout.

The rejected alternative is `path.resolve(process.cwd(), ...)`: it preserves the same coupling to the caller’s working directory. A workflow-only `working-directory` change is also rejected because the test should remain correct for local and other automated invocations.

## Risks / Trade-offs

- [Risk] A future relocation of the test module could make its relative URLs stale. -> [Mitigation] Keep the paths directly adjacent to the module and workflow layout, and retain the workflow-shaped regression command.
- [Risk] The test may pass locally while the base-owned source differs from the candidate source. -> [Mitigation] The workflow continues to check out and execute the default branch’s enforcement source before checking out the candidate.

## Migration Plan

Apply the test-only correction, run both invocation-shape checks, and land the planning change and implementation on the default branch. Re-run the affected OpenSpec checks after the default branch contains the fix. Rollback is a revert of the single test-file change; no data migration or workflow-state migration is required.
