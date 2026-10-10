# Terminal Scrollback History

## What It Is

The terminal scrollback buffer stores lines of output that have scrolled off the visible area. A larger buffer lets you scroll back further to review earlier output — useful for long agent runs that produce extensive output.

## Default

The global default is **5,000 lines**. Panes inherit that value unless they have their own override.

## Limits and safety

Finite limits range from 100 to 50,000 lines. Values outside that range are clamped automatically.

SwiftTerm does not provide true unbounded history: `nil` disables history, and very large values eagerly allocate unsafe amounts of memory. Agent Session Manager therefore exposes **Unlimited (50,000-line cap)** as a distinct, persisted mode that resolves to a 50,000-line in-memory ring buffer per pane. The explicit cap prevents terminal output from growing memory without bound.

## How to Change

- **Global default:** Open **Settings → Panes → Terminal**, then choose a custom limit or the capped unlimited mode.
- **New pane:** Choose **Scrollback History** in the New Pane or Refresh Pane sheet. **Use Global Default** keeps the pane linked to the global setting.
- **Existing pane:** Right-click the pane and use **Scrollback History** for a preset, the capped mode, a custom value, or to resume using the global default.

Global settings and pane overrides persist across launches. Global changes take effect immediately in panes that inherit the default; overridden panes do not change.

## Runtime behavior

Reducing an existing pane's effective limit immediately and irreversibly drops its oldest retained lines, so the app asks for confirmation first. Increasing the limit cannot recover output that was already discarded. Full-screen terminal applications that use the alternate screen do not add their content to scrollback.

The custom pane editor opens with the selected pane’s effective limit as one presentation item. Editing occurs in sheet-local state, so the first presentation and later reopenings show the current limit and dismissing with Cancel leaves the pane unchanged.
