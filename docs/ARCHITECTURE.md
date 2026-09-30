# lintcrux — Architecture & Engineering Manual

**Status:** Living document, tracking the shipped product (seven engines — six external-tool adapters plus the first-party structural CDC engine — the SARIF aggregation pipeline, the headless CI binary, the workspace/multi-tab/split-pane shell, CXP cross-probe, and the full Pro override surface). Section numbering mirrors the WaveCrux open-core engineering manual (`wavecrux/docs/ARCHITECTURE.md`); sections with no LintCrux-specific delta defer to WaveCrux as the source of truth. The authoritative LintCrux-specific content is the extension-point seams (§10), the dependency-flow rules (§6.2), and the glossary (§12).

User documentation lives in `docs-site/docs/` and is published at `https://docs.lintcrux.app`.

---

## How this document is organized

Section numbering mirrors WaveCrux's `ARCHITECTURE.md` so cross-references between the two projects stay valid. Sections that have no lintcrux-specific content yet defer explicitly to WaveCrux.

---

## 2. Tech Stack

### 2.1 Core Framework

Same baseline as WaveCrux: Flutter (Dart) + Riverpod. See
`wavecrux/docs/ARCHITECTURE.md` §2.1 for the full table and rationale — with one
divergence: LintCrux declares every provider by hand and ships no
`build_runner` / `riverpod_generator` toolchain.

### 2.2 Domain Engine

LintCrux does not evaluate text-level lint rules itself. It orchestrates existing external engines (Verilator, Verible, Slang, Yosys `check`, GHDL, Svlint) as subprocesses, parses each engine's stderr/JSON output into a unified SARIF-backed `Violation` model, and aggregates the results. The one first-party analysis is the structural **CDC** engine (`lib/services/engines/cdc/`): it elaborates the design with Yosys (`flatten`, no `opt`), reads the JSON netlist, and runs a Dart clock-domain-crossing analysis whose findings are ordinary `Violation`s. It is structural CDC lint, not sign-off CDC — every distinct clock net is treated as asynchronous and only a two-flop chain counts as a synchronizer; the Pro overlay swaps in a richer engine through the `cdcEngine` parameter of `defaultEngineRegistry`. The per-engine adapters live in `lib/services/engines/<engine>/`; the single engine list is `defaultEngineRegistry` (`lib/services/engines/default_engine_registry.dart`), shared by the GUI's `engineRegistryProvider` and the headless binary. `EngineRunPlanner` routes sources to engines by language, and `ParallelEngineRunner` drives concurrent runs and streams each engine's results into the store as it finishes. The Yosys and CDC engines consume the shared `crux_yosys` package (same subprocess infrastructure NetCrux uses).

### 2.3 Rendering

Standard Flutter widget tree. The centerpiece is the virtualized violation table (`ListView.builder`, stable 28 px rows via `kViolationRowHeight`, comfortable at 50K+ violations) — no `CustomPainter` is required for the current surfaces. The Pro trend charts and calendar heatmap render through the standard widget tree.

### 2.4 Panel Layout

The four-region IDE layout (`LintcruxIdeLayout`) is a thin adapter over the shared `crux_ide_layout` package's `CruxIdeLayout` (the `panes` `IdeLayout` under the hood). On desktop the regions are docks (`lib/features/workspace/widgets/lintcrux_docks.dart`): left dock (Sources, Rules), the violation table in the centre, right dock (Details — the inspector — and the movable Cross-Probe tab), bottom dock (Source preview). The web viewer fills the same four slots directly with the rules panel, table, inspector, and source preview. Multi-tab + split-pane come from the shared `crux_workspace` package (`PaneHost`).

### 2.5 Infrastructure

GitHub Actions for CI/CD, GitHub Releases for distribution. Match WaveCrux when the build matures.

---

## 3. Target Platforms

| Platform | Priority | Notes |
|----------|----------|-------|
| **Linux** | First | Primary target |
| **macOS** | First | Universal binary |
| **Windows** | First | x86_64 |
| **Web** | Read-only viewer | Static SARIF viewer (shipped). Renders a SARIF 2.1.0 report supplied by URL (`?sarif=<url>`) or file upload, reusing the desktop dashboard layout. No engine subprocesses — browsers can't spawn linters — so running engines, file watching, `.lintcrux` project files, and disk persistence stay desktop-only. Built from the open-core package; hosted at `app.lintcrux.app` (Worker `lintcrux-app`, `wrangler.jsonc`, deployed by `.github/workflows/web-deploy.yml`). |

**Mobile** is out of scope. **Web is a read-only viewer, not out of scope** (see the table). The web viewer targets desktop-class browser viewports, so the `DeviceClass` system, `MobileMetrics`, and §3.1.x mobile rules from WaveCrux still do not apply to lintcrux — the `panes` `IdeLayout` is the only layout on every platform, browser included.

---

## 5. Localization

Five ARB files ship in `lib/l10n/` — `app_en.arb`, `app_zh_CN.arb`, `app_zh.arb`, `app_ja.arb`, `app_ko.arb` — covering four locales (`en`, `zh_CN`, `ja`, `ko`) with `zh` mirroring `zh_CN`, same as WaveCrux. Every user-facing string flows through the generated `L10N`; widget tests carry a locale sweep across all five files. Mirror `wavecrux/lib/l10n/` conventions.

ARB rules (§5.2 in WaveCrux's manual): every message has a `@<key>` metadata entry with an English `description`; `app_zh.arb` mirrors `app_zh_CN.arb`; `@@locale` is the first key in every file.

---

## 6. Architecture

### 6.1 Layer Responsibilities

Same pattern as WaveCrux:

- **Domain layer** (`lib/domain/`) — Pure Dart, zero Flutter imports.
- **Services layer** (`lib/services/`) — Business logic.
- **Feature modules** (`lib/features/`) — Each owns its providers, screens, widgets.
- **Core** (`lib/core/`) — Theme, constants, shortcuts, utilities.
- **Plugins** (`lib/plugins/`) — Registry infrastructure (when needed).

### 6.2 Dependency Flow

The layers form a one-way stack. A **lower** layer must never import a
**higher** one:

```text
features/ → services/ → domain/
```

- **`domain/`** is pure: it imports only `domain/` (and third-party
  packages / the SDK). Never `services/`, `features/`, or `core/`.
- **`services/`** implements domain interfaces and holds business logic /
  cross-cutting app state (the current project, run lifecycle, CXP
  transport, …). It may import `services/`, `domain/`, and `core/`. Never
  `features/`.
- **`features/`** owns its providers, screens, and widgets. It may import
  `features/`, `services/`, `domain/`, and `core/`.
- **`core/`** is a shared **base** — theme, constants, shortcuts, CLI,
  utilities. It is itself SDK-only (plus `domain/` models) and is
  importable by any layer. It must not import `services/` or `features/`.
- **`plugins/`** — registry/extension-point wiring; imports `domain/`
  interfaces.

**Lateral imports are allowed.** Same-layer imports (`features → features`,
`services → services`) are fine — the rule governs vertical direction, not
module isolation. So a feature provider may read a sibling feature
provider (e.g. `selectedViolationProvider` → `violationTableStateProvider`).

**Sanctioned exceptions (may import `features/`):**

- **Composition root** — the router, the bootstrap theme/settings bridge,
  and the app entry (`lib/core/router/app_router.dart`,
  `lib/core/theme/lintcrux_color_theme_bootstrap.dart`, `lib/app.dart`,
  `lib/main.dart`). These wire the app together and may reach any layer.
- **`action_handlers`** (Pro overlay)
  — thin action-dispatch glue that maps `LintcruxAction`s to feature UI /
  side-effects, registered as bootstrap overrides. It is the composition
  root's sibling and is allowed to import features.

**Fixing a violation, not adding an exception.** When a lower layer needs
something a higher layer owns, move the shared type *down* (e.g. a config
model or state holder that services consume belongs in `services/` or
`domain/`, not `features/`), or invert via a **services-layer seam** the
feature writes into and the service reads — as done for the lint-run
lifecycle (`services/run/lint_run_lifecycle.dart`, fed by
`LintRunNotifier`) and the CXP transport handle
(`services/remote/cxp/cxp_outbound.dart`, fed by the CXP server
lifecycle). Adding an allowlist entry is only for genuine composition-root
wiring.

This direction is enforced by `test/static/import_layering_test.dart`
(open-core) and the parallel guard in the Pro overlay. Each
carries a commented allowlist of the sanctioned exceptions above; a new
upward import fails the test.

### 6.4 Riverpod Provider Hierarchy

The root `ProviderScope` is created by `bootstrap()` in `lib/app.dart`. Open-core overrides are placed first; Pro overrides are spread last from the Pro overlay's `proOverrides` list. Every workspace tab additionally owns its own child `ProviderContainer` (mirroring WaveCrux's per-tab `ProviderScope` architecture in `wavecrux/docs/ARCHITECTURE.md` §6.4) — see §10 "Per-tab scope contract" below for the full per-tab binding rules and the concrete provider tree.

---

## 8. Coding Standards & Conventions

See `CLAUDE.md` for the binding day-to-day rules. The detailed rationale and the cross-platform mobile UI rules live in WaveCrux's `ARCHITECTURE.md` §8. lintcrux inherits the Dart style, Riverpod, and testing conventions verbatim.

### 8.9 Test Fixture & Validation Strategy

LintCrux's fixture corpus is the **engine-output → golden-SARIF** model (the analogue of WaveCrux's decoder fixture suites). Per-engine canned outputs live under `test/fixtures/engines/<engine>/generated/<case>/` (`cmdline.txt` + `output.txt` + `expected.sarif.json`), mirrored under `verification/fixtures/engines/`, and are re-runnable via `dart run tool/generate_engine_corpus.dart`. Output captured from real binaries lives beside them under `captured/<case>/` (with `PROVENANCE.md`) — today for GHDL 6.0.0 and slang 11.0. Four static guards in `test/static/` keep the corpus self-enforcing — `engine_fixture_layout` (no loose files outside `generated/`/`captured/<case>/`), `all_engines_have_fixtures` (each of the six external-engine adapters has ≥1 generated golden; the guard constructs its own engine list and does not cover the first-party CDC engine), `engine_fixture_companion` (every case has its golden + cmdline/PROVENANCE), and `captured_fixture_licenses` (allow-list) — backed by a CI "Fixtures up to date" gate in `.github/workflows/ci.yml` that re-runs both generators and fails on a diff. The large-scale stress corpus (50K/100K) is regenerated deterministically in memory from `test/support/stress_corpus.dart` rather than committed as binaries; `tool/generate_stress_fixtures.dart` writes only its small pinning artifacts and the malformed-SARIF cases.

---

## 9. Design System

Mirror WaveCrux's design tokens (Material 3, dark default, JetBrains Mono / Fira Code for monospace fields, 4dp/8dp grids, minimal motion). Update this section once the first design surface is built.

---

## 10. Extension Points (Pro Overlay Seams)

lintcrux is consumed by the closed-source Pro overlay through Riverpod provider overrides, not through code forking. The pattern matches WaveCrux exactly:

- `lintcrux` (this repo) ships the complete standalone tool.
- The Pro overlay consumes this repo as a Git submodule, `path: ./lintcrux` in pubspec, and layers `proOverrides` into the `bootstrap()` `ProviderScope`.

When a Pro feature needs to plug into the open-core somewhere there is no hook yet, the *first* change is to this repo: define the interface, add the registry / Riverpod provider, ship a default no-op or open-core implementation. Only then does the Pro implementation land in the Pro overlay (after a submodule pin bump). Forking open-core code in the Pro overlay is not allowed — see `CLAUDE.md` for the binding rule and `wavecrux/docs/ARCHITECTURE.md` §10 for the worked examples.

### Override pattern

```dart
// lib/app.dart
Future<void> runLintcrux({
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  LinuxDesktopApp linuxDesktopApp = kLintcruxLinuxDesktopApp,
  Future<void> Function(int code)? exitProcess,
}) async {
  final handled = await bootstrap(/* … */);
  if (!handled || isWebMode) return;
  await (exitProcess ?? _flushAndExit)(exitCode); // --help, --version, bad args
}

Future<bool> bootstrap({
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  Widget Function(Widget app)? wrapApp,
  LinuxDesktopApp linuxDesktopApp = kLintcruxLinuxDesktopApp,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // … CLI parsing (returns true for --help / --version / usage and import
  // errors), --import-*, --reset / --no-restore, window chrome …
  launch(
    ProviderScope(
      overrides: <Override>[
        // Open-core overrides first.
        cliArgsProvider.overrideWithValue(effectiveCliArgs),
        launchRestoreDecisionProvider.overrideWithValue(restoreTabsOnLaunch),
        ...lintcruxPhase5Overrides(),
        ...lintcruxTelemetryOverrides,
        lintcruxCruxColorThemeOverride,
        ...extraOverrides, // the Pro overlay spreads its proOverrides here
      ],
      child: const LintcruxApp(),
    ),
  );
  return false;
}
```

The web build takes an earlier branch with the same shape (no CLI surface). Both `lib/main.dart` files call `runLintcrux`, never `bootstrap` directly: a Flutter desktop runner keeps its window and event loop alive after `main` returns, so a command-line-only invocation has to call `exit` itself (`test/app_headless_exit_test.dart`). The Pro overlay calls `runLintcrux(args: args, extraOverrides: proOverrides, linuxDesktopApp: …)` from its `lib/main.dart`. Open-core conflict semantics: open-core overrides come first; Pro overrides come last; later overrides win.

### Per-tab scope contract (project-keyed state)

LintCrux's workspace gives every open tab its own child `ProviderContainer`
(`WorkspaceRoot` → `crux.TabContainerManager`), and a tab is bound 1:1 to a
`.lintcrux` project. **The tab container is the project scope.** The binding
rules:

1. **A provider is per-tab IFF it is re-bound in a per-tab override list** —
   open-core providers in `lintcruxTabOverridesFactory`
   (`lib/features/workspace/providers/tab_overrides_factory.dart`), Pro
   providers (and Pro bindings of open-core extension points) in the Pro
   overlay's `proTabOverrides`, spread in through the
   `extraTabOverridesProvider` seam. Providers not listed resolve to the ONE
   root instance through Riverpod's parent-container lookup.

   <!-- inventory: lintcruxTabOverridesFactory -->
   The open-core per-tab list `lintcruxTabOverridesFactory` re-binds, in tab
   scope: `currentProjectProvider`, `configLoadErrorProvider`,
   `violationStoreProvider`, `lintRunProvider`, `lintRunLifecycleBusProvider`,
   `selectedViolationProvider`, `violationTableStateProvider`,
   `visibleViolationsProvider`, `presentEngineIdsProvider`,
   `savedFilterPresetsProvider`,
   `activeFilterPresetProvider`, `autoReloadControllerProvider`,
   `pendingReloadProvider`, `violationSelectionEmitterProvider`,
   `violationViewModeProvider`,
   `tabDiagnosticsReportProvider`, `appDiagnosticsReportProvider`,
   `bookmarkedViolationsCountProvider`, `lintCacheStatsProvider`,
   `lintCacheInvalidationsProvider`, `veribleAvailabilityProvider`, and
   `cruxIssueSessionContextProvider` (the beta issue reporter's Session State
   snapshot, which reads the tab's project / violation store / table state and
   would otherwise report an empty session for every bug report). This
   block is machine-checked against the factory by
   `test/static/doc_truth_test.dart`; update both together.
   <!-- /inventory -->
2. **Every project-keyed extension-point store is per-tab.** The six
   project-keyed stores (`waiverStoreProvider`, `baselineStoreProvider`,
   `violationBookmarkStoreProvider`, `filterPresetStoreProvider`,
   `lintRunCacheServiceProvider`, `veribleFixServiceProvider`) key off
   `currentProjectProvider`, which only ever holds a project INSIDE a tab —
   the production open flows (`OpenProjectInWorkspace`: File → Open, CLI
   positional paths, filelist / EDAM import, session / workspace restore) never
   write the root `currentProjectProvider`, and there is deliberately no
   root-container project loader. A root-registered binding of one of these
   stores therefore reads `null` forever (the store silently no-ops for
   every GUI-opened project) — or, worse, a stale root project, making tab
   B's dialog write into tab A's project directory. The Pro overlay binds
   all six in `proTabOverrides`; their open-core derivations
   (`bookmarkedViolationsCountProvider`, `lintCacheStatsProvider`,
   `lintCacheInvalidationsProvider`, `veribleAvailabilityProvider`) are
   re-bound in `lintcruxTabOverridesFactory` so the whole chain resolves in
   tab scope.
3. **Dialogs mount in the active tab's scope.** `showDialog` pushes onto the
   root navigator, so a dialog's `ref` resolves the ROOT container no
   matter where the call site sits. Any dialog/screen whose content reads
   per-tab providers wraps its content in `wrapInActiveTabScope`
   (`lib/features/workspace/services/active_tab_scope.dart`); imperative
   action handlers use the sibling `activeTabContainerOf` to read/mutate
   the active tab's providers directly.
4. **Root-scoped services that must act on tab state resolve it through
   `ActiveTabContainerHandle`** (`lib/services/workspace/
   active_tab_container_handle.dart`), published by `WorkspaceRoot` — the
   bridge for code with no `BuildContext` (canonically the CXP inbound
   request path, which searches/mutates the ACTIVE tab per request).
5. **Side-effecting per-tab listeners realize through
   `perTabStartupProvidersProvider`** (the per-tab sibling of
   `eagerStartupProvidersProvider`). `ProjectTabContent` holds a
   `ProviderContainer.listen` subscription on each entry, taken against
   the TAB's container. Both seams name providers, not callbacks, and the
   host keeps real subscriptions rather than issuing one-shot reads:
   Riverpod pauses a provider with no listener of its own, and the pause
   propagates into the `ref.listen` that provider installed in its
   constructor — so a `read`-realized listener observes nothing. The
   realized provider must itself be re-bound per tab or the subscription
   parent-delegates back to root.
6. **The static guard is binding.** `test/static/
   per_tab_provider_scope_leak_test.dart` scans every provider definition
   AND every `overrideWith` binding (both repos, transitively) and fails
   the build when an un-scoped provider reaches per-tab state. Allowlist
   additions require a documented reason.

App-wide state stays root by design: the trend store (`trends.db` is one
database aggregating every project's runs), the completion-event bus
(`lintRunCompletionEventBusProvider` — per-tab dispatchers emit into it;
per-tab consumers filter on `LintRunCompletionEvent.projectPath`), app
settings, the CXP server lifecycle, the project registry, and the workspace
document itself.

### CXP cross-probe (open-core)

The cross-probe infrastructure consumes the shared `crux_cxp` package and exposes LintCrux as a peer in the Crux suite cross-probe ecosystem:

- `cxpServerLifecycleProvider` — `AsyncNotifier` that owns the lifecycle of the `LintCruxCxpServer` (a thin wrapper around `LocalCxpServer`), the manifest writer (`${appSupport}/crux/cxp/peers/lintcrux-<pid>-<startedAtMillis>.json`), and the discovery watcher (`CxpDiscovery`). Watched from `LintcruxApp.build` for the whole session, so the server starts whenever Settings → CXP Cross-Probe → "Enable CXP server" is on, independent of the panel. Watches `cxpServerConfigProvider` so toggling `cxpServerEnabled` or changing `cxpServerPort` in Settings restarts the server without rebooting the app. Releases the manifest + socket on `ref.onDispose`.
- `cxpPeersProvider` — list of CXP peers discovered through the manifest directory. Refreshed whenever the discovery watcher fires a `CxpDiscoveryEvent`.
- `cxpEventLogProvider` — rolling buffer of the last 50 cross-probe events (peer connect / disconnect / discover / lose, inbound requests, outbound acks). Consumed by `LintCruxCrossProbePanel` (`lib/features/remote/widgets/cross_probe_panel.dart`), the docked Cross-Probe tab, whose per-peer Send action issues an ack-bearing `request_highlight` for the active tab's selected violation.
- `cxpRequestHandlerProvider` — exposes the pure `LintCruxCxpRequestHandler` that converts inbound `CxpMessage`s into a `CxpDispatchResult` (ack + table-state mutation + selection + open-source result). The lifecycle layer applies the result to `violationTableStateProvider`, `selectedViolationProvider`, and the existing `clickToSourceServiceProvider`.
- `LintCruxNameResolver` — maps LintCrux's natural element references into and out of canonical `ElementId` form. Owns `ElementKind.rule` (canonical path = `<engineId>/<ruleId>@<file>:<line>:<column>`, matching `ViolationTableState.idOf`) and `ElementKind.source` (`<file>:<line>[:<column>]`); recognises `ElementKind.signal` / `ElementKind.instance` for cross-probe filter routing; returns `null` for kinds LintCrux cannot represent.

CXP receive, discovery, explicit sends and automatic `notify_selection` emission are open-core capabilities that ship with every LintCrux build — cross-probe is ecosystem infrastructure, not a paid upsell, the same posture WaveCrux, NetCrux and SimCrux take. The emitter is `ViolationSelectionEmitter` (`lib/features/remote/providers/violation_selection_emitter.dart`), re-bound per tab in `lintcruxTabOverridesFactory`, watched from `ProjectTabContent`, and honouring the "Broadcast selection automatically" setting.

### Managed waiver system seam (open-core)

The managed waiver system is the headline Pro feature. The open-core ships the seam — interface, default no-op, and the transformer hook in the run pipeline — so the Pro overlay slots in via the standard provider-override pattern:

- `WaiverStore` (`lib/domain/interfaces/waiver_store.dart`) — CRUD + `match()` + event stream. Open-core default is `NoopWaiverStore` (`lib/services/waivers/noop_waiver_store.dart`) — permanently empty `all`, `match()` returns `null`, mutation methods throw `UnsupportedError`.
- `waiverStoreProvider` (`lib/services/waivers/waiver_store_provider.dart`) — `Provider<WaiverStore>` returning `NoopWaiverStore` by default. The Pro overlay overrides this provider with `JsonFileWaiverStore` (reads/writes `.lintcrux-waivers.json` in the project root).
- `ManagedWaiverTransformer` (`lib/services/transformers/managed_waiver_transformer.dart`) — `ViolationTransformer` that consults a `WaiverStore` and tags matching violations with `Violation.suppression`. Already-suppressed violations (e.g. by an inline pragma earlier in the pipeline) pass through unchanged — source pragmas always win over a managed waiver because the source is closer to the engineer's intent.
- `LintRunNotifier._buildTransformer` (`lib/features/run/providers/lint_run_notifier.dart`) composes the transformer chain in the order `SeverityOverrideTransformer → PragmaWaiverTransformer → ManagedWaiverTransformer`. The pragma transformer runs first so source pragmas claim suppression before the managed-waiver matcher gets a turn. The headless `HeadlessRunner` (`lib/services/headless/headless_runner.dart`) builds the same first two stages and appends whatever `extraTransformers` its caller passes — empty in open core, the managed-waiver transformer in the Pro CLI.

The Pro overlay's `JsonFileWaiverStore`, "Waive…" UI, waiver review screen, expiration banner, and audit-trail hook all consume the open-core seam unchanged.

### Settings extra-sections seam (open-core)

The Settings screen's section-rail is an `enum`-driven switch in open-core. Pro features that need their own Settings section (Custom Rules today; future trend / baseline / managed-waiver-defaults sections) can't extend the enum from the overlay, so they contribute entries through a Riverpod provider:

- `SettingsExtraSection` (`lib/plugins/settings_extra_sections_provider.dart`) — immutable contribution carrying an `id` (stable identifier), `labelBuilder` (resolves inside the Settings screen's `BuildContext`, so Pro overlays read `L10NPro.of(context)` here), an optional `icon`, and a `bodyBuilder` (runs inside the Settings screen's `BuildContext` / `WidgetRef` when the section is activated).
- `settingsExtraSectionsProvider` — `Provider<List<SettingsExtraSection>>` returning an empty list in open-core. The Pro overlay's `proOverrides` replaces this with one that returns the Custom Rules section and any subsequent Pro Settings sections.
- `SettingsScreen` (`lib/features/settings/screens/settings_screen.dart`) — renders the built-in rail items first, then appends one rail row per contributed entry, in the order returned by the provider. The selected index is clamped against the combined rail size so a Pro overlay re-evaluation that shrinks the extras list never leaves the rail pointing past the end.

Tier-gating is the contributing section's responsibility. The Settings screen does **not** consult `licenseTierProvider` when deciding whether to render an extra section — Pro sections that need to render an upsell card under `LicenseTier.openCore` perform that check inside their own `bodyBuilder` (the `CustomRulesSection` in the Pro overlay is the reference implementation). This matches the rest of the LintCrux extension-point seams: open-core declares the slot; the Pro overlay decides tier semantics.

### Baseline & delta seam (open-core)

The baseline & delta workflow snapshots every active violation at a single point in time and lets subsequent runs surface only the delta — violations introduced after the snapshot. Open-core ships the seam (domain models, store interface, pure-function filter, three new actions, comparison-screen opener); the Pro overlay layers a JSON-file-backed store and the UI surfaces.

- `LintBaseline` (`lib/domain/models/lint_baseline.dart`) — immutable snapshot carrying `baselineId`, `createdAt`, optional `createdBy`, `projectPath`, and a list of `BaselineViolation` records. Schema-versioned (`version: 2`) with `toJson` / `fromJson` round-trip and an `unsupported version` rejection path; a `version: 1` document (fingerprints over absolute paths) is migrated on read by recomputing each fingerprint against its `projectPath`. A project has at most one active baseline; replacing it is the supported "rebase" workflow.
- `BaselineViolation` (`lib/domain/models/baseline_violation.dart`) — frozen record carrying `fingerprint`, `ruleId`, `filePath`, `line`, `message`. The `fingerprint` is a stable FNV-1a 64-bit hash of `(ruleId, project-relative filePath, normalized-message)`; the line number is deliberately **excluded** from the hash so a violation that shifts down by a few lines still counts as the same defect against the baseline, and the checkout location is excluded so a baseline matches on any machine. `BaselineFingerprint.forProject` makes the inputs root-relative and `BaselineFingerprint.compute` is the dependency-free hash; tests rely on its determinism under whitespace normalization.
- `BaselineDelta` (`lib/domain/models/baseline_delta.dart`) — result of comparing a live run against a baseline: `newViolations`, `persistingViolations`, `resolvedViolations`. The three lists are independent and disjoint; `hasNewViolations` drives the CLI `--fail-on-new-violations` exit code.
- `BaselineStore` (`lib/domain/interfaces/baseline_store.dart`) — CRUD + watch surface: `activeBaseline()`, `setBaseline(LintBaseline)`, `clearBaseline()`, `Stream<LintBaseline?> watch()`. The Pro overlay's `JsonFileBaselineStore` reads/writes `<project-root>/.lintcrux-baseline.json` — the same file the headless binary's `CliBaselineReader` reads for `--fail-on-new-violations`.
- `NoopBaselineStore` (`lib/services/baseline/noop_baseline_store.dart`) — open-core default. `activeBaseline()` returns `null`; `setBaseline()` throws `UnsupportedError` (the feature is Pro); `clearBaseline()` is an idempotent no-op (callers can fire it defensively).
- `baselineStoreProvider` (`lib/services/baseline/baseline_store_provider.dart`) — `Provider<BaselineStore>` returning the noop by default. Pro overlay overrides this.
- `BaselineFilter.classify({current, baseline, projectRoot})` (`lib/services/baseline/baseline_filter.dart`) — pure-function classifier with no I/O. When `baseline == null`, every current violation is reported as `new`. When the baseline is set, fingerprints are matched against the run's own `projectRoot` and the three result lists are populated. Output lists are unmodifiable; `resolvedViolations` is emitted in baseline-declared order for deterministic diffs.
- `BaselineAuditSink` (`lib/services/baseline/baseline_audit_sink.dart`) — audit-trail interface with `NoopBaselineAuditSink` (the default of a store constructed without one) and a file-based `FileBaselineAuditSink` (Pro overlay). Every `setBaseline` / `clearBaseline` mutation records a `BaselineAuditEntry` with timestamp, action, projectPath, the new baseline id (when set), the previous baseline id (when replacing), and the frozen-violation count. Audit writes are best-effort: a failure must never block the underlying mutation.
- `baselineComparisonOpenerProvider` (`lib/plugins/baseline_comparison_opener_provider.dart`) — open-core extension point mirroring `waiverReviewOpenerProvider`; the open-core default is `null`. The Pro overlay overrides this to mount the comparison screen.
- `currentBaselineSnapshotProvider` (`lib/services/baseline/current_baseline_snapshot_provider.dart`) — synchronous `Provider<LintBaseline?>` defaulting to `null`. The Pro overlay overrides this with a value-typed mirror of the latest `baselineStoreProvider.watch()` emission, so `visibleViolationsProvider` can apply view-mode post-filtering inside its derive function without await-points. Without this seam, the open-core post-filter has no way to read the active baseline synchronously.
- `ViolationViewMode` enum (`lib/domain/enums/violation_view_mode.dart`) and `violationViewModeProvider` (`lib/features/violations/providers/violation_view_mode_provider.dart`) — three-state view-mode selector for the violation table (`allViolations` / `onlyNew` / `onlyResolved`). Default is `allViolations`. The open-core `visibleViolationsProvider`'s `_derive` consults both the view mode and the baseline snapshot, applying the corresponding post-filter; the Pro overlay's `BaselineViewModeToggle` widget writes to the notifier. `onlyResolved` returns an empty list at the table layer because live `Violation` instances cannot be "resolved" by definition — the resolved section of `BaselineComparisonScreen` renders frozen baseline entries directly.
- `violationTableTopActionsProvider` (`lib/plugins/violation_table_top_actions_provider.dart`) — open-core extension point through which the Pro overlay contributes widgets rendered in the violation table's top action row (above the filter chips). Default returns an empty list. Each contribution is a `ViolationTableTopActionBuilder` (`Widget Function(BuildContext, WidgetRef)`); the table wraps each in its own `Builder` so contributions can watch providers without forcing the table to rebuild. Used by Pro for the baseline set/clear toolbar, the view-mode toggle, and the active baseline status chip.

Three new actions live in `LintcruxAction`:

- `setBaseline` — snapshots the current run's violations as the project's baseline. Pro-tier; `LintCruxFeatureTierBadge(LicenseTier.pro)` rendered on the menu / palette entry.
- `clearBaseline` — clears the project's active baseline. Pro-tier.
- `openBaselineComparison` — opens the baseline-vs-current comparison screen. Pro-tier.

All three actions live under `ActionCategory.tools` (alongside `openWaiverReview` and the developer-facing diagnostic surfaces) and are added to the menu-only set in the keyboard-bindings registry. Localized labels live in `actionSetBaseline` / `actionClearBaseline` / `actionOpenBaselineComparison` across all five ARB files.

### Beta release infrastructure (open-core)

Three cross-suite packages are wired in `lib/app.dart` through
`lintcruxPhase5Overrides()`, spread before `extraOverrides` so the Pro overlay
can still layer on top:

- **`crux_updates`** — manifest fetch, status notifier, update banner.
  LintCrux supplies `lintcruxUpdateConfig` (`lib/features/update/`), an
  ARB-backed `CruxUpdateStrings` adapter, the persisted Settings → General
  auto-check setting, and `updateUrlLauncherProvider`. The banner mounts in
  `MaterialApp.builder` and never renders on web. **No Pro seam** — the
  update mechanism is open to every tier, beta and post-beta.
- **`crux_issue_reporter`** — the beta issue reporter. LintCrux supplies the
  config (`Ferrite-Engineering/lintcrux`, template `bug_report.yml`), an ARB-backed strings
  adapter, the root `RepaintBoundary` keyed by
  `cruxAppScreenshotBoundaryKeyProvider`, and — the product seam —
  `cruxIssueSessionContextProvider`, bound to
  `buildLintcruxIssueSessionContext`
  (`lib/features/issue_reporter/providers/issue_session_context.dart`).
  That contributor is **per-tab** (see the per-tab scope contract above) and
  the reporter is opened inside the active tab's container.
  **Pro seam:** `cruxIssueReporterDataProviderProvider` — the overlay
  replaces the `NoopCruxIssueReporterDataProvider` default to contribute
  extra whole categories (a "Pro State" section) from the same snapshot's
  `attributes` map. It is the *only* seam the overlay needs here: the
  session contributor itself is bound per tab by open-core, and a root-scope
  Pro override of `cruxIssueSessionContextProvider` would be shadowed by
  that tab binding. An overlay that wants to change the *product's own*
  fields does so through `extraTabOverridesProvider`, which is appended
  after the open-core per-tab list.
- **`crux_license` beta expiry** — `BetaExpiryGate`
  (`lib/features/beta_expiry/`) reads `betaExpiryStatusProvider` and mounts
  above the update banner. `observedServerTimeProvider` is bound to
  `ObservedServerTimeStore` (`lib/services/updates/`), the persisted,
  monotonic watermark that the update manifest's `server_time` advances —
  the pairing that keeps a device-clock rollback from deferring expiry. The
  gate is tier-independent by design: build shelf life is not a licence
  check.

### Extension-point seam inventory

The UI-facing Pro-overlay extension points live in `lib/plugins/`; the store and service seams live beside their open-core defaults under `lib/services/` (`trends/`, `filter_presets/`, `bookmarks/`, `verible/`, `lint_cache/`, `baseline/`, `waivers/`, `workspace/`). Today:

- `violationContextMenuEntriesProvider` — context menu entries on violation table rows.
- `waiverReviewOpenerProvider` — opens the Pro waiver review screen.
- `baselineComparisonOpenerProvider` — opens the Pro baseline-vs-current comparison screen.
- `filterPresetManagerOpenerProvider` — opens the Pro filter-preset manager screen.
- `saveFilterPresetOpenerProvider` — opens the Pro "Save current filter as preset…" dialog.
- `bookmarkPanelOpenerProvider` — opens the Pro violation-bookmark management panel.
- The remaining Pro action openers (`setBaselineOpenerProvider`, the trend-chart, Verible, lint-cache and multi-project openers) — declared together in `lib/plugins/pro_action_openers.dart`.
- `statusBarTrailingWidgetsProvider` — widgets appended to the trailing end of `LintcruxStatusBar`. Default empty list; each contribution renders `SizedBox.shrink()` when it has nothing to show.
- `extraLocalizationsDelegatesProvider` — additional `LocalizationsDelegate`s (the Pro overlay registers `L10NPro.delegate` here).
- `eagerStartupProvidersProvider` — providers the app pins for the whole session by holding a ROOT `ProviderContainer.listen` subscription on each (`_EagerStartupGate` in `app.dart`); Pro registers the root trend-ingestion listener here. Entries whose provider must observe per-tab state belong in `perTabStartupProvidersProvider` instead. A one-shot `read` is NOT equivalent — an un-listened provider is paused and its constructor-installed `ref.listen` stops receiving.
- `perTabStartupProvidersProvider` — the per-tab sibling of `eagerStartupProvidersProvider`: providers `ProjectTabContent` subscribes to once per workspace tab, against the TAB's own `ProviderContainer` (Pro registers the CXP `ViolationSelectionEmitter`, bookmark stale-detection, and Verible auto-run listeners here, each also re-bound per tab in `proTabOverrides`). See §10 "Per-tab scope contract".
- `extraTabOverridesProvider` — the per-tab override seam (`lib/features/workspace/providers/tab_overrides_factory.dart`): `WorkspaceRoot` appends its value (the Pro `proTabOverrides` list) after `lintcruxTabOverridesFactory` when building each tab's `ProviderContainer`. This is where the Pro overlay binds the six project-keyed stores and their Pro-side derivations per tab.
- `activeTabContainerHandleProvider` — services-layer handle (`lib/services/workspace/active_tab_container_handle.dart`) resolving the ACTIVE tab's `ProviderContainer` from root-scoped code with no `BuildContext`; published by `WorkspaceRoot`, consumed by the CXP inbound path.
- `settingsExtraSectionsProvider` — Settings rail contributions (Pro registers the Custom Rules section).
- `violationTableTopActionsProvider` — violation-table top-action contributions (Pro registers the baseline set/clear toolbar, the baseline view-mode toggle, and the active baseline status chip).
- `dashboardBannersProvider` — full-width banner contributions stacked between the violation-table toolbar and the table itself (`ViolationTable` renders them in list order; Pro registers the trend alerts, Verible auto-run and waiver expiration banners).
- `violationTrendStoreProvider` — Pro trend store seam. Open-core default is `NoopViolationTrendStore` (in-memory, ephemeral). The Pro overlay overrides with `SqliteViolationTrendStore` persisting to `<appSupportDir>/lintcrux/trends.db`.
- `trendRetentionPolicyProvider` — active `TrendRetentionPolicy`. Default is `TrendRetentionPolicy.proDefault` (90 days / 1000 runs / oldestFirst).
- `lintRunCompletionEventProvider` — `Stream<LintRunCompletionEvent>` producing one event per completed lint run, republishing the root `lintRunCompletionEventBusProvider` (into which every tab's per-tab dispatcher emits). Each event carries `projectPath` so per-tab consumers (bookmark stale-detection, Verible auto-run) can ignore completions belonging to another tab's project.
- `lintRunCompletionListenerProvider` — `Provider<void>` the Pro overlay pins at app boot via `eagerStartupProvidersProvider`; the open core declares it and never realizes it. Subscribes to `lintRunCompletionEventProvider` and pumps each event into the active `ViolationTrendStore`. Store-resolution and ingest failures are caught and reported to `trendIngestDiagnosticsSinkProvider` rather than swallowed; the subscription survives a failed write.
- `trendIngestDiagnosticsSinkProvider` — `Provider<TrendIngestDiagnosticsSink>` receiving every `TrendIngestFailure` the ingestion listener catches. The default logs through `package:logging` under `lintcrux.trends`; nothing in the open core reports to it. The Pro overlay overrides it to also raise a one-time user-visible signal, since the Pro SQLite store can be locked, full, or read-only.
- `lintRunCompletionDispatcherProvider` — `Provider<LintRunCompletionDispatcher>` the Pro overlay overrides with a producer that observes `lintRunProvider` + the violation store events, waits for a full project-wide run to land, builds the aggregated `LintRunCompletionEvent`, and feeds it into `lintRunCompletionEventProvider`. Open-core default is `NoopLintRunCompletionDispatcher`. Realized per tab by `ProjectTabContent` (which watches it) so the Pro dispatcher's `start()` runs before any of that tab's runs complete; `ref.onDispose` calls its `stop()`.
- `filterPresetStoreProvider` — `Provider<FilterPresetStore>`. Open-core default is `NoopFilterPresetStore` seeded with the canonical `builtinFilterPresets()` list ("All Violations" / "Errors Only" / "New Violations"). Nothing in the open core reads it, so the built-ins appear only in the Pro overlay's preset selector and manager. The Pro overlay overrides with `JsonFileFilterPresetStore` reading/writing `<project-root>/.lintcrux-filter-presets.json` while still exposing the built-ins at the top of `listAll`. Built-ins are non-deletable; mutations rejected by id match.
- `violationBookmarkStoreProvider` — `Provider<ViolationBookmarkStore>`. Open-core default is `NoopViolationBookmarkStore` (empty list; silent no-op mutations). The Pro overlay overrides with `JsonFileViolationBookmarkStore` reading/writing `<project-root>/.lintcrux-bookmarks.json`, with stale-detection wired into `lintRunCompletionEventProvider` so each completed run updates `BookmarkedViolation.lastSeenRunId` on still-firing bookmarks.
- `activeFilterPresetProvider` — per-tab `NotifierProvider<ActiveFilterPresetNotifier, FilterPreset?>`. Tracks the currently-applied `FilterPreset` for the violations table; `null` = no preset. `VisibleViolationsNotifier` watches this provider and applies the preset's `filterState` (via `overlayFilterPreset`) as an overlay on top of the user's manual `ViolationTableState`. Per-tab so two tabs apply their own presets independently.
- `bookmarkedViolationsCountProvider` — `StreamProvider<int>` reactive count of bookmarks consumed by the violations-table header count badge.

**Opener-seam contract (`lib/plugins/pro_opener.dart`).** Every open-core → Pro
action opener is a `Provider<ProActionOpener?>` whose open-core default is
`null`, never a no-op function. The null is load-bearing: a no-op default is
indistinguishable at the call site from an opener that ran and chose to do
nothing, so the dispatcher cannot detect a missing implementation and the
Pro-badged menu / palette entry becomes a silent dead item. With `null`,
`_handleOpener` in `app.dart` detects it and surfaces a localized snackbar
chosen by the action's `requiredTier` — the Pro upsell for a Pro/Enterprise
action, the neutral "not available yet" for an open-core one — so the feedback
can never contradict the tier badge the surface rendered. A new opener seam
that defaults to a no-op is a code-review-blocking defect.
- `bookmarkToggleHandlerProvider` — open-core `Provider<BookmarkToggleHandler>` (`Function(BuildContext, WidgetRef, Violation)`) read by the Pro bookmark column icon. The Toggle Bookmark action dispatches through `toggleBookmarkOpenerProvider` instead; the Pro overlay points both at the same bookmark dialog. Default no-op.
- `violationRowLeadingCellsProvider` — open-core extension point (`lib/plugins/violation_row_leading_cells_provider.dart`) through which the Pro overlay contributes leading cells (prefixed before the open-core severity / engine / rule / file / line / message columns) to each row of the violation table. Default returns an empty list. Each contribution is a `ViolationRowLeadingCell` (stable `id`, fixed `width`, `bodyBuilder`, `headerBuilder`); the table renders the body cell on each row and the header cell at the same horizontal slot so the layout stays aligned. Used by Pro for the bookmark column icon. The seam is intentionally a *prefix*-only API — inserting Pro columns between open-core columns would require open-core to know about Pro column ordering, defeating the open-core / Pro contract.
- `veribleFixServiceProvider` — `Provider<VeribleFixService>` open-core extension point (`lib/services/verible/verible_fix_service_provider.dart`) the Pro overlay overrides with `ProVeribleFixService` (which shells out to the user's installed Verible binary). Open-core default is `NoopVeribleFixService` — `checkAvailability` reports `notInstalled`; `dryRun` returns an empty `VeribleFixBatch`; `apply` returns an empty `List<VeribleFixApplyResult>`.
- `veribleAvailabilityProvider` — `FutureProvider<VeribleAvailability>` (`lib/services/verible/verible_availability_provider.dart`) that watches the active service and caches the result for the session. Consumers `ref.invalidate` after a Settings change to re-probe. Used by the toolbar action's disabled-tooltip surface.
- `lintRunCacheServiceProvider` — `Provider<LintRunCacheService>` open-core extension point (`lib/services/lint_cache/lint_run_cache_service_provider.dart`) the Pro overlay overrides with `SqliteLintRunCacheService` (per-project SQLite-backed implementation). Open-core default is `NoopLintRunCacheService` — every `lookup` returns `null`, `store` discards silently, `invalidate` is a no-op, `stats` reports `LintCacheStats.empty`, and `invalidations` is an empty stream.
- `lintCacheEnabledProvider` — `Provider<bool>` settings-driven toggle (`lib/services/lint_cache/lint_cache_enabled_provider.dart`) that gates whether `ParallelEngineRunner` consults the cache at all. Default `true`. When `false`, no lookups and no stores happen for any engine in any run — equivalent to wiring the no-op service from the runner's perspective. The Pro overlay's `LintCacheSettingsSection` overrides this provider with a notifier backed by `shared_preferences`.
- `lintCacheStatsProvider` / `lintCacheInvalidationsProvider` — `FutureProvider<LintCacheStats>` and `StreamProvider<LintCacheInvalidationEvent>` (`lib/services/lint_cache/lint_cache_stats_provider.dart`). The stats provider refreshes whenever the invalidations stream ticks so the Pro Settings UI updates without polling. On the open-core no-op service, stats resolves to `LintCacheStats.empty` and invalidations is an empty stream.
> **Lives in `crux_projects`.** The project-registry / descriptor /
> workspace / per-project-scope layer described below is shared with
> SimCrux through the `crux-shared/packages/crux_projects` package
> (consumed via `package:crux_projects/crux_projects.dart`). The on-disk
> `workspace.json` contract (JSON keys + `idForPath` hash) is part of that
> package's API.

- `projectRegistryProvider` — `Provider<ProjectRegistry>` open-core extension point (`crux_projects (crux-shared/packages/crux_projects)`) the Pro overlay overrides with `JsonFileProjectRegistry` to activate the multi-project workspace surface. Open-core default is `NoopProjectRegistry` — single-project semantics where opening a project replaces the prior one and recent projects are never retained. The command-palette / menu multi-project actions (`closeActiveProject`, `switchProject`, `pinActiveProject`, …) consume the same provider in single-project and multi-project modes; only the active registry changes. (In LintCrux the visible per-project tab bar is the shared `crux_workspace` tab strip — each tab is bound to a `.lintcrux` project — not a separate registry-driven strip.) Derived providers `projectWorkspaceProvider` (live `Stream<ProjectWorkspace>`), `activeProjectProvider` (active `ProjectDescriptor?`), and `activeProjectIdProvider` (active id string) live alongside.
- `perProjectScope<T>` — open-core helper (`crux_projects (crux-shared/packages/crux_projects)`) that wraps a per-`projectId` family provider so widgets can watch it as if it were a global provider. Internally keys the per-project cache by `activeProjectIdProvider`; state is retained across project switches; re-activating a previous project snaps back to its retained state. The binding contract for any Pro feature whose state is conceptually tied to "this project's results / configuration / analysis" (violations store, waiver store, lint cache, custom regex rules, dashboard filter / sort / column visibility).
- `ProjectWorkspaceSync` — open-core service (`lib/features/workspace/providers/project_workspace_sync.dart`) that keeps the `crux_workspace` tab surface (what the user opens/closes/activates via File → Open and the tab bar) and `projectRegistryProvider` (recents, pins, project switcher, cross-project search) in agreement. Nothing else calls `ProjectRegistry.openProject` / `setActiveProject` / `closeProject`, so without this sync the registry stays permanently empty regardless of which registry implementation is active. It runs a single serialized convergence loop (never per-event handlers, which would let two in-flight passes livelock by alternating activation between an old and a new snapshot) that, per pass: closes workspace tabs for registry-originated closures, activates/opens tabs for registry-originated activation (project switcher, recents "Reopen"), and otherwise treats the workspace tabs as the source of truth — recording unrecorded project tabs as open, closing registry entries whose tab is gone (→ recents), and aligning the registry's active project to the active tab. Under the open-core `NoopProjectRegistry` (replace-on-open, single-project semantics) it auto-detects that mode and degrades to mirroring only the active tab, so recording every tab would not alternate forever. Realized for the app's lifetime via `projectWorkspaceSyncProvider`, anchored directly from `lib/app.dart` rather than through `eagerStartupProvidersProvider` — the Pro overlay replaces that list wholesale, which would silently drop the hook. The Pro overlay's `JsonFileProjectRegistry` binding (`proProjectRegistryOverride`) must hand this sync a stable proxy at boot and attach the hydrated delegate to that *same* proxy (never swap in a different instance), or a call this loop is awaiting can strand on a discarded proxy and hang the convergence loop. Both of the loop's inventories (tab-by-path and registry-open-by-path) are keyed on `canonicalPathKey` from `crux_io`, never on the raw path string: the tab payload carries the path exactly as it arrived (a relative CLI argument, a `..`-bearing Makefile path, `/tmp` where macOS means `/private/tmp`) while `JsonFileProjectRegistry` stores `p.normalize(p.absolute(path))`, and two spellings of one project made the loop re-record it on every convergence pass — 300–500 `openProject` calls in 200 ms, measured — and open a second tab under the registry's own spelling. The registry-originated *activation* step also declines to open a tab while `LintcruxWorkspaceNotifier.launchRestoreDeclined` is set and no tab exists yet: the registry persists its own open-project list to a second `workspace.json`, so honoring it at launch would hand back the session a user who turned off "Restore tabs on launch" just asked not to have.
- `LintcruxWorkspaceCodec.identityOf` — open-core override (`lib/services/workspace/lintcrux_workspace_codec.dart`) of the `crux_workspace` `WorkspaceCodec` seam that answers "is this the same thing the user already has open?". Returns `project:<canonicalPathKey(projectPath)>`, or `null` for the empty-canvas payload (which has no identity, so two blank tabs stay openable); the `project:` namespace keeps a future second payload kind from colliding with a project tab merely by naming the same file. `WorkspaceNotifier.openTab` deduplicates on it by default, which is what makes a CLI open of an already-open project focus that tab instead of stacking another copy of it — the defect that accumulated one tab per launch, unbounded. `OpenProjectInWorkspace.openProject` checks `tabWithSameIdentityAs` first and skips the project reload + engine re-run when it deduped (a focus must not discard the run the user is looking at), reporting the focused `tabId` and a `deduped` flag on `OpenProjectSuccess` so the session importer replays filters onto the right tab rather than onto `tabs.last`.
- `launchRestoreDecisionProvider` — `Provider<bool>` (`lib/services/persistence/restore_tabs_settings_provider.dart`) holding whether this launch rehydrates the persisted workspace document. `LintcruxWorkspaceNotifier.shouldRestoreOnLaunch` reads it **synchronously** before `WorkspaceService.load`; declining starts from an empty workspace and leaves the document on disk untouched, so turning the preference back on restores the session that was there. The default is `true`; `bootstrap` resolves `loadRestoreTabsOnLaunch()` once, before `runApp`, and overrides the provider with the persisted answer (key `settings.restoreTabsOnLaunch`, shared with `CoreSettingsCodec` and therefore the same key a `defaults write flutter.settings.restoreTabsOnLaunch` sets). **The launch gate must not await storage.** `SharedPreferences.getInstance()` replies on the real event loop, which the fake-async zone a `testWidgets` body runs in never advances, so a future awaited on this path before the first pump never completes and every workspace-touching widget test times out rather than failing. Two nearby workarounds are also wrong: awaiting `appSettingsProvider.future` additionally hands the launch to Riverpod's failure retry, and stubbing the settings *service* in tests resolves `appSettingsProvider`, which panel-layout state watches. Resolving the value in `bootstrap` and handing the notifier a plain `bool` removes the await entirely.

Each provider lives in its own file and ships an open-core default that produces no visible change. The Pro overlay's `proOverrides` list registers the concrete contributions.

---

## 12. Glossary

- **CXP** — *Cross-Tool eXchange Protocol*. Peer cross-probe protocol shared across the EDACrux suite (WaveCrux, NetCrux, LintCrux, SimCrux). Specifies the message vocabulary (Hello / HelloAck, Goodbye, Subscribe / Unsubscribe, NotifySelection, RequestHighlight / RequestHighlightAck, RequestOpenSource / RequestOpenSourceAck, RequestOpenArtifact / RequestOpenArtifactAck, ErrorResponse), the newline-delimited JSON wire format, and the manifest-file discovery convention. Implemented in `package:crux_cxp` from the `crux-shared` Melos workspace.
- **CXP server (LintCrux)** — `LintCruxCxpServer`, a thin wrapper around `LocalCxpServer` that owns the LintCrux `PeerIdentity`, registers `LintCruxNameResolver`, and exposes the receive-side surface (`start` / `stop` / `sendTo` / inbound-callback). Bound to `127.0.0.1` on a configurable port (default `54324`, the LintCrux slot in the suite-wide port allocation).
- **Cross-probe panel** — `LintCruxCrossProbePanel` (`lib/features/remote/widgets/cross_probe_panel.dart`), a docked tab (right dock by default, movable to the bottom dock) rendering connected and unreachable peers, the rolling event log, the CXP server status, and a per-peer Send action. Toggled by `LintcruxAction.openCrossProbePanel` — View menu, command palette, the toolbar Cross-Probe Panel button, or Cmd/Ctrl+Shift+X.
- **Manifest directory** — shared filesystem directory at `${appSupport}/crux/cxp/peers/` where every running Crux peer writes a JSON manifest describing its `PeerIdentity` + bound host/port + start timestamp. Peers watch the same directory to discover one another. Stale manifests (`started_at` older than 5 minutes) are pruned by `CxpDiscovery`.
- **NameResolver (`LintCruxNameResolver`)** — pluggable mapping between LintCrux's local element references (violation rows, source citations) and canonical CXP `ElementId`s. Owns `rule` and `source`; passes `signal` / `instance` through verbatim for filter-routing semantics; returns `null` for unrelated kinds.
- **`NoopWaiverStore`** — open-core default `WaiverStore` (`lib/services/waivers/noop_waiver_store.dart`). Permanently empty; `match()` always returns `null`; mutation methods throw `UnsupportedError` because the managed waiver system is a Pro feature. The Pro overlay's `JsonFileWaiverStore` overrides `waiverStoreProvider` to swap this out.
- **`ManagedWaiverTransformer`** — `ViolationTransformer` (`lib/services/transformers/managed_waiver_transformer.dart`) that consults a `WaiverStore` and tags violations with their matching `Waiver`. Already-suppressed violations pass through unchanged — source pragmas (handled by the upstream `PragmaWaiverTransformer`) always beat managed waivers.
- **`LintBaseline`** — snapshot of every active violation at a single point in time (`lib/domain/models/lint_baseline.dart`). A project has at most one active baseline at a time. Schema-versioned. Pro-tier feature; open-core ships the model so the run pipeline's `BaselineFilter` can reference it under the no-op store.
- **`BaselineViolation`** — frozen violation record stored inside a `LintBaseline` (`lib/domain/models/baseline_violation.dart`). Carries `fingerprint`, `ruleId`, `filePath`, `line`, and `message`. The `fingerprint` deliberately excludes the line number so a violation that shifts down by a few lines is still recognized as the same defect.
- **`BaselineFingerprint`** — stable FNV-1a 64-bit hash of `(ruleId, project-relative filePath, normalized-message)` (`lib/domain/models/baseline_violation.dart`). Whitespace in the message is normalized (runs collapsed, edges trimmed) so reflowing or trailing newlines don't move the fingerprint.
- **`BaselineDelta`** — result of `BaselineFilter.classify` (`lib/domain/models/baseline_delta.dart`). Splits the current run into `newViolations`, `persistingViolations`, and `resolvedViolations`. The CLI `--fail-on-new-violations` exit code is derived from `hasNewViolations`.
- **`BaselineFilter`** — pure-function classifier (`lib/services/baseline/baseline_filter.dart`). No I/O — the run pipeline calls `classify` after the transformer chain so the result reflects suppressions and severity overrides.
- **`NoopBaselineStore`** — open-core default `BaselineStore` (`lib/services/baseline/noop_baseline_store.dart`). `activeBaseline()` returns `null`; `setBaseline()` throws `UnsupportedError`; `clearBaseline()` is an idempotent no-op. The Pro overlay's `JsonFileBaselineStore` overrides `baselineStoreProvider` to swap this out.
- **`BaselineAuditSink`** — append-only audit-trail interface for baseline mutations (`lib/services/baseline/baseline_audit_sink.dart`). `NoopBaselineAuditSink` is the open-core default; the Pro overlay's file-based sink writes JSON-lines to `<project-root>/.lintcrux-baseline.audit.jsonl`. Audit writes are best-effort — failures must not block the underlying mutation.
- **`baselineComparisonOpenerProvider`** — open-core extension point (`lib/plugins/baseline_comparison_opener_provider.dart`) the Pro overlay overrides with a callback that mounts the baseline-vs-current comparison screen. Default is `null`, so `LintcruxAction.openBaselineComparison` surfaces the "requires LintCrux Pro" snackbar in the open-core build.
- **`currentBaselineSnapshotProvider`** — open-core synchronous mirror of the active `LintBaseline` (`lib/services/baseline/current_baseline_snapshot_provider.dart`). Default returns `null`. The Pro overlay overrides this with the latest value emitted by `baselineStoreProvider.watch()` so `visibleViolationsProvider`'s `_derive` can apply view-mode post-filtering without await-points.
- **`ViolationViewMode`** — three-state view-mode selector for the violation table (`lib/domain/enums/violation_view_mode.dart`): `allViolations` / `onlyNew` / `onlyResolved`. Default `allViolations`. The post-filter consults the current baseline snapshot when the mode is anything other than `allViolations`; `onlyResolved` returns an empty list at the table layer (resolved entries are rendered by the Pro `BaselineComparisonScreen` from frozen baseline records, not from live violations).
- **`violationViewModeProvider`** — `NotifierProvider<ViolationViewModeNotifier, ViolationViewMode>` (`lib/features/violations/providers/violation_view_mode_provider.dart`) the Pro `BaselineViewModeToggle` writes to. Open-core consumers read it through `visibleViolationsProvider`.
- **`violationTableTopActionsProvider`** — open-core extension point (`lib/plugins/violation_table_top_actions_provider.dart`) through which Pro contributes widgets to the violation table's top action row (baseline set/clear toolbar, view-mode toggle, status chip). Default returns an empty list.
- **`ViolationTrendStore`** — abstract interface (`lib/domain/interfaces/violation_trend_store.dart`) for cross-run violation history. `ingestRunCompletion(LintRunCompletionEvent)` records every violation; `queryDataPoints` / `queryAggregates` drive the Pro chart screens; `applyRetention` enforces the active `TrendRetentionPolicy`; `storageStats` reports utilization; `dataChanged` emits after every mutation. Open-core default `NoopViolationTrendStore` is in-memory; the Pro overlay supplies SQLite-backed persistence.
- **`ViolationTrendDataPoint`** — one row in the trend store (`lib/domain/models/violation_trend_data_point.dart`). Carries `runId`, `runTimestamp`, `ruleId`, `severity`, `filePath`, optional `lineNumber`, and `message`. Drops column number — line is sufficient granularity for trend analysis.
- **`ViolationTrendAggregate`** — bucketed summary returned by `ViolationTrendStore.queryAggregates` (`lib/domain/models/violation_trend_aggregate.dart`). Keyed by `ViolationTrendAggregateKey` (`perRule` / `perSeverity` / `perFile` / `global`). Sum of `severityBreakdown.values` equals `totalViolations`.
- **`TrendRetentionPolicy`** — retention configuration (`lib/domain/models/trend_retention_policy.dart`). `maxAgeDays` and `maxRunsRetained` are optional; `pruneStrategy` is `oldestFirst` by default. `proDefault` is 90 days / 1000 runs.
- **`ViolationTrendAlert`** — anomaly produced by the Pro `ViolationTrendAlertDetector` (`lib/domain/models/violation_trend_alert.dart`). Three kinds: `severityClassDrift` / `newPersistentRule` / `suddenSpike`. Severity tier drives banner color.
- **`LintRunCompletionEvent`** — project-wide completion event consumed by the trend store (`lib/domain/models/lint_run_completion_event.dart`). Carries `runId`, `runTimestamp`, and the per-violation data point list post-transformer-chain. Producers reside in the Pro overlay; the open-core seam is `lintRunCompletionEventProvider` (empty by default).
- **`LintRunCompletionDispatcher`** — abstract interface (`lib/domain/interfaces/lint_run_completion_dispatcher.dart`) bridging per-engine `RunCompleted` events to project-wide `LintRunCompletionEvent`s. Open-core default `NoopLintRunCompletionDispatcher` does nothing. The Pro overlay provides a concrete dispatcher that watches `lintRunProvider` for full-run transitions, builds a snapshot of every active violation, and pumps it through `lintRunCompletionEventProvider`. One dispatcher per tab: `ProjectTabContent` realizes it in the tab's container, so `start()` runs before the tab's first run completes; `stop()` on container dispose.
- **`dashboardBannersProvider`** — open-core extension point (`lib/plugins/dashboard_banners_provider.dart`) for full-width banner contributions atop the violations panel. Distinct from `violationTableTopActionsProvider` (inline `Row` controls): banners are `MaterialBanner`-style notices. `ViolationTable` stacks them in list order between its top-action row and the filter chips; Pro contributes the trend alerts, Verible auto-run and waiver expiration banners. Each contribution is responsible for its own dismissal logic, tier badging, and "render nothing when empty" behavior.
- **`FilterPreset`** — Pro-tier named filter preset for the violations table (`lib/domain/models/filter_preset.dart`). Three flavors: built-in (shipped by open-core, non-deletable, stable id), user-authored (saved via the Pro "Save current as preset…" dialog, persisted to `<project-root>/.lintcrux-filter-presets.json`), and reserved-for-shared-team. Carries metadata (`id`, `description`, `createdAt`, `updatedAt`, `sortOrder`, `builtin`) plus a JSON-natural `filterState` map. Distinct from `NamedFilterPreset` (the earlier model the Filter preset dropdown saves in `LintProject.filterPresets`, written back to the project's `.lintcrux`); the two coexist on the violations table.
- **Built-in filter presets** — three shipped-by-open-core `FilterPreset`s exposed even on the Noop store: `kBuiltinAllViolationsPresetId` (empty filter), `kBuiltinErrorsOnlyPresetId` (fatal+error severities), `kBuiltinNewViolationsPresetId` (`viewMode: onlyNew`, falls back gracefully when no baseline is active). Defined in `lib/services/filter_presets/builtin_presets.dart`. Sort orders occupy the reserved `0`–`99` range so user-authored presets sort after them.
- **`FilterPresetStore`** — abstract persistence interface for `FilterPreset`s (`lib/domain/interfaces/filter_preset_store.dart`). Open-core ships `NoopFilterPresetStore` seeded with the built-in list — `addOrUpdate` / `remove` throw `UnsupportedError`; `changed` is an empty stream. The Pro overlay supplies `JsonFileFilterPresetStore` reading/writing `<project-root>/.lintcrux-filter-presets.json` with built-in protection (any attempt to mutate a built-in throws `ArgumentError`).
- **`overlayFilterPreset`** — pure helper (`lib/services/filter_presets/filter_preset_overlay.dart`) that overlays a `FilterPreset`'s `filterState` on top of a user-supplied `ViolationFilter` + `ViolationViewMode`. Returns `FilterPresetOverlayResult{effectiveFilter, effectiveViewMode}`. Severities / engineIds intersect; substrings / globs preset-wins-when-non-empty; `includeSuppressed` ORs; viewMode preset-wins-when-present. Identity when the preset is `null`.
- **`activeFilterPresetProvider`** — per-tab Riverpod provider tracking the currently-applied `FilterPreset`. `VisibleViolationsNotifier` watches this and applies `overlayFilterPreset` inside its derive function so the preset short-circuits when `null` (preserves the existing table-state-only behavior exactly).
- **`BookmarkedViolation`** — Pro-tier bookmark of a single violation for follow-up (`lib/domain/models/bookmarked_violation.dart`). Identity is the `fingerprint` (identical to `BaselineFingerprint.forProject` — same hash inputs so bookmarks and baselines agree on violation identity; a version 1 bookmark is upgraded with `withProjectFingerprint` by the store that knows the project root). Carries the violation snippet, an optional markdown `note`, an optional color tag, and `lastSeenRunId` for stale-detection. Schema-versioned; round-trippable via `toJson` / `fromJson`.
- **`ViolationBookmarkStore`** — abstract persistence interface for `BookmarkedViolation`s (`lib/domain/interfaces/violation_bookmark_store.dart`). Open-core ships `NoopViolationBookmarkStore` (empty list; silent no-op mutations — bookmarks are a Pro feature so silent rather than throw). The Pro overlay supplies `JsonFileViolationBookmarkStore` reading/writing `<project-root>/.lintcrux-bookmarks.json` with stale-detection wired into `lintRunCompletionEventProvider`.
- **`bookmarkToggleHandlerProvider`** — open-core extension point read by the Pro bookmark column icon; the Toggle Bookmark action dispatches through `toggleBookmarkOpenerProvider` instead, and the Pro overlay points both at the same bookmark dialog. Default open-core handler is a no-op.
- **`VeribleFixProposal`** — one Verible-proposed textual replacement (`lib/domain/models/verible_fix_proposal.dart`). Carries the synthetic id, file path, 1-based inclusive line range, before / after text, description, rule id, and a `VeribleFixConfidence` enum (high / medium / low). Schema-versioned via `toJson` / `fromJson`.
- **`VeribleFixBatch`** — dry-run output (`lib/domain/models/verible_fix_batch.dart`). Holds the ordered `proposals` list plus `batchId`, `generatedAt`, `sourceProject`, and `dryRunOnly` (flips from true to false after apply). Convenience `confidenceCounts` getter buckets proposals by confidence band for the review-dialog header.
- **`VeribleFixApplyResult`** — per-proposal outcome (`lib/domain/models/verible_fix_apply_result.dart`). `VeribleFixApplyOutcome.applied` / `skippedByUser` / `conflictedWithOtherFix` / `failed`. Conflict carries `conflictingProposalId`; failure carries `errorMessage`.
- **`VeribleAvailability`** — snapshot of the local Verible install (`lib/domain/models/verible_availability.dart`). Status (`notInstalled` / `installedButOldVersion` / `available`), binary path, parsed version, declared capability set (`structuredJsonOutput` / `dryRunMode` / `perRuleScoping`), and a human-readable `missingHint` for the not-installed / old-version cases.
- **`VeribleFixService`** — three-method service interface (`lib/domain/interfaces/verible_fix_service.dart`): `checkAvailability()` returns `VeribleAvailability`; `dryRun({scopeFilter, specificRules})` returns a `VeribleFixBatch`; `apply(batch, selectedIds)` returns a `List<VeribleFixApplyResult>`. Open-core ships `NoopVeribleFixService` (notInstalled / empty / empty); the Pro overlay's `ProVeribleFixService` shells out to the installed binaries.
- **`LintRunCacheService`** — cache surface consulted by `ParallelEngineRunner` before each engine invocation (`lib/domain/interfaces/lint_run_cache_service.dart`). Returns `LintCacheEntry?` on `lookup`; persists pre-transformer engine output via `store`; supports targeted `invalidate` events; emits the same events back on `invalidations` for the Pro Settings UI's rolling log. Open-core ships `NoopLintRunCacheService` so the runner integration is unconditional.
- **`LintCacheKey`** — composite identifier (`lib/domain/models/lint_cache_key.dart`) of one cached lint result: `engineId`, `sourceFingerprint` (SHA-256 of the source file's LF-normalized bytes), `configFingerprint` (SHA-256 of the canonical engine-config snapshot — sorted keys, normalized binary path, no environment leakage), `engineVersion` (the engine's reported `--version` at run time). Equality is structural; any field mismatch is a cache miss.
- **`LintCacheEntry`** — one stored lint result (`lib/domain/models/lint_cache_entry.dart`). Pairs the `key` with the pre-transformer `violations` list plus audit metadata (`createdAt`, `lastAccessedAt`, `runDurationMs`, `filePath`) used by the stats card and the Pro store's LRU eviction.
- **`LintCacheStats`** — cache-wide statistics aggregate (`lib/domain/models/lint_cache_stats.dart`). Returned by `LintRunCacheService.stats`. Includes `entryCount`, `approximateBytes`, `hitCount` / `missCount` / `invalidationCount` (monotonic across the cache's lifetime), `oldestEntryAt` / `newestEntryAt`, `averageRunDurationMs`, and `estimatedTimeSavedMs` (cached run-duration × hit-count proxy). Convenience `hitRate` getter in `[0, 1]`.
- **`LintCacheInvalidationEvent`** — sealed event hierarchy describing why entries were dropped (`lib/domain/models/lint_cache_invalidation_event.dart`). Subtypes: `LintCacheInvalidationFileChanged` (file watcher tick → file-scoped drop), `LintCacheInvalidationConfigChanged` (engine config edit → engine-scoped drop), `LintCacheInvalidationEngineVersionChanged` (engine upgraded → version-scoped drop), `LintCacheInvalidationManualClear` ("Clear cache now" or `clearAll`), `LintCacheInvalidationRetentionPrune` (LRU eviction at size budget). Pro's invalidations dialog renders a rolling log of these events.
- **`NoopLintRunCacheService`** — open-core default `LintRunCacheService` implementation. Every operation is a silent no-op so the runner can call into the cache surface unconditionally. Open-core users see no behavioral change; the Pro overlay swaps in `SqliteLintRunCacheService` via `proOverrides`.
- **`CacheFingerprint`** — pure-Dart fingerprint helpers (`lib/services/lint_cache/cache_fingerprint.dart`) shared by the runner integration. `sourceOf(filePath)` / `sourceOfBytes(bytes)` produce SHA-256 hex digests with CRLF normalized to LF (so checkout flips don't invalidate the cache). `configOf(request)` canonicalizes the engine config (sorted map keys, normalized binary path, language enum names, options-bag null-stripped) and hashes the result. Deterministic across machines and locales.
- **`CacheViolationCodec`** — round-trip codec (`lib/services/lint_cache/cache_violation_codec.dart`) that the SQLite-backed store uses to serialize cached `Violation` lists. Lives next to the cache (not in `lib/services/sarif/`) because SARIF round-trip is lossy on the wrapper; the cache needs verbatim round-trip on every wrapper field. `suppression` is intentionally NOT round-tripped — the cache stores pre-transformer engine output so waivers / severity overrides / pragmas are honored on every hit, not invalidated by config edits.
- **`ProjectDescriptor`** — stable metadata descriptor of one LintCrux project loaded into the multi-project workspace (`crux_projects (crux-shared/packages/crux_projects)`). Carries the deterministic `id` (FNV-1a hash of the path), the user-facing `displayName`, the absolute `projectPath`, `loadedAt` / `lastAccessedAt` timestamps, and the `isPinned` flag. Per-project state (violations, waivers, custom rules, dashboard filters) lives in per-project Riverpod scopes keyed by `id`; the descriptor itself is the lookup key, not the state container. JSON round-trippable and forward-compatible (unknown keys ignored).
- **`ProjectWorkspace`** — snapshot of the multi-project workspace (`crux_projects (crux-shared/packages/crux_projects)`). Captures `openProjects` (in tab order), `activeProjectId`, and `recentProjects` (MRU-ordered, capped at `recentProjectsCap = 10`). Schema-versioned. Distinct from `Workspace` (`crux_workspace`) which holds the multi-tab / multi-pane *viewing* state — `ProjectWorkspace` holds the set of open *projects*, each of which may host one or more tabs.
- **`ProjectRegistry`** — abstract extension-point interface managing the multi-project workspace (`crux_projects (crux-shared/packages/crux_projects)`). Methods: `openProject` / `closeProject` / `closeAllProjects` / `setActiveProject` / `pinProject` / `reorderProjects` / `clearRecentProject` / `shutdownAll`, plus a live `watch()` stream and synchronous `current` snapshot. Open-core binds `NoopProjectRegistry` (single-project semantics — opening replaces; pin/reorder are no-ops); the Pro overlay binds the package's `JsonFileProjectRegistry`, persisting workspace state to `<appSupportDir>/lintcrux/workspace.json`.
- **`NoopProjectRegistry`** — open-core default `ProjectRegistry` (`crux_projects (crux-shared/packages/crux_projects)`). Implements single-project semantics: `openProject` replaces any prior project; `closeProject` hard-clears (recents always empty); `pinProject` / `reorderProjects` / `clearRecentProject` are no-ops. The Pro overlay's `JsonFileProjectRegistry` overrides `projectRegistryProvider` to activate the multi-project surface.
- **`perProjectScope`** — open-core helper (`crux_projects (crux-shared/packages/crux_projects)`) that constructs a Riverpod provider whose state is scoped per active project. Internally keys the per-project cache by `activeProjectIdProvider`; widgets watch the returned provider as if it were global (no `family.call(id)` boilerplate at the call site). State retained across project switches; re-activating a previous project snaps back to its retained state. The binding contract for any Pro feature whose state is conceptually tied to "this project's results / configuration / analysis." Mirrors SimCrux's `perProjectScope`.

> **Project tabs.** LintCrux does not render a dedicated registry-driven project tab strip. Each `crux_workspace` tab is bound to a `.lintcrux` project (`LintcruxTabPayload.projectPath`), so the shared `crux_workspace` tab bar *is* the per-project switcher; `openProject` opens a tab via `openProjectInWorkspaceProvider`. Unifying the `ProjectRegistry` model with the `crux_workspace` tab model is deferred; until then the registry backs only the command-palette / menu multi-project actions, not a visible strip.

Other terms not defined here follow WaveCrux's glossary at `wavecrux/docs/ARCHITECTURE.md` §12.

---

## Revision History

This document tracks changes via `git log`.
