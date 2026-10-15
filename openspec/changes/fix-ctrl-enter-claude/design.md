# Design

## Context

See proposal.md for motivation. On macOS 15 and later, Control-Return is the system context-menu shortcut. AppKit does not deliver that key to a view as ordinary typing. It sends `contextMenuKeyDown(_:)` to the first responder and, unless a responder stops it, the request reaches the app, which shows the context menu for the focused view. Apple's `NSResponder` header says an app that gives Control-Return its own behavior should override this method, handle that combination, and return without calling `super`. The pane's menu comes from the SwiftUI `.contextMenu` in `PaneView`, which is what currently answers the request.

The terminal view is `BellCapturingTerminalView`, a `LocalProcessTerminalView` subclass from SwiftTerm. SwiftTerm already encodes keys for the Kitty keyboard protocol, and the app already relies on that protocol for Shift+Return, which it sends itself because SwiftTerm drops the Shift modifier for Return.

SwiftTerm's behavior for a Control+Return `keyDown` depends on the mode:

- With keyboard enhancement flags set, it reports Return with the Control modifier (`ESC [ 13 ; 5 u`).
- With no flags, its Control branch maps Return to no bytes, so it sends nothing at all.

The second case is why delegating everything to `keyDown` is not enough.

## Goals / Non-Goals

**Goals:**

- Control-Return in a focused terminal pane reaches the program, in both keyboard modes, with no menu.
- Menu behavior for pointer input and every other key stays exactly as it is.

**Non-Goals:**

- A new keyboard route to the pane menu.
- Reworking the key monitors in `App.swift` or `TerminalController.swift`.

## Decisions

### Override `contextMenuKeyDown(_:)` on the terminal view

The terminal view overrides the method. For Control-Return (key code 36, Control the only modifier among Control, Shift, Option, and Command) it handles the key and does not call `super`. For any other event it calls `super`, which preserves a user's remapped system shortcut.

Alternatives considered:

- **Another local key monitor that swallows Control-Return.** This is how Shift+Return is handled today. It is app-wide, would need its own focus checks, and fights the system rather than using the documented hook. The hook fires only for the focused terminal view, so no focus logic is needed.
- **Remove or restructure the SwiftUI `.contextMenu`.** This loses right-click behavior, which must remain.
- **Treat it in `performKeyEquivalent`.** The system context-menu shortcut is not routed through key equivalents, so this would not intercept it.

### Encode by mode

- **Keyboard enhancement flags set:** call `keyDown(with:)` with the original event so SwiftTerm produces the Kitty encoding, including repeat and release handling it already implements.
- **No flags:** send a carriage return (`0x0D`) directly, matching what a plain Return sends.

Alternative considered: always send the bytes ourselves, as the Shift+Return fix does. That duplicates SwiftTerm's event-type handling in enhanced modes and diverges when flags change, so SwiftTerm stays in charge of encoding wherever it produces a correct result.

### Observable through a test seam

Unit tests need to see the bytes the view sends for a synthetic Control-Return event in each mode. The implementation adds the smallest seam that records them, such as a send hook the tests assign, and does not change production routing.

## Risks / Trade-offs

- [The system might route the key somewhere other than the terminal view in some focus states, such as when a sheet is attached] → Verify in the running Dev app that Control-Return reaches Claude Code with a pane focused, and that it still behaves normally in sheets and with a non-terminal first responder. If the hook is not reached, fall back to handling the key in the existing key monitor with the same focus checks as the Shift+Return path.
- [Users who relied on Control-Return to open the pane menu lose that route] → Accepted in the proposal as a breaking change. Right-click and Control-click remain.
- [A user remapped the system context-menu shortcut] → Other key combinations go to `super`, so the remapped shortcut keeps working.
- [In a shell with no keyboard reporting, Control-Return and Return become identical] → This matches other terminals and is the specified behavior.

## Migration Plan

No data or settings migration. The change ships with the next release. Rollback is reverting the override.
