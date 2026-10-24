# Spec Delta

## Purpose

Dev builds can repair their Launch Services registration without affecting the installed production app or its active process.

## ADDED Requirements

### Requirement: Dev repair targets only the Dev registration

The app-dev Launch Services repair MUST register or repair only the Dev bundle identifier. Running or repairing the Dev build MUST leave the production Launch Services registration and production process unchanged.

#### Scenario: Repair and launch the Dev build

- **WHEN** the user runs the app-dev Launch Services repair and launches the resulting Dev build
- **THEN** Launch Services resolves the Dev bundle identifier to the Dev build while the production registration and running production process remain unchanged

### Requirement: Explicit broad repair retains its existing intent

The existing explicit broad Launch Services repair MUST remain available at its current entry point and retain its existing broad-repair intent.

#### Scenario: The user requests broad repair explicitly

- **WHEN** the user invokes the existing explicit broad Launch Services repair
- **THEN** the app performs that repair with its existing broad scope rather than applying the Dev-only scope

### Requirement: Dev builds preserve the macOS deployment floor

Dev builds MUST retain the macOS 26 minimum deployment target.

#### Scenario: Build the Dev app

- **WHEN** the Dev app is built
- **THEN** its deployment target remains macOS 26
