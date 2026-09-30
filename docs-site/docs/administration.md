# Administration <span class="tier tier-enterprise">Enterprise</span>

The org-wide CI gate threshold, the shared waiver list, the multi-project rollup, and the audit events LintCrux records. This page is for the person deploying LintCrux across a fleet — the rest of these docs are for the engineer triaging violations, and you may never open the application at all.

!!! note "The file itself is documented once, for the whole suite"
    One `.crux-policy.json` configures all four EDACrux products. Where it goes on each platform, how you sign it, discovery order, precedence and the full key table live in [the policy file reference](https://edacrux.app/policy-reference); the rollout procedure is [Deployment](https://edacrux.app/deployment). This page covers only what LintCrux's own keys do.

## LintCrux's policy keys {#keys}

All under `products.lintcrux`.

| Key | What it does | State |
|---|---|---|
| `ciGateThreshold` | The organization-wide ceiling on surviving violations. [Below.](#ci-gate) | In force |
| `teamDatabaseSubmitter` | Who pooled runs are attributed to in the [shared trend database](team-database.md#submitter). | In force |
| `ruleSeverityOverrides` | Intended as org-wide rule-severity overrides. | **Reserved** — nothing reads it |
| `mandatoryEngines` | Intended to require particular engines in every run. | **Reserved** — nothing reads it |

**Four keys, and that is the whole list.** `customRuleMetadata` was listed here until 2026-09-19 and was **removed from the schema**, because no release ever registered it: it was a key this page invented and nothing has ever parsed. `crux-policy lint` now reports it as unknown — *"unknown to this version of the CLI… check the spelling"* — so a file carrying it fails your own linter. Delete it from any policy file that has it.

!!! note "What Reserved means, precisely"
    The schema knows the key and LintCrux parses it without complaint. **Nothing consumes it, so writing it changes no behaviour.** A reserved key and a working key look identical in a file that validates and deploys without error, which is exactly why they are called out — silence here would send you to file a bug against a product doing exactly what it is built to do.

    **Severity policy is per project today**, in the `.lintcrux` file committed with the RTL — see [Severity & pragmas](severity-and-pragmas.md). If a fleet-wide severity policy is what you need, [tell us](mailto:support@ferriteengineering.com): the key already exists, so what is left is the feature.

## CI gating: what is free and what is Enterprise {#ci-gate}

!!! tip "The plain gates are free, at every tier"
    `lintcrux --exit-code` and `lintcrux --fail-on-new-violations` ship in the open-core headless binary. **A team gating its own pull requests needs no licence from us.**

What Enterprise adds is the **organization-wide threshold**: a number you sign into `.crux-policy.json`, which every project in the fleet is measured against when it runs through `lintcrux-pro`.

```json
"products": {
  "lintcrux": {
    "ciGateThreshold": { "value": 0, "locked": true }
  }
}
```

The value is a whole count of surviving (non-suppressed) violations; `0` means none may survive. A configured threshold applies on every `lintcrux-pro` run without any flag — an administrator's ceiling is not something a pipeline opts into.

**There is deliberately no command-line flag for it.** A number a pipeline can pass is a number a pipeline can raise, which would make it a preference rather than a policy. The open-core `lintcrux` binary never populates the threshold: open core owns the mechanism that honours a ceiling, and only a licensed build knows what the ceiling is.

### Exit codes {#exit-codes}

| Code | Label | Meaning | Tier |
|---|---|---|---|
| `0` | clean | Nothing to fail on — or findings present with no gate requested. A bare `lintcrux project.lintcrux` is a reporting command, not a gate. | free |
| `1` | violations | `--exit-code` was passed and at least one non-suppressed violation survived. | free |
| `2` | new-violations | `--fail-on-new-violations` was passed and at least one violation is absent from the baseline. Outranks `1`, so a job can branch on regression versus pre-existing debt. | free |
| `3` | run-failed | An engine failed, timed out or was unavailable; no engine had a compatible source; the `--config` overlay was malformed; the baseline was corrupt; or the export could not be written. **The violation count printed alongside this is not trustworthy.** Outranks every other code. | free |
| `4` | over-threshold | The organization's `ciGateThreshold` is configured and the surviving count exceeds it. **Outranks 1 and 2.** | Enterprise |
| `64` | usage-error | Bad command line — unknown flag, missing value, a positional that is neither a project nor a lintable source file — or a project file that could not be loaded. | free |
| `65` | data-error | `--import-filelist` or `--import-edam` could not convert its input. | free |

**Why `4` is separate from `2`, and why it wins.** Code `2` says "you added these; take them back out" — it is the team's own gate against its own baseline. Code `4` says "this project is over the organization's budget", which may be nobody-on-this-PR's fault and may need a conversation rather than a revert. Collapsing them into one number would leave a developer reading a CI log unable to tell which of those they are looking at.

### Two behaviours to know before you deploy a ceiling {#gate-failure-modes}

- **A policy file that will not verify yields no threshold**, and that is the safe direction rather than the strict one. A tampered or corrupt file must not be able to *invent* a ceiling: failing a build on a number nobody signed is worse than failing to enforce one somebody did, because the second shows up on the next passing run and the first looks like the linter is broken.
- **A threshold on a build whose licence does not include it says so, on stderr, every run.** It does not silently ignore it. An administrator who signed a ceiling into the fleet and finds a pipeline sailing past it needs to know the licence is why — silence there is indistinguishable from a threshold that was never set, and the two need completely different fixes. The plain gates are unaffected.

## The shared waiver repository {#waivers}

An organization-wide waiver list in [your own PostgreSQL](team-database.md) — the same endpoint, the same credential and the same handshake as the shared trend store, in an `org_waivers` table. You provision one database, and which of its tables a given feature reads is not something you should have to know.

!!! tip "It does not replace .lintcrux-waivers.json"
    **Both run.** The per-project file committed with the repository answers "who waived this rule *here*" for the team that owns the RTL, reviewable in a pull request, working with no database anywhere. The org list answers "what has the organization decided applies everywhere".

    **A violation is waived if either list waives it.** That is a union, not a precedence: an organization-wide exception cannot be revoked by a project file, and a project's own justified waiver is not ignored because the org list did not anticipate it.

Waiving a violation from the desktop app always writes to the project's own file. The organization's list has its own editor — **Organization-wide waivers**, under `Settings → Team Database` beneath the rollup, with **New waiver**, **Edit**, **Delete** and **Refresh**. Until a shared database is connected it says so rather than offering an empty table.

**That separation is deliberate, not a missing checkbox.** Waiving something in front of you is a project decision; deciding it applies everywhere is a different decision, usually made by a different person, and a checkbox on the **Waive…** dialog would erase exactly that distinction. Org waivers are entered by rule and path, because there is no violation in front of you to pre-fill from. They record to the suite audit log only, never into whichever repository happened to be open.

**An unreachable org list degrades to "the project's own waivers still work"** — unlicensed, unconfigured, no keyring, unreachable, schema refused: every one of those resolves to the local behaviour rather than to an error in front of a lint run.

### The approval workflow is not built, deliberately {#waiver-approval}

There is no `status`, no approver and no approved-at — not in the schema and not in the code. An approval workflow is shaped by *your* process: who approves, what expiry does, whether a rejection is recoverable. One guessed ahead of a real customer becomes the thing every later customer has to be talked out of. Adding it later is an additive migration, which is the case the schema discipline exists for. [Start that conversation](mailto:support@ferriteengineering.com) if it is a requirement.

## The multi-project rollup {#rollup}

Every project in the shared database in one read-only view, under **Across the organization** in `Settings → Team Database`, with **Refresh**:

- **Projects — worst trend first** — each project's latest run, its violation count, the change from its previous run, and how many runs it has pooled: which repository is trending worst this sprint.
- **Rules firing across the most projects** — each rule's spread across projects' latest runs. **A rule that fires everywhere is usually a rule that is mis-tuned for this organization**, not one everyone is ignoring.

How it is built:

- **Rendered in the desktop app. No web app, nothing hosted.** Every engineer already has a client that can reach your database; a dashboard would be a second artefact to build, host, authenticate and keep alive in order to render a query this one already runs.
- **Read-only, and structurally so.** Every statement is a `SELECT`. The rollup reads across projects this machine has never opened, and a view with that reach must not be able to write.
- **Projects are ordered by change, not by count**, and the rules table counts each project's latest run once — so the loudest rule is not simply whichever one fires in your busiest repository.
- Projects are identified by the path the client that pushed them recorded, not by a prettier invented label: two checkouts of one repository would otherwise look like two projects.

## Audit events LintCrux records {#audit}

Turned on with `suite.audit.path`, suite-wide. The envelope, the format, rotation and failure behaviour are in [the audit log reference](https://edacrux.app/audit-log). LintCrux registers six kinds:

| Kind | When | Payload |
|---|---|---|
| `waiver.created` | A managed waiver is added — a project waiver, or one made in the [organization-wide panel](#waivers). | `waiverId`, `ruleId`, `filePath`, `author`, `reason` |
| `waiver.modified` | A managed waiver is edited in place, with **Edit** on the waiver review screen or in the organization-wide panel. | as above |
| `waiver.deleted` | A managed waiver is removed. | as above, without `reason` — a removed waiver has no justification to record, and an empty string would read as one |
| `severity.overridden` | A rule's severity override is set or removed in `Settings → Engines`. | `ruleId`, `from`, `to`, `project` |
| `engine.config.changed` | An engine is repointed, or every binary override is cleared. | `engineId`, `source` — **which engine, never the path** |
| `baseline.rebased` | A baseline is promoted *or* cleared. Both, told apart by `action`: clearing un-freezes every violation the baseline held, which is the same class of event as promoting a new one. | `action`, `projectPath`, `baselineId`, `previousBaselineId`, `frozenCount`, `author` |

### The per-project audit trails still run {#audit-both}

LintCrux keeps writing `.lintcrux-waivers.audit.jsonl` and `.lintcrux-baseline.audit.jsonl` beside the project. **The org-wide log does not replace them, and both fail independently.** The file committed with the repository answers "who waived this rule here" in the team's own history, reviewable in a pull request; the org-wide log answers "what happened on this machine" for whoever runs the log shipper.

### One place a path is recorded {#audit-paths}

The suite's rule is that an audit payload carries no design source path — a path carries a username and a project code name, in a file your log shipper reads. **The waiver events are the deliberate exception**: they record the source file the waiver applies to, because a waiver without its file does not answer the question the event exists to answer. Engine paths are still withheld; `engine.config.changed` records which engine, by id.

## Managed installs and updates {#packaging}

**A managed install does not update itself.** An application installed by MSI, `.deb` or `.rpm` will not offer an in-app update and will not nag. That behaviour outranks every policy key, including `suite.updateChannel`, because it describes how the application was installed rather than what you configured.

!!! tip "See also"
    [Team trend database](team-database.md) for the connection, TLS and schema handshake · [Policy file reference](https://edacrux.app/policy-reference) · [Audit log](https://edacrux.app/audit-log) · [Deployment](https://edacrux.app/deployment) · [The end-to-end administrator workflow](https://edacrux.app/for/devops-engineers) · [Exports & CI](exports-and-ci.md) for the pipeline side
