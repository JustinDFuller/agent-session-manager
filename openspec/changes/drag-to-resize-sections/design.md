# Design

## Context

See [proposal.md](proposal.md) for motivation and [the section-resizing delta](specs/section-resizing/spec.md) for the behavior contract. `ContentView` in `App.swift` fixes the tab bar at 44 points, `NotificationSidebarView` fixes its width at 240 points, and `PaneGridView` uses equal `LazyVGrid` columns and equal computed row heights. `GridLayout` currently holds dimensions and an empty-cell count. `StatusLineView` renders explicitly configured rows; `PaneView` resolves those rows through global or profile configuration. Session persistence has no resize preferences.

Focus mode currently changes the pane container and hides sibling panes from input and accessibility. Pane header dragging reorders panes and explicitly saves the session. Terminal views belong to their controllers and begin processes only after a stable nonzero frame. Layout work must preserve those identities and the lazy-start boundary.

The main-window keyboard monitor currently routes existing app shortcuts, while Settings → Shortcuts edits single keys with fixed modifiers. The new resize bindings need arrow/modifier capture and conflict checking, but existing non-resize editors and their stored values remain in place.

## Goals / Non-Goals

**Goals:** Use one deterministic geometry model for drawing and every input method; keep saved preferences separate from temporary constrained geometry; add independently decodable state at the existing global, tab, and pane ownership boundaries.

**Non-Goals:** No terminal engine replacement, implicit process start, shared status-height edits through profiles, new layout animation, or merge-gate changes. The research informs interaction choices; concrete numerical limits below are proposed app defaults to validate in real Dev flows, not universal design standards.

## Decisions

### 1. Shared grid geometry with stable pane identity

Extend `GridLayout` with pure, testable track sizing and boundary adjustment. Use a custom SwiftUI `Layout` for the pane container, with one stable `ForEach` keyed by pane ID across grid and focus mode. Place panes in row-major order; preserve four-point gutters and outer padding and all existing empty cells. Focused layout places the selected pane across the available body and positions siblings offscreen, clipped and excluded from accessibility and hit testing. Dividers are a separate overlay, hidden while focused. Reordering changes pane order without replacing controllers or their terminal views.

A nested split tree was considered but changes the product's automatic grid and permits divergent row widths. Independent fixed pane frames were rejected because they make shared-boundary conservation and focus identity harder to maintain. SwiftUI's [Layout protocol](https://developer.apple.com/documentation/swiftui/layout) supplies sizing and placement without replacing the child content.

### 2. Boundary movement conserves the adjacent pair

At pointer-down, snapshot the two adjacent effective sizes, container bounds, active tab/pane IDs, topology, and committed preference. For a boundary between regions A and B, positive movement increases A and decreases B. With minimum sizes mA and mB, clamp movement to `[mA - A, B - mB]`; incorporate the corresponding maximum constraints for global or status sections. Only those two sizes change. Normalize the resulting grid sizes back into weights at commit. Apply the same operation to pointer, keyboard, accessibility, and menu input.

The root boundaries exchange space between the tab bar and complete body, or sidebar and complete grid. Moving the tab boundary down increases the bar. Moving a left sidebar boundary right increases the sidebar; moving a right sidebar boundary left increases it. Moving a status boundary up increases that pane's status viewport. Rows and columns use the physical upper/left track as A. Three-column resizing does not push the second boundary when column two reaches its minimum.

For window resizing or a sidebar visibility transition, scale preferred grid weights to the available track extent after subtracting padding and gutters. Clamp tracks below their minimum, freeze them, and distribute the remaining extent proportionally among unfrozen tracks until all fit; assign floating-point remainder to the final unfrozen track. Do not write these effective sizes back as preferences. This preserves feasible proportions and restores the preferred proportions when constraints relax.

### 3. Explicit bounds and content sizing

| Region | Preferred default | Proposed permitted allocation |
|---|---|---|
| Tab bar | 44 points | Minimum is the greater of 44 points and measured existing control height; maximum is the greater of that minimum and 96 points, further limited by the body minimum |
| Notification sidebar | 240 points | 160–480 points, further limited by the current grid's minimum width |
| Pane columns | Equal normalized weights | Each column at least 160 points |
| Terminal body | Remaining pane space | At least 64 points high |
| Status viewport | Content-based when unset | Explicit preferred height 24–256 points; displayed height further limited by pane space |

Row minimum is the largest occupied pane's measured header height, divider thicknesses, 64-point terminal minimum, and 24-point status minimum when status content is present. Empty cells impose no additional row minimum. Resolve root limits against the actual active topology; with no panes, reserve a 160-by-64-point body for the empty state. With focus mode active, use one pane's minimum rather than the hidden grid's minimum. The existing 900-by-600-point minimum main window remains the baseline.

Clamp displayed status height to available space after reserving its header, boundaries, and terminal minimum; do not force a large stored status height into a smaller row. If exceptional measured content makes all minima infeasible even at the supported window minimum, preserve the minimum-sized grid in an overflow scroll container rather than clipping controls or emitting negative sizes; outer bar/sidebar growth is disabled until space is available. The overflow path must retain existing terminal identities and produce no new automatic grid shapes.

Tab labels keep their existing font sizes, single-line titles, and directory subtitle; extra height adds padding, with no scaling or tab wrapping. Status content retains explicit rows, alignment, fonts, and order inside a viewport that supports scrolling on overflowing axes. Use natural row content widths when horizontal space is insufficient so text remains reachable. Content-based status height remains intrinsic when it fits and becomes scrollable when constrained. Hide the status divider if no supported configured rows are displayed, even if a monitor exists; retain the preference for future content.

### 4. Native divider input and accessible alternatives

Create one reusable AppKit-backed resize handle bridged into SwiftUI. Use a one-point visible separator with an eight-point effective grab region, native `resizeLeftRight` or `resizeUpDown` cursor, and immediate accent hover/focus feedback. Expand the grab region into pane borders only, avoiding terminal content, header controls, and reorder labels. At row/column intersections the horizontal row handle takes precedence; the current input sequence locks its axis. This follows Apple's [thin-divider guidance](https://developer.apple.com/design/human-interface-guidelines/split-views) and [separate effective hit region](https://developer.apple.com/documentation/appkit/nssplitviewdelegate/splitview(_:effectiveRect:forDrawnRect:ofDividerAt:)).

Expose the native accessibility splitter role, descriptive label, orientation, current value, bounds, and increment/decrement actions. Focused handles accept axis arrow keys in four-point steps and Shift-arrow in sixteen-point steps. Escape cancels an unfinished drag. A divider context menu exposes Increase Size, Decrease Size, and Reset Size; actions name the affected section or upper/left track to avoid ambiguity. Context-menu increments use sixteen points. Double-clicking a grid divider equalizes its adjacent pair; double-clicking a section divider resets that section's preference. These local handle actions remain available for every section; terminal-focused directional shortcuts below apply only to pane grid dimensions.

The [W3C splitter pattern](https://www.w3.org/WAI/ARIA/apg/patterns/windowsplitter/) is useful keyboard guidance, adapted to native accessibility rather than web roles. Its optional collapse behavior is excluded. [Dragging alternatives guidance](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements) motivates clickable controls in addition to keyboard support; keyboard equivalence alone does not provide a pointer alternative.

### 5. Configurable active-pane resizing

Resolve the active pane's row and column from its current row-major position. For Left or Up, select the preceding track boundary when one exists; otherwise select the following boundary. For Right or Down, select the following boundary when one exists; otherwise select the preceding boundary. Move the selected boundary in the requested physical direction using the same adjacent-pair geometry as dragging. If that axis has one track, return an unchanged result. A selected boundary at its limit stays selected; never switch to the opposite boundary to find more space. Shared tracks include empty cells. This spatial model lets a middle pane grow toward either neighbor; giving its space back requires activating that neighbor and moving the same divider toward the middle pane.

| Action | Default binding | Boundary movement |
|---|---|---|
| Resize Left / Right / Up / Down | Command–Option plus the corresponding arrow | Four points in the action's direction |
| Resize Left / Right / Up / Down (Larger Step) | Command–Option–Shift plus the corresponding arrow | Sixteen points in the action's direction |

Treat these as eight independently editable actions, so Shift is part of the default larger-step binding rather than an implicit modifier applied to every custom shortcut. Add a Pane Resizing group under Settings → Shortcuts with key-capture controls and an explicit disable action for each binding. Capture supports arrow keys and single-key combinations with Command and optional Option, Control, or Shift. Escape cancels capture. Validate the complete combination, require Command, reject modifier-only input, and keep the previous binding with an inline explanation on invalid or conflicting input. Compare against other enabled resize bindings and existing app actions, including fixed tab-switching, menu shortcuts, and Copy/Paste. Existing non-resize editors keep their UI and storage while their assignment validation also rejects collisions with enabled resize bindings. Changes to a binding save immediately through global layout settings.

Route exact normalized key/modifier matches through the existing main-window event monitor only when the active pane's terminal owns first responder and no sheet or settings overlay is active. Recognize custom larger-step bindings directly rather than inferring them from Shift. Handle recognized resize events before generic app-command dispatch, including normal key repeat, and consume them even for a blocked boundary, a single-track axis, or maximized Focus Pane mode. Unmatched, disabled, and out-of-scope events remain available to their existing recipients. Do not change tab, pane, or first responder. Use immediate divider focus styling while an adjustment key is held; clear it on key release or a focus/layout transition without adding animation. Commit each successful key adjustment as a discrete shared-geometry operation and use the existing keyboard resize telemetry source.

Direct key combinations avoid capturing a terminal prefix sequence, and independent larger-step actions keep customized modifiers unambiguous. A replacement editor for every existing shortcut was rejected to preserve this change's resize scope. The shortcut recorder's settings focus must take precedence over resize routing, so recording a combination cannot move panes.

### 6. State ownership and compatibility

Add `LayoutSettings: Codable, Equatable` containing `tabBarHeight: Double = 44`, `notificationSidebarWidth: Double = 240`, and `PaneResizeShortcutBindings` for the eight resize actions to `AppSettings`. Each binding stores a normalized key and modifier combination; an explicit null binding means disabled. Save atomically to a new `layout-settings.json` through `SettingsPersistence` and restore from `App.swift`. Expose Tab Bar Height and Notification Sidebar Width steppers and Reset Section Sizes in Settings → Panes → Layout with stable accessibility identifiers. Saved dimension inputs use the same static preferred bounds as dragging; effective container constraints remain temporary. Reset Section Sizes resets only these two global values; no layout reset changes shortcut bindings.

Decode shortcut entries independently alongside dimensions. A missing or malformed entry uses that action's default; an explicit disabled entry stays disabled. After defaults and saved entries have resolved, check conflicts against existing app shortcuts and other resize bindings. Disable any conflicting resize bindings and explain the conflicts in Settings → Shortcuts; preserve existing non-resize shortcuts, valid unrelated resize bindings, dimensions, and sessions. For a conflict between resize actions, disable every involved resize binding rather than choosing a winner. Key capture and restored bindings use the same normalized combination validation. Older layout settings without bindings receive the eight defaults, and a code rollback ignores the added entries.

Add `PaneGridSizePreferences: Codable, Equatable` containing positive finite normalized `columnWeights` and `rowWeights` to `Tab` and an optional equivalent field to `PersistedTab`. Add `statusLineHeight: Double?` to `Pane` and `PersistedPane`; nil means content-based sizing. Explicit status-height edits never modify `StatusLineConfig` or a profile. Add Reset Pane Sizes to the pane-grid context menu and Reset Status Height to the pane context menu; each resets and saves only its owning scope. Stable divider identifiers use scope IDs and axis/boundary index, with human-readable accessible labels.

Decode each new value independently. Missing values use defaults. Invalid types, nonfinite/nonpositive weights, incompatible array lengths, and out-of-range dimensions reset only the affected scalar or axis; do not discard otherwise valid sessions or global dimensions. Store only the current axis weights, rather than remembering historical topologies. After actual panes have restored, including panes skipped because their directories are absent, reconcile each axis's track count against the resulting topology. Adding/removing a pane resets only changed axes. Pane reordering leaves weights alone; status height follows pane identity. Hiding, showing, or moving the sidebar preserves its preferred width. Focused pane status edits update the same per-pane height; hidden grid preferences stay unchanged.

### 7. Live preview, commit, cancellation, and telemetry

Keep pointer-move previews in transient view state and apply them to geometry continuously. Write settings or session state once at successful pointer-up, and once per successful discrete keyboard/menu/accessibility adjustment, including repeated active-pane shortcut events. Cancel previews on Escape, active-tab changes, topology changes, focus transitions, handle removal, or view disappearance; discard the preview rather than persisting it. Restore the previous terminal first responder after pointer interaction without changing the active pane. Deliberate keyboard focus stays on the handle for repeated local adjustments; Escape returns to the prior terminal and normal focus navigation remains available. Active-pane shortcuts retain terminal focus throughout and commit without a pending gesture; blocked commands do not save unchanged dimensions. Normal terminal frame changes must drive SwiftTerm's existing terminal/PTY resize path; real-process tests will verify this rather than introducing an extra resize engine.

Emit bounded `layout.resize.completed`, `layout.resize.canceled`, `layout.resize.reset`, and `layout.resize.persistence_failed` records using existing tracing. Include section, axis, input source, before/after allocation, and result. Grid events include tab identity; status events include pane and tab IDs and names. Active-pane shortcut completions also include active-pane identity, the selected boundary index, direction, and normal/larger-step action. Do not record pointer-move streams, raw shortcut-capture keystrokes, or terminal contents. Surface save failures as nonmodal app UI while keeping the in-memory layout usable; do not emit setup text in a terminal. Add telemetry tests and the trace catalog entries during implementation.

## Risks / Trade-offs

- Thin handles compete with nearby terminal selection → Limit expanded hit regions to gutters/borders and verify real selection, copy/paste, close buttons, and header reordering.
- Layout container changes can recreate terminal representables → Use a single stable pane hierarchy, preserve controller/view identity, and test process continuity across grid, focus, reorder, and resize flows.
- Saved sizes can exceed space after topology changes → Keep preferred and effective geometry separate, cap status viewports first, and apply deterministic minimum-aware allocation.
- A taller tab bar adds padding rather than more labels → Keep the modest upper bound, unchanged typography, and a readily available reset.
- New persisted files can leak state between Dev tests → Add `layout-settings.json` to the UI helper cleanup lists and both Makefile reset lists; test only isolated Dev state.
- Custom shortcuts can collide with app commands or leak into terminals → Require Command, validate assignments in both editors, match complete combinations only in terminal focus, and consume recognized blocked commands.
- Spatial resizing of a middle pane only grows it through its own directional commands → Explain how to activate a neighboring pane to reclaim space and highlight the moved shared divider during keyboard input.

## Migration Plan

This PR records the active change only. After review, implement the task groups as continuation layers sharing this change; gather real Dev UI and process evidence before the separate archive layer. Older installations restore defaults because all new persisted fields are optional or independently defaulted. A code rollback ignores the added dimensions and settings file; the existing session shape and harness invocation remain compatible. Do not archive unfinished tasks or change enforcement policy to make a proposal appear finalized.

## Validation

Unit tests cover adjacent-pair conservation, unaffected third tracks, bounds, normalized weights, temporary window constraints, invalid saved values, partial restore, scope resets, and changed-axis reconciliation. Add directional boundary selection across every edge and middle track, empty-cell handling, no opposite-boundary fallback at limits, exact shortcut matching, increments, repeats, assignment conflicts, disabled bindings, independent shortcut decoding, and focus/window routing. Real Dev UI tests cover every handle, both sidebar sides, a partial grid, multi-row scrolling, keyboard and pointer alternatives, reordering, focus restoration, persistence, and cancellation. Exercise default and recorded shortcut combinations through the real settings UI, larger steps, held-key repeat, invalid capture, conflicts in both editors, relaunch, settings/sheet exclusion, single-track axes, maximized focus, and unchanged shortcuts after layout resets. A real shell process reports its PID and `stty size` before and after dragging and keyboard resizing, retains a recognizable scrollback marker, and accepts further input with no resize keystrokes received; at least one real supported harness also remains interactive after both input methods. Capture actual before/after layouts and divider feedback at the 900-by-600-point window minimum and a larger window. These future checks validate proposed limits; this planning PR claims no runtime evidence.
