# Codex CLI Support

Agent Session Manager supports [Codex](https://developers.openai.com/codex) alongside Claude Code and Cursor.

## What It Does

When you create a pane with Codex selected, the app resolves or creates a worktree through the shared New Pane flow and launches `codex` in that checkout with any enabled CLI flags.

## How to Enable

Codex is disabled by default. To enable it:

1. Open **Settings** (⌘,)
2. Go to the **Harnesses** tab
3. Toggle **Codex** on

Once enabled, "Codex" appears as an option in the CLI picker when creating a new pane.

## Creating a Codex Pane

1. Open a tab pointing to your project directory
2. Press **⌘P** (or click **+** in the pane area) to open the New Pane sheet
3. Select **Codex** in the CLI segmented picker
4. Enter a session name
5. Click **Open**

The pane launches `codex` in the resolved checkout with any configured CLI flags appended.

## Configuring CLI Flags

Codex-specific flags can be enabled or disabled in **Settings → Harnesses → Codex**. Enable Codex first, then configure which flags appear as toggles or text fields in the New Pane sheet.

### Available Flags

| Flag | Type | Description |
|------|------|-------------|
| `--ask-for-approval` | string | For Codex 0.162.x, use `on-request` or `never`; saved `untrusted` values are rejected before launch and require a user correction |
| `--config` | string | Override configuration values (`key=value`, JSON-parsed if possible) |
| `--dangerously-bypass-approvals-and-sandbox` | boolean | Skip all approval prompts and sandbox restrictions (dangerous) |
| `--disable` | string | Force-disable a named feature flag |
| `--enable` | string | Force-enable a named feature flag |
| `--image` | string | Attach image files to the initial prompt |
| `--model` | string | Override the configured model for this session |
| `--no-alt-screen` | boolean | Disable alternate screen mode for the TUI |
| `--oss` | boolean | Use a local open source provider (Ollama) |
| `--profile` | string | Load a named configuration profile |
| `--sandbox` | string | Sandbox policy: `read-only`, `workspace-write`, or `danger-full-access` |
| `--search` | boolean | Enable live web search during the session |

## Compatibility

Codex integration is selected from the installed CLI version before lifecycle hooks are prepared. The `codex_0_162` adapter supports `SessionStart`, `UserPromptSubmit`, `Stop`, `PermissionRequest`, `PostToolUse`, and `Interrupt`; it does not inject `StopFailure`. The retained `codex_0_136` adapter uses its documented legacy hook contract and does not support `Interrupt`. An unrecognized version starts with app-owned baseline status and no guessed Codex lifecycle hooks or rich status parsing. Agent Control setup remains independent of this compatibility selection.

Codex 0.162.x accepts `on-request` and `never` for the built-in `--ask-for-approval` option. If a saved pane or profile still contains `untrusted`, the app shows a correction message before starting Codex and preserves the saved value and custom options until the user changes them. Correct the global Codex setting or the affected profile in Settings → Harnesses → Codex or Settings → Profiles, then use Refresh with New Settings for an existing pane so its saved option snapshot is replaced. A setup-failed pane exposes removal and its pane context menu, not an inline Retry button. Custom CLI flags remain available for user-defined integrations.

Adapter selection and option validation have source and unit-test coverage. Real Dev runs with Codex 0.162.1 exercised a fresh conversation, `/new`, CLI `/resume`, and a model change from `gpt-6-luna` to `gpt-6-sol`. A fresh session populated model, context, and token facts, transitioned from working to stopped, and posted a completion notification after its six generated hooks were reviewed and trusted. Refresh observations conflict: a separate owned Dev run reported resumed status and completion after Refresh, but its telemetry had no pane selected and no screenshot artifact was retained; in `codex-hooks-runtime-check-2`, a pre-Refresh generation recorded four hook drains and rich facts, while the later 19:11:20 UTC Refresh generation restored conversation history but produced no hook records, rich status facts, or new completion notification. The earlier success was from a distinct generation and does not establish reliable Refresh behavior. App-relaunch continuation is not yet runtime verified. Foreground identity changes clear the prior conversation's facts when the matching hook event is observed; until then, the previous snapshot may remain visible. Codex permission requests and native `request_user_input` calls produce distinct fixed-copy attention; the 0.162.1 permission row clears on the next foreground turn because its hook has no request ID, while native questions clear on their matching transcript call result. Completion alerts are controlled by the default-on **Codex completion notifications** setting. Source and unit coverage exists for permission and native-question attention; their real Dev request and acknowledgement captures remain outstanding.

## Status Line

Codex combines app-owned baseline status with a version-gated local provider. Baseline facts include worktree, branch, duration, changed lines, version, profile, and PR data. Rich session facts are limited to recognized adapters and the exact foreground conversation once its binding is observed; unsupported facts, such as cost, remain unavailable. A real Dev run confirmed current model, context, and token facts after new and resumed conversations and a model change. For supported lifecycle adapters, `UserPromptSubmit` starts the pane and tab working indicators, while `Stop` and supported `Interrupt` events stop them. Codex 0.136.x has no `Interrupt` hook; unknown versions do not receive inferred lifecycle behavior. Pending Codex permission or native question attention takes precedence as waiting. See [Status Line](status-line.md) for the current fact catalog and [Agent Harness Feature Matrix](agent-harness-feature-matrix.md) for cross-harness coverage.

## Session Persistence

Codex pane names, options, resolved checkout paths, and optional exact foreground conversation metadata are saved in `sessions.json`. With **Continue on Restart** enabled, the app checks the saved session ID and transcript through the effective Codex home: the configured interactive shell's exported `CODEX_HOME`, then the inherited launch value, then `~/.codex`. The same resolved home is used by Codex state enrichment and exact-session preflight, matching the interactive Codex process. An inaccessible saved conversation opens Retry/Start New recovery; older panes without a saved ID start fresh with a notice. **Refresh and Continue** resumes the current foreground conversation, while **Refresh with New Settings…** starts fresh.

See [agent-harness-feature-matrix.md]({{ '/documentation/features/agent-harness-feature-matrix/' | relative_url }}) for the cross-harness audit.
