# Rule database

The rule database lives at `lib/data/rules/<engineId>.json` in the
LintCrux source tree, one file per engine. Each file lists engine-local
rule ids with a default severity and optional tags, plus a help link: a
per-rule `helpUrl`, or a file-level `helpBaseUrl` that LintCrux turns
into `<helpBaseUrl>#<rule id>`.

The desktop inspector renders the rule metadata from the database —
tags become chips and the help URL becomes a **Learn more** link — and
the Rules panel and the `Settings → Engines` severity-override list are
built from it. A violation whose rule is not in the database still
shows the engine's own message; it just has no tags or link.

| File | Rules | Source of the ids |
| --- | --- | --- |
| `verilator.json` | 123 | Verilator warning codes, checked against 5.050 |
| `verible.json` | 61 | `verible-verilog-lint --generate_markdown` |
| `slang.json` | 246 | slang 11.0 `-W` warning names |
| `svlint.json` | 159 | `svlint --example` on 0.9.5 |
| `ghdl.json` | 38 | `ghdl help-warnings` on 6.0.0 and 5.1.1 |
| `yosys.json` | 10 | LintCrux's own ids — Yosys does not name its checks |
| `cdc.json` | 8 | First-party CDC rules — every id the CDC engine emits |

The database is community-extensible — pull requests adding or
correcting rule metadata are welcome. `lib/data/rule_aliases.json`
alongside it maps retired rule ids to their current names (for example
`verilator/UNUSED` → `verilator/UNUSEDSIGNAL`).

## Rule ids are the engine's own vocabulary

A rule id must be exactly the identifier the engine emits, because that
is the key violations are looked up under. In practice that means the
engine's *option* name, not its internal diagnostic class name:

| Engine | Rule id spelling | How to enumerate |
| --- | --- | --- |
| Verilator | `UNUSEDSIGNAL` | `verilator --help` warning list |
| Verible | `no-tabs` | `verible-verilog-lint --generate_markdown` |
| Slang | `unused-variable` | `-W` option names; slang rejects unknown ones |
| Svlint | `style_semicolon` | `svlint --example` |
| GHDL | `unused` | `ghdl help-warnings` |
| Yosys | `undriven-wire` | the message-pattern table in `YosysCheckEngine` |

Everywhere else — the violation table, `severityOverrides`, sessions,
and the JSON / CSV / HTML exports — a rule id is namespaced by engine
(`verilator/UNUSEDSIGNAL`). SARIF output strips the prefix, because each
SARIF run already names its engine in `tool.driver.name`.

Several files carry a `verifiedAgainst<Engine>Versions` field naming the
releases their rule ids were checked against. Keeping those honest
matters beyond metadata: the curated
[rule profiles](project-file.md#rule-profiles) are validated against the
Verible file, and a rule name Verible does not have makes the engine
exit non-zero having linted nothing.

The check is mechanical for the engines that reject unknown names — pass
every id in the file back to the binary and see whether it complains:

```sh
# Slang: prints "unknown warning option '-Wfoo'" for anything it lacks.
slang -q $(jq -r '.rules[].id | "-W" + .' lib/data/rules/slang.json) empty.sv

# GHDL: exits non-zero with "unknown warning identifier: foo".
ghdl -a --warn-<id> empty.vhd
```
