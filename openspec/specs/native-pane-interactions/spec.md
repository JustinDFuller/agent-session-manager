# native-pane-interactions Specification

## Purpose
Native pane interactions present current data on first opening, deliver real terminal attention, and keep auxiliary dashboards under explicit user control.

## Requirements

### Requirement: Pane sheets contain current selection on first opening

Pane settings, refresh confirmation, and custom scrollback sheets MUST contain the selected pane's current data on their first opening. Refresh configuration MUST open after the confirmation dismisses and MUST preserve the selected pane's settings. Canceling an editor MUST leave its setting unchanged, and reducing scrollback MUST retain the existing confirmation.

#### Scenario: First pane settings opening

- **WHEN** a user opens settings for an existing pane
- **THEN** the sheet contains that pane's settings immediately

#### Scenario: Refresh with new settings

- **WHEN** a user selects refresh with new settings from a pane's refresh confirmation
- **THEN** the confirmation dismisses and configuration opens with that pane's current scrollback override

#### Scenario: Custom scrollback after inheritance

- **WHEN** a user opens Custom scrollback after returning a pane to the global default
- **THEN** the editor shows the current effective finite limit and asks for confirmation before applying a reduction

#### Scenario: Cancel a scrollback draft

- **WHEN** a user cancels the scrollback editor
- **THEN** reopening it shows the last committed limit

### Requirement: Shell panes deliver normal terminal attention

A shell pane created through Open Shell Here MUST deliver terminal bell and OSC 777 attention through the app's normal notification handlers. The sidebar row MUST identify its shell pane, tab, and supplied reason. Terminal input MUST acknowledge that pane's notification.

#### Scenario: OSC 777 from a new shell pane

- **WHEN** a new shell pane emits an OSC 777 notification containing a permission reason
- **THEN** the sidebar displays that shell pane, tab, and permission reason

### Requirement: Icon choices use their complete visible row

A custom status-line icon option MUST select and dismiss when the user clicks anywhere in its visible row, including the trailing space. The saved icon and harness selection MUST persist through editing.

#### Scenario: Select an icon through the row's trailing space

- **WHEN** a user clicks the visible icon choice row's trailing area
- **THEN** that icon becomes selected and the selector dismisses

### Requirement: Dashboards open only through an explicit request

Trace and Invariant dashboards MUST remain closed on a fresh or restored app launch. The first explicit menu or settings request MUST create the selected dashboard using the configured data directory. Closing and reopening it within one process MUST reuse a single window and its initial data source, and a later launch MUST NOT restore it. Explicit opens MUST remain observable in the app's tracing and launch invariant.

#### Scenario: Launch after a dashboard was open

- **WHEN** the app relaunches after a prior process opened a dashboard
- **THEN** only the normal main window opens until the user requests a dashboard

#### Scenario: Reopen a dashboard in one process

- **WHEN** a user closes a requested dashboard and requests it again
- **THEN** one dashboard window is shown with its configured data source and an explicit-open trace

### Requirement: Terminal panes receive Control-Return

On macOS 26 and later, while a terminal pane has keyboard focus, pressing Control-Return MUST deliver that key to the program running in the pane and MUST NOT open the pane's context menu. When the program has enabled extended keyboard reporting, the key MUST be reported as Return with the Control modifier. Otherwise it MUST be delivered as an ordinary Return. This requirement does not apply on earlier versions of macOS.

#### Scenario: Program has enabled extended keyboard reporting

- **WHEN** the program in a focused pane has enabled extended keyboard reporting and the user presses Control-Return
- **THEN** the program receives Return with the Control modifier and no menu opens

#### Scenario: Program has not enabled extended keyboard reporting

- **WHEN** the program in a focused pane has not enabled extended keyboard reporting and the user presses Control-Return
- **THEN** the program receives an ordinary Return and no menu opens

#### Scenario: Claude Code sends a queued message

- **WHEN** Claude Code is running in a focused pane with a queued message and the user presses Control-Return
- **THEN** Claude Code sends the queued message immediately and no menu opens

### Requirement: Pane context menu remains available by pointer

A terminal pane's context menu MUST continue to open when the user right-clicks or Control-clicks the pane. Key combinations other than Control-Return MUST behave as they did before this requirement.

#### Scenario: Right-click opens the pane menu

- **WHEN** the user right-clicks a terminal pane
- **THEN** the pane's context menu opens with its existing items

#### Scenario: Other keys are unaffected

- **WHEN** the user presses Return, Shift-Return, or Control with any other key in a focused pane
- **THEN** the program receives the same input it received before this change
