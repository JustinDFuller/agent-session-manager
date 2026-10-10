# Profiles

Profiles let you save a named harness type, harness-specific CLI flags, supported environment variables, and (optionally) a custom status line configuration. When you create a new pane, selecting a profile pre-fills the applicable settings automatically.

## Creating a Profile

Open **Settings → Profiles** and click **+**. You can also click **Save Profile & Create** in the New Pane sheet to snapshot the current form as a new profile.

## Editing a Profile

In **Settings → Profiles**, select a profile and click **Edit**. Every available CLI flag for the selected harness is shown. Claude Code and OpenCode profiles also show their environment-variable catalogs. For each option you can:

- **Enable/disable** the option (the checkbox on the left) — controls whether the flag or environment variable is passed when the pane starts.
- **Set a value** — for string flags like `--model`, type the value in the text field.
- **Show on create** — tick the **Show** checkbox on the right to make the option visible in the New Pane sheet whenever this profile is selected (see below).

Expanded environment-variable catalogs scroll independently inside the editor. UI automation scrolls that list until the target row is inside its visible bounds before changing a checkbox, then verifies the saved selection through New Pane.

## Show on Create

By default, options enabled in a selected profile appear in the New Pane sheet so their values can be reviewed or changed. Options stored in the profile but disabled remain hidden unless they are marked **Show on new pane**.

Marking an option **Show** means it will appear as an editable toggle or text field even when it is disabled in the profile. This is useful for options you want to decide on per-pane, like `--continue` or `--resume`.

Options that are enabled in the profile are still passed to the selected harness exactly as configured, whether or not they are changed in the sheet.

## Applying a Profile

In the New Pane sheet, choose a profile from the **Profile** picker. The harness is locked to the profile's harness. Enabled options and options marked **Show** in the profile are displayed; other catalog entries remain under **Show all options** or **Show all environment variables**.

If you change any option while a profile is selected, the picker label updates to show **(modified)**. You can click **Save Profile & Create** to save the modified form as a new or updated profile before creating the pane.

## Profile Ordering

Profiles appear in the order defined in **Settings → Profiles**. Use the up/down arrows to reorder them. The first profile that matches the active harness is pre-selected when the New Pane sheet opens.
