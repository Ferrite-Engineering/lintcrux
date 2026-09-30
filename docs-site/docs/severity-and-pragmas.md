# Severity & pragmas

Not every rule matters equally to every project. LintCrux lets you reshape severity per rule and honours the inline pragmas your RTL already carries. This page covers both.

## Per-rule severity override {#override}

Open `Settings → Engines` and scroll to **Per-rule severity overrides**. Every rule in the [rule database](reference/rule-database.md) is listed with a severity dropdown — **Error**, **Warning**, **Note** or **Off** — starting at the rule's default. Promote a style note to a warning, or demote a noisy warning to a note; rows you have changed carry an *overridden* badge. The override applies to the active tab's project and takes effect the next time the engines run.

An override chosen in Settings is saved in the project's `.lintcrux` file — only that rule's entry changes, and the file keeps its relative paths — so it survives closing the tab and reaches your team and CI once you commit the file. If the file cannot be written, an error says so. The same map can be edited by hand; it is keyed by the engine-namespaced rule id:

```json
"severityOverrides": {
  "verilator/UNUSEDSIGNAL": "note",
  "verible/line-length": "none"
}
```

Values are `fatal`, `error`, `warning`, `note` or `none`. The headless binary applies the same map, and a CI job can add or replace overrides without touching the committed file through a [`--config` overlay](cli/invocation.md#config-overlay). When an administrator has turned on the audit log, each change made in Settings is recorded as a `severity.overridden` event — see [Administration](administration.md#audit).

## Turning a rule off {#disable}

**Off** in the dropdown (`none` in the file) does not stop the rule from being reported: the violation stays in the table, re-classified as *Unclassified*, and is still exported and counted. To keep Unclassified rows out of view, select the severity chips you do want to see.

To stop a check from running at all, configure the engine itself — Verilator `warnFlags` such as `"no-DECLFILENAME"`, a Verible `ruleProfile`, an Svlint `configPath`, or GHDL `warnFlags` in the project's [`perEngineOptions`](reference/project-file.md) — or suppress it in the source with a pragma.

## Severity colors {#colors}

Severities map to a traffic-light palette — dark red for fatal, red for errors, amber for warnings, blue for notes, grey for unclassified — applied to the severity icons in the table's Severity column and the Inspector. You can change each color under `Settings → Appearance → Color overrides → Severity` to match your house style or accessibility needs, and ship the result to your team as a theme pack — see [Appearance & themes](appearance-and-themes.md#overrides).

## Inline pragma waivers {#pragmas}

LintCrux honours **Verilator's source-embedded pragmas**:

```verilog
// verilator lint_off UNUSEDSIGNAL
logic unused_sig;
// verilator lint_on UNUSEDSIGNAL
```

The block-comment form (`/* verilator lint_off RULE */`) is also recognized. A `lint_off` without a matching `lint_on` extends to the end of the file, and each rule keeps its own independent range. What the pragma reader matches, exactly:

- **Named rules only.** The rule name must be upper-case letters, digits and underscores (`UNUSEDSIGNAL`, `WIDTHTRUNC`). A bare `// verilator lint_off` with no rule name is ignored by LintCrux.
- **Verilator findings only.** A pragma suppresses violations whose rule id is `verilator/<RULE>` in the same file and line range. It does not waive the same defect reported by Verible, Slang or any other engine.

A suppressed violation is hidden from the table, and the status bar counts it as *waived*. In the headless binary it is left out of the printed listing and of the `--exit-code` / `--fail-on-new-violations` gates, and counted as `suppressed` in the summary line. Inline pragma waivers are free in Open Core — they live in your RTL and need no LintCrux feature.

In a SARIF export a pragma-suppressed violation is still written — the record stays auditable — but it carries a SARIF `suppressions` entry of kind `inSource`, with the pragma as its justification, so a SARIF consumer can tell it from an open finding.

## How pragmas and managed waivers coexist {#coexist}

LintCrux supports both source-embedded pragmas (Open Core) and [managed waivers](waivers.md) <span class="tier tier-pro">Pro</span> — a version-controlled file separate from the RTL. When both could apply to the same violation, the **pragma takes precedence**: it is closest to the code, and the managed waiver is not consulted for a violation a pragma already suppressed. Either way the violation is hidden from the table and counted as waived; the [Waivers review screen](waivers.md#review) lists the managed waivers you have recorded.

!!! note "Next steps"
    For false positives that should be recorded with a reason rather than silenced in source, use [Managed waivers](waivers.md) <span class="tier tier-pro">Pro</span>.
