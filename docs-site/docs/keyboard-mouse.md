# Keyboard & mouse reference

This is the complete default binding set — every action LintCrux ships with a keyboard shortcut, the actions that ship unbound, and the mouse gestures the violations table responds to. Bindings are written macOS first; the platform modifier is ++cmd++ on macOS and ++ctrl++ on Linux and Windows. Anything here can be rebound in `Settings → Keyboard Shortcuts`.

## Default shortcuts {#defaults}

Twenty-one actions ship with a default binding. Everything else is reachable from the command palette and the menu bar. The Menu column is where the action sits in the menu bar.

| Shortcut | Action | Menu |
|---|---|---|
| ++cmd+o++ / ++ctrl+o++ | Open Project… | File |
| ++cmd+shift+o++ / ++ctrl+shift+o++ | Open Source Files… | File |
| ++cmd+p++ / ++ctrl+p++ | Switch Project… <span class="tier tier-pro">Pro</span> | File |
| ++cmd+t++ / ++ctrl+t++ | New Tab | File |
| ++cmd+w++ / ++ctrl+w++ | Close Tab | File |
| ++cmd+shift+r++ / ++ctrl+shift+r++ | Reset Workspace… | File |
| ++cmd+shift+p++ / ++ctrl+shift+p++ | Command Palette… | View |
| ++cmd+shift+x++ / ++ctrl+shift+x++ | Cross-probe Peers | View |
| ++cmd+backslash++ / ++ctrl+backslash++ | Split Pane Right | View |
| ++ctrl+tab++ | Next Tab | View |
| ++ctrl+shift+tab++ | Previous Tab | View |
| ++cmd+shift+k++ / ++ctrl+shift+k++ | Toggle Theme | View |
| ++cmd+f++ / ++ctrl+f++ | Find in Violations… | Search |
| ++cmd+shift+f++ / ++ctrl+shift+f++ | Search Across Projects… <span class="tier tier-pro">Pro</span> | Search |
| ++f5++ | Run All Engines | Tools |
| ++escape++ | Cancel Run | Tools |
| ++cmd+shift+i++ / ++ctrl+shift+i++ | Tab Diagnostics… | Tools |
| ++cmd+shift+m++ / ++ctrl+shift+m++ | App Diagnostics… | Tools |
| ++f1++ | About LintCrux | Help (the application menu on macOS) |
| ++cmd+comma++ / ++ctrl+comma++ | Settings… | LintCrux (File on Linux and Windows) |
| ++cmd+q++ / ++ctrl+q++ | Quit LintCrux — **Exit** on Linux and Windows | LintCrux (File on Linux and Windows) |

!!! note "Bindings that are not platform-adapted"
    **Next Tab** and **Previous Tab** are ++ctrl+tab++ and ++ctrl+shift+tab++ on *every* platform, macOS included.

    **Run All Engines** is bare ++f5++, **About LintCrux** is bare ++f1++, and **Cancel Run** is ++escape++ — the suite-wide cancel convention shared with WaveCrux, NetCrux and SimCrux.

    **Toggle Theme** switches between Crux Light and Crux Dark — see [Appearance & themes](appearance-and-themes.md#light-dark).

## Actions without a default binding {#unbound}

These actions ship deliberately unbound. They are fully available from the command palette (++cmd+shift+p++ / ++ctrl+shift+p++) and the menu bar, and you can assign your own shortcut to any of them.

- **File:** New Workspace, Open Workspace…, Open Session…, Import Vivado Filelist…, Import FuseSoC EDAM…, Import SARIF report…, Save Session…, Save Workspace As…, the four **Export Violations as …** actions, Close All Tabs, Close Active Project, and the Pro project actions Reopen Recent Project, Pin Project Tab and Close All Projects.
- **View:** Save Filter Preset…, Manage Filter Presets…, Close Pane, Focus Other Pane, Move Tab to Other Pane.
- **Tools:** Run Lint (Bypass Cache) and every Pro waiver, baseline, trend, bookmark, Verible and lint-cache action.
- **Help:** Documentation, Submit Issue…, Check for Updates.

Several of these also have a button: **Open Workspace…**, **Import SARIF report…**, **Save Session…** and the exports are on the toolbar, and the welcome screen offers **Open Workspace…**, **Open Session…**, **New Project…** and **Import SARIF report…**.

## Moving around the window {#navigation}

These keys are fixed rather than rebindable, and work the same on every screen — the workspace, the imported SARIF report viewer and the web viewer.

| Key | Action |
|---|---|
| ++f6++ / ++shift+f6++ | Move focus to the next or previous region: the toolbar, the Rules, Details and bottom docks, the violations table (or the welcome screen), and the status bar when it holds a control. Returning to a region puts focus back where it was. |
| ++tab++ / ++shift+tab++ | Move between the controls inside a region. Long lists — the violations table and the rule browser — are a single stop. |
| ++cmd+shift+arrow-left++ / ++ctrl+shift+arrow-left++ and the other arrows | With focus inside the Rules, Details or bottom dock, grow or shrink that dock. The new size is saved like a drag. |
| ++arrow-up++ / ++arrow-down++ | Move between rows of the violations table or the rule browser. In the table the focused row is selected, so the Details pane follows it. |
| ++home++ / ++end++ | Move to the first or last row of the violations table. |
| ++enter++ | On a violations-table row, open the violation in your editor. |
| ++space++ | On a violations-table row, tick or clear its checkbox. |
| ++shift+f10++ or the Menu key | On a violations-table row, open its context menu. |

At launch focus starts on the welcome screen's **Open Project…**. In the desktop app, when focus lands nowhere — after a native file dialog closes, or when the control that had it goes away — LintCrux puts it back on the control that last had it, or on the main surface of the screen. See [the violations table's keyboard section](violations.md#keyboard) for the table in detail.

## Mouse {#mouse}

The violations table is the gesture surface in LintCrux. These are the gestures on a violation row.

| Gesture | Action |
|---|---|
| Click | Select that violation: the Details pane shows it and the Source pane previews it. |
| Double-click | Open the violation's location in your configured editor. |
| Right-click | Open the violation context menu at the pointer. |
| Click the row's leading checkbox | Add the row to, or remove it from, the multi-row selection. |
| Click a column header | Sort by that column; click again to reverse. |

Every row gesture has a keyboard equivalent once a row has focus — ++arrow-up++ / ++arrow-down++ select, ++enter++ opens in the editor, ++space++ ticks the checkbox, ++shift+f10++ opens the context menu; see [the violations table's keyboard section](violations.md#keyboard).

Right-clicking selects the row first, so the context menu always acts on the row under the pointer. The menu's entries come from the Pro features — **Waive…**, **Cross-probe to peer…** and **Suggest fix with Verible**, each badged <span class="tier tier-pro">Pro</span> — so an Open Core build has no row context menu.

!!! note "No other pointer gestures"
    LintCrux binds no scroll-wheel, middle-click or drag gestures on the table. Editor integration is configured under `Settings → Editors`; see [Cross-probe & the suite](integrations.md#editors).

## Customizing shortcuts {#customizing}

`Settings → Keyboard Shortcuts` is the full keymap editor. From it you can:

- **Start from a preset.** The **Preset** chooser loads a complete key map in one step — **LintCrux (Default)** ships today — and reads **Custom** once you change any binding.
- **Change** any action's shortcut: press the pencil, then type the new keys (++escape++ cancels).
- **Remove** a shortcut so the action has none.
- **Reset** one action to its shipped default, or **Reset all** bindings back to the defaults above.
- **See conflicts**: a chord already claimed by another action is flagged, including which binding wins and which is shadowed.
- **Import…** and **Export…** your keymap as a `.crux-keymap.json` file, so a team can share one binding set.

The editor is keyboard-drivable too: ++arrow-up++ and ++arrow-down++ move between shortcuts, ++enter++ changes the selected one, ++delete++ removes it, and ++shift+delete++ restores its default.

!!! note "Next steps"
    For where each of these actions lives in the UI, see [The interface](interface.md). For what the context menu does with a selected violation, see [The violations dashboard](violations.md).
