## Why

The repository currently permits explanatory comments throughout source code, tests, scripts, CI configuration, and other code-bearing files. Those comments become stale, duplicate rationale that belongs in review history, or obscure code that should instead be simplified; a strict repository rule will keep explanations in the appropriate durable channels and prevent new code comments from returning.

## What Changes

- **BREAKING** Define a repository-wide no-code-comments policy for tracked non-Markdown code and configuration files.
- Remove the existing code comments from the repository while preserving executable behavior, strings, documentation prose, and required machine directives.
- Add a dependency-free local checker that reports comment locations and scans the complete tracked candidate tree.
- Add a base-branch-owned, read-only `no-code-comments` pull-request check with a stable job name and no draft or stack-layer relaxation.
- Add concise `AGENTS.md` guidance and a dedicated agent skill describing the policy, explanation alternatives, exceptions, and verification commands.
- Deliver the work as four stacked pull requests: spec, implementation, migration, and evidence-only QA.
- Document the manual repository-owner step to require the stable check in the `main` ruleset and verify the resulting external configuration.

## Capabilities

### New Capabilities

- `no-code-comments`: Defines the repository's observable no-code-comments policy, local validation behavior, CI enforcement, allowed machine directives, and failure reporting.

### Modified Capabilities

- None.

## Impact

- Tracked Swift sources, tests, UI tests, scripts, workflows, build files, hooks, and comment-capable repository configuration will be cleaned up.
- New Node-based validation and regression tests will live with the existing repository enforcement scripts.
- A new base-owned GitHub Actions workflow will inspect immutable pull-request candidates with read-only permissions.
- `AGENTS.md` and a new internal agent skill will define where rationale, history, usage guidance, and difficult explanations belong.
- No application runtime API, user-facing product behavior, or runtime dependency will change.

### Deliberately out of scope

- Scanning or rewriting Markdown, PR titles, PR descriptions, commit titles, or commit messages; those remain the approved prose channels.
- Removing the required `Package.swift` SwiftPM tools-version directive or executable shebangs, which are machine directives rather than explanatory comments.
- Automatically changing GitHub rulesets, bypass actors, CODEOWNERS ownership, or other external repository administration.
- Replacing the existing OpenSpec gate or relaxing its strict stacked-PR lifecycle.
- Adding public product documentation for this maintainer and agent policy.
- Changing application behavior, test behavior, dependencies, or generated binary assets.

## Follow-ups after merge

- `JustinDFuller` manually adds the stable `no-code-comments` status to the `main` branch ruleset while preserving existing review, code-owner, last-push, and thread-resolution requirements.
- `JustinDFuller` verifies the resulting ruleset and confirms that `JustinDFuller-Agents` cannot bypass the required check.
- Use a temporary pull request after the workflow is available from the default branch to verify a deliberately added comment fails and its removal passes; close the temporary pull request after recording the evidence.
