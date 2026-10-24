# Spec Delta

## Purpose

Shared pane status identifies the current repository and its GitHub pull request consistently across harnesses, with clear authentication failures and recovery instead of misleading empty facts.

## ADDED Requirements

### Requirement: Repository identity is available to every harness

Every pane with a supported repository remote MUST populate its Repository fact independently of harness status payloads and GitHub authentication. A missing or unsupported remote MUST render unavailable. The displayed repository MUST belong to the pane's current checkout.

#### Scenario: A Codex pane has an HTTPS origin

- **WHEN** a Codex pane's checkout has a supported HTTPS repository remote
- **THEN** its Repository fact displays the remote's owner and repository name even if GitHub polling is unauthenticated

#### Scenario: An SSH remote is used

- **WHEN** a pane uses a supported SSH repository remote
- **THEN** its Repository fact resolves the same host, owner, and repository identity as the equivalent HTTPS remote

### Requirement: GitHub polling honors configured executable and authentication

App-side PR polling MUST honor an explicit GitHub executable override and otherwise resolve the executable using the configured interactive shell's PATH, including executable wrapper scripts. It MUST preserve the configured GitHub authentication context without switching accounts, changing credentials, or guessing account-specific configuration directories.

#### Scenario: A wrapper selects an agents account

- **WHEN** the configured shell resolves `gh` to an executable wrapper that selects an authenticated account configuration
- **THEN** app-side polling uses that wrapper and obtains PR data through that same configuration

#### Scenario: An executable override is configured

- **WHEN** an explicit GitHub executable override is present
- **THEN** polling uses that executable instead of substituting another executable found on PATH

### Requirement: PR authentication failures are actionable

A PR authentication failure MUST appear as an app-owned status error, distinguishable from a successful query that found no PR. The app MUST retain previously known PR data as visibly stale and suppress resolution notifications from failed queries. Recovery MUST use the user's configured account without automatic login or credential changes.

#### Scenario: No authenticated account is available

- **WHEN** GitHub PR polling reports an authentication failure
- **THEN** the app identifies GitHub authentication as the problem and offers Retry with guidance to authenticate the configured GitHub CLI

#### Scenario: Authentication fails after a successful result

- **WHEN** a pane already has PR data and a later query fails authentication
- **THEN** the known PR remains visibly stale and the failure does not produce a merged or closed notification

### Requirement: Successful polling recovers and distinguishes no PR

A successful retry MUST clear the previous polling error and update PR facts. A successful query finding no PR MUST clear old PR facts without being labeled an authentication failure. Confirmed merge and close transitions MUST continue using the existing notification behavior for all harnesses.

#### Scenario: The user repairs authentication

- **WHEN** the configured GitHub CLI becomes authenticated and the user retries
- **THEN** current PR data appears and its authentication error and stale indication disappear

#### Scenario: A branch has no PR

- **WHEN** an authenticated query succeeds and finds no PR for the current branch
- **THEN** the PR fact shows its normal no-PR state without an error or stale PR

### Requirement: GitHub setup stays outside the terminal

Repository discovery, executable resolution, GitHub queries, and their recovery messages MUST run through app-owned preparation and status UI. They MUST NOT prepend setup commands or credential prompts to a harness invocation. Diagnostics MUST exclude credentials, environment values, and conversation content.

#### Scenario: A background query fails

- **WHEN** repository discovery or GitHub polling fails while Codex is running
- **THEN** its terminal remains the Codex UI and app-owned diagnostics and status UI describe the failure without exposing secrets
