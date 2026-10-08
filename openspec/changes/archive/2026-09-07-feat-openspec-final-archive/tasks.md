## 1. Phase-aware merge gate

- [x] 1.1 Replace the base-versus-higher archive decision with normalized standalone, non-top, and top stack context using current `stack.position`, `stack.size`, and stack trunk metadata; verify malformed or unsupported context fails closed.
- [x] 1.2 Update the base-owned workflow to run unconditionally for relevant pull-request revisions, check out enforcement code from the protected base branch, and provide immutable candidate, stack-trunk, and immediate-base snapshots or trusted manifests; verify candidate workflow and validator code are never executed.
- [x] 1.3 Implement state-aware OpenSpec change-set comparison that rejects inherited archived changes, preserves exact names across stack layers, recognizes active-to-archived handoffs after lower merges, and fails when a layer omits or introduces a competing change; verify findings identify the mismatched names.
- [x] 1.4 Split common artifact validation from phase validation so non-top layers may retain valid active changes and unchecked tasks, while the top or standalone layer requires complete tasks, no active changes, synchronized main specifications, and strict archived validation; verify actionable guidance distinguishes continuation from finalization.
- [x] 1.5 Enforce that the top layer's direct diff contains only the exact OpenSpec archive transition and corresponding main-specification updates; verify implementation, QA, unrelated documentation, and other non-OpenSpec changes fail the archive-only check.

## 2. Regression coverage

- [x] 2.1 Add deterministic active, archived, trunk, and immediate-base fixtures plus trusted snapshot/manifest helpers; verify fixtures represent both the initial stack and a partially collapsed stack with an active change on `main`.
- [x] 2.2 Cover standalone, one-layer, and four-layer stack decisions, including each non-top position and the current top; verify only `position == size` requires archival and no minimum stack size is enforced.
- [x] 2.3 Cover stack collapse from four to three to two to one remaining pull requests; verify the finalization requirement follows the updated position and size while the shared change names remain stable.
- [x] 2.4 Cover new-change proof, inherited historical archives, active-to-archived transitions, omitted or competing change names, incomplete non-top tasks, complete top tasks, and archive-only versus mixed finalization diffs; verify each acceptance and failure scenario from the specification.
- [x] 2.5 Preserve coverage for strict CLI validation, missing or malformed artifacts, `skip_specs`, immutable head resolution, fork handling, and base-owned enforcement; verify the complete Node regression suite passes.

## 3. Workflow documentation and guidance

- [x] 3.1 Update `openspec/README.md` with the `OpenSpec -> implementation -> QA -> archive` sequence, the archive-only top pull request, allowed lower-layer state, standalone behavior, and stack-collapse behavior; verify documented commands and CI findings agree.
- [x] 3.2 Update `openspec/config.yaml` archive/apply guidance and `.github/workflows/openspec-guide.yml` status text so lower layers are told to continue implementation or QA and only the current top is told to archive; verify no guidance directs an earlier layer to archive.
- [x] 3.3 Document that four pull requests are the intended decomposition but not a CI minimum, and document the external `main` ruleset requirements for `openspec-check` and non-fast-forward protection without changing the existing CODEOWNERS boundary; verify the documentation uses `Agent Session Manager` in full.

## 4. Repository policy and verification

- [x] 4.1 Have the human repository owner configure and verify the external `main` ruleset to require the stable `openspec-check`, block force pushes, preserve existing review and thread requirements, and retain only the approved human bypass; record the observed ruleset result before archival.
- [x] 4.2 Run the merge-gate Node tests, strict OpenSpec validation, workflow/YAML checks, repository lint, and documentation checks; record successful results and any manual ruleset evidence before the change is archived.
