// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/domain/models/rule.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/search/widgets/search_dialog.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_view_mode_provider.dart';
import 'package:lintcrux/features/violations/widgets/filter_preset_dropdown.dart';
import 'package:lintcrux/features/violations/widgets/violation_filter_chips.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/rules/rule_database.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/host_independent_editor_resolver.dart';
import '../../support/noop_process.dart';
import '../../support/telemetry_test_store.dart';

/// One test per catalog counter, fired through the **real** code path.
///
/// Each case drives the production seam — the workspace notifier's own
/// `openTab`, the run notifier's `runAll`, the click-to-source service, the
/// filter chips widget — with `telemetryServiceProvider` bound to a recording
/// fake, and asserts the event name and the closed-vocabulary properties. What
/// is deliberately *not* done anywhere here is calling `record()` directly:
/// a test that did would assert only that the recorder works.
///
/// The events these tests cannot reach cheaply (`workspace.created`,
/// `project.opened`, `export.completed`, `sarif.imported`, `cxp.crossprobe`)
/// are dispatched from `app.dart` and its feature widgets and are covered by
/// `test/telemetry_dispatch_events_test.dart`, which boots the real app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingTelemetryService telemetry;
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    telemetry = RecordingTelemetryService();
    tmp = Directory.systemTemp.createTempSync('lintcrux_telemetry_events_');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ProviderContainer container({List<Override> extra = const []}) {
    final c = ProviderContainer(
      overrides: [
        telemetryServiceProvider.overrideWithValue(telemetry),
        telemetryStorageProvider.overrideWithValue(TelemetryTestStore()),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Map<String, Object?> propsOf(String name) =>
      Map<String, Object?>.from(telemetry.only(name).properties);

  // ── the shared workspace set ──────────────────────────────────────────────

  group('workspace, tabs, panes', () {
    ProviderContainer workspaceContainer() => container(
      extra: [
        workspaceServiceProvider.overrideWithValue(
          WorkspaceService(
            codec: const LintcruxWorkspaceCodec(),
            directoryFactory: () async => tmp,
          ),
        ),
      ],
    );

    LintcruxTabPayload payload(String path) =>
        LintcruxTabPayload(projectPath: path);

    test('workspace.restored carries the tab and pane counts', () async {
      final c = workspaceContainer();
      await c.read(workspaceProvider.future);

      expect(telemetry.only('workspace.restored').properties, <String, Object?>{
        'tabs': 0,
        'panes': 1,
      });
    });

    test('tab.opened fires once per opened tab, never on a dedupe', () async {
      final c = workspaceContainer();
      final notifier = c.read(workspaceProvider.notifier);
      await c.read(workspaceProvider.future);

      await notifier.openTab(displayName: 'a', payload: payload('/a.lintcrux'));
      expect(telemetry.named('tab.opened'), hasLength(1));
      expect(propsOf('tab.opened'), <String, Object?>{'tabs': 1, 'panes': 1});

      // Re-opening the same project focuses the existing tab. That is not a
      // tab open, and counting it would make "how many tabs do people open"
      // a count of how often they clicked a project.
      await notifier.openTab(displayName: 'a', payload: payload('/a.lintcrux'));
      expect(telemetry.named('tab.opened'), hasLength(1));
    });

    test('pane.split fires once; a second split is a no-op', () async {
      final c = workspaceContainer();
      final notifier = c.read(workspaceProvider.notifier);
      await c.read(workspaceProvider.future);

      await notifier.splitPaneRight();
      await notifier.splitPaneRight();

      expect(telemetry.named('pane.split'), hasLength(1));
    });

    test('pane.closed fires only when a pane actually closes', () async {
      final c = workspaceContainer();
      final notifier = c.read(workspaceProvider.notifier);
      final initial = await c.read(workspaceProvider.future);

      // The sole pane cannot close — the package refuses, so nothing happened.
      await notifier.closePane(initial.activePaneId);
      expect(telemetry.named('pane.closed'), isEmpty);

      final second = await notifier.splitPaneRight();
      await notifier.closePane(second);
      expect(telemetry.named('pane.closed'), hasLength(1));
    });

    test('workspace.reset fires on a reset', () async {
      final c = workspaceContainer();
      await c.read(workspaceProvider.future);

      await c.read(workspaceProvider.notifier).resetWorkspace();

      expect(telemetry.named('workspace.reset'), hasLength(1));
    });

    test('workspace.named.saved fires after the document is written', () async {
      final c = workspaceContainer();
      await c.read(workspaceProvider.future);
      final path = '${tmp.path}/named.lintcrux-workspace';

      await c.read(workspaceProvider.notifier).saveAs(path);

      expect(telemetry.named('workspace.named.saved'), hasLength(1));
      expect(File(path).existsSync(), isTrue);
    });

    test('workspace.named.opened carries the loaded counts', () async {
      final c = workspaceContainer();
      final notifier = c.read(workspaceProvider.notifier);
      await c.read(workspaceProvider.future);
      await notifier.openTab(displayName: 'a', payload: payload('/a.lintcrux'));
      final path = '${tmp.path}/named.lintcrux-workspace';
      await notifier.saveAs(path);

      await notifier.loadFrom(path);

      expect(propsOf('workspace.named.opened'), <String, Object?>{
        'tabs': 1,
        'panes': 1,
      });
    });
  });

  // ── the lint run ──────────────────────────────────────────────────────────

  group('run.completed and engine.run', () {
    LintProject project(List<String> engineIds) => LintProject(
      name: 'p',
      rootPath: tmp.path,
      sourceFiles: <String>['${tmp.path}/top.sv'],
      enabledEngineIds: engineIds,
    );

    ProviderContainer runContainer(List<LintEngine> engines) => container(
      extra: [
        engineRegistryProvider.overrideWithValue(EngineRegistry(engines)),
      ],
    );

    test('a manual run reports its trigger and engine count', () async {
      final c = runContainer(<LintEngine>[_FakeEngine('verilator')]);

      await c
          .read(lintRunProvider.notifier)
          .runAll(project(<String>['verilator']));

      expect(propsOf('run.completed'), <String, Object?>{
        'trigger': 'manual',
        'engines': 1,
      });
    });

    test('a watcher-driven run reports the auto trigger', () async {
      // `runIncremental` falls back to `runAll` for engines that cannot go
      // incremental, and the fallback keeps the `auto` trigger: the routing
      // decision is an implementation detail, not a different user action.
      final c = runContainer(<LintEngine>[_FakeEngine('verilator')]);

      await c.read(lintRunProvider.notifier).runIncremental(
        project(<String>['verilator']),
        <String>{
          '${tmp.path}/top.sv',
        },
      );

      expect(propsOf('run.completed')['trigger'], 'auto');
    });

    test('a clean engine reports status ok', () async {
      final c = runContainer(<LintEngine>[_FakeEngine('verilator')]);

      await c
          .read(lintRunProvider.notifier)
          .runAll(project(<String>['verilator']));

      expect(propsOf('engine.run'), <String, Object?>{
        'engine': 'verilator',
        'status': 'ok',
      });
    });

    test('a missing binary reports status missing, not crash', () async {
      final c = runContainer(<LintEngine>[
        _FakeEngine(
          'verible',
          error: const EngineNotAvailableException(
            engineId: 'verible',
            reason: 'not on PATH',
          ),
        ),
      ]);

      await c
          .read(lintRunProvider.notifier)
          .runAll(project(<String>['verible']));

      expect(propsOf('engine.run')['status'], 'missing');
    });

    test('a crashed engine reports status crash', () async {
      final c = runContainer(<LintEngine>[
        _FakeEngine('slang', error: const FormatException('bad output')),
      ]);

      await c.read(lintRunProvider.notifier).runAll(project(<String>['slang']));

      expect(propsOf('engine.run')['status'], 'crash');
    });

    test('a watchdog kill reports status timeout, not crash', () async {
      // The whole reason `EngineRunOutcome` exists: both of these are
      // `EngineRunPhase.failed`, and "the engine hung" and "the engine died"
      // are different answers to "is this engine healthy in the field".
      final c = runContainer(<LintEngine>[
        _FakeEngine(
          'ghdl',
          error: const EngineTimedOutException(
            engineId: 'ghdl',
            timeout: Duration(seconds: 1),
          ),
        ),
      ]);

      await c.read(lintRunProvider.notifier).runAll(project(<String>['ghdl']));

      expect(propsOf('engine.run')['status'], 'timeout');
    });

    test('an unregistered engine id reports `other`, never itself', () async {
      final c = runContainer(<LintEngine>[_FakeEngine('some-pro-engine')]);

      await c
          .read(lintRunProvider.notifier)
          .runAll(project(<String>['some-pro-engine']));

      expect(propsOf('engine.run')['engine'], 'other');
    });
  });

  // ── triage ────────────────────────────────────────────────────────────────

  group('view_mode.changed', () {
    test('fires on a real change and not on a re-selection', () {
      final notifier = container().read(violationViewModeProvider.notifier)
        ..setMode(ViolationViewMode.onlyNew)
        ..setMode(ViolationViewMode.onlyNew);
      expect(notifier.state, ViolationViewMode.onlyNew);

      expect(telemetry.named('view_mode.changed'), hasLength(1));
      expect(propsOf('view_mode.changed'), <String, Object?>{
        'mode': 'only_new',
      });
    });

    test('every mode produces a catalog token', () {
      final c = container();
      final notifier = c.read(violationViewModeProvider.notifier);
      // The build default is `allViolations`, so reaching it has to be a
      // *return* — otherwise the first assignment is the no-op the setter
      // correctly declines to count.
      <ViolationViewMode>[
        ...ViolationViewMode.values,
        ViolationViewMode.allViolations,
      ].forEach(notifier.setMode);

      expect(
        telemetry
            .named('view_mode.changed')
            .map((e) => e.properties['mode'])
            .toSet(),
        <String>{'only_new', 'only_resolved', 'all_violations'},
      );
    });
  });

  group('rule_doc.viewed', () {
    Violation violation(String engineId, String ruleId) => Violation(
      engineId: engineId,
      ruleId: ruleId,
      severity: Severity.warning,
      message: 'a message that must never be transmitted',
      location: const SourceLocation(
        file: '/secret/top.sv',
        line: 1,
        column: 1,
      ),
    );

    ProviderContainer docContainer() => container(
      extra: [
        ruleDatabaseProvider.overrideWith(
          (ref) async => RuleDatabase(<String, RuleEngineEntry>{
            'verilator': const RuleEngineEntry(
              engineId: 'verilator',
              displayName: 'Verilator',
              rules: <Rule>[
                Rule(
                  id: 'verilator/UNUSEDSIGNAL',
                  defaultSeverity: Severity.warning,
                ),
              ],
            ),
          }),
        ),
      ],
    );

    test('fires with the engine when the rule is documented', () async {
      final c = docContainer();
      await c.read(ruleDatabaseProvider.future);

      c
          .read(selectedViolationProvider.notifier)
          .select(violation('verilator', 'verilator/UNUSEDSIGNAL'));

      final event = telemetry.only('rule_doc.viewed');
      expect(event.properties, <String, Object?>{'engine': 'verilator'});
      // The never-collect assertion, stated as a test rather than as a comment:
      // no property carries the rule id, the message, or the file.
      expect(event.properties.keys, <String>['engine']);
      expect(
        event.properties.values.join(),
        isNot(contains('UNUSEDSIGNAL')),
      );
    });

    test('does not fire when the rule has no database entry', () async {
      final c = docContainer();
      await c.read(ruleDatabaseProvider.future);

      c
          .read(selectedViolationProvider.notifier)
          .select(violation('verilator', 'verilator/NOT_IN_THE_DB'));

      expect(telemetry.named('rule_doc.viewed'), isEmpty);
    });
  });

  group('editor.launched', () {
    ClickToSourceService service({required bool succeeds}) =>
        ClickToSourceService(
          commandFor: () => EditorCommand.defaultPreset,
          launcher: _FakeLauncher(succeeds: succeeds),
          resolver: hostIndependentEditorResolver,
          environmentBuilder: () => <String, String>{'PATH': '/usr/bin'},
          onLaunched: (preset, {required ok}) => telemetry.record(
            TelemetryEvent(
              'editor.launched',
              properties: <String, Object?>{
                'preset': telemetryEnumToken(preset),
                'ok': ok,
              },
            ),
          ),
        );

    const location = SourceLocation(
      file: '/secret/top.sv',
      line: 42,
      column: 7,
    );

    test('a successful launch reports the preset and ok: true', () async {
      await service(succeeds: true).openInEditor(location);

      expect(propsOf('editor.launched'), <String, Object?>{
        'preset': 'vs_code',
        'ok': true,
      });
    });

    test('a failed launch is still counted, with ok: false', () async {
      // "Click-to-source reliability" is the question, so the failures are
      // the half that matters most.
      await service(succeeds: false).openInEditor(location);

      expect(propsOf('editor.launched')['ok'], false);
    });

    test('the file and line are never properties', () async {
      await service(succeeds: true).openInEditor(location);

      expect(propsOf('editor.launched').keys.toSet(), <String>{'preset', 'ok'});
    });
  });

  group('filter.used', () {
    Future<void> pumpChips(WidgetTester tester) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          telemetryServiceProvider.overrideWithValue(telemetry),
          telemetryStorageProvider.overrideWithValue(TelemetryTestStore()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [L10N.delegate],
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(body: ViolationFilterChips()),
        ),
      ),
    );

    testWidgets('a severity chip reports kind: severity', (tester) async {
      await pumpChips(tester);

      await tester.tap(
        find.byKey(const ValueKey('violationFilterChip-severity-warning')),
      );
      await tester.pump();

      expect(propsOf('filter.used'), <String, Object?>{'kind': 'severity'});
    });

    testWidgets('the rule field reports kind: rule, once', (tester) async {
      await pumpChips(tester);

      await tester.enterText(
        find.byKey(const ValueKey('violationFilterRuleField')),
        'UNUSED',
      );
      // The field is debounced; the counter follows the debounce so one
      // typed word is one filter, not seven.
      await tester.pump(const Duration(milliseconds: 400));

      expect(telemetry.named('filter.used'), hasLength(1));
      expect(propsOf('filter.used'), <String, Object?>{'kind': 'rule'});
    });

    testWidgets('the file field reports kind: file', (tester) async {
      await pumpChips(tester);

      await tester.enterText(
        find.byKey(const ValueKey('violationFilterFileField')),
        'src/**',
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(propsOf('filter.used'), <String, Object?>{'kind': 'file'});
    });

    testWidgets('the preset dropdown reports kind: preset', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            telemetryServiceProvider.overrideWithValue(telemetry),
            telemetryStorageProvider.overrideWithValue(TelemetryTestStore()),
          ],
          child: const MaterialApp(
            localizationsDelegates: [L10N.delegate],
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: FilterPresetDropdown()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Selecting "none" is still a preset gesture: the user reached for the
      // preset control, which is what the counter is counting.
      await tester.tap(find.byKey(const ValueKey('filterPresetDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();

      expect(propsOf('filter.used'), <String, Object?>{'kind': 'preset'});
    });

    testWidgets('session restore does NOT report a filter', (tester) async {
      // The reason `filter.used` lives on the widget and not on
      // `ViolationTableNotifier`: tab hydration and session restore replay a
      // saved filter through the same setters, and a counter on the notifier
      // would report a filter every time a tab was rehydrated.
      await pumpChips(tester);
      final element = tester.element(find.byType(ViolationFilterChips));
      final ref = ProviderScope.containerOf(element);

      ref.read(violationTableStateProvider.notifier)
        ..setRuleSubstring('restored')
        ..setFileGlob('restored/**')
        ..toggleSeverity(Severity.error);
      await tester.pump();

      expect(telemetry.named('filter.used'), isEmpty);
    });
  });

  group('search.used', () {
    testWidgets('fires when a result is activated, with the mode', (
      tester,
    ) async {
      final store = InMemoryViolationStore();
      addTearDown(store.dispose);
      store
        ..replaceFromEngine('verilator', const <Violation>[
          Violation(
            engineId: 'verilator',
            ruleId: 'verilator/UNUSEDSIGNAL',
            severity: Severity.warning,
            message: 'signal is never used',
            location: SourceLocation(
              file: '/secret/top.sv',
              line: 3,
              column: 1,
            ),
          ),
        ])
        ..completeStreaming('verilator');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            telemetryServiceProvider.overrideWithValue(telemetry),
            telemetryStorageProvider.overrideWithValue(TelemetryTestStore()),
            violationStoreProvider.overrideWithValue(store),
          ],
          child: const MaterialApp(
            localizationsDelegates: [L10N.delegate],
            supportedLocales: L10N.supportedLocales,
            home: SearchDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('searchDialogInput')),
        'UNUSED',
      );
      await tester.pumpAndSettle();
      // Typing alone must not count — `CruxSearchDialog` re-runs the search on
      // every keystroke, and counting there would report a dozen searches for
      // one.
      expect(telemetry.named('search.used'), isEmpty);

      await tester.tap(find.textContaining('UNUSEDSIGNAL').first);
      await tester.pumpAndSettle();

      final event = telemetry.only('search.used');
      expect(event.properties, <String, Object?>{'mode': 'substring'});
      // The query is free text the user typed; free text is never collected.
      expect(event.properties.values.join(), isNot(contains('UNUSED')));
    });
  });
}

/// A [LintEngine] that either emits nothing or throws [error] on its first
/// event, so each `engine.run` status has a reachable path.
class _FakeEngine implements LintEngine {
  _FakeEngine(this.id, {this.error});

  @override
  final String id;

  final Object? error;

  @override
  String get displayName => id;

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog, HdlLanguage.verilog},
  );

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';

  @override
  Stream<Violation> run(LintRunRequest request) => _stream();

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => _stream();

  Stream<Violation> _stream() {
    final failure = error;
    if (failure == null) return const Stream<Violation>.empty();
    return Stream<Violation>.error(failure);
  }

  @override
  void cancel() {}
}

/// An [EditorLauncher] that either returns or throws, without spawning.
class _FakeLauncher implements EditorLauncher {
  const _FakeLauncher({required this.succeeds});

  final bool succeeds;

  @override
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    if (!succeeds) {
      throw const ProcessException('editor', <String>[], 'no such file', 2);
    }
    // Nothing consumes the handle; `openInEditor` awaits and discards it.
    // This used to spawn coreutils `true`, which does not exist on Windows.
    return const NoopProcess();
  }
}
