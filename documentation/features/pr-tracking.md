# GitHub PR Tracking

## What it does

GitHub PR Tracking detects the pull request associated with the current git branch and displays its status in the status line at the bottom of each pane. The PR fact shows the build status with a colored circle, the PR number, and the PR state (draft, open, merged, closed).

Clicking the PR fact opens a popover with detailed information: PR title, failing status checks (with links), unresolved comment count, and a link to open the PR in the browser.

This works for all CLI tools because it runs independently of session data. It uses authenticated `gh api graphql` queries for PR facts and unresolved review comment counts.

## How to use

1. Ensure the [GitHub CLI](https://cli.github.com) (`gh`) is installed and authenticated in the shell selected in **Settings → Panes → Terminal**. PR tracking uses that shell's GitHub CLI configuration.
2. Open **Settings** (⌘,) and go to the **Status Line** tab.
3. Enable the **Track pull requests** toggle in the **GitHub PR Tracking** section.
4. Add the **PR** item to a status line row (it appears in the "Add Item" menu as "PR").
5. When you create a pane on a branch that already has an open pull request, the PR fact appears in the status line with the format `<circle> #<number> (<state>)`.

## Circle colors

The colored circle represents the build and conflict status:

| State | Circle Color | Meaning |
|---|---|---|
| `merged` | Purple | Always purple — merged PRs |
| `closed` | Red | Always red — closed (not merged) |
| `draft` or `open` | Red | PR has merge conflicts (takes precedence over build status) |
| `draft` or `open` | Green | All status checks passing |
| `draft` or `open` | Yellow | Status checks are running, queued, or pending |
| `draft` or `open` | Red | At least one status check failed |
| `draft` or `open` | Gray | All status checks were cancelled |
| `draft` or `open` | Gray (secondary) | No status checks configured |

## PR fact display

The status line shows: `<circle> #<number> (<state>)`

Examples:
- `🟢 #31 (open)` — builds passing
- `🟡 #311 (draft)` — builds running
- `🔴 #42 (open)` — builds failing
- `🟣 #55 (merged)` — always purple
- `🔴 #12 (closed)` — always red

## Popover

Click the PR fact to open a popover showing:

- **PR number** with the colored status circle
- **PR title** (truncated to 2 lines)
- **Merge conflicts** — shown in red with a warning icon when GitHub reports the branch cannot be merged due to conflicts
- **Failing checks** — listed with truncated names (60 chars max) and links to the check details page. If more than 5 checks are failing, "and N more failing checks..." is shown.
- **Unresolved comments** — count of unresolved review threads (fetched via the GitHub GraphQL API)
- **Open Pull Request** — button to open the PR in the default browser

Click outside the popover to dismiss it.

## How it works

Each polling cycle determines the current branch for eligible panes and sends one batched, aliased GraphQL request. Each alias contains the PR metadata, status rollup, and review-thread count for one pane, so all eligible panes are updated from that single request. The owner and repository are extracted from `git remote get-url origin`. Polling repeats every 60 seconds to catch status changes.

PR polling starts the configured interactive shell to resolve its current `PATH` and exported GitHub CLI configuration, then runs `gh` with that in-memory environment. An explicit `GH_PATH` override takes precedence over shell lookup, including when the override is invalid. If shell startup fails or times out, polling falls back to the app's inherited environment. Shell output and environment values are bounded and excluded from diagnostics. `gh` remains the authentication boundary and must be installed and authenticated for PR tracking.

A successful query with an empty `nodes` list clears the item and displays **No PR**. Missing or malformed response aliases are failures, not evidence that the branch has no PR. Failed queries retain the last known PR, mark it stale in the status line and popover, and cannot trigger merge or close notifications. The popover offers **Retry**; authentication failures direct the user to authenticate the configured GitHub CLI before retrying. The `pr.graphql.query` and `pr.result.delivered` diagnostics distinguish classified query failures from a successful `not_found` result; they record bounded result categories without response content or credentials.

The batched GraphQL request is passed to `gh` through standard input. If `gh` exits or closes standard input before consuming the request, Agent Session Manager records bounded pipe failure details and treats the poll as failed. A classified authentication, network, or API failure remains the primary outcome; otherwise the result is `stdin_write`. The closed pipe cannot terminate the app.

### Fallback behavior

- If `git remote get-url origin` fails (no remote configured), the unresolved comment count is omitted from the popover.
- If the GraphQL query fails for any reason, unresolved comments are simply not shown — the rest of the popover still works.
- If no status checks are configured on the PR, the circle shows the secondary color and the "Failing Checks" section is hidden.

## How to configure

| Setting | Location | Default | Description |
|---|---|---|---|
| GitHub PR Tracking | Settings → Status Line | On | Enable or disable PR detection |

The setting is persisted to `~/Library/Application Support/agent-session-manager/pr-tracking-settings.json`.

### Hiding Claude Code's native PR footer badge

When PR tracking is enabled, the app injects both `showPRStatus: false` and `prStatusFooterEnabled: false` into the per-pane `--settings` file passed to Claude Code. This suppresses Claude Code's own `PR #N` footer badge so the app's PR fact is the sole PR indicator, avoiding duplication.

> **Note:** Claude Code renamed this setting from `showPRStatus` to `prStatusFooterEnabled` in version 2.1.145+. Both keys are injected for backward compatibility — unknown keys are ignored by each version, so writing both is safe.
