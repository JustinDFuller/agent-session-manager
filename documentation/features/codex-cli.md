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

Adapter selection and option validation have source and unit-test coverage. The installed Codex 0.162.1 Dev launch and hook-queue behavior have not yet received real-runtime acceptance in this change, and foreground conversation tracking, rich metric accuracy, attention, and continuation remain pending their implementation and runtime review.

## Status Line

Codex combines app-owned baseline status with a version-gated local provider. Baseline facts include worktree, branch, duration, changed lines, version, profile, and PR data. Rich session facts are limited to recognized adapters and must describe only data available for that exact conversation; unsupported facts, such as cost, remain unavailable. See [Status Line](status-line.md) for the current fact catalog and [Agent Harness Feature Matrix](agent-harness-feature-matrix.md) for cross-harness coverage.

## Session Persistence

Codex pane names, options, and resolved checkout paths are saved in `sessions.json`. On relaunch, Codex panes are restored when their checkout still exists.

See [agent-harness-feature-matrix.md]({{ '/documentation/features/agent-harness-feature-matrix/' | relative_url }}) for the cross-harness audit.
