# Managed waivers <span class="tier tier-pro">Pro</span>

A managed waiver records a decision: "this finding is acceptable, here is why, and here is who said so." Unlike an inline pragma, it lives in a version-controlled file separate from your RTL, carries an audit trail, and can expire.

## The Waive dialog {#waive-dialog}

Right-click a violation in the table and choose **Waive…**. The **Waive violation** dialog opens for that violation with these fields:

| Field | Meaning |
|---|---|
| Rule ID | The rule being waived, taken from the violation. |
| File path | The file the waiver applies to, prefilled with the path the engine reported. |
| Lines | Prefilled with the violation's line. Enter `42` or `42-48`, or leave it blank to waive the rule for the whole file. |
| Justification | **Required.** Why this is acceptable. A waiver with no reason is not a waiver. |
| Author | Prefilled with your operating-system user name; editable. |
| Expires (optional) | A date after which the waiver lapses and the violation returns. |

**Waive** writes the waiver; the confirmation says how many active waivers the project now has. Each waiver covers one rule in one file, so waive each false positive in turn — a blank **Lines** field is the way to cover every occurrence of a rule in a file.

## The waiver file & audit log {#files}

Waivers are stored in `.lintcrux-waivers.json` in the project root — a plain, version-controllable file your whole team shares. Every addition, edit and deletion is also appended to `.lintcrux-waivers.audit.jsonl`, one JSON record per line, so there is a permanent, append-only history of who waived what, when, and why. Check both into git alongside your RTL.

On an Enterprise seat with a [team database](team-database.md), an organization-wide waiver list applies as well; a violation is waived if either list waives it — see [Administration](administration.md#waivers).

## Waivers in CI {#ci}

The Pro command line applies the same committed `.lintcrux-waivers.json` in your pipeline, the way the desktop app does, so a waiver a reviewer approved in the app does not fail the build. Applying managed waivers in CI is part of Pro, like the rest of this page: without a Pro licence the file is not applied, the violations it waives count toward the exit code, and the run says so on stderr. The free `lintcrux` binary applies inline pragma waivers only. See [Managed waivers in CI](exports-and-ci.md#waivers-in-ci) for the command and the licence a build agent runs as.

## Matching scope {#matching}

A waiver matches a violation when all of these hold:

- **Rule** — the waiver's rule id equals the violation's. Engine rule renames are tolerated through the rule-alias table, so a waiver written against a retired id (for example `verilator/UNUSED`) still matches the renamed rule.
- **File** — the waiver's file path equals the violation's file path exactly. There is no glob or directory matching.
- **Lines** — if the waiver has a line range, the violation's line falls inside it; a waiver without one covers the whole file.
- **Not expired** — the waiver has no expiry date, or it has not passed.

Choosing the right breadth matters: a line-range waiver stops matching if the finding moves off those lines, while a whole-file waiver covers every occurrence of the rule in that file — including ones added later.

## The Waivers review screen {#review}

Open the review screen with `Tools → Review Waivers…` or the command palette. It lists every waiver for the active project — rule, file, lines, reason, author and a status badge (Active, Expired, or *Expires in N d*) — with filter chips **All**, **Active**, **Expired** and **Expiring soon**. Each row can be copied as JSON or deleted.

1. **Open the review screen.**

    Choose `Tools → Review Waivers…`. The list opens on **All**.

2. **Find waivers that need attention.**

    Switch to **Expiring soon** to see waivers that lapse within the next 14 days, or **Expired** to see ones whose findings have already returned to the table.

3. **Act on a waiver.**

    **Edit** opens the waiver in the same form it was created with, so you can extend or remove its expiry, narrow or widen its line range, or update the justification. The waiver keeps its id and creation date, and the change is recorded in the audit log as a modification. **Delete** a waiver when the underlying issue is fixed or the decision no longer stands — the violation is reported again and the deletion is recorded in the audit log. **Copy as JSON** puts the waiver record on the clipboard.

## Expiration & re-review {#expiration}

An expired waiver stops matching: the violation it covered reappears in the table on the next run. When waivers have expired or are about to, a banner above the table says so (*1 waiver has expired*, *2 waivers expire soon*), with **Review waivers** to open the review screen and **Dismiss**. This is deliberate — waivers are decisions with a shelf life, and expiry forces a periodic re-review rather than letting suppressions accumulate forever.

!!! note "Next steps"
    Walk through a full triage-and-waive pass in the [Cookbook recipe](cookbook-triage-and-waive.md). To gate CI on *new* findings only, set up a [baseline](baselines.md) <span class="tier tier-pro">Pro</span>.
