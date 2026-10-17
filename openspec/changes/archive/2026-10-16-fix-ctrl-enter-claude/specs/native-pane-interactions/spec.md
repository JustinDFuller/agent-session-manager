# Spec Delta

## ADDED Requirements

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
