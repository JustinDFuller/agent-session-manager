# OpenSpec in this repo

This repo uses [OpenSpec](https://openspec.dev)'s `opsx` workflow. OpenSpec keeps the agreed requirements, design decisions, and implementation tasks in the repository so a human can review the contract before implementation is merged.

## Every pull request needs OpenSpec

Every pull request requires a valid OpenSpec change, including drafts and pull requests that change only code, documentation, automation, dependencies, or repository metadata. The `openspec-check` status is strict on every pull request and every layer of a formal GitHub stacked pull request. A draft does not relax the gate.

Continuation layers may retain the shared active change and unchecked tasks while implementation or QA proceeds. The current top layer of a stack, and every standalone pull request, is the finalization layer. It must contain:

- the repository's spec-driven artifacts (`.openspec.yaml`, `proposal.md`, `design.md`, `tasks.md`, and a delta specification);
- a corresponding main specification under `openspec/specs/`;
- no `skip_specs` shortcut;
- every task checked; and
- no active change remaining under `openspec/changes/`.

The finalization layer must archive the exact shared change set in an archive-only pull request. Existing archived changes on the stack trunk do not count as a new change, and higher layers must preserve the change names handed off by their immediate base.

The gate runs the pinned OpenSpec CLI with strict validation and archived-change validation. Its production workflow is base-owned on `main`, and it evaluates the immutable candidate revision for the pull request rather than scripts or workflows supplied by that candidate.

## The command sequence

1. `/opsx:explore` — work out the requirements and open questions with the agent
2. `/opsx:propose` — write `proposal.md`, `specs/<capability>/spec.md`, `design.md`, and `tasks.md` for review; **no implementation yet**
3. Iterate on the spec with your reviewer(s) until it is locked in
4. `/opsx:apply` — implement `tasks.md`
5. PR review — human and AI feedback on the implementation and the spec
6. Run QA in its own continuation pull request when the stack has a separate QA layer; record the commands, results, and evidence links in that PR's description.
7. Create the final archive pull request at the current top of the stack. It must contain only the archive transition and synchronized main specifications.
8. `/opsx:archive` — archive the change as the last OpenSpec step, after review feedback is resolved and before the archive pull request is marked ready for review
9. Merge

### Stacked pull requests

For a formal stack rooted at `main`, the change follows this lifecycle:

`OpenSpec -> implementation 1..n -> QA -> archive`

#### Use the `gh stack` CLI

Use the [canonical stacked-PR skill](../.agents/skills/openspec-stacked-prs/SKILL.md) for the complete command procedure. The short form is:

1. Create a new stack with `gh stack init`, `gh stack add`, and `gh stack submit`, or formally link existing PRs with `gh stack link <bottom-pr> <next-pr> ...` in bottom-to-top order.
2. Import the remote stack with `gh stack checkout <top-pr>`.
3. Verify formal metadata with `gh stack view --json` and verify every PR's immediate-parent base with `gh pr view`.

`gh pr create --base` establishes a branch dependency but does not prove formal stack membership. One implementation PR contains one complete top-level task group and all of its subtasks. `gh stack sync`, `gh stack push`, and `gh stack rebase` may use `--force-with-lease` for eligible stack feature branches; never force-update `main` or another protected branch. See GitHub's [stacked pull request overview](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs), [quickstart](https://docs.github.com/en/pull-requests/get-started/stacked-prs-quickstart), and [CLI reference](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands).

The archive pull request is always the current top layer. Lower layers must carry the exact active change set from their immediate base, may leave tasks unchecked, and must not archive or introduce a competing change. The top layer must complete the tasks, archive the shared changes, synchronize the matching main specifications, and contain no implementation, QA, or unrelated files in its direct diff.

Four pull requests are the intended decomposition: the OpenSpec proposal, implementation, QA, and archive. Keeping QA separate from the archive layer preserves the archive-only final diff. This is guidance rather than a CI minimum; standalone and shorter stacks are supported. A standalone pull request is treated as a one-layer stack and must perform the final archive step itself.

When lower pull requests merge, GitHub reduces the remaining stack's position and size. The pull request that is then `position == size` remains the archive owner. The stack trunk may temporarily contain the active change during this collapse; the immediate base preserves the shared identity and permits the active-to-archived handoff. Do not use the original stack length or pull request number to choose the archive owner.

When the QA work is the last non-archive layer, record its exact validation steps, expected and observed results, useful CI links, and any disposable fixture cleanup in that QA pull request's description. Then create the separate archive pull request and resolve its review feedback before marking it ready.

## Install OpenSpec

Install the repository's pinned OpenSpec CLI version:

```bash
npm install -g @fission-ai/openspec@1.10.0
```

The `/opsx:*` commands are OpenSpec workflows that run inside a supported AI coding assistant. Follow the [official OpenSpec setup guide](https://openspec.dev/docs/getting-started) to install the integration for your assistant. The `openspec` CLI must be on `PATH` before a workflow starts.

### Preserve the repository configuration

This repository has a curated `openspec/config.yaml`. Review the working-tree diff after running `openspec init` or `openspec update`, and do not overwrite that file with profile-generated defaults.

## What a reviewer should read

Read `specs/<capability>/spec.md`. It is the requirement contract, written to stand on its own. The other planning artifacts (`proposal.md`, `design.md`, `tasks.md`, `.openspec.yaml`) are working material for the agent and a historical record; they remain visible to automated code review and are not out of scope for findings.

## If you disagree with a requirement

Stop reviewing the parts of the implementation affected by that requirement until the disagreement is resolved. Reviewing an implementation against a requirement you do not agree with wastes both sides' time.

## Archiving is the last OpenSpec step

A change is archived only after review feedback on the change has been resolved, immediately before the pull request is marked ready for review. The archive is required even when the pull request is a draft; keeping a draft only allows the work to remain under review while the strict check explains what is still missing.

Tasks must describe work that can be completed and verified before archiving. Verifying, archiving, marking the pull request ready, and merging are the workflow itself, not tasks. Work that can only happen after merge belongs under a `## Follow-ups after merge` heading in `proposal.md`, with a tracking issue when it needs an owner.

## What CI enforces

`openspec-check` runs on every pull request through the base-owned `pull_request_target` workflow and on pushes to the default branch. Its validation is strict for ordinary pull requests, drafts, and every layer of a formal stack:

| Invariant | Required result |
|---|---|
| An OpenSpec change is present in the candidate tree | pass |
| Required artifacts and matching main specifications exist | pass |
| Artifacts pass `openspec validate --all --strict` | pass |
| Archived-change validation passes | pass |
| Continuation layers preserve the shared active change set | pass |
| The current top or standalone layer archives the shared change set | pass |
| The current top or standalone layer has no active change and all tasks checked | pass |

Missing or malformed changes fail the check on every layer. Active or incomplete changes fail only when a current top or standalone layer attempts finalization; the guide comment and `openspec` label are informational, while the `openspec-check` job is the merge gate.

## GitHub merge controls and ownership

The `main` branch ruleset is external repository configuration. It must require the stable `openspec-check` status, block force pushes and other non-fast-forward updates, and preserve the repository's existing review, code-owner, latest-push approval, and thread-resolution requirements. Only the human account `JustinDFuller` may use the configured ruleset bypass. `JustinDFuller-Agents` must not have administrator, maintain, or ruleset-bypass permission. The ruleset is configured and verified manually; CI does not change repository administration settings.

This workflow change does not alter the existing `.github/CODEOWNERS` boundary.

The existing `.github/CODEOWNERS` policy remains in force:

- `JustinDFuller` owns the repository by default.
- Selected implementation paths remain intentionally agent-editable.
- The enforcement surface, including `.github/workflows/`, `.github/scripts/`, `.github/CODEOWNERS`, and `openspec/`, remains covered by the human default because no exception grants those paths to the agent.

The ruleset and CODEOWNERS policy are complementary: CODEOWNERS controls human review of enforcement changes, while the ruleset controls the required status, non-fast-forward protection, and its only authorized bypass.

## The OpenSpec guide comment

The `.github/workflows/openspec-guide.yml` workflow maintains a sticky pull request comment reporting OpenSpec status. It is purely informational and is not itself a required status check.

## The `openspec` label

Any pull request whose diff touches `openspec/` is labeled `openspec` automatically, so OpenSpec's impact on cycle time and quality can be measured. No contributor action is required.
