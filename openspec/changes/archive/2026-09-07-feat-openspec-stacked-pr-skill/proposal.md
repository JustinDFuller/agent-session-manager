## Why

Agents can create dependent pull requests with `gh pr create --base` while leaving them outside GitHub's formal stacked pull request metadata. The repository needs focused guidance for using the `gh stack` CLI correctly so agents create, import, and verify real stacks rather than relying on branch names alone.

## What Changes

- Add one canonical agent skill for the `gh stack` CLI workflow.
- Document new-stack and already-created-PR flows, including bottom-to-top ordering and formal linking.
- Require `gh stack checkout <top-pr>`, `gh stack view --json`, and per-PR base verification before treating a stack as ready.
- Document the relevant side effects and recovery paths for stack commands that push, rebase, or merge.
- Add concise references from `AGENTS.md`, `openspec/README.md`, and OpenSpec workflow skills.
- State that one implementation PR owns one top-level OpenSpec task group and all of its subtasks.

### Deliberately out of scope

- Defining the complete OpenSpec implementation, QA, or archive lifecycle.
- Changing the OpenSpec merge gate, GitHub rulesets, authentication, remotes, or credential helpers.
- Automating remote stack mutations or merges.
- Adding application behavior or a public documentation page.

## Capabilities

### New Capabilities

- `openspec-stacked-prs`: Agent guidance for correctly creating and verifying formal GitHub stacks with the `gh stack` CLI.

### Modified Capabilities

- None.

## Impact

- Agent-facing guidance under `AGENTS.md`, `openspec/README.md`, and `.agents/skills/`.
- No application code, dependencies, persisted user data, or runtime interfaces.
