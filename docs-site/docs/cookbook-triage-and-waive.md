# Triage a run & waive false positives

You ran lint and got hundreds of findings. Most are real-but-known or outright false positives. This recipe walks from a raw run to a triaged table — sorting, filtering, inspecting, and recording waivers with a reason — so the next person sees only what matters.

- **Goal:** Turn a noisy first run into a triaged table where every remaining finding is real, and every false positive is waived with a justification.
- **Time:** About 10 minutes.
- **Tier:** Open Core to run, sort, filter and inspect. Waivers (steps 4–5) are <span class="tier tier-pro">Pro</span>.
- **You will use:** [The violations table](violations.md), the [Inspector](violations.md#inspector), and [managed waivers](waivers.md).

## Steps {#steps}

1. **Run every engine.**

    Open your project with ++cmd+o++ / ++ctrl+o++; the engines run as it opens (press ++f5++ to run them again). With no violation selected, the **Details** pane lists each engine's status — confirm each one says Completed rather than Failed or Binary not available.

2. **Sort and filter to the worst first.**

    Click the **Severity** column header to bring errors to the top. Use the severity chips to focus on Errors and Warnings, and the engine chips if you want to triage one engine at a time. For a specific rule, type its id into **Filter by rule or message…**, or press ++cmd+f++ / ++ctrl+f++ to search.

3. **Inspect a finding before you judge it.**

    Click a violation. The **Details** pane shows the message, the location, and the rule's tags and **Learn more** link; the **Source** pane shows the offending lines. If it is real, double-click the row (or click **Open in editor**) and fix it; if it is a false positive, move to the next step.

4. **Waive a false positive.**

    Right-click the violation and choose **Waive…**. The rule id, file path and line are prefilled; write a **Justification** — it is required — and optionally set an **Expires (optional)** date so the waiver gets re-reviewed later. Press **Waive**. The waiver is written to `.lintcrux-waivers.json` and the violation drops out of the table.

5. **Waive a rule that fires falsely all over a file.**

    When the same rule fires falsely many times in one file, clear the **Lines** field in the Waive dialog so the waiver covers that rule for the whole file, and give it a reason that explains the pattern. Each waiver covers one rule in one file, so repeat for each affected file.

6. **Confirm the table is clean.**

    Waived findings are hidden from the table, and the status-bar summary counts them as *waived* — check that what remains is the work that needs doing. Open `Tools → Review Waivers…` to confirm what you recorded.

## Where to go next {#next}

Commit `.lintcrux-waivers.json` (and `.lintcrux-waivers.audit.jsonl`) so your team shares the triage state, then make the gate permanent: set a [baseline](baselines.md) and follow [Gate CI on new violations](cookbook-baseline-ci.md).
