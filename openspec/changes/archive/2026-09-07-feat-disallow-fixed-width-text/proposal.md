## Why

Agents are increasingly hard-wrapping prose at a fixed width in Markdown files and pull-request descriptions instead of allowing readers and renderers to wrap complete paragraphs naturally. The existing code-comment policy does not cover these prose channels, so the repository needs an enforceable rule and a one-time cleanup before the pattern spreads further.

## What Changes

- **BREAKING** Define a repository-wide prohibition on fixed-width hard-wrapped prose in tracked Markdown and pull-request descriptions.
- Add a dependency-free local validator and regression tests that require each logical prose block to occupy one physical line while preserving inherently line-oriented Markdown structures.
- Add a base-owned, immutable-candidate GitHub Actions check with a stable status name that fails on drafts, ordinary pull requests, and every stacked-pull-request layer when prohibited wrapping is found.
- Scan the complete tracked Markdown tree and the current pull-request description.
- Add the local command and concise guidance to `AGENTS.md`, the repository workflow skill, and a dedicated agent skill; explicitly state that CI will fail, commit bodies have strong guidance but are not a hard block, and force-pushes must not be used to bypass the rule.
- Reflow the existing tracked Markdown corpus without rewriting Git history or changing executable code behavior.
- Deliver the change as a five-layer stack: OpenSpec draft, implementation, migration, QA evidence, and an archive-only final pull request after the top-layer OpenSpec archive workflow is available on `main`.

## Capabilities

### New Capabilities

- `fixed-width-prose`: Defines the observable prose-formatting rule, accepted structural exceptions, local validation behavior, CI enforcement, and failure diagnostics.

### Modified Capabilities

- None.

## Impact

- Adds a dependency-free Node validator, tests, a local Make target, and a base-owned GitHub Actions workflow.
- Updates repository and agent authoring guidance.
- Changes tracked Markdown formatting across documentation, internal guidance, skills, and OpenSpec artifacts.
- Adds no application runtime APIs, dependencies, or user-facing product behavior.

### Deliberately out of scope

- Rewriting existing Git commit history or historical pull-request descriptions.
- Hard-blocking commit bodies: force-pushes are prohibited, so a pushed commit message cannot be removed from the pull request's commit set without rewriting history. Commit bodies still receive strong authoring guidance.
- Applying the rule to source-code comments, which are governed by the existing policy.
- Rejecting line-oriented code fences, indented code, tables, YAML front matter, headings, thematic breaks, or raw HTML blocks.
- Automatically modifying GitHub rulesets, branch protection, pull requests, or force-push permissions.
- Implementing or changing the pending top-layer OpenSpec archive workflow; this change depends on that workflow being merged first.
