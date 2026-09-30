# The violations dashboard

The violations table is where you spend your time. It unifies every engine's findings into one virtualized list that stays responsive at tens of thousands of rows, with sorting, filtering, search, an Inspector and a source preview. This page is the complete reference.

## The table {#table}

The table is virtualized — it renders only the rows on screen — so a run with 50,000 violations scrolls smoothly. Each row has six columns: **Severity**, **Engine**, **Rule**, **File**, **Line** and **Message**, plus a leading checkbox. Pro adds a bookmark column in front of them. Hover a truncated message to read it in full.

Rule ids are namespaced by engine (`verilator/UNUSEDSIGNAL`, `verible/no-tabs`), so the same defect reported by two engines shows as two rows you can tell apart.

## Sorting {#sort}

Click any column header to sort by it; click again to reverse. The column a tab starts sorted by is set with `Settings → General → Default sort column` (Severity, Engine, Rule or File).

## Filtering {#filter}

The strip above the table combines several independent filters:

- **Severity chips** — Fatal, Error, Warning, Note, Unclassified. No chip selected means every severity; selecting chips shows only those.
- **Engine chips** — one per engine that actually reported something in the loaded results.
- **Filter by rule or message…** — a case-insensitive substring matched against the rule id and the message text.
- **Filter by file glob** — a glob matched against the violation's file path, for example `**/top.sv`.

Filters compose: a text filter, two severity chips and a file glob all apply at once, and the status-bar summary reflects the filtered set. Violations suppressed by an inline pragma or a managed waiver are left out of the table; the status bar counts them as *waived*.

With a baseline set, Pro adds an *All violations / Only new / Only resolved* toggle to the same row — see [Baselines & deltas](baselines.md#viewmode).

## Search {#search}

++cmd+f++ / ++ctrl+f++ (`Search → Find in Violations…`, or the toolbar's search button) opens the **Search violations** dialog. Pick **Substring** (the default), **Glob** or **Regex**; the query matches the rule id and message text together, across every violation in the active tab. Use ++arrow-up++ / ++arrow-down++ and ++enter++, or click a result, to select that violation in the table.

With Pro, **Search Across Projects…** (++cmd+shift+f++ / ++ctrl+shift+f++) searches every open project's violations by rule id, message or file path — see [Multi-project workspaces](integrations.md#workspace).

## Selection & context menu {#select}

Click a row to select it: the **Details** pane shows the violation and the **Source** pane previews its code. Double-click a row to open its location in your editor. Tick the leading checkbox to add rows to a multi-row selection.

Right-click a row for its context menu. The entries are Pro features, so an Open Core build shows no menu:

- **Waive…** <span class="tier tier-pro">Pro</span> — open the [Waive dialog](waivers.md#waive-dialog) for that violation.
- **Cross-probe to peer…** <span class="tier tier-pro">Pro</span> — pick a connected suite peer and send it the violation's location — see [Cross-probe](integrations.md#cxp).
- **Suggest fix with Verible** <span class="tier tier-pro">Pro</span> — run a Verible dry-run scoped to the violation's file and rule and review the proposed fix — see [Verible auto-fix](exports-and-ci.md#autofix).

## Inspector & Source Preview {#inspector}

Selecting a violation fills the **Details** pane on the right. The **Inspector** shows the severity and rule id, the message, the exact location with an **Open in editor** button, the rule's tags and **Learn more** documentation link from the [rule database](reference/rule-database.md), and any related locations (click one to navigate). **Back to engine status** clears the selection and returns the pane to the per-engine run status.

The **Source** pane in the bottom dock renders the lines around the violation — ten either side — in a monospace listing with line numbers, highlighting the violation's line and any related lines in the same file.

Opening in your editor uses the command configured in `Settings → Editors` — for example `code -g {file}:{line}:{column}` for Visual Studio Code. See [Editor presets & click-to-source](integrations.md#editors).

## Filter presets & bookmarks {#presets}

**Filter presets.** The **Filter preset** dropdown above the table saves the current chip and text-filter combination under a name (**Save current filters as preset…**), re-applies it with one click, and deletes presets you no longer want (**Manage presets…**).

Presets saved from the dropdown are written to the project's `.lintcrux` file (its `filterPresets` list), so they are there the next time you open the project — and for everyone else once you commit the file. Presets you save while viewing an imported SARIF report, which has no project file, last for that session. If the project file cannot be written, an error says so.

With Pro, a second **Filter preset** selector <span class="tier tier-pro">Pro</span> sits in the table's action row. It lists three built-in presets — **All Violations**, **Errors Only** and **New Violations** (the new-violation view, meaningful once a baseline is set) — followed by your own presets, which it saves per project in `.lintcrux-filter-presets.json`. **Save current as preset…** adds one, with an optional description; **Manage presets…** opens the **Filter Preset Library**, where you can create, edit, duplicate and delete your presets (built-ins cannot be edited or deleted). When you change the filters after applying a preset, the selector reads **Custom filter**.

**Violation bookmarks** <span class="tier tier-pro">Pro</span> pin individual violations so you can build a working set during a triage pass and return to it. Click the bookmark icon in a row's bookmark column, or run **Toggle Bookmark** from the `Tools` menu for the selected violation; a bookmark can carry a color tag and a Markdown note. The bookmark count in the table's action row opens the **Bookmarks** panel (also `Tools → Show Bookmarked Violations…`), with All / Active / Stale filters — a stale bookmark is one whose violation has not fired in recent runs. Bookmarks are saved per project in `.lintcrux-bookmarks.json`.

## Keyboard {#keyboard}

These keys work on the table from anywhere in the window:

| Key | Action |
|---|---|
| ++cmd+f++ / ++ctrl+f++ | Open the search dialog; ++arrow-up++ / ++arrow-down++ and ++enter++ select a matching violation. |
| ++f5++ | Run all engines again. |
| ++escape++ | Cancel the run in progress. |
| ++cmd+shift+p++ / ++ctrl+shift+p++ | Open the command palette — for example to run **Toggle Bookmark** <span class="tier tier-pro">Pro</span> on the selected violation. |

The rows themselves are a single ++tab++ stop, so ++tab++ moves on to the **Details** pane rather than through every row. With focus on a row, everything the mouse does has a key:

| Key | Action |
|---|---|
| ++arrow-up++ / ++arrow-down++ | Move to the previous or next violation. The row scrolls into view, shows a focus ring, and is selected — the **Details** and **Source** panes follow it as they follow a click. |
| ++home++ / ++end++ | Move to the first or last violation. |
| ++enter++ | Open the violation's location in your editor, as a double-click does. |
| ++space++ | Tick or clear the row's checkbox. |
| ++shift+f10++ or the Menu key | Open the row's context menu, as a right-click does. |

Clicking a row also moves that ++tab++ stop, so tabbing back into the table returns to the row you last clicked. ++f6++ / ++shift+f6++ jump between the toolbar, the docks and the table, and ++cmd+shift+arrow-left++ / ++ctrl+shift+arrow-left++ (and the other arrows) resize the dock that has focus — see [Moving around the window](keyboard-mouse.md#navigation). Screen readers announce each row as one sentence — severity, rule, file, line and message — followed by its checkbox state.

Every default binding is on the [Keyboard & mouse reference](keyboard-mouse.md).

!!! note "Next steps"
    Tune what counts as a problem on [Severity & pragmas](severity-and-pragmas.md), then put false positives to rest with [Managed waivers](waivers.md) <span class="tier tier-pro">Pro</span>.
