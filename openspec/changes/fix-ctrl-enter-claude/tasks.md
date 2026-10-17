# Tasks

## 1. Deliver Control-Return to the terminal

- [ ] 1.1 Override the context-menu key handler on `BellCapturingTerminalView` so Control-Return (Control the only modifier) is handled without calling `super`, delegating to the existing key handling when keyboard enhancement flags are set and sending a carriage return otherwise, and passing every other event to `super`; verify with unit tests in `Tests/` that record the bytes sent for a synthetic Control-Return event with flags set (`ESC [ 13 ; 5 u`) and with no flags (`0x0D`)
- [ ] 1.2 Add unit tests that a non-Control-Return event reaches `super` and sends nothing, including Return, Shift-Return, and Control with another key; verify `swift test --filter` for the new test file passes
- [ ] 1.3 Run `make lint`, `make no-code-comments`, and `swift test`; verify all pass

## 2. Documentation

- [ ] 2.1 Add a short note to `documentation/reference/shortcuts.md` that Control-Return is sent to the program in the focused pane and no longer opens the pane menu, which right-click still opens, following the Diataxis skill; verify `make docs-check` and `scripts/test-release-publishing.sh` pass

## 3. Final validation with Computer Use on a Dev build

- [ ] 3.1 Start a fresh owned Dev run with `scripts/recursive-development.sh start` from the implementation commit and confirm with Computer Use that the window title shows the Dev build for this branch and commit; verify with a screenshot of the title
- [ ] 3.2 With Computer Use, open a Claude Code pane, start a turn, type a follow-up so Claude Code queues it, then press Control-Return; verify with a screen recording or before-and-after screenshots that Claude Code sends the queued message immediately and no context menu appears
- [ ] 3.3 With Computer Use, right-click the same pane; verify with a screenshot that the pane context menu opens with its existing items
- [ ] 3.4 With Computer Use, open a plain shell pane, type a command, and press Control-Return; verify with a screenshot that the command runs as with Return and no menu appears
- [ ] 3.5 With Computer Use, press Control-Return while a sheet is open and while a non-terminal control has focus; verify with screenshots that behavior there is unchanged. If 3.2 fails because the key never reaches the terminal, move the handling into the existing key monitor with the same focus checks as the Shift+Return path and repeat 3.2 through 3.5
- [ ] 3.6 Stop the owned Dev run's PID and confirm the production app was untouched; record the evidence links, commit, and run ID in the QA pull request description
