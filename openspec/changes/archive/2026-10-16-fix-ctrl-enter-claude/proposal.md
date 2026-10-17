# Proposal

## Why

Claude Code uses Ctrl+Enter to send queued messages and the current draft immediately, which steers a running turn. In Agent Session Manager, pressing Ctrl+Return in a terminal pane opens the pane's context menu instead, so Claude Code never receives the key and the shortcut cannot be used. The application should deliver the key to the program running in the focused pane.

## What Changes

- **BREAKING**: While a terminal pane has keyboard focus, Control-Return is delivered to the program in that pane and no longer opens the pane's context menu.
- When the program has enabled extended keyboard reporting, Control-Return is reported as a distinct Control+Enter key. Otherwise it is delivered as an ordinary Return, matching other terminals.
- Right-click and Control-click continue to open the pane's context menu, and every other key combination is unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `native-pane-interactions`: adds a requirement that a focused terminal pane receives Control-Return instead of showing its context menu.

## Impact

- Code: `BellCapturingTerminalView` in `Sources/AgentSessionManager/Controllers/TerminalController.swift`, and new unit tests under `Tests/`.
- Behavior: macOS 15 and later route Control-Return through the system context-menu shortcut, so this is the only place the user-visible behavior changes. No settings, persistence, or documentation pages describe the old shortcut, so none change.
- Dependencies: none. The existing SwiftTerm keyboard encoding is reused.

## Out of Scope

- A setting to restore Control-Return as the pane menu shortcut, or any other way to open the pane menu from the keyboard.
- Changes to the existing Shift+Return handling or any other key binding.
- Changes to Claude Code's own key bindings or to how other harnesses interpret Control+Enter.
- Changing the system-wide context-menu shortcut in macOS settings, and its behavior outside terminal panes.
- Delivering Control-Return to terminal panes on macOS 25 and earlier. Only macOS 26 and later are supported for this behavior.
