# Spec Delta

## Purpose

Let people allocate space between existing sections of Agent Session Manager while preserving usable terminals, familiar grid placement, and recoverable saved layouts.

## ADDED Requirements

### Requirement: Section boundaries exchange space

The app SHALL support dragging below the tab bar, beside a visible notification sidebar, and above an available pane status line. Each movement SHALL give one adjoining region exactly the space taken from the other, subject to limits. Resizing a status line SHALL leave the pane's outer bounds unchanged. Sidebar resizing SHALL behave consistently on either side of the window.

#### Scenario: Increase tab-bar height

- **WHEN** a user drags the tab-bar boundary down by an allowed distance
- **THEN** the bar grows by that distance and the body loses the same height

#### Scenario: Resize a right-hand sidebar

- **WHEN** a user moves the boundary of a right-hand notification sidebar left
- **THEN** the sidebar grows and the pane area shrinks by the same width

#### Scenario: Enlarge a status viewport

- **WHEN** a user drags a pane's status boundary upward
- **THEN** its status viewport grows by the height taken from its terminal and sibling panes keep their outer sizes

### Requirement: Pane dividers adjust adjacent shared tracks

The app SHALL retain its automatic grid shapes and empty cells. A vertical divider SHALL adjust its two adjacent column widths across every row; a horizontal divider SHALL adjust its two adjacent row heights across every column. Other tracks SHALL retain their sizes during that adjustment. A single-track axis SHALL have no internal divider. Dragging SHALL NOT change pane order or create additional empty space.

#### Scenario: Resize the first boundary of three columns

- **WHEN** a user moves the divider between columns one and two right by an allowed distance
- **THEN** column one gains that width, column two loses it, and column three retains its width

#### Scenario: Resize a partially occupied grid

- **WHEN** a user resizes a column in a three-pane two-by-two grid
- **THEN** both rows use the new column widths and the existing fourth empty cell remains in its grid position

#### Scenario: Resize rows

- **WHEN** a user moves a horizontal divider down by an allowed distance
- **THEN** the upper row gains that height, the lower row loses it, and every column uses the resulting row heights

### Requirement: Active-pane shortcuts move dividers spatially

Directional resize commands SHALL move the active pane's adjoining grid divider on the requested side in that direction. At an outside edge, they SHALL move the opposite adjoining divider in the same direction. They SHALL use the same adjacent-track exchange and limits as dragging, including shared rows, columns, and empty cells. A blocked divider SHALL NOT fall back to another divider.

#### Scenario: Shrink the leftmost pane

- **WHEN** the active pane is in the leftmost column and the user invokes Resize Left
- **THEN** its right-hand divider moves left, shrinking its column and giving the adjacent column the same width

#### Scenario: Grow the rightmost pane leftward

- **WHEN** the active pane is in the rightmost column and the user invokes Resize Left
- **THEN** its left-hand divider moves left, growing its column by the width taken from the adjacent column

#### Scenario: Grow a middle pane toward either side

- **WHEN** the active pane is in a middle column and the user invokes Resize Left or Resize Right
- **THEN** the divider on that side moves in the requested direction, growing the active column at that neighbor's expense and leaving the other divider unchanged

#### Scenario: Give space back from a middle column

- **WHEN** the user activates the pane immediately left of a middle column and invokes Resize Right
- **THEN** the active column grows by the width taken from the middle column

#### Scenario: Shrink the top row upward

- **WHEN** the active pane is in the top row and the user invokes Resize Up
- **THEN** its lower divider moves up, shrinking the top row and giving the row below the same height

#### Scenario: Grow the top row downward

- **WHEN** the active pane is in the top row and the user invokes Resize Down
- **THEN** its lower divider moves down, growing the top row by the height taken from the row below

#### Scenario: Grow a middle row toward either neighbor

- **WHEN** the active pane is in a middle row and the user invokes Resize Up or Resize Down
- **THEN** the divider on that side moves in the requested direction, growing the active row at that neighbor's expense and leaving the other divider unchanged

#### Scenario: Shrink the bottom row downward

- **WHEN** the active pane is in the bottom row and the user invokes Resize Down
- **THEN** its upper divider moves down, shrinking the bottom row and giving the row above the same height

#### Scenario: Exchange space with an empty cell's track

- **WHEN** a directional command selects a divider beside an empty cell in a partially occupied grid
- **THEN** it adjusts the same shared tracks as dragging and the empty cell remains in its existing position

#### Scenario: Stop without changing a different boundary

- **WHEN** a directional command selects a divider whose adjacent track has reached its minimum
- **THEN** movement stops at the limit, the opposite divider remains unchanged, and no section collapses

### Requirement: Pane-size shortcuts retain terminal focus

Enabled pane-size shortcuts SHALL operate only while the active terminal has input focus in the main window. They SHALL retain that focus, highlight the selected divider during adjustment, and consume the recognized key event without sending terminal input, even when movement is blocked. A single-track axis and maximized Focus Pane mode SHALL leave layout unchanged. Normal key repeat SHALL repeat the same command under the same limits.

#### Scenario: Resize without selecting a handle

- **WHEN** the active terminal has input focus and the user invokes an enabled pane-size shortcut
- **THEN** the appropriate divider is highlighted and adjusted without requiring handle focus, and subsequent terminal input reaches the same running process

#### Scenario: Hold a resize shortcut

- **WHEN** the user holds an enabled resize shortcut while the active terminal has input focus
- **THEN** repeated key events repeat its adjustment until released or limited, without entering characters into the terminal

#### Scenario: Preserve a settings or sheet interaction

- **WHEN** a settings control, sheet, or another window has input focus and the user presses a configured resize combination
- **THEN** the pane layout remains unchanged and the resize handler leaves the event available to that focused interface

#### Scenario: Resize an axis with one track

- **WHEN** the active terminal has input focus and the user invokes a resize shortcut on an axis with one track
- **THEN** layout remains unchanged and the recognized shortcut sends no terminal input

#### Scenario: Resize while maximized

- **WHEN** the terminal in maximized Focus Pane mode has input focus and the user invokes a pane-size shortcut
- **THEN** its full-size layout and saved grid proportions remain unchanged and the recognized shortcut sends no terminal input

### Requirement: Pane-size shortcuts are configurable

Settings → Shortcuts SHALL provide editable normal and larger-step bindings for all four resize directions through key capture supporting arrows and modifiers. Each enabled binding SHALL require Command and SHALL be disableable. Normal commands SHALL move four points; larger-step commands SHALL move sixteen points. Defaults SHALL use Command–Option–arrows and Command–Option–Shift–arrows respectively. Assignment conflicts with another enabled app shortcut SHALL be rejected.

#### Scenario: Use the default increments

- **WHEN** the user invokes default Command–Option–Right and then Command–Option–Shift–Right with sufficient space available
- **THEN** the selected divider moves right by four points and then sixteen points

#### Scenario: Record a custom combination

- **WHEN** the user records a valid nonconflicting Command-modified combination for a resize action
- **THEN** that combination invokes the chosen direction and increment, and its replaced combination no longer invokes that action

#### Scenario: Reject a conflicting assignment

- **WHEN** the user tries to assign a combination already used by another enabled app shortcut
- **THEN** the interface explains the conflict and retains both existing assignments

#### Scenario: Reject a combination without Command

- **WHEN** the user records a resize combination without Command
- **THEN** the interface explains the modifier requirement and retains the existing binding

#### Scenario: Disable a binding

- **WHEN** the user disables a resize binding
- **THEN** its former combination no longer invokes resizing and the resize handler leaves that combination available to the terminal

### Requirement: Resize bindings persist independently of dimensions

Resize bindings SHALL be saved globally across relaunches, including disabled bindings. Missing or invalid saved bindings SHALL use defaults at the affected binding without discarding valid siblings, dimensions, or sessions. A restored binding that conflicts with another enabled app shortcut SHALL be disabled with an explanation rather than overriding that shortcut. Layout reset actions SHALL NOT reset shortcut choices.

#### Scenario: Relaunch with custom bindings

- **WHEN** the app relaunches after a user customizes one resize binding and disables another
- **THEN** those choices return for every tab while the other bindings and saved dimensions retain their values

#### Scenario: Restore an older or partly invalid shortcut configuration

- **WHEN** saved resize bindings are absent or one saved binding is invalid
- **THEN** only missing or invalid bindings use defaults and valid sibling bindings, dimensions, and sessions remain available

#### Scenario: Restore a conflicting resize binding

- **WHEN** a restored resize binding conflicts with another enabled app shortcut
- **THEN** the conflicting resize binding is disabled with an explanation and the other shortcut remains available

#### Scenario: Reset dimensions after customizing shortcuts

- **WHEN** a user resets global section sizes, tab grid proportions, or a pane's status height
- **THEN** the relevant dimensions reset while custom and disabled resize bindings remain unchanged

### Requirement: Resizing preserves usable bounds

The app SHALL constrain resizing so visible controls and resize boundaries remain reachable and each terminal retains a usable positive area. Reaching a limit SHALL stop the selected divider without pushing unrelated dividers or collapsing sections. Reduced available space SHALL constrain displayed sizes without overwriting saved preferences; increasing space SHALL restore the preferred allocation when it fits.

#### Scenario: Reach an adjacent pane minimum

- **WHEN** a user continues dragging after an adjacent pane reaches its minimum size
- **THEN** the boundary stops at that limit and unrelated tracks remain unchanged

#### Scenario: Shrink and enlarge the window

- **WHEN** a user shrinks the window so a preferred allocation cannot fit and later enlarges it
- **THEN** the smaller layout preserves reachable controls and usable terminals, and the preferred allocation returns when space permits

### Requirement: Resizing has recognizable feedback and alternatives

Resize boundaries SHALL present an axis-appropriate pointer and visible hover or keyboard-focus feedback, and update adjoining sizes during dragging. Each boundary SHALL expose an accessible name, orientation, current value, and adjustment actions. Keyboard adjustment and clickable increase/decrease actions SHALL apply the same limits and redistribution as dragging. Terminal content and reorder handles SHALL retain their existing interactions.

#### Scenario: Adjust without dragging

- **WHEN** a user adjusts a selected divider through a keyboard or clickable size action
- **THEN** the same adjoining regions resize under the same limits and the updated value is available to assistive technology

#### Scenario: Select terminal text beside a divider

- **WHEN** a user selects text within the terminal content area
- **THEN** the terminal receives the interaction and no resize starts

### Requirement: Status-line height controls a viewport

Each pane's status-line height SHALL control a viewport with its existing fonts, configured rows, item order, and alignment. Overflow SHALL remain reachable by scrolling rather than automatic item reflow or font scaling. An unset height SHALL use content-based sizing within available space. A pane without displayed status content SHALL have no status resize handle; temporarily unavailable content SHALL NOT erase its saved height.

#### Scenario: Reduce a multi-row status line

- **WHEN** a user reduces the height below that required for its configured status rows
- **THEN** the rows retain their order and typography and hidden content is reachable by scrolling within the status viewport

#### Scenario: Restore status content

- **WHEN** a pane's status content becomes available again after being temporarily absent
- **THEN** the viewport uses that pane's saved height subject to current space limits

### Requirement: Dimensions persist at their owning scope

The app SHALL remember tab-bar height and sidebar width globally, grid proportions per tab, and status-line height per pane across relaunches. Changing a pane status height SHALL NOT change other panes' saved heights or their profile configuration. Missing or invalid saved dimensions SHALL use defaults at the affected scope without preventing session restoration. Sidebar visibility or side changes SHALL preserve its preferred width.

#### Scenario: Relaunch a customized layout

- **WHEN** the app relaunches after a user customizes two tabs and their panes
- **THEN** global dimensions and each restored tab's grid proportions and pane's status height return within available space

#### Scenario: Restore older settings

- **WHEN** the app restores a session that contains no custom dimensions
- **THEN** it uses a 44-point tab bar, a 240-point sidebar, equal grid tracks, and content-based status heights

#### Scenario: Restore an invalid dimension

- **WHEN** one saved resize preference is invalid
- **THEN** its affected dimension uses the default and valid sibling preferences and restorable sessions remain available

#### Scenario: Hide or move the sidebar

- **WHEN** a user hides the sidebar and later reveals it or changes its side
- **THEN** it returns at its saved preferred width subject to available space

### Requirement: Layout transitions preserve applicable preferences

Pane reordering SHALL keep proportions attached to grid positions while each pane retains its status height. Adding, removing, or restoring panes SHALL preserve an axis's proportions when its track count is unchanged and reset only changed axes to equal proportions. Entering focus mode SHALL hide grid dividers; leaving it SHALL restore the saved grid allocation. Focused status resizing SHALL use the same pane preference.

#### Scenario: Add a fourth pane

- **WHEN** a user adds a fourth pane to a customized three-pane two-by-two grid
- **THEN** row and column proportions remain unchanged

#### Scenario: Add a fifth pane

- **WHEN** a user adds a fifth pane to a customized two-by-two grid
- **THEN** the new three-column axis uses equal proportions and the two-row proportions remain unchanged

#### Scenario: Reorder panes

- **WHEN** a user moves a pane into another grid position
- **THEN** grid track proportions stay in their positions and the moved pane carries its status-height preference

#### Scenario: Leave focus mode

- **WHEN** a user returns from a focused pane to the grid
- **THEN** the previous grid proportions return and no terminal process restarts because of the layout transition

### Requirement: Users can recover default allocations

The app SHALL provide explicit reset actions for global section sizes, the current tab's grid proportions, and an individual pane's status height. Resetting SHALL restore that scope's default allocation and persist the result without changing other tabs, panes, profile content, or section visibility. Reset and size controls SHALL be reachable without relying on a drag gesture.

#### Scenario: Reset current grid

- **WHEN** a user chooses Reset Pane Sizes for the current tab
- **THEN** its rows and columns become equal, other tabs remain unchanged, and the result survives relaunch

#### Scenario: Reset a pane's status height

- **WHEN** a user resets one status viewport's height
- **THEN** it returns to content-based sizing while other panes keep their saved heights

### Requirement: Resizing preserves terminal continuity

Resizing SHALL preserve running terminal processes, active-pane selection, and retained scrollback. Pointer resizing SHALL restore prior terminal input focus on completion. Terminal rows and columns SHALL follow the actual viewport dimensions during resizing. Resize gestures SHALL NOT send terminal input or app setup output. Interrupting a resize by changing tabs or layout SHALL leave the last committed preference intact.

#### Scenario: Resize a running terminal

- **WHEN** a user resizes a pane containing a running process and then enters terminal input
- **THEN** the same process receives input using its resized viewport, the pane remains active, and retained scrollback remains available

#### Scenario: Interrupt a resize

- **WHEN** a user changes tabs or pane topology before a resize gesture completes
- **THEN** the unfinished resize is canceled and the last committed dimensions remain saved

#### Scenario: Save keyboard-adjusted proportions

- **WHEN** a user resizes the active pane through a shortcut and later switches tabs or relaunches
- **THEN** the adjusted proportions remain saved for that tab under the same rules as a completed drag
