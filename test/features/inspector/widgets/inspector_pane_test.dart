// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/rule.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/inspector/widgets/inspector_pane.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/rules/rule_database.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

import '../../../support/host_independent_editor_resolver.dart';

/// Widget coverage for [InspectorPane] — the violation-detail pane:
/// empty state, per-engine status list, rule/message/location sections,
/// open-in-editor (success + failure snackbar), rule-database metadata,
/// related-location navigation, and the standard locale sweep.
void main() {
  const violation = Violation(
    engineId: 'verilator',
    ruleId: 'verilator/UNUSEDSIGNAL',
    severity: Severity.warning,
    message: 'unused signal foo',
    location: SourceLocation(file: '/p/a.sv', line: 10, column: 3),
  );

  const relatedA = SourceLocation(file: '/p/pkg.sv', line: 4, column: 1);
  const relatedB = SourceLocation(file: '/p/top.sv', line: 88, column: 7);

  final ruleDb = RuleDatabase({
    'verilator': const RuleEngineEntry(
      engineId: 'verilator',
      displayName: 'Verilator',
      rules: [
        Rule(
          id: 'verilator/UNUSEDSIGNAL',
          defaultSeverity: Severity.warning,
          tags: ['style', 'unused'],
        ),
      ],
    ),
  });

  Widget wrap(
    Widget child, {
    Locale locale = const Locale('en'),
    List<Override> overrides = const [],
    List<Violation> storeViolations = const [violation],
  }) {
    // The selection notifier auto-clears any violation missing from the
    // visible set on its next rebuild (async settles of the filter-preset
    // / baseline deps trigger one), so the store must actually hold the
    // violation each test selects.
    final store = InMemoryViolationStore()
      ..replaceFromEngine('verilator', storeViolations);
    addTearDown(store.dispose);
    return ProviderScope(
      overrides: [
        violationStoreProvider.overrideWithValue(store),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(InspectorPane)));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(InspectorPane)));

  Future<void> selectViolation(WidgetTester tester, [Violation v = violation]) {
    containerOf(tester).read(selectedViolationProvider.notifier).select(v);
    return tester.pump();
  }

  group('InspectorPane', () {
    testWidgets('renders the discoverable empty state with no selection', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const InspectorPane()));
      await tester.pump();
      expect(find.text(l10nOf(tester).inspectorEmpty), findsOneWidget);
    });

    testWidgets(
      'renders the per-engine status list when a run has statuses, with the '
      'configure hint on unavailable engines',
      (tester) async {
        final runNotifier = _TestLintRunNotifier();
        await tester.pumpWidget(
          wrap(
            const InspectorPane(),
            overrides: [lintRunProvider.overrideWith(() => runNotifier)],
          ),
        );
        await tester.pump();
        runNotifier.setStatuses(const {
          'verilator': EngineRunStatus(
            engineId: 'verilator',
            phase: EngineRunPhase.completed,
          ),
          'slang': EngineRunStatus(
            engineId: 'slang',
            phase: EngineRunPhase.unavailable,
            error: 'slang: binary not found on PATH',
          ),
        });
        await tester.pump();

        final l10n = l10nOf(tester);
        expect(find.text(l10n.inspectorEngineStatusHeader), findsOneWidget);
        expect(find.text('verilator'), findsOneWidget);
        expect(find.text('slang'), findsOneWidget);
        expect(find.text(l10n.inspectorEnginePhaseCompleted), findsOneWidget);
        expect(find.text(l10n.inspectorEnginePhaseUnavailable), findsOneWidget);
        expect(find.text('slang: binary not found on PATH'), findsOneWidget);
        expect(find.text(l10n.inspectorEngineConfigureHint), findsOneWidget);
      },
    );

    testWidgets(
      'renders rule id, message, and location for the selected violation',
      (tester) async {
        await tester.pumpWidget(wrap(const InspectorPane()));
        await tester.pump();
        await selectViolation(tester);

        final l10n = l10nOf(tester);
        expect(find.text(l10n.inspectorRuleHeader), findsOneWidget);
        expect(find.text('verilator/UNUSEDSIGNAL'), findsOneWidget);
        expect(find.text(l10n.inspectorMessageHeader), findsOneWidget);
        expect(find.text('unused signal foo'), findsOneWidget);
        expect(find.text(l10n.inspectorLocationHeader), findsOneWidget);
        expect(find.text('/p/a.sv:10:3'), findsOneWidget);
        expect(find.text(l10n.inspectorOpenInEditor), findsOneWidget);
      },
    );

    testWidgets('Open in editor launches the configured editor command', (
      tester,
    ) async {
      final launcher = _RecordingLauncher();
      await tester.pumpWidget(
        wrap(
          const InspectorPane(),
          overrides: [_clickToSourceOverride(launcher)],
        ),
      );
      await tester.pump();
      await selectViolation(tester);

      await tester.tap(find.text(l10nOf(tester).inspectorOpenInEditor));
      await tester.pump();
      await tester.pump();

      expect(launcher.launched, hasLength(1));
      expect(launcher.launched.single.arguments.join(' '), contains('/p/a.sv'));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed editor launch surfaces the reproducer snackbar', (
      tester,
    ) async {
      final launcher = _RecordingLauncher(
        failWith: const ProcessException('code', ['--goto'], 'not found'),
      );
      await tester.pumpWidget(
        wrap(
          const InspectorPane(),
          overrides: [_clickToSourceOverride(launcher)],
        ),
      );
      await tester.pump();
      await selectViolation(tester);

      await tester.tap(find.text(l10nOf(tester).inspectorOpenInEditor));
      await tester.pump();
      await tester.pump();

      expect(launcher.launched, hasLength(1));
      final command = launcher.launched.single;
      expect(
        find.text(
          l10nOf(tester).editorLaunchFailed(
            '${command.executable} ${command.arguments.join(' ')}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders rule-database metadata tags for the selected rule', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const InspectorPane(),
          overrides: [
            ruleDatabaseProvider.overrideWith((ref) async => ruleDb),
          ],
        ),
      );
      await tester.pump();
      await selectViolation(tester);
      // The rule-database FutureProvider only starts loading once the
      // detail branch first watches it; one more pump delivers the data.
      await tester.pump();

      final l10n = l10nOf(tester);
      expect(find.text(l10n.inspectorMetadataHeader), findsOneWidget);
      expect(find.text('style'), findsOneWidget);
      expect(find.text('unused'), findsOneWidget);
    });

    testWidgets('related locations render and navigate on tap', (
      tester,
    ) async {
      final launcher = _RecordingLauncher();
      final withRelated = violation.copyWith(
        relatedLocations: const [relatedA, relatedB],
      );
      await tester.pumpWidget(
        wrap(
          const InspectorPane(),
          overrides: [_clickToSourceOverride(launcher)],
          storeViolations: [withRelated],
        ),
      );
      await tester.pump();
      await selectViolation(tester, withRelated);

      expect(
        find.text(l10nOf(tester).inspectorRelatedLocationsHeader),
        findsOneWidget,
      );
      expect(find.text('/p/pkg.sv:4:1'), findsOneWidget);
      expect(find.text('/p/top.sv:88:7'), findsOneWidget);

      await tester.tap(find.text('/p/top.sv:88:7'));
      await tester.pump();
      expect(launcher.launched, hasLength(1));
      expect(
        launcher.launched.single.arguments.join(' '),
        contains('/p/top.sv'),
      );
    });
  });

  group('InspectorPane locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders localized sections without exceptions in $locale', (
        tester,
      ) async {
        await tester.pumpWidget(
          wrap(
            const InspectorPane(),
            locale: locale,
            overrides: [
              ruleDatabaseProvider.overrideWith((ref) async => ruleDb),
            ],
          ),
        );
        await tester.pump();
        expect(find.text(l10nOf(tester).inspectorEmpty), findsOneWidget);

        await tester.pump();
        await selectViolation(tester);
        // Extra pump: the rule-database future starts on first watch.
        await tester.pump();
        final l10n = l10nOf(tester);
        expect(find.text(l10n.inspectorRuleHeader), findsOneWidget);
        expect(find.text(l10n.inspectorMessageHeader), findsOneWidget);
        expect(find.text(l10n.inspectorLocationHeader), findsOneWidget);
        expect(find.text(l10n.inspectorOpenInEditor), findsOneWidget);
        expect(find.text(l10n.inspectorMetadataHeader), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Overrides [clickToSourceServiceProvider] with a service backed by the
/// recording [launcher] and the default (VS Code) editor command.
Override _clickToSourceOverride(_RecordingLauncher launcher) =>
    clickToSourceServiceProvider.overrideWithValue(
      ClickToSourceService(
        commandFor: () => EditorCommand.defaultPreset,
        launcher: launcher,
        resolver: hostIndependentEditorResolver,
      ),
    );

/// [EditorLauncher] double: records every invocation; optionally fails
/// with [failWith] to drive the snackbar path. Never spawns a process.
class _RecordingLauncher implements EditorLauncher {
  _RecordingLauncher({this.failWith});

  final ProcessException? failWith;
  final List<RenderedEditorCommand> launched = [];

  @override
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    launched.add(
      RenderedEditorCommand(executable: executable, arguments: arguments),
    );
    final fail = failWith;
    if (fail != null) throw fail;
    return _NeverProcess();
  }
}

/// Inert [Process] stand-in for the success path (the service never
/// inspects the returned process).
class _NeverProcess implements Process {
  @override
  Future<int> get exitCode async => 0;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => throw UnsupportedError('stdin');

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();
}

/// Minimal [LintRunNotifier] exposing direct status control.
class _TestLintRunNotifier extends LintRunNotifier {
  @override
  LintRunState build() => LintRunState.idle;

  void setStatuses(Map<String, EngineRunStatus> statuses) {
    state = LintRunState(statuses: statuses);
  }
}
