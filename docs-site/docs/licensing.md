# Tiers & licensing

Licensing terms are the same for all four EDACrux products, so they live in one place on the suite site: [edacrux.app/licensing](https://edacrux.app/licensing).

For what each tier adds in LintCrux, see [One app, four tiers](index.md#tiers).

## Educational license {#edu}

An Educational license is for non-commercial teaching, learning and research. While LintCrux runs on one, it says so in two places.

**The status bar.** The right end of the status bar shows the EDU chip, *Non-commercial use* and the email address the license was issued to. Hover over it for the terms and the date the license ends, or click it to open `Settings → License`. No other tier shows anything there.

**The HTML report.** An HTML report exported under an Educational license ends with the line *Made with LintCrux Educational · Non-commercial use only*, in the language LintCrux runs in. The line never carries your address. A headless run marks its HTML report the same way, in English, when the license it resolved (with `--license-file` or `LINTCRUX_LICENSE_FILE`, see [the licence a CI agent runs as](team-database.md#ci-license)) is an Educational one; the open-core binary reads no license and writes no mark.

Data formats are never marked. SARIF, JSON and CSV exports, waiver and baseline files, project, workspace and session files are written exactly as on every other tier, so the tools that read them back see no difference.
