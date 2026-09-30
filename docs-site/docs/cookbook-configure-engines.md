# Configure which engines run

Out of the box, LintCrux runs every engine that has a source file in a language it supports. But you will often want to leave one out, pin a binary to match CI, or pass an engine its own options. This recipe walks the engine configuration end to end so a run does exactly what you intend.

- **Goal:** A project whose enabled engines, binaries and per-engine options exactly match what you want lint to do.
- **Time:** About 5 minutes.
- **Tier:** Open Core — engine configuration is free.
- **You will use:** [Per-engine configuration](projects-and-engines.md#per-engine), [Engine binaries](projects-and-engines.md#binaries), and the [diagnostics](interface.md#diagnostics).

## Steps {#steps}

1. **Choose the engines in the project file.**

    Open the project's `.lintcrux` file in your editor and set `enabledEngineIds` to the engines you want — for example `["verilator", "verible", "slang"]` on a pure-SystemVerilog design. An empty or missing list means *every* engine, so list only the ones you have installed. Engines left out never launch and never produce findings. For a one-off headless run, `--engine <id>` (repeatable) does the same without editing the file.

2. **Pin the binaries.**

    Press ++cmd+comma++ / ++ctrl+comma++ and open `Settings → Engines`. Under **Engine binary paths**, each engine has **Auto-detect** (search `PATH`), **Bundled** (no engines ship with LintCrux, so this falls back to `PATH`) and **Custom**. Choose **Custom**, enter the **Binary path** of the exact build your CI uses, and press **Probe** to confirm the version it reports. The choice is saved for the next launch. The headless binary does not read Settings; for CI and scripts, use `--verilator-path` and its siblings. The CDC engine has no row: it runs the binary the **Yosys check** row selects.

3. **Set per-engine options.**

    Add the options each engine needs under `perEngineOptions` in the `.lintcrux` file — Verilator `warnFlags` and `extraOptions`, a Verible `ruleProfile` or `rulesConfigSearch`, an Svlint `configPath`, GHDL `warnFlags`. Defines, include paths and the top module are project-level keys. Because all of this lives in the project file, the whole team runs the same configuration. The keys are listed in the [project file reference](reference/project-file.md).

4. **Re-run and check what ran.**

    Save the file, close the project's tab (++cmd+w++ / ++ctrl+w++) and open the project again: LintCrux reads the project file when it opens a project, and opening a project that is already open only focuses its tab. The engines run as the project opens. With no violation selected, the **Details** pane lists each engine's status. Open `Tools → Tab Diagnostics…` (++cmd+shift+i++ / ++ctrl+shift+i++) to confirm each engine's binary path, version and duration.

## Where to go next {#next}

With the right engines running, reshape what counts as a problem on [Severity & pragmas](severity-and-pragmas.md), then triage the result with the [Triage a run](cookbook-triage-and-waive.md) recipe.
