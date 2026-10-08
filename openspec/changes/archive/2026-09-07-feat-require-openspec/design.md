## Context

The existing `openspec-check` job runs only when a pull request touches `openspec/`, downgrades archive and task failures on drafts to notices, and is not currently required by the `main` ruleset. OpenSpec validation also exits successfully when no changes exist, so validation alone cannot prove that a pull request supplied a requirements record. The current `CODEOWNERS` policy gives `JustinDFuller` ownership by default while intentionally leaving selected implementation paths agent-editable.

GitHub's formal stacked pull requests expose stack metadata to Actions and evaluate the stack against its trunk. A stack rooted at `main` therefore cannot use a relaxed higher-layer merge gate to enable incremental merges: lower layers must also satisfy the trunk requirements before a higher layer can merge. The intended workflow is consequently strict on every layer: higher PRs may carry implementation work and remain blocked while the change is active, then the base PR completes and archives the change and the stack is cascade-rebased.

See `proposal.md` and `specs/openspec-merge-gate/spec.md` for the motivation and observable contract.

## Goals / Non-Goals

**Goals:**

- Make the `openspec-check` job a strict, always-running pull request gate on every layer, including higher layers of a formal stack.
- Require a cumulative-diff OpenSpec presence check in addition to CLI validation.
- Ensure the enforcement logic comes from the protected base branch and uses read-only permissions.
- Enforce the repository's spec-driven artifact set, strict validation, completed tasks, archived state, and synchronized main specification.
- Configure the `main` ruleset so only `JustinDFuller` can bypass the OpenSpec requirement.
- Preserve the existing ownership boundary for ordinary agent-editable paths.
- Give contributors actionable, stack-aware guidance when a higher PR is blocked by the base PR's active or incomplete OpenSpec change.

**Non-Goals:**

- Changing OpenSpec schemas, the pinned CLI version, or the agent workflow itself.
- Relaxing the required OpenSpec gate for higher layers of a main-rooted stack.
- Making the informational guide comment or label workflow a merge prerequisite.
- Requiring human ownership for source, test, asset, or documentation paths that the existing `CODEOWNERS` policy intentionally leaves agent-editable.

## Decisions

### Use a base-branch-owned pull request gate

Run the required check from `pull_request_target` so the workflow and validation logic are loaded from the protected base branch. Check out the pull request head into an isolated candidate directory and treat it as input data. Run only the base-branch validator and the pinned OpenSpec CLI; do not execute scripts, workflows, package hooks, or other code from the candidate checkout. Grant only `contents: read` and `pull-requests: read` permissions.

This is preferred over a normal `pull_request` workflow because an agent could otherwise change the workflow or validation implementation in its own branch. CODEOWNERS remains the human review control for proposed enforcement changes, but the base-branch execution also prevents a candidate commit from changing the result of its own gate.

### Keep the required check unconditional, stable, and strict

Remove path-based job skipping, draft severity relaxation, and any stack-position-based relaxation. The `openspec-check` job will run for every pull request event relevant to merge eligibility, including new commits and draft/ready transitions, and will retain its stable job name for the required ruleset status. A higher stacked-PR layer may receive a more specific explanation of the blocking base PR, but it still receives the same failing result until the complete archived state is present.

The check will inspect a trusted effective-diff manifest in addition to the candidate checkout. For an ordinary pull request, the manifest covers the pull request base-to-head diff. For a formal stack, it covers the stack trunk-to-head cumulative diff. For a fork pull request, it uses the trusted pull-request file listing because formal cross-fork stacks are unsupported. At least one added, copied, or renamed path under `openspec/changes/<name>/` or `openspec/changes/archive/<name>/` must be present; an inherited archive or an edit to an existing archive is not sufficient. It will detect change directories by path shape rather than assuming a particular date or change name.

### Make the base PR the sole archive owner

For a non-stacked pull request, the pull request itself owns the OpenSpec change and its final archive. For a formal stack rooted at `main`, the bottom PR (the PR whose base is the stack trunk) owns the change lifecycle. Higher PRs contain implementation layers only; they must not archive the change or create a competing change record. When implementation is complete, update the task checklist and archive the change in the bottom PR, then cascade-rebase the higher branches so every layer contains the same completed state before merging the stack.

Use `github.event.pull_request.stack` only to improve contributor guidance. The workflow may identify a higher layer and point to its base branch or base PR, but it must not turn a higher layer into a relaxed merge path. If stack metadata is missing or malformed, fail closed with the ordinary strict guidance.

### Explain the stacked workflow at the point of failure

The failure output must distinguish the base PR from a higher implementation PR. The base-PR message must say to complete all tasks and archive there. A higher-layer message must say not to archive in that PR, to finish the implementation layer, and to wait for the base PR to be completed and archived before cascading a rebase. The same lifecycle must be documented in `openspec/README.md`, including the fact that strict failures in higher layers are expected until the base PR is finalized.

### Fail closed around the spec-driven artifact contract

The base-owned workflow will create the effective-diff manifest outside the candidate checkout and pass it to the validator. Missing or malformed manifest data fails closed. After the presence check, validate the candidate checkout with the pinned OpenSpec CLI. The gate will require the default spec-driven artifact set, reject `skip_specs`, reject remaining active changes, require all task checkboxes to be complete, and run both strict full validation and archived-change validation. Missing items, empty reports, command failures, or malformed JSON will fail the job rather than being treated as no-op success.

Keep the existing CLI version pin and Node 22 setup unchanged for reproducibility; version upgrades are a separate change.

### Use repository rulesets for merge and bypass enforcement

Update the `main` ruleset outside the repository file tree to require the `openspec-check` status. Replace its current repository-role bypass with a direct user bypass for `JustinDFuller` and no bypass entry for `JustinDFuller-Agents`. Preserve the existing one-review, code-owner, last-push, and thread-resolution requirements.

The remote ruleset is authoritative for merge behavior because YAML files cannot make a GitHub status required. The implementation must verify the resulting ruleset through the GitHub API and confirm the agent account remains a non-admin write collaborator.

### Preserve the existing CODEOWNERS boundary

Do not replace the current broad-default-plus-agent-exceptions policy. The OpenSpec workflow, supporting enforcement files placed under `.github/`, OpenSpec artifacts, and the CODEOWNERS file remain covered by the human default. Ordinary implementation paths retain their existing ownership behavior.

## Risks / Trade-offs

- [Risk] `pull_request_target` can be unsafe if it executes candidate code or exposes write credentials. -> [Mitigation] Keep permissions read-only, execute only base-branch logic, isolate the candidate checkout, and validate files through the pinned OpenSpec CLI.
- [Risk] The required status check can deadlock the bootstrap PR before the remote ruleset knows its context. -> [Mitigation] Publish the stable workflow first, confirm the observed check name, then have `JustinDFuller` add that context to the `main` ruleset before the change is marked ready.
- [Risk] GitHub ruleset configuration is external state and can drift from the repository documentation. -> [Mitigation] Add an explicit API verification step and document the expected actor and required-check configuration.
- [Risk] Fork pull requests may have a different head repository or unavailable checkout ref. -> [Mitigation] Resolve the head repository and SHA from the pull request event, fail closed when the candidate cannot be obtained, and never grant write permissions to fork-triggered execution.
- [Risk] Requiring an archived specification for every pull request increases work for documentation and tooling changes. -> [Mitigation] Treat that cost as an intentional policy decision and keep the workflow guidance explicit about the required archive lifecycle.
- [Risk] A contributor may archive the change in a higher stacked-PR layer, leaving the base PR active and the stack blocked. -> [Mitigation] Fail higher layers with explicit no-archive guidance, document the base-PR ownership rule, and add stacked-PR regression coverage.
- [Risk] Contributors may interpret a strict higher-layer failure as a broken gate. -> [Mitigation] Explain that the failure is expected until the base PR is archived, and identify the base branch or PR in the diagnostic.

## Migration Plan

1. Add and locally test the base-owned validator and strict workflow behavior.
2. Update the repository guide to remove optional/draft-relaxed language.
3. Open the base pull request with the OpenSpec change, then stack implementation pull requests above it if desired. Keep the change active while implementation proceeds; after review feedback and implementation are complete, finish tasks and archive only in the base pull request, then cascade-rebase the stack.
4. Confirm the `openspec-check` status context on the pull request.
5. Have `JustinDFuller` update the `main` ruleset to require that context and replace the role-level bypass with the direct human-user bypass.
6. Verify the ruleset, collaborator permissions, and representative pre-archive validator results before marking the base pull request ready. The final merge activates the protected default-branch workflow; no post-merge validation task is required.

Rollback consists of reverting the workflow/documentation implementation and having `JustinDFuller` remove the required status context from the `main` ruleset. The agent account cannot perform that rollback because it has no ruleset bypass or administrative permission.
