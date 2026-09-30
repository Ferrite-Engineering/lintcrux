# Trends & regressions <span class="tier tier-pro">Pro</span>

A single run tells you where you are; the trend tells you where you are going. LintCrux records a snapshot of every run and charts how your violation counts move over time, with automatic alerts for regressions you would otherwise miss.

## Per-run snapshots & retention {#snapshots}

Each completed run writes its non-suppressed violations as data points to a local SQLite database, `trends.db`, in the `lintcrux` folder of LintCrux's application-support directory. The data stays on your machine; sharing trends across a team is the Enterprise [team trend database](team-database.md). A CI job can record runs too, with [`lintcrux-pro push-trends`](exports-and-ci.md#ci-setup).

How much history is kept is set in `Settings → Trend Retention`: **Maximum age (days)** (90 by default), **Maximum runs retained** (1,000 by default), either of which can be switched to never delete, and a **Prune strategy** — **Oldest first** or **Sparse history**. The section also shows storage stats (data points, distinct runs, oldest and newest) and an **Apply now** button that prunes immediately.

## Trend charts {#charts}

Three charts are available from the `Tools` menu and the command palette:

- **Project Trend** (`Tools → Show Project Trend Chart…`) — total violations per run over time.
- **Rule trend** (`Tools → Show Rule Trend Chart…`) — one rule's count per run; type the engine-namespaced rule id (for example `verilator/WIDTHTRUNC`) and pick a 7, 30 or 90-day window.
- **Severity Drift** (`Tools → Show Severity Drift Chart…`) — the error / warning / note mix over time.

1. **Open a chart.**

    Choose `Tools → Show Project Trend Chart…`, or type "trend" into the command palette.

2. **Read the movement.**

    A rising line is accumulating debt; a falling line is a cleanup landing. Hover a point to see the exact count for that run.

## The calendar heatmap {#heatmap}

`Tools → Show Calendar Heatmap…` shows lint activity day by day as a contributions-style grid over a window you choose — the last **30 days**, **90 days** (the default) or **year**. Hover a day to see how many violations were recorded across how many runs. It is the fastest way to spot the day a regression landed: a darker cell jumps out.

## Regression detection {#regressions}

After each run LintCrux scans the recent trend and raises a banner above the table when it detects one of three kinds of regression:

| Detector | What it catches |
|---|---|
| Severity-class drift | A severity's count up 25% or more over the last 3 runs compared with the 10 before them. |
| New persistent rule | A rule that fired in each of the last 3 runs after being quiet in the 5 before. |
| Sudden spike | A rule whose count in this run is at least 3× its recent average. |

Each alert in the banner offers **Show trend**, which opens the rule trend chart on the offending rule (or with an empty rule field for a severity-drift alert), and **Dismiss**. Dismissing acknowledges that alert and remembers it, so a deliberate change does not keep nagging while a genuine new surprise still gets your attention.

!!! note "Next steps"
    Walk through catching and clearing a spike in the [Track regressions over time](cookbook-track-regressions.md) recipe. To share trends across a team, see the [team trend database](team-database.md) <span class="tier tier-enterprise">Enterprise</span>.
