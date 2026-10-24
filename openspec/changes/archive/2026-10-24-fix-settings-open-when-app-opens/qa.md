# QA

Validated on 2026-10-22 against the implementation branch with a Dev build from `make app-dev`, started with `scripts/recursive-development.sh start` (run ID `f5a7d82d-0223-4d86-bb90-33dae240fa4b`). The production app (PID 93011) kept running untouched throughout.

## Before the fix

A build of the proposal commit (macOS 14 floor, `make app-dev`) launched through Launch Services showed two on-screen windows: the 1200x800 main window and a 900x450 blank window, the "AgentSessionManagerDev Settings" window.

## After the fix

Observed with Computer Use screenshots and an on-screen window count for the launched process:

- Fresh launch: one on-screen window, the 1200x800 main window, with the Dev build's name in the menu bar. The first-run welcome card appeared inside the main window, and no Settings window existed.
- Cmd+, opened the real window titled "AgentSessionManager Settings" with its sidebar sections: Panes, Profiles, Harnesses, Shortcuts, Status Line, Notifications, Debug, About.
- Quit from the app menu with Settings open, then relaunched: one on-screen window, the main window only.
- Cmd+, after the relaunch opened the real Settings window again, and a second Cmd+, closed it.

## Findings

- Raising the floor to macOS 26 alone removed the blank window in this environment. The scene modifiers are belt and braces on top of it.
- The new launch UI tests pass on the unfixed floor-14 code when run through the Xcode-built test app, which is linked against a newer SDK than the `make app-dev` build. They are regression guards, and the before and after above is the proof of the fix. This was accepted by the user.
- `scripts/recursive-development.sh stop` refused to stop the relaunched process because its recorded identity was the first process. The relaunched Dev process was quit with a normal app quit.
- The update feed had no minimum system version, so Sparkle would have offered the macOS 26 build to macOS 14 and 15. New items now carry `sparkle:minimumSystemVersion` 26.0 and the app bundle declares `LSMinimumSystemVersion` 26.0. An item generated with a fixture key contained `<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>`.
