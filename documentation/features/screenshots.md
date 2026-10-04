# UI Test Screenshots

The screenshot suite captures real UI flows for documentation and PR review.

## Coverage

ScreenshotTests captures all 34 views:

- onboarding-welcome
- onboarding-shell
- onboarding-tools
- onboarding-status-line
- onboarding-cli-flags
- onboarding-profiles
- empty-state
- new-tab-sheet
- new-tab-sheet-filled
- main-window-tab
- new-pane-sheet
- new-pane-agent-control
- new-pane-cli-options
- split-panes
- pane-scrollback-menu
- existing-worktree-prompt
- worktree-cleanup-alert
- reordered-tabs-and-panes
- settings-panes
- settings-agent-control
- settings-notifications
- settings-profiles
- settings-tools
- settings-shortcuts
- settings-status-line
- settings-status-line-custom-field-selector
- settings-status-line-custom-field-harnesses
- settings-debug
- pane-status-indicators
- notification-sidebar
- focused-pane
- trace-dashboard
- trace-waterfall
- invariant-dashboard

`testWalkthrough` captures 31 screenshots in one continuous app session. The trace-dashboard and invariant-dashboard screenshots each run in their own clean session.

BaseTestCase.screenshot() writes PNG files only when SCREENSHOTS_OUTPUT_PATH is set. Normal make test-ui-dev runs retain screenshots as XCTest attachments; make screenshots additionally writes them to screenshots/ in the repository root.

For the macOS 26 visual baseline, the walkthrough prepares the default branch fixture as main before launch so the New Tab sheet uses the canonical branch.

## Generating screenshots

    make screenshots

This runs `ScreenshotTests` and `ClaudeNotificationFlowTests` and writes PNGs to `screenshots/`. The Claude notification scenarios require an installed, authenticated Claude Code and exercise real background work, question/plan attention, and interrupted-turn recovery. Skipped or failed scenarios are not screenshot evidence; the shipment inventory requires all expected captures. The directory is gitignored; the workflow force-adds it when creating a PR.

## Multi-worktree safety

The Makefile passes the absolute worktree screenshots directory through TEST_RUNNER_SCREENSHOTS_OUTPUT_PATH. xcodebuild strips the TEST_RUNNER_ prefix before forwarding the variable to the test process, so simultaneous worktrees write to separate directories.

## Authenticity

Screenshots are produced through real UI flows. Panes are created through the New Pane sheet, worktree prompts use real Git worktrees, reordering uses real drag gestures, and terminal attention uses the existing bell handling. The walkthrough does not inject sessions, panes, notification arrays, activity states, or GitHub pull-request data.

## Workflow integration

The workflow skill runs make screenshots during verification. make pr-screenshots captures the same canonical set, uploads the PNGs to a gist, and rewrites the PR Example section in place.
