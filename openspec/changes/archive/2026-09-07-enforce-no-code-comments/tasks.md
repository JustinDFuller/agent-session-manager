## 1. Validator implementation

- [x] 1.1 Add the dependency-free tracked-tree validator and command-line entry point, then verify it reports repository-relative file, line, and column for every detected violation.
- [x] 1.2 Add regression coverage for supported comment syntaxes, inline and block forms, unterminated comments, strings and URLs, raw and multiline strings, embedded scripts, CSS colors, heredocs or multiline content, shebangs, and the SwiftPM tools-version directive; verify `node --test .github/scripts/no-code-comments.test.mjs` passes.
- [x] 1.3 Add the local Make target and document the exact invocation in the agent skill; verify the command reaches the same validator used by the tests.

## 2. Protected CI enforcement

- [x] 2.1 Add the separate base-owned pull-request workflow with stable job name `no-code-comments`, required pull-request events, `main` push coverage, and read-only permissions; verify the workflow contains no draft or stack-layer relaxation.
- [x] 2.2 Make the workflow load enforcement logic from the protected base branch and scan the immutable pull-request candidate without executing candidate scripts; verify the workflow source and candidate checkout paths through review and a representative local candidate run.
- [x] 2.3 Add CI-facing failure output and workflow regression checks for clean candidates, violating candidates, modified enforcement files, and higher stacked layers; verify failures identify locations and cannot be bypassed by candidate changes.

## 3. Agent guidance

- [x] 3.1 Add the concise no-code-comments rule and approved explanation channels to `AGENTS.md`; verify the rule names PR descriptions, commit messages, Markdown documentation or skills, and code simplification as the alternatives.
- [x] 3.2 Add `.agents/skills/no-code-comments/SKILL.md` with valid frontmatter, complete policy scope, allowed machine directives, scanner command, and migration guidance; verify the skill directory and referenced content validate successfully.

## 4. Existing-comment migration

- [x] 4.1 Remove explanatory, documentation, section, and inline comments from tracked Swift sources, tests, and UI tests while preserving behavior, strings, and the SwiftPM tools-version directive; verify the focused Swift format, lint, and unit checks pass.
- [x] 4.2 Remove explanatory comments from tracked scripts, workflows, Make, hooks, CODEOWNERS, `.gitignore`, and other supported configuration while preserving shebangs and executable data; verify the complete no-code-comments scan passes.
- [x] 4.3 Review the migration diff for accidental behavior changes and verify the repository build, format, lint, documentation, and applicable test checks pass.

## 5. QA evidence

- [x] 5.1 Run the complete local and CI-equivalent validation set, including the no-code-comments tests and scan, OpenSpec strict validation, build, unit tests, format, lint, and applicable documentation checks; record the results in the QA PR description.
- [x] 5.2 Exercise a temporary pull request or equivalent immutable candidate with one deliberate code comment, then remove it and rerun the check; verify the first result fails with a location and the second passes.
- [x] 5.3 Exercise comment-looking strings and allowed machine directives in a temporary candidate; verify they pass without exceptions being added to the policy.
