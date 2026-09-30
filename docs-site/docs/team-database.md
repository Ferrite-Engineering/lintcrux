# Team trend database <span class="tier tier-enterprise">Enterprise</span>

A shared PostgreSQL trend history that *you* own, fed by the CI pipeline you already run. Reading it back in every engineer's desktop app is planned for 1.1. Nothing is hosted by us, no account or cloud service sits in the path, and lint data never leaves your network. This page is the database itself — connection, credentials, schema, and how CI pushes to it. The org-wide waiver list and the rollup that read the same database are on [Administration](administration.md).

!!! note "What it takes to run one"
    The shared database is Enterprise: the desktop app reads its licence from `Settings → License`, and a headless run is told which licence it holds — see [the licence a CI agent runs as](#ci-license). Without one the push is refused and the run still passes. See [Tiers & licensing](https://edacrux.app/licensing).

## Why trends, and why shared {#why}

Trend data is the one thing that genuinely benefits from being pooled: a single shared history of how the organization's RTL quality moves, written by every CI job. Project files, waiver files, baselines, bookmarks, filter presets and workspace metadata are deliberately **not** synced through the database — they already live in version control next to the RTL, which is the right system of record for them, and git already shares them through review and branching.

Waivers are the exception, and they are additive rather than a replacement: an organization-wide waiver list lives in this same database, and the per-project `.lintcrux-waivers.json` committed with each repository keeps working exactly as before. See [Administration](administration.md#waivers).

## The hybrid model {#hybrid}

**Hybrid, never remote-only.** Each client keeps the fast local SQLite trend store it already has, and additionally pushes completed runs to your PostgreSQL. Local charts stay instant because they keep reading SQLite; the PostgreSQL side accumulates a durable team-wide history.

The consequence worth deploying on: **a laptop on a plane keeps working exactly as it did before the feature existed.** The interactive experience is never coupled to a network round-trip, and an unreachable database degrades to "your own trends still work" rather than to an error in front of a lint run. Retention settings apply to each machine's local store only; LintCrux never deletes from the shared database.

## Connecting {#connecting}

You provision the server. It is whatever PostgreSQL you already operate — on premises or in your own cloud — and it is almost always TLS-terminated. Configure it in `Settings → Team Database`: **Host**, **Port**, **Database**, **Role**, **Password** and **Connection security**, then **Test connection** and **Save**.

### TLS, named for what it does {#tls}

| Setting | In `LINTCRUX_TEAM_DB_URL` | What it means |
|---|---|---|
| **Encrypt and verify the certificate** | `sslmode=verify-full` (the default) | **The default, and the only choice that resists an active attacker.** Encrypted, with the server's certificate verified against the platform's trust store. |
| **Encrypt without verifying the certificate** | `sslmode=encrypted-only` | Encrypted, certificate *not* verified. For an internal CA that is not yet in the platform trust store. It is a real weakening — anyone who can reroute the connection can read and change every query — so it is an explicit choice with a warning in front of you, and **never a silent fallback** when verification fails. |
| *(not offered in Settings)* | `sslmode=disable` | **Loopback only**, and refused for any other host. It exists for a throwaway container on `127.0.0.1`. Off the loopback interface it would send a password and a team's entire lint history across a network in the clear. |

!!! note "A support answer worth having ready"
    Certificate verification is done by the operating system's trust store — Keychain on macOS, the certificate store on Windows, the system bundle on Linux. So **the same server and the same build can verify on one machine and fail on another** when your internal CA is installed in some of your images and not others. That is a fleet-imaging question rather than a LintCrux bug, and it is the first thing to check when one engineer cannot connect and everybody else can.

### Where the credential lives {#credentials}

- **In the app** — platform secure storage: Keychain, Credential Manager, or libsecret. **Never a preferences file, and never a project file.** A credential in a file next to the RTL ends up in the repository.
- **In CI** — the `LINTCRUX_TEAM_DB_URL` environment variable, a `postgres://role:password@host:port/database` URL that carries the role and its password together.

**`--password` is rejected by name, and the value is never echoed.** A password on a command line lands in the CI log, in the job definition somebody copied it from, and in the shell history of whoever tested it locally. The CLI refuses the flag and says to use the environment variable instead. An unparseable URL is an error, and the error never repeats the value.

On Linux, secure storage needs a running secret service such as gnome-keyring; without one, the settings panel says the password cannot be stored. On a headless CI box there is usually none — which is why CI uses the environment variable rather than the keyring.

### Creating the tables {#provisioning}

**Nothing is created implicitly.** Provisioning is an explicit administrative action — **Initialize database** in the Team Database settings panel, which creates the tables or brings an older schema up to date — and connecting never creates anything on its own. So the first engineer to type a colleague's hostname into the connection panel does not silently provision it, and a typo in a hostname stays distinguishable from a correct one.

## The schema handshake, and why a colleague on an older build still works {#schema}

*N* engineers and a CI fleet, each on whatever build they last installed, all connect to one database. Heterogeneous clients are the design here rather than the accident, so a rule that stopped everyone working until the whole team updated would defeat the feature.

```
database epoch  != client epoch     refuse, both directions
database version <  client needs    refuse, and name the upgrade action
database version >= client needs    WORK — this is the ordinary case
no schema at all                    refuse, and name the initialize action
```

**A database ahead of the client is not an error.** Migrations are additive-only, so a newer schema is this schema plus columns and tables an older build never names — every statement it issues still resolves. Treating a newer database as skew would turn each schema bump into a flag day for the whole organization.

The *epoch* is the escape hatch that keeps that promise honest. Additive-only is a rule a future change could break; if it ever has to be broken, the epoch bumps and every client refuses in both directions rather than issuing statements against a shape it does not understand.

Submitter attribution is nullable, so an anonymous CI writer can push. **An unattributed run is honest; a fabricated attribution is a name in a dashboard next to a failure that person never saw.**

## Pushing from CI {#ci}

```bash
export LINTCRUX_TEAM_DB_URL='postgresql://lintcrux:…@db.example.internal/lintcrux'
export LINTCRUX_ORIGIN_ID='ci-runner-07'     # required — see below
export LINTCRUX_SUBMITTER='ci-nightly'

lintcrux-pro push-trends project.lintcrux
```

`push-trends` runs the lint, records the run's non-suppressed violations in the local SQLite trend store (`--db <path>` names that file), and — when `LINTCRUX_TEAM_DB_URL` is set — pushes the same run to the shared database. The local write lands first and never depends on the shared one. With no URL set, nothing is attempted and nothing fails.

!!! warning "`LINTCRUX_ORIGIN_ID` is required once a URL is set"

    **It is not optional, and leaving it out is refused rather than guessed.** With `LINTCRUX_TEAM_DB_URL` set and `LINTCRUX_ORIGIN_ID` unset or empty, the push exits **`6`** and nothing reaches the shared database:

    ```
    lintcrux-pro: this installation has no id, so a pushed run could collide
    with another agent. Set the LINTCRUX_ORIGIN_ID variable to a stable string
    per CI runner or per pipeline. Nothing was pushed; the local trend
    database is unaffected.
    ```

    A generated id would defeat the point — the id exists so two agents starting a run in the same millisecond do not collide on the run key, and an id that changes on every run collides exactly as often. Pick a stable string per runner or per pipeline (`ci-runner-07`, `nightly-soc-lint`) and set it beside the URL. The local trend store is written either way.

### The licence a CI agent runs as {#ci-license}

The shared database is Enterprise, and a CI agent has no keychain entry to read a licence from, so a headless run has to be told which licence it holds. It looks in three places, and the first hit wins:

1. `--license-file <path>`, accepted by every `lintcrux-pro` form
2. the `LINTCRUX_LICENSE_FILE` environment variable
3. the `license` key of the organization's signed `.crux-policy.json`, inline or naming a file — see [Administration](administration.md)

The credential is verified offline, with the same signature check the desktop app makes and no network call of any kind. An expired licence keeps its tier for its grace period, exactly as it does in the app.

Every run that found something to say prints one `license:` line on stderr naming the tier and where it came from, or why a credential was not honoured, so a pipeline that is quietly unlicensed is visible in the log rather than in a dashboard that stays empty. A run with no licence configured anywhere says nothing and runs as Open Core. A `--license-file` or `LINTCRUX_LICENSE_FILE` that cannot be read stops the run, because a pipeline that asked for a licence and silently ran without one would skip the gates it was built to apply.

A **machine file** — it starts `-----BEGIN MACHINE FILE-----`, and it is what offline activation issues — works only on the installation it was issued for. Anywhere else the run is Open Core and the `license:` line says `wrongMachine`. A licence key or a licence file names no machine and works on any agent. A headless run learns which machine it is from a fingerprint file, `crux/license/install.fingerprint` in the user account's application-data folder: `~/Library/Application Support` on macOS, `%LOCALAPPDATA%` on Windows, and `$XDG_DATA_HOME` (default `~/.local/share`) on Linux. It never reads the system keychain, so nothing on a build agent waits on a prompt. The file is the machine's one fingerprint: the desktop app, `lintcrux-pro` and every other EDACrux product run by the same user read the same file, so on a workstation where you use the app, a machine file you imported under **Settings → License** also licenses headless runs by that user. On an agent where no EDACrux product has run yet, the first headless run that needs the fingerprint creates it. A fingerprint an earlier release kept in `crux/license/lintcrux.fingerprint` (under `%APPDATA%` on Windows) is adopted into the shared file the first time, so a machine file issued for it keeps working — unless another EDACrux product on the machine recorded its own fingerprint first, in which case ask support to reissue the machine file for the shared one. No command yet prints a build agent's fingerprint or exports an offline activation request without the app, so license a dedicated build agent with a licence key or a licence file.

**Without an Enterprise licence the shared push is refused, and the run does not fail.** The line says so on every run, the local trend store is still written, and the lint's own exit code is untouched — a build does not start failing because of a licence tier, it tells you.

**A run that failed pushes nothing.** A partial run recorded as a data point shows on the dashboard as a fake improvement, which is worse than a gap in the history. The command says so on stderr rather than exiting quietly.

When the lint itself is clean, a problem with the shared database sets the exit code, and the two codes mean different things to a pipeline:

| Code | Meaning | Retry? |
|---|---|---|
| `5` | The server could not be reached, refused the connection, or refused the credential. | Reasonable. |
| `6` | The database is reachable, but this run cannot be recorded in it — a different epoch, an older schema, none at all, an unparseable `LINTCRUX_TEAM_DB_URL`, or no `LINTCRUX_ORIGIN_ID`. | Never — it needs an administrator or a fixed job definition. |

A run already present in the database is a success. A lint result of `1`, `2`, `3` or `4` takes precedence over either code, and neither code is reused by the lint itself, so a pipeline can branch on the number alone. `5` means the same thing as it does for `simcrux-pro push-results`, so one retry rule covers both products.

### Who a run is attributed to {#submitter}

Highest first:

```
1. a LOCKED products.lintcrux.teamDatabaseSubmitter    the organization decided
2. LINTCRUX_SUBMITTER                                  this job named itself
3. an unlocked policy default                          the organization's suggestion
4. the OS user                                         who is at the keyboard
```

**The OS user sits *below* an unlocked policy default**, and that ordering is worth reading twice. The level above a policy default is reserved for what somebody actually chose, and nobody chose the name their login happens to have. So: leave the key out entirely if you want each engineer named; set it unlocked to say "call it this unless a job says otherwise"; lock it to fix the value across a CI fleet.

`LINTCRUX_SUBMITTER` sits at the *user setting* level because that is what it is — the choice made by whoever is running this client. A CI runner's OS user is `runner`, `jenkins` or `root` on every job in the fleet, so the machine-derived default is exactly wrong in the one place the shared database is most read.

**This is a string, not an identity.** There is no user-management subsystem and no SSO; nothing authorises against it.

## What a push records {#pushed}

Each pushed run becomes a row in `lint_runs` — the project path the pushing client recorded, the run time, the submitter (or none), and the violation count — plus one row per violation in `violation_data_points` with its rule, severity, file, line and message. The run key is built from the [required `LINTCRUX_ORIGIN_ID`](#ci), which is what keeps two agents starting a run in the same millisecond from colliding on it. A push is not an audit event; the events LintCrux records are listed on [Administration](administration.md#audit).

!!! note "Education institutions"
    The shared trend database is an Enterprise feature and is not part of the <span class="tier tier-edu">EDU</span> tier — see [Tiers & licensing](https://edacrux.app/licensing).

!!! tip "See also"
    [Administration](administration.md) for the policy keys, the org-wide waiver list, the rollup and CI gating · [Trends & regressions](trends.md) for the local half · [Policy file reference](https://edacrux.app/policy-reference) · [Audit log](https://edacrux.app/audit-log)
