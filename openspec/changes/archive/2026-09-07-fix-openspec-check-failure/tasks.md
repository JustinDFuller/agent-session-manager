## 1. Remove working-directory coupling

- [x] 1.1 Update `.github/scripts/openspec-merge-gate.test.mjs` to read the validator and workflow through module-relative `URL` paths, and verify no workflow or validator source changes are introduced.
- [x] 1.2 Run `node --test .github/scripts/openspec-merge-gate.test.mjs` from the repository root and verify all 21 tests pass.

## 2. Verify the base-owned CI invocation

- [x] 2.1 Reproduce the workflow checkout shape in a temporary directory containing `enforcement-source/.github/scripts/` and `enforcement-source/.github/workflows/`, run `node --test enforcement-source/.github/scripts/openspec-merge-gate.test.mjs` from its workspace root, and verify all 21 tests pass.
- [x] 2.2 Run `openspec validate --all --strict` and the repository’s applicable lint/comment checks, verifying they pass with the completed planning change and implementation.
