# Use in VS Code

The **LintCrux extension** shows your lint results where you write RTL: as squiggles in your Verilog and VHDL and as entries in VS Code's Problems panel.

It installs from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.lintcrux) and from [Open VSX](https://open-vsx.org/extension/ferrite-engineering/lintcrux), which is where Cursor, Windsurf, VSCodium and Theia install from. To install all four EDACrux extensions at once, install the [EDACrux Suite](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.edacrux) pack.

## Point it at a results file { #results }

The extension reads a LintCrux results file; it never runs the linter itself. Produce the file however you already run LintCrux — locally, in a pre-commit hook, or in CI — for example:

```bash
lintcrux rtl/*.sv --sarif lintcrux.sarif
```

By default the extension reads `lintcrux.sarif` in each workspace folder; set `edacrux.lint.resultsPath` to read a different file. SARIF and the flat JSON export (`--export json --out <path>`) both work, and the format is detected from the file's contents rather than its extension. See [Exports & CI](exports-and-ci.md) and the [command-line reference](cli/invocation.md) for the options.

Diagnostics update on their own when the results file or the waiver file changes. If you point `edacrux.lint.resultsPath` at an absolute path outside the workspace, run **EDACrux: Refresh Lint Diagnostics** after each new run instead.

## Waive from the editor { #waivers }

A quick fix on a violation files a waiver for that line, or for that rule in that file. The waiver is written to `.lintcrux-waivers.json` in the project root — the same file [managed waivers](waivers.md#files) use — and the violation disappears from the editor straight away. LintCrux Pro applies the same waivers in the desktop app. Set `edacrux.lint.waiverAuthor` to control the author recorded on the waiver; left empty, it uses your operating-system user name.

## Triage in the desktop app { #desktop }

The extension shows the current results; it is not a triage dashboard. What is new since the last run, which waivers are in force and how counts are trending need the run history the desktop app keeps. **EDACrux: Triage This Design in LintCrux Desktop** opens the design there.

Your VS Code window also joins the suite's cross-probe network as **one** peer, however many of the EDACrux extensions you install: a desktop app can ask it to open a source file at a line, and **EDACrux: Send Selection to Crux App** / **EDACrux: Highlight Selection in Crux App** send the identifier under your cursor to a running EDACrux app. See [Cross-probe & the suite](integrations.md).

## Commands, settings and telemetry { #reference }

The extension's listing on the [Marketplace](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.lintcrux) has the full list of commands and settings. The extension sends usage statistics only while VS Code's own telemetry setting is on.
