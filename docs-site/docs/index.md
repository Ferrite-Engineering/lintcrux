# Welcome to LintCrux

LintCrux is a multi-engine RTL lint aggregation and waiver-management dashboard for Verilog, SystemVerilog and VHDL. It runs Verilator, Verible, Slang, GHDL, Yosys and Svlint for you, adds its own clock-domain-crossing analysis, parses every engine's output, and unifies the results into one sortable, filterable table — with waivers, baselines, trend tracking and CI integration on top. This guide is written for people who run lint for a living: it is precise about what each feature does, the files involved, and the keys you will actually press.

!!! tip "New here?"
    Start with [Installation & first run](getting-started.md), then take the [interface tour](interface.md). If you already have a Vivado-style `.f` filelist or a FuseSoC core, jump straight to [Projects & engines](projects-and-engines.md) — both import directly. Prefer to learn by doing? The [Cookbook](cookbook.md) walks through complete workflows step by step.

## One dashboard, every engine {#multi-engine}

The status quo for RTL lint is a stack of terminal streams: run `verilator --lint-only`, then `verible-verilog-lint`, then `slang`, and read three output formats side by side. LintCrux runs every configured engine in one action, parses each engine's native output, and aggregates everything into a single virtualized table that stays responsive at tens of thousands of rows. The engines themselves stay exactly as they are — LintCrux invokes the copies installed on your machine and reads what they emit. You bring the RTL and the engines; LintCrux brings the dashboard.

## One app, four tiers {#tiers}

LintCrux ships as a single application. The free **Open Core** dashboard is fully featured on its own; **Pro** and **Enterprise** add capability on top without changing anything you already use, and **Education** grants the Pro feature set free to verified students and educators. This documentation covers all four. Wherever a feature requires a paid tier, a badge sits next to its name:

- **Open Core** — free and open, no account, no license key, no time limit. All seven engines (including structural clock-domain-crossing analysis), the unified table, the Inspector and source preview, click-to-source, per-rule severity overrides, inline pragma waivers, SARIF / JSON / CSV / HTML export, sessions and workspaces, receiving cross-probes, the read-only web viewer, and the headless `lintcrux` binary with its `--exit-code` and `--fail-on-new-violations` gates. Unmarked features are Open Core.
- <span class="tier tier-pro">Pro</span> — managed waivers, baselines & deltas, trend tracking and regression alerts, custom regex rules, saved filter presets and violation bookmarks, Verible auto-fix, lint result caching, multi-project workspaces, originating cross-probes, Pro clock-tree tracing for CDC, and the `lintcrux-pro` command line (`baseline`, `push-trends`).
- <span class="tier tier-enterprise">Enterprise</span> — the shared team trend database, the organization-wide waiver list, the multi-project rollup, the organization-wide CI gate threshold from a signed policy file, and the audit log.
- <span class="tier tier-edu">EDU</span> — every Pro feature, free for verified students and non-commercial educational use. The Enterprise features are not part of EDU.

!!! note "Beta builds, and what changes at 1.0"
    Through the 0.8.x public beta every tier is unlocked for everyone: the badges are there so you can see which tier a feature belongs to, but nothing is gated in those builds. From 1.0 the badges are load-bearing — Open Core stays free, with no account, no license key and no time limit, while a feature carrying a <span class="tier tier-pro">Pro</span> or <span class="tier tier-enterprise">Enterprise</span> badge needs a license key, entered under `Settings → License`. See [Tiers & licensing](https://edacrux.app/licensing) for the full picture, including how the Education tier and license keys work.

## How this guide is organized {#map}

- [Installation & first run](getting-started.md) — download for Linux, macOS and Windows; installing the lint engines; running your first lint; updates, issue reporting and usage statistics.
- [The interface](interface.md) — the docked layout, the toolbar and menu bar, the command palette, filter and sort controls, the status bar, and Settings.
- [Appearance & themes](appearance-and-themes.md) — the six built-in color presets, how the active preset drives light and dark, per-token color overrides, and theme packs.
- [Keyboard & mouse reference](keyboard-mouse.md) — every default shortcut, the actions that ship unbound, the violations-table gestures, and rebinding your own keymap.
- [Tiers & licensing](https://edacrux.app/licensing) — what each of the four tiers unlocks, how license keys work from 1.0, and how the Education tier works.
- [Projects & engines](projects-and-engines.md) — the `.lintcrux` project file, filelist and EDAM import, the engines and their binaries, sessions and workspaces.
- [The violations dashboard](violations.md) — the virtualized table, sorting and filtering, search, the Inspector and source preview, presets and bookmarks.
- [Severity & pragmas](severity-and-pragmas.md) — per-rule severity overrides and inline pragma waivers.
- [Managed waivers](waivers.md) <span class="tier tier-pro">Pro</span> — the Waive dialog, the version-controlled waiver file, the Waivers review screen, and expiration.
- [Baselines & deltas](baselines.md) <span class="tier tier-pro">Pro</span> — snapshot a baseline, classify New / Persisting / Resolved, the baseline diff, and gating CI on new violations.
- [Trends & regressions](trends.md) <span class="tier tier-pro">Pro</span> — per-run snapshots, the trend charts, the calendar heatmap, and regression alerts.
- [Clock-domain crossings](cdc.md) — structural CDC analysis in open core, and what Pro adds.
- [Exports & CI](exports-and-ci.md) — SARIF, JSON, CSV and HTML exports; headless CI runs with a real exit-code contract; lint caching and Verible auto-fix.
- [Team trend database](team-database.md) <span class="tier tier-enterprise">Enterprise</span> — the shared PostgreSQL trend store and how CI pushes to it.
- [Cross-probe & the suite](integrations.md) — cross-probe with WaveCrux, NetCrux and SimCrux; editor click-to-source; multi-project workspaces.
- [The web viewer](user-guide/web-mode.md) — the read-only SARIF viewer at app.lintcrux.app.
- [Administration](administration.md) <span class="tier tier-enterprise">Enterprise</span> — for the person deploying LintCrux across a fleet: the org-wide CI gate threshold, the shared waiver list, the rollup, and the audit events LintCrux records.
- [Cookbook](cookbook.md) — task-driven recipes: triage a run, lint a FuseSoC core, gate CI on new violations, track regressions, configure engines.
- Reference — the [command line](cli/invocation.md), the [project file](reference/project-file.md), the [session file](reference/session-file.md) and the [rule database](reference/rule-database.md).

## Conventions used in this guide {#conventions}

- Keyboard shortcuts are written for both platforms, macOS first: ++cmd+o++ / ++ctrl+o++. Where only one key is shown, it applies to all platforms.
- `Monospace` marks file names, rule IDs, engine flags, menu paths, and anything you type.
- A <span class="tier tier-pro">Pro</span> or <span class="tier tier-enterprise">Enterprise</span> badge beside a heading means everything under it requires that tier.
- LintCrux is desktop-first (Linux, macOS, Windows). The web build is a read-only SARIF viewer; where a surface is desktop-only, the text says so.
- A **Known issue** box describes how something behaves today when that differs from how it is designed to behave. Fixes are scheduled; the box goes away when the fix ships.

!!! note "Quick links"
    [Download LintCrux](https://lintcrux.app/download) · [Open source](https://edacrux.app/open-source) · [Pricing](https://lintcrux.app/pricing) · [Cookbook](cookbook.md)

LintCrux Open Core is licensed under the Apache License 2.0. Pro and Enterprise are commercially licensed by [Ferrite Engineering](https://ferriteengineering.com/).
