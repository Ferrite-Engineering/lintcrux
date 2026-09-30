# Track regressions over time

Counts drift. A refactor lands, a new module arrives, and one morning the warning total is up 40%. This recipe uses the trend charts and regression alerts to catch a spike, find the rule behind it, fix or waive it, and confirm the line comes back down.

- **Goal:** Notice a regression in the trend, identify the rule and the day that introduced it, act on it, and verify the recovery.
- **Time:** About 8 minutes.
- **Tier:** <span class="tier tier-pro">Pro</span> — trend tracking and regression alerts are Pro.
- **You will use:** [Trends & regressions](trends.md), the [filters](violations.md#filter), and [waivers](waivers.md).

## Before you start {#before}

Trend charts need a history. If this is your first day with LintCrux, run lint a few times (or add `lintcrux-pro push-trends` to CI for a run or two) so there is a line to read. History is kept for 90 days and 1,000 runs by default — see [retention](trends.md#snapshots).

## Steps {#steps}

1. **Open the project trend.**

    Choose `Tools → Show Project Trend Chart…` (or type "trend" into the command palette with ++cmd+shift+p++ / ++ctrl+shift+p++). Look for an upward step in the total, and hover the points on either side of it to read the counts.

2. **Read the regression banner.**

    If LintCrux already flagged the jump, a banner above the table describes it — a *sudden spike*, a *new persistent rule*, or *severity-class drift* — and names the rule when there is one.

3. **Pin the day on the heatmap.**

    Choose `Tools → Show Calendar Heatmap…` and switch to the 30-day window. The darker cell is the day the regression landed; hover it to see the violation and run counts for that day.

4. **Drill into the rule.**

    Click **Show trend** on the banner, or choose `Tools → Show Rule Trend Chart…` and type the rule id, to see how that rule's count moved. Back in the table, filter by the rule id with **Filter by rule or message…** to see exactly where it now fires.

5. **Fix or waive.**

    For each new finding, either double-click it to open it in your editor and fix it, or — if it is acceptable — right-click it, choose **Waive…** and record a reason.

6. **Dismiss and watch it recover.**

    If the change was deliberate, **Dismiss** the alert in the banner — it is acknowledged and stops nagging, while a genuinely new alert still appears. Re-run lint (++f5++); the next data point should bring the trend line back down, confirming the fix took.

## Where to go next {#next}

Make the recovery stick by gating CI so the same regression cannot return — [Gate CI on new violations](cookbook-baseline-ci.md). To pool trends across the whole team, see the [team trend database](team-database.md) <span class="tier tier-enterprise">Enterprise</span>.
