## Context

See `proposal.md` for the motivation. The repository currently has general OpenSpec and stacked-PR guidance, but it does not clearly distinguish a correct pull request base chain from GitHub's formal stack metadata. The canonical agent guidance should solve that command-use problem without becoming a second OpenSpec gate or lifecycle policy.

## Goals / Non-Goals

**Goals:**

- Make the correct `gh stack` command sequence easy to follow.
- Make formal metadata verification a required acceptance check.
- Prevent agents from splitting one top-level OpenSpec task group into one PR per subtask.
- Keep detailed command guidance in one reusable skill and use short repository pointers elsewhere.

**Non-Goals:**

- Define the complete OpenSpec implementation, QA, or archive process.
- Change GitHub Actions, repository rulesets, authentication, or application code.
- Perform remote stack operations automatically.

## Decisions

### Use one canonical operational skill

Add `.agents/skills/openspec-stacked-prs/SKILL.md` as the detailed `gh stack` command guide. `AGENTS.md`, `openspec/README.md`, and the existing OpenSpec skills will point to it instead of duplicating command syntax.

### Separate new-stack and existing-PR procedures

The skill will document `gh stack init`, `gh stack add`, and `gh stack submit` for new stacks. When pull requests already exist, it will require `gh stack link` in bottom-to-top order, even if `gh pr create --base` previously established the branch chain.

### Require two independent verification checks

Every procedure will end by importing or selecting the stack with `gh stack checkout`, inspecting `gh stack view --json`, and checking each pull request with `gh pr view`. The stack is not accepted unless both formal metadata and immediate-parent base branches are correct.

### Keep task grouping as a narrow OpenSpec rule

The guidance will state only the necessary mapping: one implementation PR per top-level task group, with all subtasks in that group together. It will not define the broader OpenSpec QA or archive lifecycle.

### Describe side effects without automating them

The skill will identify read-only inspection, local checkout/rebase, remote push/link/submit/sync, and merge commands. It will call out force-with-lease-capable updates, distinguish eligible stack feature branches from protected trunk branches, and document rebase conflict recovery. Rebasing is allowed only when the rewritten stack branches are outside the repository's protected-branch or ruleset coverage; `main` must never be force-updated.

## Risks / Trade-offs

- [Risk] GitHub's stacked pull request feature and `gh stack` extension may change while in public preview. -> [Mitigation] Link the official GitHub overview, quickstart, and CLI reference and validate examples against the installed CLI.
- [Risk] A correct branch chain can still lack formal stack metadata. -> [Mitigation] Require both `gh stack view --json` and per-PR `gh pr view` checks.
- [Risk] A broad lifecycle document could obscure the CLI procedure. -> [Mitigation] Keep this change limited to command usage, verification, and the single task-group mapping needed for stack construction.
