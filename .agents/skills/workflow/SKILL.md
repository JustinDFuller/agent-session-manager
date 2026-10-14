---
name: workflow
description: "Development workflow for this repo: plan → test → implement → human review → repeat. Load when starting any feature, bug fix, or refactor."
---

## Fixed-width prose policy

Use the canonical [fixed-width-prose skill](../fixed-width-prose/SKILL.md) for prose-formatting guidance and load it before authoring or reviewing Markdown, pull-request descriptions, commit bodies, agent guidance, or repository documentation.

## Workflow

**1. Plan** — Always present a plan before writing code, whether or not plan mode is active. Use knowledge of the codebase from AGENTS.md. Explor relevant details further. Reference specific files and functions. End with a clear list of changes.

**1.5 Configuration** — For any feature with user-facing behavior that could vary by project or preference, design a configurable setting. Add the property to `AppSettings`, persist it via `SettingsPersistence` (save + restore pair, new JSON file), expose it in a `SettingsView` tab with an appropriate control and accessibility identifier, and call restore from `App.swift`.

**1.7 Documentation** — Create or update `documentation/features/<feature>.md` describing what the feature does, how to use it, and how to configure it. Ensure there is an `.agents/skills` entry linking to the feature documentation.

**1.8 Runtime telemetry** — For every runtime behavior feature, fix, or refactor, load `instrument-runtime-telemetry` before implementation. Add or update spans, invariants, telemetry tests, and catalogs as required by that checklist.

**2. Test** — Write tests before or alongside implementation. This repo has two test layers:
- **Unit tests** (`Tests/`) — fast, `swift test`, for logic and model behavior
- **UI tests** (`UITests/`) — full app, `make test-ui-dev`, for user-visible behavior

Every new behavior needs **both** a unit test and a UI test. Every changed behavior needs its tests updated. UI tests must drive real flows — create tabs/panes through the real sheets, trigger real notifications — not write a fabricated `sessions.json` or use `--inject-pane-*` launch flags to force state.

**3. Implement** — Write the minimal code to make the tests pass. Refactor code and tests together as implementation reveals better structure. Build must be clean: `swift build`.

**4. Verify** — REQUIRED before pausing for human review. Run all CI checks:

```bash
swift test                                                        # unit tests — must pass
swift-format lint --recursive --strict Sources/ Tests/ UITests/  # format — must pass
swiftlint lint --strict --config .swiftlint.yml                   # lint — must pass
make xcodeproj && make test-ui-dev                                # UI tests — must pass (dev build, isolated from prod settings)
make screenshots                                                  # capture UI screenshots — must pass
make pr-screenshots                                               # upload screenshots and embed under ## Example in PR body
```

Screenshots must depict real app state produced through real flows; screenshots captured via injected or forced state are being migrated away (see issue #221). UI test regressions are easy to miss and costly to fix later. **Never skip this step.** The git pre-commit hook runs format, lint, and the comment and prose checks; the pre-push hook runs unit tests and UI smoke tests (`AppLaunchTests`, `NewTabTests`, `NewPaneTests`) when the pushed commits include native changes, so most regressions will be caught before they reach a PR. Run `make setup-hooks` once to install them.

Use `make test-ui-dev` (not `make test-ui`) so tests run against the dev build and write to `agent-session-manager.dev` instead of the production app support directory. If a test run is interrupted before tearDown completes, the settings will be left dirty — run `make reset-app-state-dev` to clean them up (`make reset-app-state` for the prod directory).

Treat any prod-targeted UITest invocation as a workflow failure, not a harmless variation. Do not run `make test-ui`, do not run `xcodebuild test` unless it explicitly preserves the Dev configuration, and do not proceed if the command would touch `~/Library/Application Support/agent-session-manager/` instead of `~/Library/Application Support/agent-session-manager.dev/`.

**5. Commit & PR** — After all CI checks pass, automatically:

1. Stage and commit all changes with a message that includes the issue number and explains *why* the change was made.
2. Push the branch.
3. Open a PR with `gh pr create` using this exact template (fill in the bracketed placeholders):

```
gh pr create --title "[conventional-type]: [issue title] (#[N])" --body "$(cat <<'EOF'
> [!NOTE]
> This PR title, description, and code were generated with [active agent tool].

## Summary

One or two sentence overview.

## Changes

* change one, one sentence
* change two, also one sentence
* no more than ten bullet points

## Example

EOF
)"
```

Use the current tool's display name for `[active agent tool]`: `OpenAI Codex`, `Claude Code`, or `Cursor`. If the tool is different, use its actual display name. Never attribute one tool's work to another tool. Do not add an AI `Co-Authored-By` trailer unless the current tool provides an exact configured trailer; never copy another tool's trailer or invent an email address.

4. Run `make pr-screenshots` to upload screenshots and embed them under `## Example` in the PR body.

The PR title must use a conventional commit prefix (`feat:`, `fix:`, `refactor:`, etc.) and include the GitHub issue title so reviewers immediately see what is being addressed.

**6. Pause** — After the PR is open, stop and tell the human what to manually verify. Link to the open PR. Don't claim success until a human has exercised the feature.

**7. Repeat** — Incorporate feedback and return to step 1 for the next change.

## Test commands

```bash
swift build                                                       # must pass before any commit
swift test                                                        # unit tests (no Xcode needed)
make lint                                                         # swift-format check (matches CI)
swiftlint lint --strict --config .swiftlint.yml                   # swiftlint check (matches CI)
make xcodeproj                                                    # regenerate after project.yml changes
make test-ui-dev                                                  # ONLY approved default UI test command; isolated from prod settings
make reset-app-state-dev                                          # clear dev settings if a test run was interrupted mid-tearDown
make reset-app-state                                              # same for prod settings
```

## UI test maintenance

`UITestAppSupport.directory` (`UITests/Helpers/UITestAppSupport.swift`) is the single source of truth for which app support directory UITests read and write. It returns `agent-session-manager.dev` when compiled with `DEV_BUILD` (`-configuration Dev`), and `agent-session-manager` otherwise.

Before any ad hoc or focused UITest run, verify all three conditions:
- The command includes `-configuration Dev` or delegates to `make test-ui-dev`.
- The derived bundle identifier will contain `.dev` or `.xcode-dev`, never the production bundle identifier.
- The persisted-state directory is `~/Library/Application Support/agent-session-manager.dev/`.

If any of those checks fail or are unknown, stop and fix the command before launching the test runner. Do not "just try it" against production.

When a new settings file is added to the app, update it in **two places**:
1. `UITests/Helpers/BaseTestCase.swift` — `clearPersistedState()` file list
2. `Makefile` — both the `reset-app-state` and `reset-app-state-dev` file lists

## Screenshot maintenance

Screenshots are captured by `UITests/ScreenshotTests.swift` (real-flow, canonical) and `UITests/ScreenshotInjectedTests.swift` (legacy injected path, under active migration — see issue #221). New screenshots go in `ScreenshotTests.swift`; do not add entries to `ScreenshotInjectedTests.swift`. The `make screenshots` target runs both classes; `make pr-screenshots` runs them and uploads to a gist, then rewrites the `## Example` section of the open PR.

The `## Example` section is auto-generated from the PNGs actually produced — no manifest to keep in sync.

When adding or removing a screenshot, update **one place**:
1. `UITests/ScreenshotTests.swift` or `UITests/ScreenshotInjectedTests.swift` — add/remove the `screenshot(...)` call

If adding a **new test class** (rare), also add `-only-testing:AgentSessionManagerUITests/<ClassName>` to the `screenshots` target in the `Makefile`.

`scripts/ship.sh` verifies that the set of PNGs produced by `make screenshots` exactly matches the set of `screenshot(...)` calls in the UITest source files, and hard-fails with a diagnostic if they diverge.
