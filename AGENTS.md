# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, Cursor CLI, OpenCode) when working with code in this repository.

## What This Is

Agent Session Manager is a native macOS app (Swift/SwiftUI, macOS 14+) for running multiple AI agent sessions in parallel. It provides a tabbed, multi-pane terminal window where each pane runs Claude Code, Cursor, Codex, or OpenCode in a git worktree context, letting you work on several tasks simultaneously without context switching between windows.

**Tabs** represent a working directory. Each tab has a name and a root directory. You can have many tabs open at once and switch between them with ⌘1–⌘9.

**Panes** are terminal sessions inside a tab. When you create a pane you choose a harness and give it a session/worktree name. All four harnesses use the shared app-owned worktree path. Worktrees **created by the app** live only under `<repo>/.agent-session-manager/worktrees/<name>`. If a branch is already checked out in any path `git worktree list` knows about, the app can open that checkout. Panes auto-arrange in a grid (1×1 → 2×1 → 2×2 → 3×2 → 3×3) as you add more. Each pane shows a live status indicator: green pulsing dot when the process is running, gray when it has exited.

**Status line** — each pane shows a configurable status bar at the bottom. Claude Code uses a `statusLine` hook; Cursor combines app-owned baseline data with hook model data; Codex uses app-owned baseline data; OpenCode uses a per-pane HTTP provider. Catalog availability and populated provider fields are tracked in [documentation/features/agent-harness-feature-matrix.md](documentation/features/agent-harness-feature-matrix.md).

**CLI options** are configurable per-pane. Each harness has a built-in flag catalog; enabled flags appear as toggles and text fields in the New Pane sheet. Users can also add custom flags. Settings are persisted across launches.

**Session persistence** saves tabs and pane names to `~/Library/Application Support/agent-session-manager/sessions.json`. On relaunch the app restores tabs and restarts each pane's harness when its resolved checkout still exists on disk. Legacy Claude entries can still fall back to `.agent-session-manager/worktrees/<name>` or `.tree/<name>`.

**Keyboard shortcuts:**
- ⌘T — new tab
- ⌘P — new pane
- ⌘W — close active pane
- ⌘K — close active tab
- ⌘1–⌘9 — switch to tab by index

## Core Design Principle

The tab/pane workflow is fixed — that structure is the product. What happens *inside* a pane is not. People use agent harnesses in very different ways (different tools, flags, models, personas, workflows), and that diversity is a feature, not a problem to solve. Every design decision should preserve room for that customization within the core workflow rather than hardcoding assumptions about how a harness should be invoked.

Concretely: the core workflow (create tab → create pane → terminal session) should remain simple and opinionated. The configuration surface (CLI flags, custom options, per-pane settings) should remain open and extensible.

## Naming

Do not use the acronym **ASM** for this app in documentation, comments, UI copy, or commit messages—write **Agent Session Manager** in full. Avoid new temp-file basenames or code identifiers that use `asm-` as shorthand for the product; prefer explicit prefixes such as `agent-session-manager-…`.

## No Code Comments

Do not add explanatory comments to tracked non-Markdown code or configuration files. Use the appropriate durable channel instead:

- Document how behavior should work in the relevant OpenSpec specification or change delta.
- Document how an implementation should be built and why that approach was chosen in the active OpenSpec change's `proposal.md` and `design.md`.
- Explain why a change is needed in the pull-request description.
- Record change history in commit messages.
- Explain usage in the user-facing documentation site or an agent skill.
- Simplify confusing code first; put any remaining rationale in the pull-request description.
- Explain package purpose in the nearest `README.md` or feature map.

Markdown files, pull-request prose, and commit messages may contain prose. Keep executable shebangs and the first-line SwiftPM tools-version directive in `Package.swift`. Run `make no-code-comments` before review.

## Fixed-Width Prose

The canonical fixed-width prose policy is [the `fixed-width-prose` skill](.agents/skills/fixed-width-prose/SKILL.md); load it before writing or reviewing Markdown, pull-request descriptions, commit bodies, agent guidance, or repository documentation. It defines the one-line logical-prose rule, structural exceptions, local validator, CI hard block, commit-body guidance, and no-force-push rule.

## No One-Off Methods

Do not introduce or retain a named Swift function with fewer than two explicit call sites. This applies to instance, static, free, and local functions. Inline behavior at its sole caller and delete dead functions. Count production and test call sites separately. A production function may count direct test calls only in the rare case where it isolates substantial logic that is meaningfully tested apart from its caller. Exempt required indirect entry points such as protocol witnesses, overrides, delegate callbacks, Codable methods, SwiftUI representable requirements, and test-runner entry points. Do not satisfy this rule with ceremonial calls or another one-off wrapper.

## Terminal Purity

The terminal pane is the selected harness's UI, not a setup script runner. Users should never see app-level plumbing (git commands, setup output, error text from the app) in the terminal. Any setup the app needs to do before launching a harness — creating worktrees, fetching branches, writing config files — must happen in Swift using `Foundation.Process` or file APIs, not by prepending shell commands to the final invocation.

Concretely: `buildClaudeCommand()` and similar functions must only emit the final tool invocation (`claude ...`, `codex ...`). All prerequisite work runs in the app layer (e.g. `Tab.resolveOrAttachWorktree()` when attaching to an existing branch/worktree) and surfaces errors through SwiftUI UI (sheets, inline error text), not through the terminal.

## No Fake UI Tests / Screenshots

UI tests and screenshots are the primary evidence that the app actually works. For every PR they must answer: did this change work, and did it break anything? A test or screenshot that uses fabricated data, injected state, or a test-only code branch to make the app merely *look* like it works gives false confidence and is forbidden.

Concretely:
- Tests must build their state through the same flows a user would — create tabs/panes via the real sheets, trigger real notifications, run a real harness — not by writing a fabricated `sessions.json` or forcing UI state.
- Production code under `Sources/` must not contain branches whose only purpose is to alter behavior for tests/screenshots (`--inject-pane-*`, `uiTestActivityStateOverride`, the `!isUITesting` terminal bypass, etc.). The existing ones are tracked for removal in issue #221.
- Do not add new fakes. Making the existing fakes real is an active, in-progress migration — see issue #221.

## Build & Run Commands

```bash
make build        # swift build -c release
make app          # build + bundle into .app
make run          # build, bundle, and open the app
make restart      # kill and reopen the running app without rebuilding
make watch        # watch Sources/ and Tests/ for changes, auto rebuild+restart (no external tools needed)
make xcodeproj    # regenerate Xcode project via xcodegen (required before UI tests)
make lint         # swift-format lint --recursive --strict (matches CI format check)
make setup-hooks  # configure git hooks: fast checks on commit, full checks for the pushed changes on push
make clean        # remove .build/, .app/, .xcodeproj/
make docs-check   # render the GitHub Pages site and check generated local links
```

The documentation check requires a current Ruby installation and Bundler. It builds the site into `.build/docs-site` and validates the rendered HTML without checking external URLs over the network.

## Testing

**Unit tests** (fast, no Xcode needed):
```bash
swift test
swift test --filter CLIOptionConfigTests/testSpecificTest  # run a single test
```

**UI tests** (requires Xcode + xcodegen):
```bash
make xcodeproj    # regenerate if project.yml changed
make test-ui-dev  # ONLY approved default UI test command; runs the UITests scheme in the Dev build
make open-results # open .xcresult bundle to inspect failures
```

**WARNING**: Never run UI tests against production. `make test-ui`, `xcodebuild test` without `-configuration Dev`, or any run that targets `com.justinfuller.agent-session-manager`, `com.justinfuller.agent-session-manager.xcode-release`, or `~/Library/Application Support/agent-session-manager/` is a blocking mistake because it can read or dirty real app state. Stop and fix the invocation before running the tests.

If you must run a focused `xcodebuild test` command, keep the same isolation guarantees as `make test-ui-dev`: pass `-configuration Dev`, confirm the app support path resolves under `~/Library/Application Support/agent-session-manager.dev/`, and treat any missing `.dev` / `.xcode-dev` marker as a failure in the command itself. If a dev UITest run is interrupted before tearDown completes, clean up with `make reset-app-state-dev`.

**IMPORTANT**: Update the test suite with every change. Unit tests live in `Tests/` (e.g. `CLIOptionConfigTests.swift`, `WorktreeListParserTests.swift`). UI tests live in `UITests/`. The app passes `--uitesting-skip-restore` during UI test runs to bypass session restoration.

Run `make setup-hooks` after cloning to install git hooks. Commits run only fast checks on the staged files (comment and prose checks, OpenSpec validation, format and lint). Pushes run the remaining checks for the commits not yet on the remote, cheapest first and stopping at the first failure: CI script tests, hook tests, the documentation build, `swift test`, and UI smoke tests. Native checks run only when native files changed, and any unrecognized file runs them. `scripts/git-hook-checks.sh` holds the classification.

**No fake UI tests or screenshots**: see the `## No Fake UI Tests / Screenshots` rule above and the migration backlog in issue #221.

## Architecture

**Entry point:** `Sources/AgentSessionManager/App.swift` — initializes `AppState` and `AppSettings`, restores persisted state, registers ⌘T shortcut.

**Models** (`Models/`):
- `AppState` — `@Observable` root state; owns the list of tabs and tracks active tab/pane IDs
- `Tab` — A directory context containing one or more `Pane`s; responsible for spawning harness processes and resolving or creating git worktrees—new trees only under `.agent-session-manager/worktrees/`, existing checkouts anywhere listed by `git worktree list`
- `Pane` — One terminal session; holds a `TerminalController`
- `AppSettings` — In-memory state for which CLI flags are enabled and status line configuration
- `CLIOptionConfig` — Defines harness-specific CLI flag catalogs plus user-added custom flags; handles flag type mapping (boolean vs. string) and JSON persistence
- `StatusLineConfig` — Defines the status line chip catalog (visibility, labels, harness availability); `StatusLineData` stores provider output
- `GridLayout` — Computes pane grid dimensions (1×1 → 2×1 → 2×2 → 3×2 → 3×3) based on pane count

**Controllers** (`Controllers/`):
- `TerminalController` — Wraps SwiftTerm's `LocalProcessTerminalView`; tracks process state (idle/running/exited) via `LocalProcessTerminalViewDelegate`
- `SessionPersistence` — Saves/restores tabs, panes, and active tab to `~/Library/Application Support/agent-session-manager/sessions.json`
- `SettingsPersistence` — Saves/restores enabled CLI flags to `settings.json` and status line config to `statusline-settings.json`
- `StatusLineMonitor` — Per-pane `@Observable` class; uses Claude's temp `statusLine` settings file or a harness-specific data provider, merges PR data, and exposes parsed `StatusLineData`

**Views** (`Views/`):
- `ContentView` — Root; composes `TabBarView` + `PaneGridView`; owns NSEvent keyboard monitor for ⌘W and ⌘1–9
- `TerminalRepresentable` — `NSViewRepresentable` wrapping SwiftTerm; defers process start until the view frame is non-zero (layout must be complete before the terminal resizes correctly)
- `NewPaneSheet` — Harness picker, shared worktree resolution flow, and dynamic CLI option toggles from `CLIOptionConfig`
- `SettingsView` — In-window settings overlay with sections: Panes, Profiles, Harnesses, Shortcuts, Status Line, Notifications, Debug, and About
- `StatusLineView` — Renders visible status items as a monospaced caption bar; formats durations, reset times, cost, token counts, and all other Claude data fields

## Visual Design System

The app uses a **macOS-native, system-integrated** design with no custom color palette or design token file. All styling is inline; follow these implicit patterns to stay consistent.

**Colors — use system semantics only:**
- Backgrounds: `.controlBackgroundColor`, `.windowBackgroundColor` (headers), `.textBackgroundColor` (pane body)
- Text: `.primary`, `.secondary`, `.tertiary`, `.quaternary` — never hardcoded colors for text
- Status: `.green` (running), `.gray.opacity(0.4)` (exited), `.red` (destructive actions only)
- Interactive: `.accentColor` for buttons/active borders; `accentColor.opacity(0.15/0.4/0.6)` for tints

**Active/selected state:** dual signal — background tint (`accentColor.opacity(0.15)`) + stroke border (`accentColor.opacity(0.4–0.6)`). Inactive borders use `opacity(0.1)`.

**Typography:**
- `.headline` — sheet titles, section headers
- `.subheadline` — form field labels
- `.caption` — footer/description text
- Monospaced (`design: .monospaced`) for all technical content: flag names, paths, pane names
- Active tab: `size: 12, weight: .semibold`; inactive: `size: 12, weight: .regular`
- Pane header name: `size: 11, weight: .semibold, design: .monospaced`

**Spacing — multiples of 4:**
- Grid/tight gaps: `4px`
- Form field gaps: `8px`
- Header padding: `10px` horizontal, `5px` vertical
- Sheet content spacing: `20px`
- Sheet outer padding: `24px`

**Corner radii:** `4px` badges, `6px` tab highlights, `8px` pane containers

**Fixed dimensions:** sheets 420px wide (320px for small dialogs), settings window 560×580, tab bar 44px tall, status dot 7×7px, add-pane button 36×36px circle

**Animation:** one animation in the entire app — the running status dot pulses opacity 1.0→0.5 with `.easeInOut(duration: 1.2).repeatForever(autoreverses: true)`. Don't add animations elsewhere without strong justification.

**Empty states:** large icon (`size: 36`) in `.quaternary`, centered, with `.secondary` descriptive text below.

## Project & Issues

- GitHub repo: https://github.com/JustinDFuller/agent-session-manager
- Tasks and bugs are tracked as GitHub Issues: https://github.com/JustinDFuller/agent-session-manager/issues
- Reference the relevant issue number in commit messages and PR descriptions.

## Documentation

For the optional OpenSpec `opsx` workflow, see [`openspec/README.md`](openspec/README.md).

When an OpenSpec change spans dependent pull requests, follow the canonical [`openspec-stacked-prs` skill](.agents/skills/openspec-stacked-prs/SKILL.md) for `gh stack` creation, linking, import, and verification. Each implementation pull request owns one top-level OpenSpec task group and all of its subtasks; never split subtasks such as `2.1` through `2.5` into separate stack PRs.

Load `.agents/skills/diataxis-documentation` before creating, editing, moving, or reviewing documentation.

Public documentation has four types, each serving one dominant need:

- **Tutorials** teach a successful learning path.
- **How-to guides** help a capable user complete a real task.
- **Reference** pages provide neutral, exact facts for consultation.
- **Explanation** pages provide context, relationships, and rationale.

Public pages belong under `documentation/tutorials/`, `documentation/how-to/`, `documentation/reference/`, or `documentation/explanation/`. Internal feature, architecture, diagnostic, release, and agent documentation remains excluded from the Jekyll site.

Preserve existing public permalinks when moving pages. Verify user-facing claims against the current UI, source, tests, or canonical internal feature documentation. Keep implementation-only details out of public pages, explain product terms at first use, and update navigation, related links, inventories, screenshots, and rendered-site checks when documentation changes. Use `Agent Session Manager` in full; do not use the acronym `ASM`.

## Skills

Skills are stored in `.agents/skills/`. Load them when working on relevant features.

- `swiftui-macos-form-alignment` — SwiftUI macOS Form alignment quirks, background control, and VStack-based alternative
- `swiftui-documentation` — SwiftUI official doc index; **load before implementing any SwiftUI feature**, views, modifiers, state management, data flow, or AppKit bridging — do not guess at behavior.
- `appkit-documentation` — AppKit official doc index; **load before implementing any AppKit feature**, NSView, NSWindow, NSEvent handling, NSColor, NSWorkspace, or AppKit bridging — do not guess at behavior.
- `claude-documentation` — Claude Code official doc index; **load before implementing any Claude Code feature**, hooks, or settings integration — do not guess at behavior.
- `cursor-documentation` — Cursor official doc index; **load before implementing any Cursor feature**, CLI integration, rules, skills, MCP, or worktrees — do not guess at behavior.
- `gh-documentation` — GitHub CLI official doc index; **load before implementing any GitHub CLI feature**, PR/issue automation, API scripting, or any gh CLI behavior — do not guess at behavior.
- `codex-documentation` — Codex official doc index; **load before implementing any Codex feature**, CLI integration, hooks, config, or AGENTS.md support.
- `usernotifications-documentation` — UserNotifications official doc index; **load before implementing any notification feature**, requesting authorization, scheduling local notifications, handling notification actions, or any UserNotifications framework behavior — do not guess at behavior.
- `swifterm-documentation` — SwiftTerm official doc index; **load before working with SwiftTerm**, terminal emulation, terminal views, process lifecycle, delegate callbacks, GPU rendering, pseudo-terminals, or any SwiftTerm-specific behavior. Any project that uses or interacts with SwiftTerm should load this skill.
- `sqlite-documentation` — SQLite official doc index; **load before working with SQLite**, the C/C++ API, `import SQLite3`, prepared statements, binding, query execution, result codes, or any SQLite-specific behavior. Any project that uses or interacts with SQLite should load this skill.
- `git-worktree-documentation` — Git worktree official doc index; **load before implementing any git worktree feature**, worktree creation, listing, removal, locking, pruning, repair, or any git worktree CLI behavior — do not guess at behavior.
- `opentelemetry-swift-documentation` — OpenTelemetry Swift official doc index; **load before implementing any OpenTelemetry feature**, tracing, metrics, logging, instrumentation, exporters, or context propagation — do not guess at behavior.
- `agents-documentation` — AGENTS.md and Agent Skills official doc index; **load before implementing any AGENTS.md or Agent Skills feature**, SKILL.md format, frontmatter fields, skill creation, client integration, skills-ref validation, or the agentskills.io spec — do not guess at behavior.
- `diataxis-documentation` — classify, write, review, and reorganize public and internal documentation using the Diátaxis framework.
- `fixed-width-prose` — prevent fixed-width prose in Markdown files and pull-request descriptions, while providing strong commit-body guidance.
- `instrument-runtime-telemetry` — mandatory telemetry checklist; **load before implementing any runtime behavior feature, fix, or refactor** so span context, failure coverage, bounded output, tests, and catalogs stay complete.
- `agent-data-access` — read-only incident diagnosis workflow for current prod/dev sessions, per-pane traces, invariants, global spans, and separately reported legacy files.
- `dictionary` — glossary of project domain terms (Tab, Pane, Worktree, Profile, Status line, Chip, CLI options, Tracing, Terminal Purity, …); load when you need a definition

## Feature Skills

Each feature has a skill that loads its documentation on demand. Do NOT auto-load these — only load the one relevant to the feature you are currently working on.

- terminal-scrollback: `feature-terminal-scrollback`
- notifications: `feature-notifications`
- tab-loading-indicator: `feature-tab-loading-indicator`
- profiles: `feature-profiles`
- dev-build: `feature-dev-build`
- profile-ordering: `feature-profile-ordering`
- session-names: `feature-session-names`
- default-branch: `feature-default-branch`
- observability-dashboard: `feature-observability-dashboard`
- worktree-cleanup: `feature-worktree-cleanup`
- panes: `feature-panes`
- section-resizing: `feature-section-resizing`
- focus-pane: `feature-focus-pane`
- codex-cli: `feature-codex-cli`
- continue-on-restart: `feature-continue-on-restart`
- opencode-cli: `feature-opencode-cli`
- tab-pane-reordering: `feature-tab-pane-reordering`
- pr-tracking: `feature-pr-tracking`
- sticky-notifications: `feature-sticky-notifications`
- cursor-cli: `feature-cursor-cli`
- pr-merged-notifications: `feature-pr-merged-notifications`
- tracing: `feature-tracing`
- invariants: `feature-invariants`
- debug-logging: `feature-debug-logging`
- terminal-rendering: `feature-terminal-rendering`
- worktree-creation: `feature-worktree-creation`
- agent-harness-matrix: `feature-agent-harness-matrix`
- agentic-control: `feature-agentic-control`
- distribution: `feature-distribution`
- update-reminder: `feature-update-reminder`
- recursive-development: `feature-recursive-development`

**Workflow reminders:**
1. **When working on a feature** — load the corresponding skill (e.g. `feature-panes`) before starting.
2. **After updating a feature doc** (`documentation/features/<name>.md`) — verify the skill still points to it correctly (no action needed if skill uses `!`cat``, but confirm the doc path hasn't changed).
3. **When creating a new feature** — create all three artifacts in order: a. `documentation/features/<name>.md` — the feature guide b. `.agents/skills/feature-<name>/SKILL.md` — the skill (use `!`cat`` to reference the doc) c. Add a line to the `## Feature Skills` section of `AGENTS.md`

## Key Behaviors to Know

- Processes are started lazily inside `TerminalRepresentable` once the frame is laid out — don't move process start earlier.
- Session persistence triggers on tab count or active-tab changes; settings persistence triggers on settings changes.
- The app does not enable the App Sandbox. It is distributed via Developer ID + notarization, not the Mac App Store or TestFlight for macOS.
- `URL(string:)` is used in session restore — known issue with paths containing spaces; prefer `URL(filePath:)` in new code.
