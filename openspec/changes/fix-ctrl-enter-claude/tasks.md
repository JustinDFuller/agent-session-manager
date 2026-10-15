# Tasks

## 1. Deliver Control-Return to the terminal

- [ ] 1.1 Override the context-menu key handler on `BellCapturingTerminalView` so Control-Return (Control the only modifier) is handled without calling `super`, delegating to the existing key handling when keyboard enhancement flags are set and sending a carriage return otherwise, and passing every other event to `super`; verify with unit tests in `Tests/` that record the bytes sent for a synthetic Control-Return event with flags set (`ESC [ 13 ; 5 u`) and with no flags (`0x0D`)
- [ ] 1.2 Add unit tests that a non-Control-Return event reaches `super` and sends nothing, including Return, Shift-Return, and Control with another key; verify `swift test --filter` for the new test file passes
- [ ] 1.3 Run `make lint`, `make no-code-comments`, and `swift test`; verify all pass

## 2. Documentation

- [ ] 2.1 Add a short note to `documentation/reference/shortcuts.md` that Control-Return is sent to the program in the focused pane and no longer opens the pane menu, which right-click still opens, following the Diataxis skill; verify `make docs-check` and `scripts/test-release-publishing.sh` pass

## 3. Real-app proof

- [ ] 3.1 Build and launch the Dev app, open a Claude Code pane, queue a follow-up while a turn is running, and press Control-Return; verify with a screen recording or screenshots that Claude Code sends the queued message immediately and no menu opens
- [ ] 3.2 In the same Dev app, right-click the pane and open a plain shell pane, pressing Control-Return in each; verify with screenshots that the menu still opens on right-click and that the shell treats Control-Return as Return with no menu
- [ ] 3.3 Confirm Control-Return still behaves normally with a sheet attached and with a non-terminal control focused; verify with a short note and screenshot, or if the hook is not reached for a terminal pane, move the handling into the existing key monitor with the same focus checks and repeat 3.1
