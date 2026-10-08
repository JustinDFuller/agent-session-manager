## Context

The repository already has a base-owned OpenSpec `pull_request_target` gate that checks an immutable candidate checkout with read-only permissions. Existing comments are spread across Swift sources and tests, shell and Ruby scripts, Make, GitHub workflows, hooks, CODEOWNERS, `.gitignore`, and other configuration. The policy must remove that baseline and prevent new comments without mistaking URLs, strings, embedded scripts, or machine directives for comments.

See `proposal.md` for motivation and `specs/no-code-comments/spec.md` for the observable contract.

## Goals / Non-Goals

**Goals:**

- Make the complete tracked non-Markdown code/configuration tree pass a deterministic no-comment check.
- Keep the checker dependency-free and locally runnable.
- Make the pull-request check base-owned, read-only, immutable-candidate, and stable enough to require in a ruleset.
- Preserve the repository's four-layer stack: spec, implementation, migration, and evidence-only QA.
- Give agents concise policy guidance and a full skill reference.

**Non-Goals:**

- Modifying application runtime behavior or introducing a runtime dependency.
- Scanning Markdown, pull-request prose, commit messages, binary assets, or non-code communication channels.
- Automatically changing GitHub rulesets or bypass actors.
- Replacing or relaxing the existing OpenSpec gate.

## Decisions

### Use a dependency-free Node validator

Implement the checker as an ES module using the repository's existing Node 22 CI convention, native filesystem/process APIs, and `node:test`. Node 22 is a consistency choice rather than a language requirement: it avoids introducing a second CI runtime while matching the current base-owned OpenSpec workflow.

The validator will enumerate tracked files from the candidate repository, skip Markdown and binary content, classify supported comment syntaxes, and scan outside string/data literals. It will emit repository-relative path, line, and column for each violation and return a nonzero status when findings exist.

### Use lexical scanning with explicit language boundaries

The checker will recognize the comment forms used by the repository: C-style line and block comments, shell/Ruby/Make/YAML hash comments, and XML comments. It will preserve comment-like text inside quoted strings, raw or multiline strings, URLs, CSS colors, embedded scripts, and executable data. It will explicitly allow first-line interpreter shebangs and the first-line SwiftPM tools-version directive.

Regression fixtures will cover every supported syntax, block and inline forms, unterminated comments, strings containing comment tokens, heredoc or multiline content, and allowed directives. The fixture source itself will contain comment examples only as string data so the repository scan remains clean.

### Separate the protected check from OpenSpec

Add a distinct workflow and stable `no-code-comments` job. The workflow will load its validator and test suite from the protected base branch, check out the pull request head by immutable SHA, and run the validator against that candidate without executing candidate workflow or script code. It will run for the same pull-request lifecycle events as the existing OpenSpec gate and will not relax for drafts or stacked layers.

The external `main` ruleset will be updated manually by `JustinDFuller` after the check is observed. Repository documentation will state the exact status name and verification command, but no repository code will mutate rulesets.

### Separate implementation from baseline cleanup

The implementation PR adds the validator, tests, workflow, local command, and agent guidance while leaving existing comments in place. The migration PR then removes all baseline comments without changing behavior. This keeps enforcement design reviewable separately from the large mechanical cleanup and makes the migration's acceptance condition explicit: the complete tracked tree passes.

### Keep the Spec PR as archive owner

The Spec PR remains the base of the four-layer stack. Higher PRs must not archive or recreate the change. After implementation, migration, and QA evidence are complete, finish the task checklist and archive the change in the Spec PR, cascade-rebase the higher branches, and rerun all required checks before merge.

## Risks / Trade-offs

- [Risk] A lexical scanner can mistake comment-like characters in language literals for comments. -> [Mitigation] Keep syntax boundaries explicit, test strings and embedded data for every supported language, and require a clean full-tree scan.
- [Risk] A candidate could modify the checker or workflow to make its own result pass. -> [Mitigation] Run the workflow from the protected base branch and scan the immutable candidate with read-only permissions.
- [Risk] The migration touches many files and could accidentally alter behavior. -> [Mitigation] Use syntax-aware or targeted comment removal, inspect the complete diff, and run the existing build, unit, format, lint, and documentation checks.
- [Risk] Requiring the status before the workflow is available on the default branch can deadlock setup. -> [Mitigation] Publish and validate the stable check first, perform the manual ruleset update only after the QA pass, and verify the observed context before requiring it.
- [Risk] The OpenSpec gate can block intermediate stack layers while the change is active. -> [Mitigation] Treat those failures as expected, keep completion and archiving in the base Spec PR, and cascade-rebase after finalization.

## Migration Plan

1. Open the Spec PR containing only the new OpenSpec artifacts.
2. Stack the Implementation PR with the validator, tests, workflow, local command, and agent guidance.
3. Stack the Migration PR and remove all existing in-scope comments until the full-tree checker passes.
4. Stack the evidence-only QA PR, run local and CI-equivalent checks, and use throwaway PRs to verify failing and passing behavior plus false-positive protections.
5. Have `JustinDFuller` manually require `no-code-comments` in the `main` ruleset and verify the status and bypass configuration read-only.
6. Complete and archive the OpenSpec change in the base Spec PR, cascade-rebase the higher branches, and rerun the complete gate set.

Rollback is limited to removing the external required status and reverting the enforcement workflow or validator if a defect is found. Removing comments is behavior-preserving and does not require restoring the deleted prose.
