# Tasks

## 1. Geometry and compatible resize preferences

- [ ] 1.1 Extend the grid geometry model with preferred weights, minimum-aware effective track sizing, adjacent-pair adjustment, and changed-axis reconciliation; verify unit tests cover conservation, fixed third tracks, partial grids, bounds, normalization, and shrink/enlarge restoration.
- [ ] 1.2 Add global layout settings, per-tab grid preferences, and per-pane optional status height with independent decoding and save/restore support; verify old-session defaults, invalid scalar/axis isolation, partial pane restore, and round-trip persistence in unit tests.
- [ ] 1.3 Add the new settings file to isolated Dev UI cleanup and both Makefile reset lists; verify cleanup inventories contain `layout-settings.json` and no production-targeted test invocation is introduced.
- [ ] 1.4 Create the internal section-resizing feature guide, its referencing feature skill, and the AGENTS.md feature entry in the required order; verify paths resolve and the documented ownership and allocation rules match this design and unit tests.

## 2. Shared divider interactions and global sections

- [ ] 2.1 Implement the reusable native resize handle with cursor/hit-region behavior, accessible splitter values/actions, arrow-key steps, clickable size actions, reset, and cancellation; verify unit tests for input-to-allocation logic and real Dev UI tests for pointer, keyboard, menu, and Escape interaction.
- [ ] 2.2 Replace root tab-bar/sidebar fixed dimensions with preferred and effective geometry, including both sidebar sides, visibility transitions, empty states, and bounded growth; verify Dev UI tests observe equal exchanged space and retained preferred sizes after hide/show and window resizing.
- [ ] 2.3 Add Settings → Panes → Layout controls and global reset, restoring and saving the new layout settings; verify unit tests for global reset scope and real Dev UI tests for settings edits, reset, and relaunch persistence.
- [ ] 2.4 Instrument resize completion, cancellation, reset, and persistence failure without per-pointer-move logging; verify bounded attributes, required scope context, failure results, and telemetry tests, and update the internal feature guide and tracing catalog for these interactions.
- [ ] 2.5 Add a user-facing resize how-to guide and update the relevant navigation and links; verify visible labels against the implemented root/settings UI and run rendered documentation/link checks for this group's content.

## 3. Pane grid and status viewports

- [ ] 3.1 Replace equal lazy-grid sizing with the stable custom layout and shared row/column divider overlay; verify unit and real Dev UI tests cover all existing grid shapes, empty cells, unchanged third tracks, minimum limits, divider intersection priority, and exceptional overflow reachability.
- [ ] 3.2 Integrate topology changes, reorder, focus transitions, cancellation, and Reset Pane Sizes with per-tab preferences; verify unit tests and real Dev UI flows cover unchanged-axis preservation, changed-axis reset, positional weights, focus restoration, and interrupted-preview rollback.
- [ ] 3.3 Add independently resizable scrollable status viewports, content-based default sizing, hidden-handle behavior, and Reset Status Height; verify unit and real Dev UI tests cover configured multi-row content, overflow scrolling, absent content, per-pane/profile isolation, and focused edits returning to the grid.
- [ ] 3.4 Preserve terminal controller/view identity, input focus, active-pane selection, and scrollback through all layout changes; verify a real shell retains its PID and scrollback marker, reports changed `stty size`, and accepts subsequent input, and verify a real supported harness remains interactive after resizing.
- [ ] 3.5 Complete pane/status resize telemetry and update feature, focus, reordering, and user-facing resize documentation with real-flow evidence; verify pane/tab context in telemetry tests, documentation links, and actual screenshots without injected app state.

## 4. Integrated layout evidence

- [ ] 4.1 Exercise resize, reset, focus, reordering, sidebar movement, and relaunch together across two tabs at the supported minimum window size and a larger size; record observed dimensions and real before/after screenshots demonstrating usable controls, terminal continuity, and persisted scope isolation.
- [ ] 4.2 Validate the proposed numerical bounds and grab regions with the integrated Dev flows, including the densest existing grid, long labels, and multi-row status content; retain the chosen values or update design and regression expectations together with evidence while preserving the specification's allocation contract.
- [ ] 4.3 Run the complete applicable build, unit, format, lint, policy, documentation, and isolated Dev UI checks and correct any regressions; record exact commands and results with links to genuine UI evidence before the change's eventual archive transition.
