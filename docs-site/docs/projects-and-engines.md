# Projects & engines

A LintCrux project tells the engines what to compile and how to run. This page covers the `.lintcrux` project file, importing an existing Vivado filelist or FuseSoC design, the engines and their binaries, auto-reload, and the session and workspace files that remember your UI state.

## The `.lintcrux` project file {#project-file}

A project is a single JSON file with a stable, version-controllable schema. It captures everything the engines need to reproduce a run:

- **`sourceFiles`** — the RTL files to lint, with an optional per-file language override in `sourceFileLanguages`.
- **`includePaths`** — include search paths.
- **`defines`** — preprocessor macros.
- **`topModule`** — the top module or entity.
- **`language`** — `verilog`, `systemverilog` (the default), `vhdl` or `mixed`.
- **`enabledEngineIds`** — which engines run (see [Which engines run](#which-engines)).
- **`severityOverrides`** — per-rule severity overrides (see [Severity & pragmas](severity-and-pragmas.md)).
- **`perEngineOptions`** — engine-specific options (see [Per-engine configuration](#per-engine)).

Relative paths resolve against the directory that holds the `.lintcrux` file, so a committed project works from any checkout location. Because the file is plain JSON, you check it into the same repository as your RTL and your whole team lints identically. The full schema is in the [project file reference](reference/project-file.md).

**Creating one.** **New Project…** on the welcome screen, or **New Tab** (++cmd+t++ / ++ctrl+t++), asks where to save, writes an empty `.lintcrux`, and opens it. `File → Open Source Files…` (++cmd+shift+o++ / ++ctrl+shift+o++) then adds the files you pick to the active project — stored relative to the project file — and re-runs the engines. The **Sources** tab in the left dock lists what the project holds and removes a file from it.

**Opening one.** `File → Open Project…` (++cmd+o++ / ++ctrl+o++), the welcome screen, or a `.lintcrux` path on the command line. Each project opens in its own tab; opening a project that is already open focuses its tab instead. Opening a project runs its engines immediately.

**On macOS, from Finder.** Double-clicking a LintCrux file, choosing LintCrux under `Open With`, or dropping a file on the Dock icon opens it the same way the matching command does, whether or not LintCrux is already running:

| File | Opens as |
|---|---|
| `.lintcrux` project, `<design>.crux-project` manifest | a new tab, as `File → Open Project…` does |
| `.lintcrux-workspace` | the whole workspace, as `File → Open Workspace…` does |
| `.lintcrux-session` | its project with the saved view, as `File → Open Session…` does |
| `.f` filelist | a new project written beside it, as `File → Import Vivado Filelist…` does |
| `.sarif` report | the read-only report viewer, as `File → Import SARIF report…` does |
| `.v` `.vh` `.sv` `.svh` `.vhd` `.vhdl` source | added to the active project, as `File → Open Source Files…` does (with no project open, LintCrux says so) |

A file of any other type is refused with a message naming it. (macOS types `.f` as Fortran source, together with `.for`, so it also offers LintCrux for a `.for` file; that one is refused.)

On Linux the AppImage's desktop entry claims the same file types, so a file manager offers LintCrux for them — with one exception: `.f`, which every Linux desktop reads as Fortran source. Open a filelist from inside LintCrux (`File → Import Vivado Filelist…` or `lintcrux --import-filelist`); a double-clicked `.f` goes to your Fortran editor.

## Opening a design with `<design>.crux-project` {#crux-project}

A design usually spans more than one EDACrux product — the dump in WaveCrux, the RTL in NetCrux, the lint project in LintCrux, the regression suite in SimCrux. A design manifest — a file named after the design, like `uart_tx.crux-project`, at the root of your design — names all of them. It is a small YAML file you write once and check in alongside the RTL:

```yaml
# uart_tx.crux-project
version: 1
name: uart_tx

design:
  top: uart_tx
  sources:
    - rtl/uart_tx.v

artifacts:
  waveform:   sim/uart_tx.vcd
  lint:       project.lintcrux
  simulation: simcrux.yaml
```

LintCrux's part is the `lint` artifact — the `project.lintcrux` the manifest points at. Every path is relative to the manifest's own directory, so the file travels with the repository.

**Opening a manifest.** Choose it in `File → Open Project…` (the dialog lists `.crux-project` files alongside `.lintcrux` projects), or pass its path on the command line (`lintcrux uart_tx/uart_tx.crux-project`): LintCrux opens the project the manifest's `lint:` entry names. A manifest with no `lint:` entry, or one naming a file that is missing, is reported rather than opened. A design folder holds exactly one manifest; if it holds two, LintCrux names both and opens neither, so remove or merge the extra.

A manifest still named with the old bare name `.crux-project` opens too, and LintCrux asks you to rename it to `<design>.crux-project` — a later release stops reading the old name.

**Everything except `version` is optional.** A design that has a dump but no lint project yet just omits the `lint:` line. Keys a newer release understands and an older one does not are ignored, so a manifest never becomes unreadable.

A design manifest holds no view state and no personal settings — it says what the design *is*, not how you last looked at it. That is what sessions are for.

## Importing a Vivado filelist {#filelist}

If you already maintain a `.f` filelist, you do not have to retype it. Choose `File → Import Vivado Filelist…` and select the `.f`: LintCrux resolves nested `-f` includes, `+incdir+`, `+define+` and environment variables, writes `<name>.lintcrux` beside the filelist, and opens it. The same conversion is available from the command line with `lintcrux --import-filelist rtl.f`, which prints the path of the project it wrote and then lints it. A filelist that cannot be read or converted exits `65`.

## Importing a FuseSoC project (EDAM) {#edam}

If your design is packaged as FuseSoC `.core` files, let FuseSoC do the resolution and hand LintCrux the **EDAM** file it generates. Run `fusesoc run --target=lint --setup <core>`, then either choose `File → Import FuseSoC EDAM…` and pick the `.eda.yml` from the FuseSoC build directory, or run `lintcrux --import-edam <design>.eda.yml`. The import carries the resolved source list with per-file languages, include directories, defines, the top module, Verilator options, and any `.vlt` waiver files (routed to Verilator only). Which FuseSoC core contributed each file is recorded in the generated project as `sourceFileProvenance`. Anything the importer skips is reported as a warning rather than silently dropped. The [Lint a FuseSoC core](cookbook-fusesoc.md) recipe walks through it.

You can also point the headless binary directly at loose files with `lintcrux foo.v bar.sv --top top_module`. It builds an ad-hoc project rooted at the files' common directory, inferring the language from their extensions. A positional argument that is neither a `.lintcrux` nor a lintable source file is reported as an error rather than skipped — a typo must not produce a clean run over zero files.

!!! tip "Language is detected per file"
    Each engine receives only the sources in a language it supports: GHDL sees only the VHDL files, the other engines only the Verilog and SystemVerilog files. A mixed-language project runs the Verilog engines over the Verilog sources and GHDL over the VHDL sources in the same run, and an engine left with no compatible file is skipped.

## Per-engine configuration {#per-engine}

LintCrux registers seven engines. Six run a real tool as a subprocess and normalize its output; the seventh, CDC, is LintCrux's own analysis over a Yosys-elaborated netlist.

| Engine id | Tool and invocation | Languages | Options in `perEngineOptions` |
|---|---|---|---|
| `verilator` | Verilator, `--lint-only` with `-Wall` by default | Verilog, SystemVerilog | `warnFlags` (the `-W*` selectors), `extraOptions` (raw flags), `waiverFiles` (`.vlt` files) |
| `verible` | `verible-verilog-lint` | Verilog, SystemVerilog | `ruleProfile`, `rulesConfigSearch`, `textModeFallback` |
| `slang` | Slang | Verilog, SystemVerilog | `textModeFallback` |
| `yosys` | Yosys `hierarchy -check` + `check -assert` | Verilog, SystemVerilog | — |
| `ghdl` | GHDL `-a` | VHDL | `warnFlags` (the `--warn-*` classes) |
| `svlint` | Svlint | Verilog, SystemVerilog | `configPath`, `textModeFallback` |
| `cdc` | Structural clock-domain-crossing lint | Verilog, SystemVerilog | — (no binary of its own; it drives Yosys — see [Clock-domain crossings](cdc.md)) |

Defines, include paths and the top module are project-level, so every engine that understands them receives them. The option keys and their defaults are in the [project file reference](reference/project-file.md). Engine options are edited in the `.lintcrux` file; `Settings → Engines` configures binaries and severity overrides, not engine flags.

### Which engines run {#which-engines}

`enabledEngineIds` selects the engines. **An empty list means every registered engine** — which is what a new or imported project starts with — so list only the engines you have installed if you do not want the rest reported as unavailable. On the command line, `--engine <id>` (repeatable) narrows a headless run without editing the file.

### Verible rule profiles

Verible can be pointed at a named, curated rule selection instead of its own defaults:

```json
"perEngineOptions": {
  "verible": {"ruleProfile": "lowrisc"}
}
```

`lowrisc` is the lowRISC / OpenTitan Verilog style guide — the one Ibex and OpenTitan follow — packaged so you do not have to transcribe it. See [Rule profiles](reference/project-file.md#rule-profiles).

A `.rules.verible_lint` in the project root turns on Verible's config search by itself, and a `.svlint.toml` in the project root is passed to Svlint with `--config` — even for sources that live outside the root. Set `"rulesConfigSearch": true` under `perEngineOptions.verible` to have Verible look for per-directory `.rules.verible_lint` files when the root has none. With the Pro lint cache on, editing either file invalidates that engine's cached result.

### Engine binaries {#binaries}

**LintCrux does not ship the engines** — install them and put them on `PATH` (see [Installation & first run](getting-started.md#engines)). Each engine's binary is resolved in this order:

1. A per-launch command-line flag: `--verilator-path`, `--verible-path`, `--slang-path`, `--yosys-path`, `--ghdl-path`, `--svlint-path`.
2. `Settings → Engines → Engine binary paths` → **Custom** → **Binary path**. The **Probe** button runs the engine's version command and shows the detected version, so you can confirm the path before you rely on it. The choice is saved and restored at the next launch, before any restored tab runs its engines.
3. Otherwise the bare executable name, resolved against `PATH`.

**Auto-detect** is the `PATH` lookup. **Bundled** is reserved for per-platform binaries shipped with LintCrux; none ship, so it resolves nothing and falls through to `PATH` unless the `LINTCRUX_BUNDLED_BIN_DIR` environment variable names a root directory containing a per-platform subdirectory (`macos-universal`, `linux-x86_64` or `windows-x86_64`) that holds each binary named by its engine id.

The `cdc` engine has no binary of its own and no row in `Settings → Engines`: it runs the `yosys` that the **Yosys check** row (or `--yosys-path`) selects.

The desktop app lists each engine's run status — Pending, Running, Completed, Failed, Binary not available, Cancelled — in the **Details** pane while no violation is selected; one engine being unavailable does not stop the others. The headless binary is stricter: a missing engine fails the run unless you pass `--allow-missing-engines` — see [Missing engines](cli/invocation.md#missing-engines).

!!! note "Every engine ships rule metadata"
    All seven engines have entries in the bundled rule database — 645 rules with default severity, tags and documentation links, browsable from the **Rules** tab in the left dock. Where that metadata came from differs per engine: the Verilator, Verible, Slang and GHDL ids are checked against real releases; Svlint's 159 rules are enumerated from the binary itself; CDC's are LintCrux's own; and Yosys' come from LintCrux's message-pattern table, because Yosys does not name its checks. See the [rule database reference](reference/rule-database.md).

### Version drift

Engines rename and retire rules between releases. LintCrux carries a rule-alias table mapping retired rule ids to their current names (for example `verilator/UNUSED` → `verilator/UNUSEDSIGNAL`); the Pro managed-waiver matcher consults it so a waiver written against an old id still matches. Inline source pragmas and severity overrides match the id exactly. Pin the engine versions your CI image installs and use the same versions locally.

## Auto-reload {#auto-reload}

`Settings → General` has an **Auto-reload on source change** setting that decides what happens when you save a source file of an open project:

- **Prompt me first** (the default) — a snackbar says the source files changed and offers **Re-run now**, which runs the tab's engines.
- **Re-run automatically** — the engines re-run shortly after the save, re-linting only the changed files where an engine supports it.
- **Do nothing** — no files are watched; re-run with ++f5++ or the toolbar run button.

Each tab watches its own project's source files, so a save re-runs only that project. The choice applies to the current session; it is not saved across restarts.

## Sessions & workspaces {#sessions}

LintCrux remembers your UI state separately from the project. A project file describes the RTL inputs; a session or workspace describes the lens on top.

A **`.lintcrux-session`** file is a snapshot of one tab: the project it belongs to, the active severity and engine chips, the rule/message and file-glob filter text, the sort column and direction, the selected rule, the active filter-preset name, and the view mode. `File → Save Session…` (or the toolbar button) writes one for the active tab; restore it with `File → Open Session…`, **Open Session…** on the welcome screen, or `lintcrux --session debug.lintcrux-session`. Opening a session opens the project it names — or focuses its tab if it is already open — and then applies the filters and sort on top. The project path is stored absolute, so a session file is tied to the machine and checkout it was saved from. See the [session file format](reference/session-file.md).

### Workspaces {#workspaces}

A **`.lintcrux-workspace`** file captures the whole window instead: every open tab and pane. Use `File → Save Workspace As…` and `File → Open Workspace…`, or launch with `--workspace <file>`. The current workspace is also saved automatically and restored on the next launch while `Settings → General → Restore tabs on launch` is on; a change to that setting takes effect on the next launch, and turning it off keeps the saved workspace on disk. If a saved workspace stops the app from starting, launch with `--no-restore` (skip the restore this once) or `--reset` (clear the saved workspace and per-tab session state; settings are kept).

Open several projects in tabs with ++cmd+t++ / ++ctrl+t++, cycle them with ++ctrl+tab++ and ++ctrl+shift+tab++, and close a tab with ++cmd+w++ / ++ctrl+w++.

1. **Split the view to compare two projects.**

    Press ++cmd+backslash++ / ++ctrl+backslash++ to split the active pane to the right, then open a second project in the new pane.

2. **Move between and close panes.**

    Run **Focus Other Pane**, **Move Tab to Other Pane** and **Close Pane** from the `View` menu or the command palette (++cmd+shift+p++ / ++ctrl+shift+p++). These actions have no default keyboard shortcut.

Session and workspace files are desktop-only; the headless `lintcrux` binary accepts `--session` and `--workspace` and ignores them.

!!! note "Next steps"
    With a project configured and a run on screen, move on to [The violations dashboard](violations.md). For switching among many projects at once, see [multi-project workspaces](integrations.md#workspace) <span class="tier tier-pro">Pro</span>.
