# Installation & first run

LintCrux is a desktop application that runs Verilator, Verible, Slang, GHDL, Yosys and Svlint for you and aggregates their output, plus its own [clock-domain-crossing analysis](cdc.md). There is no account to create and no license key to enter before your first run. This page covers how to get the app on each platform, where the lint engines come from, how to run your first lint, and how updates, issue reports and usage statistics work.

## Platforms {#platforms}

LintCrux is desktop-first. The same dashboard runs on Linux, macOS and Windows. A read-only [web viewer](user-guide/web-mode.md) renders SARIF reports in the browser.

| Platform | Versions | How you get it |
|---|---|---|
| Linux | x86_64 | AppImage or `.tar.gz` from the [downloads page](https://lintcrux.app/download). A native binary, no webview wrapper. |
| macOS | 12 or later, universal (Apple silicon and Intel) | `.dmg` from the [downloads page](https://lintcrux.app/download). |
| Windows | 10 / 11, x86_64 | Installer or portable `.zip` from the [downloads page](https://lintcrux.app/download). |
| Web | A current desktop browser | The read-only SARIF viewer at [app.lintcrux.app](https://app.lintcrux.app) — not the full dashboard. |

The 0.8.x public-beta builds carry an expiry date, so a stale beta retires instead of drifting on indefinitely; 1.0 and later production builds do not expire. Either way the app tells you when a newer build is out (see [Staying up to date](#staying-up-to-date)).

!!! note "No activation step"
    You do not need an account or a license key to begin: Open Core is free, with no sign-up and no time limit. Through the 0.8.x public beta the Pro and Enterprise features are unlocked as well, so nothing at all needs a key in those builds. From 1.0 those features need a license key, entered under `Settings → License`, and Open Core carries on unchanged. See [Tiers & licensing](https://edacrux.app/licensing).

## The lint engines {#engines}

LintCrux does not reimplement static analysis — it orchestrates the open-source engines and parses what they emit. **LintCrux does not ship the engines**: install the ones you want and make sure they are on your `PATH`. Most are available through `apt`, Homebrew or `winget`, and all six are in [OSS-CAD-Suite](https://github.com/YosysHQ/oss-cad-suite-build).

| Engine | Languages | How it is invoked | Executable LintCrux looks for |
|---|---|---|---|
| Verilator | Verilog, SystemVerilog | `verilator --lint-only`, `-Wall` by default, with your defines, includes and top module | `verilator` |
| Verible | Verilog, SystemVerilog | `verible-verilog-lint`, optionally with a curated rule profile | `verible-verilog-lint` |
| Slang | Verilog, SystemVerilog | `slang` elaboration with JSON diagnostics | `slang` |
| GHDL | VHDL | `ghdl -a` with a set of `--warn-*` flags | `ghdl` |
| Yosys | Verilog, SystemVerilog | `hierarchy -check` followed by `check -assert` | `yosys` (`yosys.exe` on Windows) |
| Svlint | Verilog, SystemVerilog | `svlint` with its TOML rule configuration | `svlint` |

The built-in CDC engine needs no binary of its own — it elaborates the design with the same `yosys`, so whatever the Yosys engine is configured to run, CDC runs too.

For each engine, `Settings → Engines` offers **Auto-detect** (search `PATH`), **Bundled** or **Custom** (a path you supply, with a **Probe** button that runs the engine's version command and shows what it found). No engine binaries are packaged with LintCrux, so **Bundled** currently behaves exactly like **Auto-detect**. Per-engine options and the full resolution order are on [Projects & engines](projects-and-engines.md#per-engine).

An engine whose binary is not installed is reported as **Binary not available** rather than as a clean run — the other engines still run.

## First launch {#first-launch}

With nothing open, LintCrux shows a welcome screen with **Open Project…**, **Open Workspace…**, **Open Session…**, **New Project…** and **Import SARIF report…** buttons, and a **Recent projects** list of the projects you opened most recently — click one to reopen it. You do not need a project loaded to explore: the toolbar, status bar, menu bar, command palette and Settings are all reachable from the welcome screen. LintCrux is localized in English, Simplified Chinese, Japanese and Korean — the **Language** picker lives in `Settings → Appearance`.

## Run your first lint {#run-first-lint}

1. **Open or create a project.**

    Open an existing `.lintcrux` project with ++cmd+o++ / ++ctrl+o++ (`File → Open Project…`), or click **New Project…** on the welcome screen, which asks where to save and writes an empty project. With a project open, add RTL to it with ++cmd+shift+o++ / ++ctrl+shift+o++ (`File → Open Source Files…`) — the files are added to the active project, stored relative to the project file. No project yet but a build that already describes one? `File → Import Vivado Filelist…` and `File → Import FuseSoC EDAM…` generate one.

2. **Run all engines.**

    Opening a project, or adding sources to it, runs the engines immediately. To run again, press ++f5++, click the run button on the toolbar, or choose `Tools → Run All Engines`. Engines run in parallel; while no violation is selected, the **Details** pane on the right lists each engine's status (Pending, Running, Completed, Failed, Binary not available, Cancelled), and violations stream into the center table as each engine finishes. Each engine receives only the sources in a language it supports, and an engine with no compatible file is skipped.

3. **Read the result.**

    The status bar summarizes the run — `X total · Y errors · Z warnings · N notes · M waived`. Click a column header to sort, use the severity and engine chips to filter, and click a violation to see its details and the surrounding source; double-click it to open the location in your editor. To stop a run early, press ++escape++ or click the stop button that replaces the run button while a run is in flight.

!!! tip "From the command line"
    The desktop app opens from the command line: `lintcrux project.lintcrux` opens a project, `--workspace <file>` opens a saved multi-tab workspace, `--session <file>` restores a session, and `--import-filelist rtl.f` converts a Vivado-style filelist into a `.lintcrux` project.

    A separate **headless binary** does the same lint with no window and a meaningful exit code: `lintcrux project.lintcrux --exit-code` gates on findings, and `lintcrux foo.v bar.sv --top top_module` lints loose sources without a project file. It shares the desktop app's engine planner — see [Exports & CI](exports-and-ci.md) and the [command-line reference](cli/invocation.md).

## Staying up to date {#staying-up-to-date}

LintCrux checks a release manifest on launch, once every 24 hours while it is running, and when the app comes back to the foreground. When a newer version is out, a strip appears above the app content:

- **View Changes** opens the release's changelog (shown only when the release has one).
- **Update Now** opens the [download page](https://lintcrux.app/download) in your browser. There is no in-app download and no self-update: LintCrux tells you, you decide.
- **✕** dismisses the strip for this session and this version. A release flagged mandatory has no dismiss button.

Turn the automatic check off with `Settings → General → Automatically check for updates`. You can always check by hand from `Help → Check for Updates` (the application menu on macOS), the command palette, or the About box — the manual check runs even when the automatic one is off. The request is a plain `GET` for a static manifest; the only thing it carries is a `User-Agent` of the form `LintCrux/<version> (<os>)`. The update strip does not appear in the web viewer.

## Reporting issues {#reporting-issues}

The fastest way to get something fixed is the built-in issue reporter, reachable from `Help → Submit Issue…`, the command palette, or the **Submit Issue** button in the About box. Give the issue a short title, then choose what to attach. Each category has a live preview of exactly what will be included:

| Category | What it attaches |
|---|---|
| **App & Environment** *(always included)* | App name, version and build number, build SHA, platform, OS, architecture, screen DPI, locale, Flutter and Dart SDK versions. |
| **Session State** | Whether a project is loaded, project language, source-file count, enabled engine ids and their resolved versions, registered-engine count, total and per-severity violation counts, distinct rules firing, active waiver count, table view mode, whether a filter preset is active, which severity and engine filters are set, whether a rule-text or file-glob filter is set (yes/no only), and the number of selected rows. |
| **Diagnostics** | The last 100 warning-or-higher log entries plus the last 20 entries at any level from this session. |
| **Screenshot** | A PNG of the app window, saved to your temp directory and revealed in your file manager so you can drag it in. Desktop only. |

On **Submit**, LintCrux copies the report to your clipboard and opens a pre-filled issue in your browser; if the report is too long to pre-fill, paste it from the clipboard.

The rule is **counts, ids, versions and enum names — nothing else**. A report never contains file paths of any kind, source-file contents, violation message text, the names of your filter presets, or the text you typed into the filters. Version strings are scrubbed of anything path-shaped, because a locally built engine can print its install prefix in its `--version` banner. Nothing leaves your machine until you press **Submit**.

## Usage statistics {#usage-statistics}

The 0.8.x public-beta builds collect no usage statistics: no disclosure appears and nothing is recorded.

From 1.0, the first launch shows a one-time disclosure with a **Send anonymous usage statistics** toggle. It starts **on**, except on machines whose locale or time zone places them in the EEA, the United Kingdom, Switzerland or South Korea, where it starts **off**. Nothing is sent until the disclosure has been answered, and you can change the choice at any time under `Settings → Privacy`. On an Enterprise seat, an organization policy file can decide for the whole fleet instead, and no disclosure appears.

What is sent: feature, engine and error counters, app and OS version, form factor, language, and license tier — never file names, rule identifiers, or the text of any lint or error message. An error the desktop app did not handle is counted by its kind alone (for example, a state error in the widgets library), never with its message or stack trace. The headless `lintcrux` binary never asks; it sends only on a machine where the desktop app has stored an affirmative answer.

!!! note "Next steps"
    With a run on screen, take the tour of [the interface](interface.md), learn the details of [projects & engines](projects-and-engines.md), and then dig into [the violations dashboard](violations.md) to start triaging in earnest.
