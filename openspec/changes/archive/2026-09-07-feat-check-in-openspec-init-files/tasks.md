## 1. OpenSpec Bootstrap Record

- [x] 1.1 Keep the CLI-generated OpenSpec workflow skills and `.openspec-target` marker in the repository, and verify all seven workflow skill directories pass `skills-ref validate`.
- [x] 1.2 Keep the initialized `openspec/changes/archive/.gitkeep` and `openspec/specs/.gitkeep` markers plus the change `.openspec.yaml`, and verify `openspec status --change feat-check-in-openspec-init-files --json` reports the intended scaffold and spec-driven behavior.

## 2. Repository Validation

- [x] 2.1 Validate the complete repository OpenSpec state with `openspec validate --all --strict` and verify the change artifacts are structurally valid.
- [x] 2.2 Confirm the pull request contains only the OpenSpec and agent-workflow files in scope, with no application source, tests, dependencies, or runtime behavior changes.
