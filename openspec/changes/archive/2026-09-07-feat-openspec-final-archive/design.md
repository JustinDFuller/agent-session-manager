## Context

The current repository workflow is path-scoped, draft-relaxed, and requires every candidate tree to contain an archived, task-complete change. The prior stacked-PR design made the bottom pull request the archive owner, but GitHub's stacked pull requests evaluate every layer against the stack trunk and automatically rebase remaining layers as lower pull requests merge.

The implementation must keep the base-branch-owned `pull_request_target` security boundary and the pinned `spec-driven` OpenSpec contract. The relevant enforcement files are `.github/workflows/openspec.yml`, `.github/scripts/openspec-merge-gate.mjs`, `.github/scripts/openspec-merge-gate.test.mjs`, `.github/workflows/openspec-guide.yml`, `openspec/README.md`, and `openspec/config.yaml`.

## Goals / Non-Goals

**Goals:**

- Make the current top stack layer, rather than the original bottom layer, the only archive owner.
- Keep lower implementation and QA layers mergeable while they carry the same active change.
- Preserve change identity and new-change proof as the stack collapses onto `main`.
- Make the final archive layer an OpenSpec-only pull request.
- Keep strict structural, security, and required-status enforcement.

**Non-Goals:**

- Enforcing a minimum stack size or requiring exactly four pull requests.
- Automatically archiving, rebasing, force pushing, or changing GitHub administration settings.
- Changing the OpenSpec schema, CLI version, application behavior, or unrelated CI policy.

## Decisions

### Derive finalization from current stack metadata

Use `github.event.pull_request.stack.position` and `github.event.pull_request.stack.size` for formal stacks. The top layer is `position == size`; this remains correct after GitHub removes lower layers from the remaining stack. Treat a null stack as a standalone top layer. Missing, malformed, contradictory, or non-main-rooted stack metadata fails closed rather than silently selecting an archive owner.

The validator will receive normalized stack context rather than infer ownership from whether the direct base is `main`. Direct-base detection remains useful for comparing the inherited change set, but it is not the archive decision.

### Compare three immutable repository states

The base-owned workflow will validate the immutable pull-request head and obtain immutable snapshots or trusted manifests for:

- the stack trunk, normally `main`, to identify change names that predate the stack;
- the pull request's immediate base, to identify the active change set handed from one layer to the next; and
- the candidate head, to inspect its final OpenSpec state and direct diff.

The workflow will create these inputs without executing candidate scripts, hooks, workflows, or package code. The validator will fail closed if a required snapshot or trusted file manifest is absent, malformed, or incomplete.

### Preserve identity through stack collapse with state-aware change sets

The validator will represent active and archived change directories by change name and compare them across the snapshots.

- If the immediate base has active changes, those names are the expected shared set. A non-top candidate must retain exactly that active set; the top candidate must archive exactly those names.
- If the immediate base has no active changes, a non-top bottom layer must introduce a nonempty active set absent from the trunk; a top standalone candidate must introduce a nonempty archived set absent from the trunk.
- Archived names already present on the trunk never count as newly introduced. An active-to-archived transition from a lower layer or temporarily updated `main` is valid because the immediate base proves the change was part of the current stack handoff.

This supports both the initial `main <- OpenSpec <- implementation...` state and the post-merge state where `main` temporarily contains the active change while fewer pull requests remain.

### Split common validation from phase validation

All layers run strict structural and OpenSpec CLI validation, require the spec-driven artifacts, reject `skip_specs`, and validate synchronized main specifications whenever an archived change is present. Phase-specific checks then apply:

- Non-top layers require valid active shared changes and may have incomplete task checklists. They fail if they archive or change the shared names.
- The top layer and standalone pull requests require complete tasks, no active changes, archived shared names, valid main specifications, and an archive-only direct diff.

The failure guidance will name the current phase and explain whether to continue implementation/QA or create the final archive-only pull request.

### Keep archival isolated and administration manual

The top layer's direct diff will be checked against its immediate base and limited to the exact OpenSpec archive transition and corresponding main specifications. GitHub's `main` ruleset will be documented and manually verified to require `openspec-check` and block non-fast-forward updates; CI will not mutate the ruleset or push branches.

The informational guide comment will consume the same phase vocabulary so it does not tell a lower layer to archive prematurely. Repository documentation and `openspec/config.yaml` will describe the sequence `OpenSpec -> implementation -> QA -> archive` and the collapse behavior.

## Risks / Trade-offs

- [Risk] The default branch temporarily contains an active change after a lower stack layer merges. -> [Mitigation] Use the immediate-base active set as the handoff identity and distinguish active-to-archived transitions from historical archived changes.
- [Risk] A higher layer adds a second unrelated change that looks valid in isolation. -> [Mitigation] Require exact change-name continuity from the immediate base and reject additions or omissions.
- [Risk] Stack metadata is a public-preview GitHub feature and may be absent during unusual events. -> [Mitigation] Fail closed on malformed stack context and retain standalone handling when the stack property is explicitly null.
- [Risk] Large or incomplete API file listings could weaken archive-only or new-change proof. -> [Mitigation] use immutable repository snapshots or a validated, complete trusted manifest and fail closed on truncation or missing data.
- [Risk] Requiring an archive-only final pull request adds one workflow step. -> [Mitigation] Keep the final step mechanical and make the guide comment state the exact expected diff and command.
