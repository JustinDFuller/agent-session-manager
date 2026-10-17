# GitHub PR Tracking

## What it does

GitHub PR Tracking detects the pull request associated with the current git branch and displays its status in the status line at the bottom of each pane. The PR fact shows the build status with a colored circle, the PR number, and the PR state (draft, open, merged, closed).

Clicking the PR fact opens a popover with detailed information: PR title, failing status checks (with links), unresolved comment count, and a link to open the PR in the browser.

This works for all CLI tools because it runs independently of session data. It uses authenticated `gh api graphql` queries for PR facts and unresolved review comment counts.

## How to use

1. Ensure the [GitHub CLI](https://cli.github.com) (`gh`) is installed and authenticated (`gh auth login`).
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

Each polling cycle determines the current branch for eligible panes and sends one batched, aliased GraphQL request. Each alias contains the PR metadata, status rollup, and review-thread count for one pane, so all eligible panes are updated from that single request. The owner and repository are extracted from `git remote get-url origin`. Polling repeats on the configured interval to catch status changes.

Repository identity is fetched by the shared status monitor for every pane, independently of the selected harness's rich status provider and GitHub authentication. This keeps the Repository fact available when GitHub PR queries fail.

The PR item distinguishes an in-progress check, a current pull request, a successful query with no pull request, and an unavailable result after a failed check. A failure after a successful result keeps the previous pull request visible with a warning; failed queries cannot trigger merge or close notifications. Authentication failures show **GitHub CLI authentication failed. Authenticate the configured `gh`, then retry.** and **Retry**. A successful query with no pull request shows **No PR** without an error. Retry rebuilds the command context from the configured interactive shell so repaired authentication or shell settings can recover without restarting the pane.

The GitHub CLI executable is selected from the configured interactive login shell's PATH, unless the app inherited an explicit `GH_PATH`, which takes precedence. Explicitly inherited GitHub configuration and token variables take precedence over values exported by that shell; missing values are filled from the shell context. The app disables interactive prompts and runs the resolved executable directly. It does not sign in, switch accounts, change credentials, or write shell environment values to diagnostics.

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
