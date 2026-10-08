Each implementation PR SHALL contain one numbered task group below, including all subtasks in that group. For example, one PR owns task group 2 and all of `2.1` through `2.5`; subtasks SHALL NOT become separate stack PRs. The final QA group is validation work only.

## 1. Canonical gh stack CLI skill

- [x] 1.1 Add `.agents/skills/openspec-stacked-prs/SKILL.md` with valid Agent Skills frontmatter and focused `gh stack` scope; verify it with `skills-ref validate .agents/skills/openspec-stacked-prs`.
- [x] 1.2 Document new-stack and existing-PR procedures using `gh stack init`, `add`, `submit`, and bottom-to-top `link`; verify the guidance rejects `gh pr create --base` as sufficient formal-stack proof.
- [x] 1.3 Document `gh stack checkout`, `view --json`, and per-PR `gh pr view` verification plus command side effects and conflict recovery; verify the acceptance checklist requires both metadata and base-chain checks.

## 2. Repository pointers

- [x] 2.1 Add concise `AGENTS.md` guidance pointing agents to the canonical skill and stating the one-top-level-task-group-per-PR rule; verify the pointer and grouping rule are discoverable.
- [x] 2.2 Add the focused `gh stack` procedure and official links to `openspec/README.md`; verify it does not duplicate unrelated OpenSpec lifecycle or gate policy.
- [x] 2.3 Add short references from the existing OpenSpec workflow skills; verify they all point to the same canonical skill.

## 3. QA validation

- [x] 3.1 Run `skills-ref validate` for the new and modified skills plus `openspec validate --all --strict`; record the observed results.
- [x] 3.2 Validate the command examples against the installed `gh stack` help and official GitHub CLI reference; record any version-sensitive behavior.
- [x] 3.3 In a dedicated worktree, inspect a real formal stack with `gh stack checkout <top-pr>`, `gh stack view --json`, and `gh pr view` for every layer; record evidence that branch bases alone are insufficient.
