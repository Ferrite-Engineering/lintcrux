// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What a screen reader user hears in LintCrux, asserted.
//
// The first external NVDA pass (Windows 11, NVDA 2026.1, on WaveCrux) found
// the shapes these cases guard against: nothing announced at launch, bare
// "check box" Tab stops, and one control under two names. The transcripts
// under `goldens/` are what the focus walk records; a change in what is
// announced shows up as a diff there. Rewrite them with
// `flutter test --update-goldens test/accessibility` and read the diff before
// committing it.

import 'dart:io';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_config.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_strings.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/import_viewer/providers/imported_sarif_providers.dart';
import 'package:lintcrux/features/import_viewer/screens/imported_sarif_viewer_screen.dart';
import 'package:lintcrux/features/import_viewer/services/sarif_import_service.dart';
import 'package:lintcrux/features/inspector/widgets/inspector_pane.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/widgets/severity_chip.dart';
import 'package:lintcrux/features/violations/widgets/violation_table.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/viewer_scaffold.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';

import '../support/telemetry_test_store.dart';

// ── harness ─────────────────────────────────────────────────────────────────

const _delegates = <LocalizationsDelegate<Object?>>[
  L10N.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// A picker that is never asked for anything: the launch walk only reads.
class _IdlePicker extends ProjectPicker {}

void _useDesktopSurface(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps the real workspace screen with no tabs open, nested the way
/// `app.dart` nests it: the workspace root and the screen-level shortcut
/// `Actions` above the routed screen.
Future<void> _pumpStartScreen(WidgetTester tester, Directory dir) async {
  _useDesktopSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...telemetryDeclinedOverrides(),
        workspaceServiceProvider.overrideWithValue(
          WorkspaceService(
            codec: const LintcruxWorkspaceCodec(),
            directoryFactory: () async => dir,
          ),
        ),
        engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        projectPickerProvider.overrideWithValue(_IdlePicker()),
        recentProjectsProvider.overrideWithValue(const <String>[]),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: _delegates,
        supportedLocales: L10N.supportedLocales,
        builder: (context, child) => WorkspaceRoot(
          child: ShortcutManagerWidget(child: child ?? const SizedBox()),
        ),
        home: const ViewerScaffold(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Pumps the start screen as a first launch does: the usage-statistics
/// disclosure over it, from a store nobody has answered, wrapped the way
/// `app.dart` wraps the routed screen.
///
/// The EULA gate sits outside this one in the app and has its own tests in
/// `crux_eula`; this walk is about what a screen-reader user meets when the
/// disclosure is the thing in front of them.
Future<void> _pumpFirstLaunchDisclosure(
  WidgetTester tester,
  Directory dir,
) async {
  _useDesktopSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(lintcruxTelemetryConfig),
        cruxTelemetryStringsProvider.overrideWith(
          (ref) => LintcruxTelemetryStrings(lookupL10N(const Locale('en'))),
        ),
        // Nobody has answered: the disclosure is up.
        telemetryStorageProvider.overrideWithValue(TelemetryTestStore()),
        telemetryBetaPeriodProvider.overrideWithValue(false),
        workspaceServiceProvider.overrideWithValue(
          WorkspaceService(
            codec: const LintcruxWorkspaceCodec(),
            directoryFactory: () async => dir,
          ),
        ),
        engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        projectPickerProvider.overrideWithValue(_IdlePicker()),
        recentProjectsProvider.overrideWithValue(const <String>[]),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: _delegates,
        supportedLocales: L10N.supportedLocales,
        builder: (context, child) => WorkspaceRoot(
          child: ShortcutManagerWidget(
            child: TelemetryConsentGate(child: child ?? const SizedBox()),
          ),
        ),
        home: const ViewerScaffold(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Imports the committed Verilator SARIF fixture the way
/// `runSarifImportFlow` does, then pumps the real imported-report viewer.
///
/// Returns the imported violations in table order.
Future<List<Violation>> _pumpImportedViewer(
  WidgetTester tester, {
  ClickToSourceService? editor,
}) async {
  _useDesktopSurface(tester);
  final container = ProviderContainer(
    overrides: [
      ...telemetryDeclinedOverrides(),
      if (editor != null)
        clickToSourceServiceProvider.overrideWithValue(editor),
    ],
  );
  addTearDown(container.dispose);
  final display = container.read(importedSarifStoreProvider);
  final text = File(
    'test/fixtures/sarif/verilator_basic.sarif.json',
  ).readAsStringSync();
  await tester.runAsync(
    () => SarifImportService(SarifFileLoader()).importFromXFile(
      XFile.fromData(
        Uint8List.fromList(text.codeUnits),
        name: 'verilator_basic.sarif',
      ),
      display: display,
    ),
  );
  container
      .read(importedSarifSourceProvider.notifier)
      .record('verilator_basic.sarif');
  // Resolve the rule database before pumping. Its asset load is real async;
  // once a previous test has cached it, a fake-async pump never completes
  // it, and the rule browser's progress indicator animates forever.
  await tester.runAsync(() => container.read(ruleDatabaseProvider.future));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: _delegates,
        supportedLocales: L10N.supportedLocales,
        home: const ImportedSarifViewerScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  return display.all.toList();
}

// ── tests ───────────────────────────────────────────────────────────────────

void main() {
  const goldens = 'test/accessibility/goldens';

  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lintcrux_a11y_');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('launch puts focus on Open Project, so something is announced', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpStartScreen(tester, tempDir);

    expectFocusAnnounced(tester, named: 'Open Project', context: 'launch');
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'start screen');
    expectFocusWalkGolden(walk, '$goldens/start_screen.txt');
    handle.dispose();
  });

  testWidgets('a first launch puts focus in the usage-statistics disclosure, '
      'and every stop in it is named', (tester) async {
    // The first thing a new user meets. Until the disclosure is answered it
    // is what the keyboard is in, so a silent stop here is a user who cannot
    // tell what they are agreeing to.
    final handle = tester.ensureSemantics();
    await _pumpFirstLaunchDisclosure(tester, tempDir);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'first-launch disclosure');
    expectFocusWalkGolden(walk, '$goldens/first_launch_disclosure.txt');
    handle.dispose();
  });

  testWidgets('imported violations: the rows are one Tab stop and one '
      'sentence each', (tester) async {
    final handle = tester.ensureSemantics();
    final violations = await _pumpImportedViewer(tester);
    expect(violations, hasLength(4));

    // The default stop budget is also the assertion that the rule browser
    // beside the table is one Tab stop: it used to be two per rule, well over
    // a thousand, so the walk never cycled.
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'imported SARIF viewer');

    final l10n = await L10N.delegate.load(const Locale('en'));
    final sentences = {for (final v in violations) _sentence(l10n, v)};
    final lines = walk.stops.map((s) => s.line).toList();
    final rowLines = lines
        .where((line) => sentences.any(line.contains))
        .toList();
    expect(
      rowLines,
      hasLength(1),
      reason:
          'The rows are one Tab stop, announced as one sentence plus the '
          'check box state; Up and Down reach the others.',
    );
    expect(rowLines.single, endsWith('check box not checked'));
    // The table's own controls: the preset dropdown says what it is, not
    // only its value; a severity chip is one word, not the icon's label and
    // the chip's; a column header is a button. Focus on a row selects it, so
    // the Details pane's Open in editor button follows the row.
    expect(
      lines,
      containsAllInOrder(<String>[
        'Filter preset None button collapsed',
        'Warning button',
        'Severity button',
        rowLines.single,
        '[Location grouping] Open in editor button',
      ]),
    );
    expectFocusWalkGolden(walk, '$goldens/imported_violations.txt');
    handle.dispose();
  });

  testWidgets('imported violations: the keyboard reaches every row, its '
      'details and its source', (tester) async {
    final handle = tester.ensureSemantics();
    final editor = _RecordingEditor();
    final violations = await _pumpImportedViewer(tester, editor: editor);
    final l10n = await L10N.delegate.load(const Locale('en'));
    final byName = {for (final v in violations) _sentence(l10n, v): v};
    Violation? focusedRow() => byName[describeFocus(tester).name];
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(ViolationTable)),
    );

    for (var i = 0; i < 80 && focusedRow() == null; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
    }
    expect(focusedRow(), isNotNull, reason: 'Tab reaches the rows');

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump();
    }

    await press(LogicalKeyboardKey.home);
    final visited = <Violation>[];
    for (var i = 0; i < violations.length; i++) {
      final row = focusedRow();
      expect(row, isNotNull);
      // Focus selects: the Details pane shows the focused violation.
      expect(scope.read(selectedViolationProvider), row);
      final location = row!.location;
      expect(
        find.descendant(
          of: find.byType(InspectorPane),
          matching: find.text(
            '${location.file}:${location.line}:${location.column}',
          ),
        ),
        findsOneWidget,
      );
      visited.add(row);
      await press(LogicalKeyboardKey.arrowDown);
    }
    expect(visited.toSet(), violations.toSet());

    await press(LogicalKeyboardKey.enter);
    expect(editor.opened, [visited.last.location]);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}

String _sentence(L10N l10n, Violation v) => l10n.accessibilityViolationRow(
  severityLabel(l10n, v.severity),
  v.ruleId,
  v.location.file,
  v.location.line,
  v.message,
);

/// Records what the editor was asked to open; never spawns a process.
class _RecordingEditor implements ClickToSourceService {
  final List<SourceLocation> opened = <SourceLocation>[];

  @override
  Future<ClickToSourceResult> openInEditor(SourceLocation location) async {
    opened.add(location);
    return const ClickToSourceResult(
      success: true,
      command: RenderedEditorCommand(executable: 'code', arguments: []),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
