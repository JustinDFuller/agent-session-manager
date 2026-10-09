## Purpose

Native pane interactions present current data on first opening, deliver real terminal attention, and keep auxiliary dashboards under explicit user control.

## ADDED Requirements

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
