## Context

The implementation commit already contains the files produced by the repository's `openspec init` command: seven workflow skills, the `.openspec-target` marker, and initialized archive/spec directory markers. The repository's curated `openspec/config.yaml` and the OpenSpec workflow documentation remain the sources of truth for this bootstrap. See `proposal.md` for the motivation.

## Goals / Non-Goals

**Goals:**

- Keep the OpenSpec record in the same pull request as the initialization files it documents.
- Use the CLI-created change scaffold and configured `spec-driven` workflow so the entry is discoverable by repository checks.
- Make the change self-contained, reviewable, and ready for later archival after PR feedback is resolved.

**Non-Goals:**

- Do not add application behavior, source code, tests, dependencies, or public product requirements.
- Do not overwrite the curated `openspec/config.yaml` or normalize generated skill content by hand.
- Do not archive the change while the pull request is still in draft review.

## Decisions

- **Use `openspec new change` for the scaffold.** This preserves the CLI's required `.openspec.yaml` metadata and avoids manually recreating an OpenSpec change directory.
- **Set `skip_specs: true`.** This is repository tooling/bootstrap work with no observable product requirement delta; inventing a capability spec would create a false contract. The proposal, design, and tasks remain the durable planning record.
- **Keep the change active in this draft PR.** The active change must be present in the cumulative PR diff for the repository check to associate the check-in with OpenSpec. Archiving is deferred until review feedback is resolved and the PR is ready for review.
- **Validate the artifacts directly.** Run `openspec validate --all --strict`, verify the generated skills with `skills-ref validate`, and check the staged diff for whitespace and scope. Application build/UI evidence is reported separately because this change does not modify application code.

## Risks / Trade-offs

- **[Generated CLI content may drift from a future OpenSpec release]** → Preserve the exact files created by the installed CLI and keep the generated version metadata visible for future upgrades.
- **[The active change remains unarchived while the PR is draft]** → This matches the repository workflow; archive only after review feedback is resolved and immediately before marking the PR ready.
- **[No product spec exists for a tooling-only change]** → `skip_specs: true` records the deliberate exception instead of fabricating observable application behavior.

## Migration Plan

Commit the change artifacts to this PR, run strict OpenSpec validation, and keep the PR draft while it is reviewed. If the change is rejected, remove the active change directory in a follow-up commit; if accepted, complete any review-driven task updates and archive it as the final step before marking the PR ready.
