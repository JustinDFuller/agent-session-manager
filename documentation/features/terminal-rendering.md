# Terminal Rendering

## What

Agent Session Manager uses the upstream SwiftTerm package for terminal emulation. The minimum supported SwiftTerm version includes a resize fix that processes populated buffer lines instead of materializing every line allowed by the scrollback capacity.

## Why

Older SwiftTerm releases resized every possible scrollback line, including empty capacity. Large scrollback settings could therefore make routine pane layout changes allocate many terminal lines and block input. SwiftTerm may also represent blank cells with the null character (code 0), which would appear as `^@` in captured debug output without normalization.

## Fix

### Upstream resize behavior

SwiftTerm 1.18.0 or newer limits resize work to populated lines in the terminal buffer. Agent Session Manager depends on that upstream behavior so a pane with the 50,000-line capped mode remains responsive while panes are added, removed, or rearranged.

### `renderedScreenText` null → space replacement

`TerminalController.renderedScreenText` replaces any remaining null cells (code 0) with space characters before building the output string. This matches SwiftTerm's own visual renderer (`buildAttributedString` in `AppleTerminalView`) which does the same: `ch.code == 0 ? " " : terminal.getCharacter(for: ch)`.

Replacing with spaces (rather than filtering them out) preserves the layout of multi-column terminal output in the debug log. For example, Claude Code's todo table — where columns are separated by null cells — renders as `"Files     Modified"` rather than collapsing to `"FilesModified"`.

Trailing spaces are trimmed per line, and fully-blank lines are removed from the output, so all-null rows still produce empty strings.

## How to verify

1. Enable debug logging in Settings > Debug
2. Open the Debug Log window and click "Capture Terminal"
3. Verify the terminal content shows clean text without `^@` characters
4. For multi-column output (e.g. Claude's task list), verify column spacing is preserved

## Updating SwiftTerm

Keep `Package.swift` and `project.yml` on the same minimum version. Run `TerminalScrollbackTests.testHighCapacityTerminalResizeRemainsResponsive` after dependency updates to confirm resize work does not regress to scaling with scrollback capacity.

The native terminal view exposes a named accessibility group for each pane, including shell panes. Its identifier is assigned directly to the AppKit view so accessibility clients can focus or open the context menu on the real terminal surface. The unit suite checks the accessible surface, and the Dev UI suite exercises terminal input and context menus.

Shell panes and restored panes install their real terminal controllers during UI testing through the same `Tab.addPane` path used in normal app launches. Process startup remains deferred until the terminal view has a stable layout.
