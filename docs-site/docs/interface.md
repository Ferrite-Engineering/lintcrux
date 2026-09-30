# The interface

LintCrux uses a docked IDE layout built around the violations table. This page tours every surface — the panes, the toolbar, the menu bar, the command palette, the filter and sort controls, the status bar, and Settings — so you know where everything lives before you start triaging.

## The layout {#layout}

Each open project is a tab. Inside a tab, the violations table fills the center and three docks surround it. Each dock shows its panes as tabs, and a dock you collapse leaves a slim restore bar along its window edge.

| Dock | Tab | What it shows |
|---|---|---|
| Left | Sources | Every source file in the project, with a remove button on each. Removing a file (after a confirmation) rewrites the project file and re-runs the engines; the file on disk is untouched. |
| Left | Rules | The rule browser — 645 rules across all seven engines. Search the rules, narrow the list to one engine, open a rule's upstream **Documentation**, or click a rule to filter the violations table to it. |
| Center | — | The unified violations table. Columns: Severity, Engine, Rule, File, Line, Message. The heart of the app; covered in full on [The violations dashboard](violations.md). |
| Right | Details | Engine run status while nothing is selected; the Inspector when a violation is — the message, the location with an **Open in editor** button, the rule's tags and **Learn more** link, and related locations. **Back to engine status** returns from one to the other. |
| Right | Cross-Probe | The [Cross-Probe panel](#crossprobe), shown when you open it. You can drag it to the bottom dock. |
| Bottom | Source | The source preview: the lines around the selected violation (ten either side), with the violation's line highlighted. |

Tabs can be split into two panes. Split the active pane right with ++cmd+backslash++ / ++ctrl+backslash++. **Close Pane**, **Focus Other Pane** and **Move Tab to Other Pane** are in the `View` menu and the command palette.

## Toolbar & menu bar {#toolbar}

The toolbar carries the actions you reach for constantly. It is split in two. The left group is shared across the EDACrux suite, so it looks the same in WaveCrux, NetCrux and SimCrux: **Open Project…**, **Save Session…**, **Close Active Project**, then **Find in Violations…**, **Cross-Probe Panel** (with a badge counting connected peers) and **Settings…**. The right group is LintCrux's own: **Open Source Files…**, **Open Workspace…** and **Import SARIF report…**, then a single run control that becomes a stop button while a run is in flight, and an **Export Report** button grouping the SARIF, JSON, CSV and HTML exports.

Buttons grey out when they have nothing to act on, using the same rules as the menu bar and the command palette. **Open Source Files…** adds sources to the project you already have open — LintCrux lints a *project*, not loose files — so it stays greyed until one is loaded. If the window is too narrow for every button, the extras move into an **Actions** overflow menu at the end of the strip rather than being clipped.

On desktop there is also a native menu bar — `File`, `View`, `Search`, `Tools`, `Help`. On macOS the `LintCrux` application menu holds About, Check for Updates, Settings… and **Quit LintCrux**; on Linux and Windows, Settings… and **Exit** sit at the bottom of `File`, and About and Check for Updates under `Help`. The wording differs because the platforms do — it is the same command on the same key either way. Running the engines, waivers, baselines, trends, bookmarks, Verible auto-fix, the lint cache and the diagnostics surfaces live under `Tools`; the imports, sessions, workspaces and exports live under `File`.

## Command palette {#palette}

Every command in LintCrux is reachable from the command palette: press ++cmd+shift+p++ / ++ctrl+shift+p++, type a few letters, and run it. The palette shows each command's keyboard shortcut and a <span class="tier tier-pro">Pro</span> or <span class="tier tier-enterprise">Enterprise</span> badge where the action requires a paid tier.

## Filter & sort controls {#filters}

Above the violations table is the filter strip:

- **Filter preset** — a dropdown that saves the current filters under a name (**Save current filters as preset…**) and re-applies them. Pro adds a second preset selector with the built-in presets and saved presets that persist per project — see [Filter presets & bookmarks](violations.md#presets).
- **Severity chips** — Fatal, Error, Warning, Note, Unclassified.
- **Engine chips** — one per engine that reported something in the loaded results.
- **Filter by rule or message…** — a case-insensitive substring matched against the rule id and message.
- **Filter by file glob** — for example `**/top.sv`.

With Pro, the same row also carries the baseline buttons and the *All violations / Only new / Only resolved* toggle, the active-baseline chip, the bookmark count, and the Verible dry-run button.

Click any column header to sort by it; click again to reverse. For substring, glob or regex search across rule ids and messages, press ++cmd+f++ / ++ctrl+f++ — see [Search](violations.md#search).

## Status bar {#statusbar}

The status bar at the bottom edge shows the active project's name (or *No project open*) and the live run summary: `X total · Y errors · Z warnings · N notes · M waived`. The counts follow the table's current filter, so as you narrow the table the summary follows. While engines are running it says so.

## Settings {#settings}

Open Settings with ++cmd+comma++ / ++ctrl+comma++. On desktop it opens as a dialog over the workspace. The sections are:

| Section | What it controls |
|---|---|
| General | **Auto-reload on source change** (Prompt me first / Re-run automatically / Do nothing — see [Auto-reload](projects-and-engines.md#auto-reload)), **Default sort column**, **Default filter set on launch**, **Restore tabs on launch**, **Automatically check for updates**, and in release builds **Enable diagnostics** (see [Diagnostics](#diagnostics)). |
| Appearance | The **Language** picker (English, 中文, 日本語, 한국어), color theme presets, per-token color overrides (including the severity colors), and theme packs — see [Appearance & themes](appearance-and-themes.md). |
| Privacy | The **Send anonymous usage statistics** toggle. Shown only on builds that can send statistics: the 0.8.x public-beta builds collect nothing, so the section is absent there; from 1.0 it is present — see [Usage statistics](getting-started.md#usage-statistics). |
| Engines | **Engine binary paths** — Auto-detect / Bundled / Custom per engine, with a **Probe** button — and **Per-rule severity overrides**. |
| Editors | The click-to-source editor — Visual Studio Code, Sublime Text, Vim / Neovim, Emacs, or a Custom executable and arguments template, with a live preview. |
| CXP Cross-Probe | **Enable CXP server**, **CXP port**, **Request attention on cross-probe**, **Broadcast selection automatically**, and the live server status. |
| Keyboard Shortcuts | View and rebind shortcuts, load a preset, and import or export a keymap — see [Customizing shortcuts](keyboard-mouse.md#customizing). |
| License | License status, key entry, machine activation and offline activation. |
| Custom Rules <span class="tier tier-pro">Pro</span> | User-defined regex rules over source text, signal names or identifiers. |
| Trend Retention <span class="tier tier-pro">Pro</span> | How much per-run trend history is kept (by default 90 days and 1,000 runs), the prune strategy, and storage stats. |
| Verible <span class="tier tier-pro">Pro</span> | The Verible binary used for auto-fix and its auto-fix options. |
| Lint Cache <span class="tier tier-pro">Pro</span> | Enable the lint result cache, its maximum size, statistics, the invalidations log, and **Clear cache now**. |
| Team Database <span class="tier tier-enterprise">Enterprise</span> | The shared PostgreSQL trend store connection and the organization rollup — covered on [Team trend database](team-database.md). |

## Diagnostics {#diagnostics}

Two diagnostic surfaces help you understand what the app and the engines are doing, both under `Tools`. In a release build they are off until you turn on `Settings → General → Enable diagnostics`; until then, either command tells you where that switch is.

The **Tab Diagnostics…** drawer (++cmd+shift+i++ / ++ctrl+shift+i++) reports, for the active tab: the project path, source-file count and last run time; for each engine, where its binary comes from (a Custom path, a bundled binary, or `PATH`), the version the binary reports, and how long its last run took; per-rule violation counts by severity; and a Yosys section. An engine whose binary did not answer its version check says `not detected`.

The **App Diagnostics…** dialog (++cmd+shift+m++ / ++ctrl+shift+m++) reports the app's resident memory and the active tab's violation count, followed by the tab report, and can copy the whole thing, which is the right thing to attach to a bug report.

Every line in both reports is measured: a value LintCrux did not measure, such as the run time of an engine that has not run, is left out rather than shown as zero.

## Cross-Probe panel {#crossprobe}

The Cross-Probe panel (++cmd+shift+x++ / ++ctrl+shift+x++, `View → Cross-probe Peers`) lists connected peers (WaveCrux, NetCrux, SimCrux), shows the cross-probe event log, and reports the CXP server status. Receiving cross-probes is Open Core; originating them is <span class="tier tier-pro">Pro</span>. See [Cross-probe & the suite](integrations.md).

## About box {#about}

The About box (++f1++, `Help → About LintCrux`) shows the tagline, version, build and commit, and your edition when it is not Open Core. It carries **Visit Website**, **Documentation**, **Submit Issue**, **Check for Updates**, **Privacy Policy**, **Terms of Service** and **Copy Version Info** actions.

!!! note "Next steps"
    Now that you know the layout, set up your [project and engines](projects-and-engines.md), then learn the [violations dashboard](violations.md) in depth.
