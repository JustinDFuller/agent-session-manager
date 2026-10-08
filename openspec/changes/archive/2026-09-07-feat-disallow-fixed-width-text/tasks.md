## 1. Prose validator and local interface

- [x] 1.1 Add the dependency-free Markdown prose validator and local command, including repository-relative file, source-channel, line, and reason diagnostics, and verify clean and violating fixtures return the expected exit status.
- [x] 1.2 Add regression tests for wrapped paragraphs, list items, blockquotes, pull-request bodies, blank-separated paragraphs, fenced and indented code, tables, front matter, headings, thematic breaks, raw HTML, and non-width-specific continuations; verify commit-body guidance is documented without making commit bodies blocking inputs; and verify the complete validator test suite passes.
- [x] 1.3 Add a local Make target that runs the same validator used by CI and verify it scans every tracked Markdown-family file in the candidate tree.

## 2. Base-owned CI enforcement

- [x] 2.1 Add the stable `no-fixed-width-prose` pull-request check for opened, edited, synchronized, reopened, and draft-state transitions, and verify draft and stacked pull requests remain fail-closed.
- [x] 2.2 Make CI load enforcement logic from the protected default branch, inspect the immutable candidate revision, and consume the trusted pull-request description without executing candidate enforcement code; verify candidate workflow or validator edits cannot weaken the check.
- [x] 2.3 Add full-tree Markdown scanning and pull-request description scanning with bounded actionable diagnostics, and verify a deliberate violation fails while clean communication passes.

## 3. Repository and agent guidance

- [x] 3.1 Update `AGENTS.md` and the repository workflow skill to reference the canonical fixed-width-prose policy for the one-line logical-prose rule, structural exceptions, local command, CI failure behavior, strong commit-body guidance, and the prohibition on force-push bypasses; verify all guidance uses the repository's required terminology.
- [x] 3.2 Add the canonical fixed-width-prose agent skill with valid front matter, authoring examples, migration guidance, and validation instructions, and verify it passes the available Agent Skills validator.

## 4. Existing Markdown migration

- [x] 4.1 Reflow every existing tracked Markdown-family file with a one-time behavior-preserving migration, including internal guidance, public documentation, skills, root documents, and OpenSpec artifacts, and verify the complete candidate tree produces no prose findings.
- [x] 4.2 Review the migration diff for preserved fenced code, tables, front matter, raw HTML, headings, list structure, links, and rendered Markdown semantics, and verify `make docs-check` and the relevant documentation checks pass.

## 5. Integrated acceptance

- [x] 5.1 Run the validator tests, local prose check, strict OpenSpec validation, workflow/YAML checks, documentation checks, and the repository's applicable CI-equivalent checks, and verify every required result passes.
- [x] 5.2 Exercise a disposable candidate containing one wrapped Markdown paragraph and one wrapped pull-request paragraph, then remove each violation and verify the corresponding CI findings fail and pass as specified; separately verify that a wrapped commit body receives guidance but does not block.
- [x] 5.3 Exercise accepted structural examples and verify code, tables, front matter, headings, raw HTML, and separate one-line list items do not produce false positives.
