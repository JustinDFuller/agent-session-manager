# Proposal

## Why

The October 12 production screenshot shows a working Codex conversation with an idle app indicator and status facts frozen on a conversation that ended October 10. Investigation also found missing native attention notifications, incorrect context math, incomplete continuation, and shared repository and GitHub authentication failures, making the app's surrounding UI unreliable even while Codex itself works.

## What Changes

- Track the foreground Codex conversation throughout a pane's lifetime, including native new/resume actions, and update model, tokens, context, and quota facts from that exact conversation.
- Match supported Codex context calculations and keep distinct quota buckets from erasing the standard usage facts.
- Drive working, stopped, and waiting indicators from real Codex lifecycle and attention events; deliver completion, permission, and question notifications through the existing sidebar and banner system.
- Make Refresh and Continue and enabled Continue on Restart resume the exact saved Codex conversation, preserving its pane configuration and worktree.
- Use an explicit, tested CLI compatibility contract, remove unsupported hook injection and the rejected `untrusted` approval suggestion, and expose unsupported rich data as unavailable.
- Populate Repository for every harness and make app-side GitHub polling use the user's configured executable and authentication context, with a visible recovery path for authentication failures.
- Update feature documentation and real Dev acceptance coverage so advertised support reflects behavior exercised with the installed CLI.
- Add a separate Dev-only Launch Services prerequisite that repairs the Dev registration without changing production registration or its running process, while preserving the macOS 26 floor.

## Capabilities

### New Capabilities

- `codex-session-status`: Exact foreground conversation tracking and current model, token, context, quota, and compatibility behavior.
- `codex-attention`: Codex lifecycle indicators, actionable attention, completion notification delivery, and acknowledgement.
- `codex-continuation`: Exact conversation continuation on pane refresh and opted-in app restoration.
- `codex-cli-compatibility`: Valid Codex pane options and version-appropriate lifecycle integration.
- `harness-status-baseline`: Shared repository identity and authenticated GitHub PR status with actionable failure reporting.
- `dev-launch-services`: Dev-only Launch Services registration and isolation from the production app.

### Modified Capabilities

None. Existing native pane interaction and native test validation requirements continue to apply; Claude-specific stop-alert behavior is outside these new Codex contracts.

## Impact

The implementation touches Codex providers and hook transport, status monitors, pane activity and notifications, persisted pane metadata, launch/refresh/restore command construction, CLI option copy, and shared GitHub executable resolution. Existing saved panes gain optional Codex conversation metadata without losing settings; there is no public MCP tool signature change or new hosted service. Runtime diagnostics remain metadata-only and pane-scoped.

This proposal defines the behavior and implementation plan for review. Its tasks remain unchecked until implementation and real Dev acceptance are complete. The Dev-only Launch Services prerequisite is a separate task group and implementation step; the six Codex task groups are consolidated into one implementation pull request as an approved exception to the usual one-group-per-pull-request rule.

## Deliberately Out of Scope

- Changing Codex's own TUI, model selection policy, approval decisions, sandbox protections, or hook trust policy; installing global user hooks or managed system hooks.
- Adding Codex facts that remain unsupported by its integration contract, such as monetary cost, or copying Claude's background-work lists into Codex.
- Replacing all harness providers with a new universal runtime, changing notification styling, or redesigning the tab/pane workflow.
- Switching GitHub accounts, refreshing credentials automatically, broadening account permissions, changing repository rulesets, or weakening the OpenSpec merge gate.
- Implementation, main-spec synchronization, or archival in this proposal PR. Subsequent implementation layers own whole top-level task groups; QA precedes an archive-only final layer.
