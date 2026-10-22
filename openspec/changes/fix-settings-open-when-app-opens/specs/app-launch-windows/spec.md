# Spec Delta

## Purpose

Defines which windows Agent Session Manager shows when it starts and restarts, so that opening the app always presents the main window alone and every other window appears only when the user asks for it.

## ADDED Requirements

### Requirement: Launch shows only the main window

When the app starts, it MUST show the main window and no other window. In particular, no Settings window, blank or populated, MUST appear at launch.

#### Scenario: Fresh launch

- **WHEN** a user opens the app with no prior state
- **THEN** exactly one window is visible, the main window, and no window titled with "Settings" exists

#### Scenario: Launch while another app window was open at quit

- **WHEN** a user quits the app while the Settings window is open and then opens it again
- **THEN** only the main window is shown, and the Settings window stays closed until requested

#### Scenario: Launch after the user's system restores windows

- **WHEN** the app starts with the macOS option to reopen windows from the previous session enabled
- **THEN** only the main window is shown

### Requirement: Settings opens only on request

The Settings window MUST open only when the user chooses Settings… from the app menu or presses Cmd+,. It MUST show the app's settings content, never an empty window.

#### Scenario: Open Settings with the shortcut

- **WHEN** a user presses Cmd+, in the running app
- **THEN** a window titled "AgentSessionManager Settings" opens and shows the settings sections

#### Scenario: Toggle Settings closed

- **WHEN** a user presses Cmd+, while the Settings window is open
- **THEN** the Settings window closes and the main window remains

#### Scenario: Single Settings menu item

- **WHEN** a user opens the app menu
- **THEN** it contains exactly one Settings… item
