// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One entry of the LintCrux event catalog: an event name and the closed
/// vocabulary of each property it may carry.
///
/// [enumeratedValues] lists the string values a property key is allowed to
/// take. A key mapped to an empty list carries something that is not a closed
/// string set — a bool, or a bounded integer — and is checked by the
/// conformance test's per-key rules instead.
@immutable
class TelemetryCatalogEvent {
  /// Pins one catalog event and its property vocabulary.
  const TelemetryCatalogEvent(
    this.name, {
    this.enumeratedValues = const <String, List<String>>{},
    this.boolProperties = const <String>[],
    this.intProperties = const <String>[],
  });

  /// The catalog event name, as recorded.
  final String name;

  /// String-valued properties → every value the call site may emit.
  final Map<String, List<String>> enumeratedValues;

  /// Properties whose value is a `bool`.
  final List<String> boolProperties;

  /// Properties whose value is a bounded integer.
  final List<String> intProperties;

  /// Every property key this event may carry.
  Iterable<String> get propertyKeys => <String>[
    ...enumeratedValues.keys,
    ...boolProperties,
    ...intProperties,
  ];
}

/// **The** LintCrux event catalog — every telemetry event either repository
/// may record, with the closed vocabulary of every property.
///
/// This list is the single source of truth for LintCrux telemetry events. Two
/// tests hold it to that role: one scans both source trees and fails on an
/// event name that is recorded but not listed here, and one checks every name,
/// key and value in this list against the ingestion Worker's grammar.
///
/// The second check is the load-bearing one. The Worker drops a malformed
/// event name *silently* — the batch still returns 202, the row is counted
/// only in the response's `dropped` field, and the client is not told. A
/// property whose key or value fails its class is dropped while the event is
/// kept, which is worse: the counter looks healthy and its dimension is
/// simply, permanently empty. Neither failure is visible from the app, from
/// the queue, or from a dashboard that has never seen the missing rows. The
/// conformance test is the only place either one can be caught.
///
/// ## The LintCrux-specific hazard
///
/// The suite telemetry policy (https://edacrux.app/telemetry) allows engine and
/// rule *names* as application vocabulary and bans "lint rule names paired with
/// file content" and "lint output bodies" outright. This catalog therefore
/// carries **engine** ids and no rule ids at all: `rule_doc.viewed` reports
/// which engine's rule database was consulted, never which rule, and nothing
/// anywhere carries a violation message, a file name, or a source excerpt.
/// `telemetryEngineToken` is what keeps the engine dimension closed — see its
/// own doc for why it is a hand-written `switch` and not a sanitizer.
const List<TelemetryCatalogEvent> kLintcruxEventCatalog =
    <TelemetryCatalogEvent>[
      // ── workspace, tabs, panes (open core) ─────────────────────────────────
      // The same eight names WaveCrux records, with the same properties. A
      // suite-wide "how many tabs do people actually keep open" question that
      // resolved differently per product would answer nothing.
      TelemetryCatalogEvent(
        'workspace.restored',
        intProperties: <String>['tabs', 'panes'],
      ),
      TelemetryCatalogEvent('workspace.created'),
      TelemetryCatalogEvent('workspace.reset'),
      TelemetryCatalogEvent('workspace.named.saved'),
      TelemetryCatalogEvent(
        'workspace.named.opened',
        intProperties: <String>['tabs', 'panes'],
      ),
      TelemetryCatalogEvent(
        'tab.opened',
        intProperties: <String>['tabs', 'panes'],
      ),
      TelemetryCatalogEvent('pane.split'),
      TelemetryCatalogEvent('pane.closed'),

      // ── the lint run (open core) ───────────────────────────────────────────
      TelemetryCatalogEvent(
        'run.completed',
        enumeratedValues: <String, List<String>>{
          // `LintRunTrigger.values` under `telemetryEnumToken`; the
          // conformance test derives the same list from the enum.
          'trigger': <String>['manual', 'auto', 'cli'],
        },
        intProperties: <String>['engines'],
      ),
      TelemetryCatalogEvent(
        'engine.run',
        enumeratedValues: <String, List<String>>{
          'engine': kLintcruxEngineTokens,
          // `EngineRunOutcome.values` under `telemetryEnumToken`.
          'status': <String>['ok', 'timeout', 'crash', 'missing'],
        },
      ),

      // ── triage (open core) ─────────────────────────────────────────────────
      TelemetryCatalogEvent(
        'project.opened',
        enumeratedValues: <String, List<String>>{
          'source': <String>['picker', 'filelist', 'edam', 'recent'],
        },
      ),
      TelemetryCatalogEvent(
        'filter.used',
        enumeratedValues: <String, List<String>>{
          'kind': <String>['severity', 'engine', 'rule', 'file', 'preset'],
        },
      ),
      TelemetryCatalogEvent(
        'view_mode.changed',
        enumeratedValues: <String, List<String>>{
          // `ViolationViewMode.values` under `telemetryEnumToken`. The first
          // constant is `allViolations`, so the token is `all_violations`,
          // not the shorter `all`: the enum is authoritative.
          'mode': <String>['all_violations', 'only_new', 'only_resolved'],
        },
      ),
      TelemetryCatalogEvent(
        'search.used',
        enumeratedValues: <String, List<String>>{
          'mode': <String>['substring', 'glob', 'regex'],
        },
      ),
      TelemetryCatalogEvent(
        'rule_doc.viewed',
        // The engine whose rule database answered, and nothing else. A rule
        // id here would breach the never-collect list on its own and far worse
        // paired with the file the violation came from — so the rule id never
        // leaves the process, and the property that would carry it does not
        // exist.
        enumeratedValues: <String, List<String>>{
          'engine': kLintcruxEngineTokens,
        },
      ),
      TelemetryCatalogEvent(
        'editor.launched',
        enumeratedValues: <String, List<String>>{
          // `EditorPreset.values` under `telemetryEnumToken`. The first
          // constant is `vsCode`, so the token is `vs_code`, not `vscode`:
          // the enum is authoritative.
          'preset': <String>['vs_code', 'sublime', 'vim', 'emacs', 'custom'],
        },
        boolProperties: <String>['ok'],
      ),
      TelemetryCatalogEvent(
        'export.completed',
        enumeratedValues: <String, List<String>>{
          'format': <String>['sarif', 'json', 'csv', 'html'],
        },
      ),
      TelemetryCatalogEvent('sarif.imported'),
      TelemetryCatalogEvent(
        'cxp.crossprobe',
        enumeratedValues: <String, List<String>>{
          'direction': <String>['inbound', 'outbound'],
        },
        boolProperties: <String>['honored'],
      ),

      // ── recorded by the shared telemetry package ─────────────────────
      // `crux_telemetry`'s `TelemetryUncaughtErrorCounter` records this from
      // the global error handlers `captureFlutterErrors` installs, so no call
      // site in either repository spells it. At most once per (source, kind,
      // library) per session and ten per session; never the message, the stack
      // or a file name. `kind` is the error's class bucketed by `is` checks,
      // never its runtime type name, and `library` is the Flutter framework
      // library that reported it. The value lists mirror the package's
      // `kTelemetryUncaughtError*` constants, which the ingestion Worker
      // enforces value by value for this one event.
      //
      // They are copies, not references, and must stay that way: the headless
      // `lintcrux` binary reaches this file through `HeadlessTelemetry`, and
      // `package:crux_telemetry` imports Flutter, so importing it here stops
      // the CLI from compiling at all. The catalog conformance test, which
      // may import Flutter, holds each list equal to the package's constant.
      TelemetryCatalogEvent(
        'app.uncaught_error',
        enumeratedValues: <String, List<String>>{
          'source': <String>['flutter', 'platform'],
          'kind': <String>[
            'flutter_error',
            'state_error',
            'argument_error',
            'range_error',
            'format_exception',
            'file_system_exception',
            'io_exception',
            'platform_exception',
            'timeout_exception',
            'type_error',
            'no_such_method_error',
            'assertion_error',
            'unsupported_error',
            'concurrent_modification_error',
            'out_of_memory_error',
            'stack_overflow_error',
            'other',
          ],
          'library': <String>[
            'framework',
            'foundation',
            'animation',
            'gestures',
            'painting',
            'image_resource_service',
            'rendering',
            'scheduler',
            'semantics',
            'services',
            'widgets',
            'widget_inspector',
            'material',
            'none',
            'other',
          ],
        },
        boolProperties: <String>['silent'],
      ),

      // ── the commercial group ───────────────────────────────────────────────
      // Recorded on the Pro overlay's gate-denial path (`proFeatureAvailable`),
      // which is the only place `CruxUpgradeDialog.show` is reached from. It
      // measures the one thing feature-usage counters structurally cannot:
      // which paid features people reach for and do NOT have.
      //
      // Dormant until the beta ends, by construction — the gate admits every
      // tier while `betaPeriodProvider` is true, so no build shipping today can
      // emit this. That is not dead code to be tidied away; it is the same dark
      // launch the rest of the pipeline is under.
      //
      // GUI-only by construction too: `lintcrux --ci` has no dialog to raise
      // and no tier to deny at, and `HeadlessTelemetry` exposes no method that
      // could record this.
      TelemetryCatalogEvent(
        'tier.gate_hit',
        enumeratedValues: <String, List<String>>{
          // `LintcruxGatedFeature.values` under `telemetryEnumToken`.
          'feature': kLintcruxGatedFeatureTokens,
          // `LicenseTier.pro.name` / `LicenseTier.enterprise.name`. Never
          // `openCore` or `edu`: a gate demands a tier, and no gate demands
          // either of those (EDU is Pro-equivalent for gating).
          'required': <String>['pro', 'enterprise'],
        },
      ),

      // ── Pro overlay ────────────────────────────────────────────────────────
      TelemetryCatalogEvent(
        'waiver.created',
        enumeratedValues: <String, List<String>>{
          // `WaiverScope.values` under `telemetryEnumToken`.
          'scope': <String>['file', 'line', 'range'],
        },
        boolProperties: <String>['expires'],
      ),
      TelemetryCatalogEvent('waiver.deleted'),
      TelemetryCatalogEvent('baseline.set'),
      TelemetryCatalogEvent(
        'trend.chart_opened',
        enumeratedValues: <String, List<String>>{
          // `TrendChartKind.values` under `telemetryEnumToken`.
          'chart': <String>[
            'project',
            'per_rule',
            'severity_drift',
            'calendar',
          ],
        },
      ),
      TelemetryCatalogEvent(
        'autofix.run',
        enumeratedValues: <String, List<String>>{
          // `AutofixStage.values` under `telemetryEnumToken`.
          'stage': <String>['dry_run', 'applied'],
        },
      ),
      TelemetryCatalogEvent('cache.lookup', boolProperties: <String>['hit']),
      TelemetryCatalogEvent(
        'custom_rule.evaluated',
        enumeratedValues: <String, List<String>>{
          // `CustomRulePatternKind.values` under `telemetryEnumToken`.
          'kind': <String>['source_text', 'signal_name', 'identifier'],
        },
      ),
      TelemetryCatalogEvent(
        'bookmark.saved',
        boolProperties: <String>['edit', 'note'],
      ),
      TelemetryCatalogEvent(
        'filter_preset.saved',
        boolProperties: <String>['edit'],
      ),
      TelemetryCatalogEvent(
        'cross_project.searched',
        intProperties: <String>['projects'],
      ),
    ];

/// The closed `engine` vocabulary, shared by `engine.run` and
/// `rule_doc.viewed`.
///
/// The six ids `defaultEngineRegistry()` ships, plus `custom` for the
/// synthetic custom-regex-rule slice (`kCustomRuleEngineId`) and `other` for
/// anything a future registry or a Pro engine pack adds. The token is
/// `custom`, not `custom_rules`, because the catalog follows the constant —
/// see [telemetryEngineToken].
///
/// `custom` cannot appear on `engine.run`: custom-regex rules are evaluated
/// in-process by `LintRunNotifier._evaluateCustomRules` and never produce an
/// `EngineRunStatus`. It is listed once for both events rather than split,
/// because a vocabulary that differed between the two would eventually be
/// edited in one place only.
const List<String> kLintcruxEngineTokens = <String>[
  'verilator',
  'verible',
  'slang',
  'yosys',
  'ghdl',
  'svlint',
  'cdc',
  'custom',
  'other',
];

/// Maps an engine id onto the closed [kLintcruxEngineTokens] vocabulary.
///
/// This is **not** a `String → String` sanitizer, and the distinction matters:
/// a sanitizer would accept any string and wash it into something that passes
/// the Worker's character class, which is exactly how a rule id or a file name
/// would leak past a check that cannot see the difference. This is a `switch`
/// over literals with a literal fallback — the output is drawn from a list
/// written down in this file, so an id the registry grows tomorrow reports
/// `other` rather than itself. That is the same closed-set guarantee
/// `telemetryEnumToken` gives, spelled out by hand because LintCrux's engine
/// ids are `String`s on the `LintEngine` interface rather than a Dart enum
/// (the package's own doc calls this case out).
///
/// The conformance test asserts every id `defaultEngineRegistry()` actually
/// ships maps to itself, so an engine added to the registry without being
/// added here fails the build instead of silently reporting `other`.
String telemetryEngineToken(String engineId) => switch (engineId) {
  'verilator' => 'verilator',
  'verible' => 'verible',
  'slang' => 'slang',
  'yosys' => 'yosys',
  'ghdl' => 'ghdl',
  'svlint' => 'svlint',
  'cdc' => 'cdc',
  'custom' => 'custom',
  _ => 'other',
};

/// Which triage filter the user reached for.
///
/// LintCrux has no pre-existing enum for this — the filters are four separate
/// setters on `ViolationTableNotifier` plus the saved-preset dropdown — so the
/// vocabulary is declared once, here, and `telemetryEnumToken` turns it into
/// the property value. Declaring it beats five string literals at five call
/// sites for the usual reason: the compiler now owns the closed set.
enum LintcruxFilterKind {
  /// The severity chips.
  severity,

  /// The per-engine chips.
  engine,

  /// The rule-substring field.
  rule,

  /// The file-glob field.
  file,

  /// A saved filter preset was activated.
  preset,
}

/// What started a lint run.
///
/// `manual` is the Run action (toolbar, menu, shortcut, or opening a project);
/// `auto` is the file-watcher's incremental re-run; `cli` is the headless
/// `lintcrux --ci` binary. The three answer "manual vs auto-reload vs CI
/// usage mix".
enum LintRunTrigger {
  /// A user-initiated run.
  manual,

  /// A run the file watcher started after a source file changed.
  auto,

  /// A run from the headless binary.
  cli,
}

/// How the user got to the project they just opened.
///
/// `recent` is a project opened from the welcome screen's Recent projects
/// list.
enum ProjectOpenSource {
  /// The file picker.
  picker,

  /// A Vivado-style `.f` filelist import.
  filelist,

  /// A FuseSoC/Edalize EDAM (`.eda.yml`) import.
  edam,

  /// An entry in the recent-projects list.
  recent,
}

/// Which Pro trend view was opened.
///
/// Declared in open core although only the Pro overlay records it, for the
/// same reason the Pro entries live in [kLintcruxEventCatalog]: the catalog
/// and its grammar test are one document, and a vocabulary the open-core
/// conformance test cannot see is a vocabulary nothing checks.
enum TrendChartKind {
  /// The project-wide violation-count chart.
  project,

  /// The per-rule trend chart.
  perRule,

  /// The severity-class drift chart.
  severityDrift,

  /// The calendar heat map.
  calendar,
}

/// Which half of the Verible auto-fix funnel this run was.
///
/// The funnel question — proposal → apply rate — needs both
/// halves counted with the same event name, or the ratio has no denominator.
enum AutofixStage {
  /// Fixes were proposed but nothing was written.
  dryRun,

  /// The user applied a selection of the proposed fixes.
  applied,
}

/// Which locked feature the user reached for when the upgrade dialog was
/// raised — the `feature` property of `tier.gate_hit`.
///
/// The suite telemetry rules require a **closed id from LintCrux's own
/// vocabulary** here, and require that the dialog's `featureName` never be
/// sent: that string is localized display text, so it would differ per locale
/// and fails the ingestion Worker's `[a-z0-9_]{1,64}` class outright. These
/// constants are what the call sites pass instead.
///
/// One constant per *purchasable* capability, not per call site. Several
/// openers share an id on purpose — "set baseline" and "clear baseline" are
/// the same line on the tier table and the same upgrade decision, so splitting
/// them would divide one signal in two without answering anything extra. The
/// call sites are listed on each constant so the mapping stays checkable.
///
/// Declared in open core although only the Pro overlay records it, for the
/// same reason the Pro entries live in [kLintcruxEventCatalog]: the catalog
/// and its grammar test are one document.
enum LintcruxGatedFeature {
  /// Set / clear the baseline (`_setBaseline`, `_clearBaseline`).
  baseline,

  /// The baseline & delta comparison screen
  /// (`proBaselineComparisonOpenerOverride`).
  baselineComparison,

  /// Creating a managed waiver from the violation context menu
  /// (`buildWaiveViolationMenuEntry`).
  waiverCreate,

  /// The managed-waiver review screen (`proWaiverReviewOpenerOverride`).
  waiverReview,

  /// Toggling a bookmark on the selected violation (`_toggleBookmark`).
  bookmark,

  /// The bookmark panel (`proBookmarkPanelOpenerOverride`).
  bookmarkPanel,

  /// Verible auto-fix: dry run, review-and-apply, and the binary setting
  /// (`_runVeribleDryRun`, `_applyVeribleFixes`, `_configureVeribleBinary`).
  autofix,

  /// The lint run cache: clear, stats, and the bypass-cache re-run
  /// (`_clearLintCache`, `_openLintCacheStats`, `_forceLintRunWithoutCache`).
  lintCache,

  /// Trend tracking: the four charts and the retention setting
  /// (`_showRuleTrendChart`, `_showSeverityDriftChart`,
  /// `_showProjectTrendChart`, `_showCalendarHeatmap`,
  /// `_configureTrendRetention`).
  trendChart,

  /// User filter presets: the manager and save-current-as-preset
  /// (`proFilterPresetManagerOpenerOverride`,
  /// `proSaveFilterPresetOpenerOverride`).
  filterPresets,

  /// The multi-project switcher, including "reopen recent" which opens it
  /// (`switchProjectOpenerProvider`, `reopenRecentProjectOpenerProvider`).
  projectSwitcher,

  /// Cross-project search (`searchAcrossProjectsOpenerProvider`).
  crossProjectSearch,

  /// Multi-project workspace bookkeeping: pin, close all
  /// (`_pinActiveProject`, `_closeAllProjects`).
  projectRegistry,

  /// Originating a cross-probe to a peer, by either route: the violation
  /// row's "Cross-probe to peer…" entry (`buildCrossProbeMenuEntry`) and the
  /// cross-probe panel's per-peer send button
  /// (`crossProbeOriginateGateProvider`).
  crossProbe,
}

/// The closed `feature` vocabulary of `tier.gate_hit`, spelled out because
/// [kLintcruxEventCatalog] is a `const`.
///
/// The conformance test asserts this equals
/// `LintcruxGatedFeature.values.map(telemetryEnumToken)`, so a constant added
/// to the enum without being added here fails the build rather than losing the
/// dimension at the edge.
const List<String> kLintcruxGatedFeatureTokens = <String>[
  'baseline',
  'baseline_comparison',
  'waiver_create',
  'waiver_review',
  'bookmark',
  'bookmark_panel',
  'autofix',
  'lint_cache',
  'trend_chart',
  'filter_presets',
  'project_switcher',
  'cross_project_search',
  'project_registry',
  'cross_probe',
];

/// How wide a managed waiver was scoped when it was created.
///
/// Derived from the waiver's line range alone — `null` start ⇒ the whole
/// [file], one line ⇒ [line], more than one ⇒ [range]. It never carries, and
/// cannot be derived back into, the file itself or the rule the waiver
/// suppresses: the never-collect list bans both, and the whole value of the
/// property is that it answers "is managed-waiver *scoping* used, or is every
/// waiver a whole-file blanket" without touching either.
enum WaiverScope {
  /// No line range — the waiver suppresses the rule across the whole file.
  file,

  /// A single line.
  line,

  /// A multi-line range.
  range,
}

/// Every catalog event name, for the source-scanning conformance tests here
/// and in the Pro overlay, which reach it through `package:`.
@visibleForTesting
Set<String> get kLintcruxEventNames => <String>{
  for (final event in kLintcruxEventCatalog) event.name,
};
