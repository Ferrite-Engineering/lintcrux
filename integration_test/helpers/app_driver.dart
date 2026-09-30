// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/helpers/app_driver.dart
//
// Open-core LintCrux integration-test helper library. Mirrors the WaveCrux /
// NetCrux harness: `bootLintcrux` launches the real app via `bootstrap` from
// `package:lintcrux/app.dart`, and the `pumpUntil` / `rootContainer` /
// workspace round-trip primitives follow the suite-wide conventions (never
// `pumpAndSettle(Duration)` — the live binding treats the duration as a
// per-pump interval, not a timeout).
//
// LintCrux boots into a `ProviderScope` (not `UncontrolledProviderScope`), so
// `rootContainer` resolves the container via `ProviderScope.containerOf` off
// the `LintcruxApp` element rather than reading a scope widget's field.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_storage.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/custom_regex_rule.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart'
    show visibleViolationsProvider;
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/open_project_in_workspace.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';
import 'package:lintcrux/services/persistence/recent_projects_settings_codec.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/transformers/managed_waiver_transformer.dart';
import 'package:lintcrux/services/transformers/pragma_waiver_transformer.dart';
import 'package:lintcrux/services/transformers/severity_override_transformer.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:lintcrux/services/waivers/pragma_waiver_reader.dart';
import 'package:lintcrux/services/waivers/waiver_store_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/eula_test_acceptance.dart';

/// Suppresses the macOS embedder's mid-test "semantics enabled" signal so
/// integration tests don't trip `_verifySemanticsHandlesWereDisposed` at
/// teardown. Call once in `main()` after `ensureInitialized`.
///
/// Prefer [disablePlatformSemantics] for new tests — this variant only
/// blocks *later* enable flips; when the OS has semantics enabled before
/// Dart `main` runs (an a11y client probed the app at launch), the
/// framework has already acquired its platform semantics handle and keeps
/// emitting semantics updates for the whole run.
void suppressPlatformSemanticsLeak() {
  ui.PlatformDispatcher.instance.onSemanticsEnabledChanged = () {};
}

/// Force-disables framework semantics for the current test. Called by
/// [bootLintcrux] automatically; call directly only from tests that boot
/// the app some other way.
///
/// On this macOS embedder the OS enables semantics shortly after launch
/// (an a11y client probes the app), which (a) leaks a semantics handle
/// past teardown and (b) can segfault the embedder's
/// `AccessibilityBridge` (`CreateRemoveReparentedNodesUpdate`, SIGSEGV)
/// when list-heavy UI — e.g. a seeded violation table — reparents
/// semantics nodes. Pinning the test dispatcher's semantics value to
/// `false` drives the framework's own platform-semantics handler, which
/// releases the auto-acquired handle and stops emitting semantics
/// updates; later real enable flips then no-op against the pinned value.
///
/// Must run INSIDE the test body: the flutter_test harness clears every
/// `TestPlatformDispatcher` test value when a `testWidgets` starts, so a
/// `main()`-time pin is wiped before the app boots. (This also subsumes
/// [suppressPlatformSemanticsLeak] for tests that boot through
/// [bootLintcrux].)
void disablePlatformSemantics() {
  TestWidgetsFlutterBinding
          .instance
          .platformDispatcher
          .semanticsEnabledTestValue =
      false;
}

/// Installs a [FlutterError.onError] filter for the duration of the
/// current test that swallows the known debug-only wart: the
/// markNeedsBuild-during-build assert trips when one tab's
/// `ProviderContainer` is mounted under two sibling
/// `UncontrolledProviderScope`s (the tab content and an open dialog or
/// the diagnostics drawer), because whichever flushes the Riverpod
/// scheduler first notifies listeners in the other subtree. Every OTHER
/// error still reaches the original handler and fails the test normally.
///
/// The wart can fire on a frame that lands after the triggering test
/// body line has already moved on (including during teardown), so a
/// plain `tester.takeException()` call site misses it; filtering at the
/// source catches those.
///
/// **This does not make a seeding journey reliable.** Riverpod reports
/// the assert through `Zone.handleUncaughtError`, which `flutter_test`
/// turns into a test failure however the filter answers. Those reports
/// arrive tagged with the test framework as their library and are passed
/// through, so the failure names the real assertion; swallowing them only
/// traded it for flutter_test's opaque "A test overrode
/// FlutterError.onError" assertion. The workspace status bar no longer
/// shares a tab's container this way; dialogs and the diagnostics drawer
/// still do. See the Pro overlay's `integration_test/PENDING.md` "Known
/// issues" for the mechanism.
void tolerateKnownFirstBuildWart() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library != 'Flutter test framework' &&
        details.exceptionAsString().contains(
          'setState() or markNeedsBuild() called during build',
        )) {
      return;
    }
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

/// Bounded condition-poll — use this, NOT `pumpAndSettle(Duration)`. Under the
/// live binding the pump `duration` is a per-pump interval, not a timeout.
Future<bool> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final maxIterations = (timeout.inMilliseconds / interval.inMilliseconds)
      .ceil();
  for (var i = 0; i < maxIterations; i++) {
    if (condition()) return true;
    await tester.pump(interval);
  }
  return condition();
}

/// Bounded poll until [finder] resolves to exactly one widget that is
/// actually *hittable* at its centre — the entrance animation of an
/// overlay (a context menu, a popup) mounts its children well before it
/// stops absorbing pointers, so a finder that merely resolves is not yet
/// a thing `tester.tap` can reach. Tapping too early produces the
/// "derived an Offset that would not hit test" warning and a tap that
/// goes nowhere, which then fails several lines later on whatever the
/// tap was supposed to open. Cold runs (CI is always one) lose this race
/// far more often than a warm local rerun.
Future<bool> pumpUntilTappable(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 50),
}) {
  // `Finder.hitTestable()` is the framework's own definition of "a tap
  // here reaches this widget" — the same predicate `tester.tap` warns
  // about when it misses — so this waits on exactly what the tap needs.
  final hittable = finder.hitTestable();
  return pumpUntil(
    tester,
    () => hittable.evaluate().length == 1,
    timeout: timeout,
    interval: interval,
  );
}

/// The root [ProviderContainer] the live app renders against — resolved via
/// `ProviderScope.containerOf` off the `LintcruxApp` element (which sits just
/// below the root `ProviderScope` that `bootstrap` mounts).
ProviderContainer rootContainer(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(LintcruxApp).first),
    listen: false,
  );
}

/// The live workspace value, or `null` while it is still hydrating.
Workspace? liveWorkspaceOrNull(WidgetTester tester) =>
    rootContainer(tester).read(workspaceProvider).value;

/// The live workspace value. Throws if it has not hydrated yet.
Workspace liveWorkspace(WidgetTester tester) {
  final ws = liveWorkspaceOrNull(tester);
  if (ws == null) {
    throw StateError('liveWorkspace: workspace has not hydrated yet');
  }
  return ws;
}

/// The number of tabs currently open across every pane.
int tabCount(WidgetTester tester) =>
    liveWorkspaceOrNull(tester)?.tabs.length ?? 0;

/// Loads the persisted `{appSupportDir}/workspace.json` through a FRESH
/// `WorkspaceService` — what the next cold start would hydrate.
Future<Workspace> freshWorkspaceLoad() {
  return WorkspaceService(codec: const LintcruxWorkspaceCodec()).load();
}

/// Deletes the auto-managed `workspace.json` so a fresh launch starts empty.
Future<void> clearPersistedWorkspace() async {
  await WorkspaceService(codec: const LintcruxWorkspaceCodec()).clear();
}

/// Gives the booting app the preferences of an installation that has
/// accepted the current EULA and never opened a project, restoring whatever
/// was there before once the test ends.
///
/// Both are real per-installation state that survives from one integration
/// test file to the next — and, on a developer's machine, from the app they
/// actually use:
///
/// * **EULA acceptance.** Without it `CruxEulaGate` mounts its blocking
///   modal over the whole app, and its barrier swallows every tap a test
///   makes. Seeded exactly as `test/support/eula_test_acceptance.dart` does
///   for widget tests, through the real preference `LintcruxEulaStorage`
///   reads.
/// * **Recent projects.** Every project a test opens is recorded and
///   persisted, so a later file's cold boot showed the fixtures an earlier
///   file opened instead of the empty-canvas "No recent projects yet."
/// * **Telemetry consent.** Since the public beta ended, an installation
///   that has not answered the usage-statistics disclosure gets it over the
///   app on launch, a second blocker of the EULA gate's kind. Seeded as an
///   answered "no" in the real file `LintcruxTelemetryStorage` reads, so
///   nothing is sent from a test run either.
///
/// Restored rather than deleted: this is the developer's real app state, and
/// a test suite has no business erasing it to make itself hermetic.
Future<void> seedFreshInstallPreferences() async {
  const telemetry = LintcruxTelemetryStorage();
  final savedConsent = await telemetry.read(kTelemetryConsentKey);
  addTearDown(() async {
    if (savedConsent == null) {
      await telemetry.remove(kTelemetryConsentKey);
    } else {
      await telemetry.write(kTelemetryConsentKey, savedConsent);
    }
  });
  await telemetry.write(
    kTelemetryConsentKey,
    TelemetryConsentState.disabled.name,
  );

  final prefs = await SharedPreferences.getInstance();
  final keys = <String>[
    ...kEulaAcceptedPrefs.keys,
    RecentProjectsSettingsCodec.prefsKey,
  ];
  final saved = <String, Object?>{for (final key in keys) key: prefs.get(key)};
  addTearDown(() async {
    for (final MapEntry(:key, :value) in saved.entries) {
      switch (value) {
        case null:
          await prefs.remove(key);
        case final String text:
          await prefs.setString(key, text);
        case final List<Object?> list:
          await prefs.setStringList(key, list.cast<String>());
      }
    }
  });
  for (final MapEntry(:key, :value) in kEulaAcceptedPrefs.entries) {
    await prefs.setString(key, value as String);
  }
  await prefs.remove(RecentProjectsSettingsCodec.prefsKey);
}

/// Boots the open-core LintCrux app via [bootstrap] and pumps until the
/// workspace hydrates and the first frame settles. Call once per test body.
///
/// Every boot starts from [seedFreshInstallPreferences]: the EULA accepted,
/// telemetry declined, and no recent projects.
Future<void> bootLintcrux(
  WidgetTester tester, {
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  bool clearWorkspace = true,
  Size surfaceSize = const Size(1600, 1000),
}) async {
  disablePlatformSemantics();
  await seedFreshInstallPreferences();
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (clearWorkspace) {
    await clearPersistedWorkspace();
    addTearDown(clearPersistedWorkspace);
  }
  await bootstrap(
    args: args,
    extraOverrides: extraOverrides,
    // The OS enables accessibility for the test app; under semantics-
    // node churn (seeded violation tables) the macOS embedder's
    // AccessibilityBridge can segfault. Excluding semantics at the
    // root keeps the semantics tree trivially small for the whole run.
    wrapApp: (app) => ExcludeSemantics(child: app),
  );
  await tester.pump();
  await pumpUntil(
    tester,
    () => rootContainer(tester).read(workspaceProvider).hasValue,
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ── Seeded lint run ────────────────────────────────────────────────
//
// The prerequisite named by both PENDING.md files: a way to drive the
// core product loop (open project → lint → violations → act) without
// engine binaries. A fixture project is opened through the real
// File → Open seam, then a parsed fixture engine output is injected
// through the per-tab violation store exactly the way the runner
// writes it — including the same transformer pipeline (severity
// overrides → source pragmas → managed waivers), so Pro journeys can
// model "the next run" by re-seeding after a waiver / override edit.

/// Engine id that matches no registered engine, so opening a fixture
/// project routes zero engine pairs and the auto-kicked run completes
/// instantly without touching any real binary.
const String kSeededFixtureEngineId = 'integration-seeded';

/// Writes a fixture `.lintcrux` project (plus optional [sources],
/// keyed by project-relative path) under [dir] and returns the
/// project-file path. The project enables only
/// [kSeededFixtureEngineId] so no real engine ever runs against it.
///
/// [customRegexRules] seeds the project's `customRegexRules` — the
/// custom-regex-rule corpus the run pipeline feeds to the active
/// `CustomRuleEvaluator`. Under open-core the Noop evaluator ignores
/// them; the Pro overlay's evaluator produces violations, which is how a
/// Pro integration test drives the custom-rule path end to end through a
/// real `runAll`.
Future<String> createFixtureProject(
  Directory dir, {
  String name = 'seeded_fixture',
  Map<String, String> sources = const {},
  List<CustomRegexRule> customRegexRules = const <CustomRegexRule>[],
}) async {
  final sourcePaths = <String>[];
  for (final entry in sources.entries) {
    final file = File(p.join(dir.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
    sourcePaths.add(file.path);
  }
  final project = LintProject(
    name: name,
    rootPath: dir.path,
    sourceFiles: sourcePaths,
    enabledEngineIds: const [kSeededFixtureEngineId],
    customRegexRules: customRegexRules,
  );
  final path = p.join(dir.path, '$name.lintcrux');
  await const ProjectFileService().write(path, project);
  return path;
}

/// The live [WorkspaceRootState] (per-tab / per-pane container
/// managers) of the booted app.
WorkspaceRootState workspaceRootState(WidgetTester tester) =>
    tester.state<WorkspaceRootState>(find.byType(WorkspaceRoot).first);

/// Opens [projectPath] through the same [OpenProjectInWorkspace] seam
/// the File → Open flow uses, waits (bounded) for the tab to appear
/// and hydrate, and returns the new tab's `ProviderContainer`.
///
/// Deliberately does NOT touch the root `currentProjectProvider`: the
/// production open flows never write it, and the per-project services
/// (the Pro waiver / baseline / bookmark / cache / Verible store
/// overrides) are per-tab. A journey that only passes with a root-side
/// project load is exercising a path no user can reach.
Future<ProviderContainer> openFixtureProject(
  WidgetTester tester,
  String projectPath,
) async {
  final root = rootContainer(tester);
  final scope = workspaceRootState(tester);
  final opener = root.read(openProjectInWorkspaceProvider)(
    scope.tabs.containerFor,
  );
  final result = await opener.openProject(projectPath);
  if (result is! OpenProjectSuccess) {
    throw StateError('openFixtureProject: failed to open $projectPath');
  }
  await pumpUntil(tester, () => tabCount(tester) > 0);
  final workspace = liveWorkspace(tester);
  final activeTabId = workspace.activeTabId;
  if (activeTabId == null) {
    throw StateError('openFixtureProject: no active tab after open');
  }
  final tabContainer = scope.tabs.containerFor(activeTabId);
  await pumpUntil(
    tester,
    () =>
        tabContainer.read(currentProjectProvider) != null &&
        !tabContainer.read(lintRunProvider).isRunning,
  );
  return tabContainer;
}

/// Parses fixture Verilator stderr [lines] with the real
/// [VerilatorParser] rooted at [rootPath] — the same parse path the
/// unit-test fixtures exercise.
List<Violation> parseVerilatorFixture(String rootPath, List<String> lines) =>
    VerilatorParser(rootPath: rootPath).parse(lines);

/// Seeds a completed fixture lint run into [tabContainer]'s per-tab
/// violation store, mirroring `ParallelEngineRunner`'s write path:
/// the violations run through the same transformer pipeline the
/// runner applies (severity overrides → source pragmas → managed
/// waivers) before the engine slice is replaced.
///
/// Re-invoke with the same fixture after mutating waivers or severity
/// overrides to model "the next run" deterministically — this is how
/// the Pro waiver journey asserts suppression without engine
/// binaries.
Future<void> seedLintRun(
  WidgetTester tester,
  ProviderContainer tabContainer, {
  required List<Violation> violations,
  String engineId = 'verilator',
}) async {
  final project = tabContainer.read(currentProjectProvider);
  const pragmaReader = PragmaWaiverReader();
  final rangeMap = await pragmaReader.readFiles(
    project?.sourceFiles ?? const [],
  );
  final transformer = CompositeViolationTransformer([
    SeverityOverrideTransformer(project?.severityOverrides ?? const {}),
    PragmaWaiverTransformer(rangeMap),
    ManagedWaiverTransformer(tabContainer.read(waiverStoreProvider)),
  ]);
  final transformed = [
    for (final v in violations) transformer.transform(v),
  ];
  tabContainer
      .read(violationStoreProvider)
      .replaceFromEngine(engineId, transformed);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The active tab's visible (filtered + sorted + view-mode-applied)
/// violation list.
List<Violation> visibleViolations(ProviderContainer tabContainer) =>
    tabContainer.read(visibleViolationsProvider);
