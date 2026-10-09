# Observability Dashboard

Agent Session Manager includes an in-app trace dashboard that visualizes OpenTelemetry spans as a waterfall timeline, organized by tab and pane.

## Enabling

1. Open **Settings → Debug**.
2. Toggle on **Enable Debug Mode**.

Spans are written to per-pane JSONL files under `traces/` immediately. No output target selection is required — file output is the only mode.

## Opening the Dashboard

Press **⌘⇧D** or use the menu **Window → Open Trace Dashboard**.

The Trace Dashboard opens as a separate auxiliary macOS window with the standard traffic-light controls. Close it with the window close button or **⌘W**; that dismissal does not target the active pane in the main window.

Both diagnostic dashboards use explicitly created AppKit windows with saved-window restoration disabled. Open a dashboard explicitly each time it is needed. Closing and reopening a dashboard reuses its window during the current app session.

## Layout

The dashboard uses a fixed-width custom sidebar plus a detail column so the screenshot baseline does not drift with SDK sidebar materials.

### Sidebar: Tab → Pane tree

The left column is 220 points wide, uses the pinned macOS 26 dark sidebar color, and lists discovered pane files grouped by tab. Each entry represents one per-pane JSONL file written under `traces/`. Click **↺** (refresh button) to re-scan the `traces/` directory for new files. The selected pane row is highlighted in the pinned blue selection color.

### Trace list

Selecting a pane loads its spans and shows a list of traces (grouped by trace ID). The visible dashboard title is rendered in the detail column header rather than using the centered macOS window title. Each row shows:

| Column | Description |
|--------|-------------|
| Name | Root span name for the trace |
| Spans | Number of spans in this trace |
| Duration | End-to-end duration |
| Time | Wall-clock start time |

Click a row to drill into the waterfall view.

### Waterfall view

Each row represents one span. The bar's horizontal position and width show when the span started and how long it lasted relative to the trace's time window. Zero-duration spans (instant events) appear as small circles.

Span bars are color-coded by name prefix:

| Prefix | Color |
|--------|-------|
| `terminal.*` | Accent (blue/purple) |
| `pane.*` | Blue |
| `tab.*` | Green |
| `pr.*` | Orange |
| `statusline.*` | Purple |
| `session.*` | Teal |
| other | Gray |

Click any row to select it and show its details in the panel below.

## Detail Panel

Shows the span name, trace ID, span ID, start time, duration, and all attributes as key=value rows. Text is selectable for copying.

## Filter Field

Type in the **Filter** field in the trace list toolbar to narrow traces by root span name. The span count badge updates as you type.

## Refresh

Click the **↺** button in the sidebar toolbar to rescan `traces/` for new pane files written since the dashboard was opened. Existing pane selections are preserved.
