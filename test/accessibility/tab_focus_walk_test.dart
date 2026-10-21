// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What a keyboard and a screen reader get from an open project tab, and from
// a dialog on that tab's own navigator (Find in Violations): the whole window
// walks as one cycle with every stop named; a tab dialog keeps Tab inside
// itself; Escape closes it and focus returns to the control that opened it;
// and the window-level shortcut manager leaves the dialog's keys alone.
//
// The transcripts under `goldens/` are what the walks record. Rewrite them
// with `flutter test --update-goldens test/accessibility` and read the diff
// before committing it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
import 'package:lintcrux/features/search/widgets/search_dialog.dart';
import 'package:lintcrux/features/violations/widgets/violation_table.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/viewer_scaffold.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;

import '../support/in_memory_recent_store.dart';
import '../support/telemetry_test_store.dart';

const _goldens = 'test/accessibility/goldens';

const _delegates = <LocalizationsDelegate<Object?>>[
  L10N.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class _IdlePicker extends ProjectPicker {}

/// Serves a one-tab document and saves nowhere, so the real workspace notifier
/// runs without writing the workspace file.
class _OneTabService extends WorkspaceService {
  _OneTabService(this._seed) : super(codec: const LintcruxWorkspaceCodec());

  final Workspace _seed;

  @override
  Future<Workspace> load() async => _seed;

  @override
  Future<void> save(Workspace workspace) async {}
}

Workspace _oneTab(String projectPath) {
  final pane = crux.PaneId.generate();
  final tab = crux.TabId.generate();
  return Workspace(
    tabs: [
      WorkspaceTab(
        id: tab,
        displayName: 'demo',
        paneId: pane,
        payload: LintcruxTabPayload(projectPath: projectPath),
      ),
    ],
    panes: [crux.WorkspacePane(id: pane, activeTabId: tab)],
    activePaneId: pane,
  );
}

/// Pumps the real workspace screen with one project tab open, nested the way
/// `app.dart` nests it. [handlers] are the window-level shortcut handlers.
Future<String> _pumpTab(
  WidgetTester tester,
  Directory dir, {
  Map<LintcruxAction, VoidCallback> handlers = const {},
}) async {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final path = p.join(dir.path, 'demo.lintcrux');
  await tester.runAsync(
    () => File(path).writeAsString(
      jsonEncode({
        'version': 1,
        'name': 'demo',
        'rootPath': dir.path,
        'enabledEngineIds': <String>[],
      }),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...telemetryDeclinedOverrides(),
        workspaceServiceProvider.overrideWithValue(
          _OneTabService(_oneTab(path)),
        ),
        engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        projectPickerProvider.overrideWithValue(_IdlePicker()),
        recentProjectsSeed(),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: _delegates,
        supportedLocales: L10N.supportedLocales,
        builder: (context, child) => WorkspaceRoot(
          child: ShortcutManagerWidget(
            handlers: handlers,
            child: child ?? const SizedBox(),
          ),
        ),
        home: const ViewerScaffold(),
      ),
    ),
  );
  // The tab hydrates its project from disk: real I/O, so give it real time.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
  return path;
}

/// Compares [walk] with the transcript at [golden], the way
/// `expectFocusWalkGolden` does, after replacing the project file's path (a
/// per-run temporary directory, spoken in the tab's tooltip) with a fixed
/// token so the transcript is the same on every machine.
void _expectTranscript(FocusWalk walk, String golden, String projectPath) {
  final actual = walk.transcript.replaceAll(projectPath, '<project file>');
  final file = File(golden);
  if (autoUpdateGoldenFiles) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(actual);
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason: 'No transcript at $golden; run flutter test --update-goldens.',
  );
  expect(
    file.readAsStringSync().replaceAll('\r\n', '\n'),
    actual,
    reason: 'The focus walk differs from $golden.',
  );
}

/// Tabs to the first stop named like [name] and returns its description.
Future<void> _tabTo(WidgetTester tester, String name) async {
  for (var i = 0; i < 120; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (describeFocus(tester).line.contains(name)) return;
  }
  fail('Tab never reached a stop named "$name"');
}

void main() {
  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lintcrux_tab_a11y_');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('a project tab open: one Tab cycle walks the whole window and '
      'every stop is named', (tester) async {
    final handle = tester.ensureSemantics();
    final path = await _pumpTab(tester, tempDir);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'project tab open');
    _expectTranscript(walk, '$_goldens/project_tab.txt', path);
    handle.dispose();
  });

  testWidgets('a tab dialog keeps Tab inside itself, names every stop, and '
      'Escape returns focus to the control that opened it', (tester) async {
    final handle = tester.ensureSemantics();
    final path = await _pumpTab(tester, tempDir);

    await _tabTo(tester, 'Filter preset');
    final opener = describeFocus(tester).line;
    final openerContext = FocusManager.instance.primaryFocus!.context!;
    unawaited(showViolationSearchDialog(openerContext));
    await tester.pumpAndSettle();

    // On the tab's own navigator, not the window's.
    expect(find.byType(SearchDialog), findsOneWidget);
    expect(cruxFocusIsInPushedRoute(), isTrue);
    expectFocusAnnounced(tester, context: 'tab dialog opened');

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'tab dialog');
    _expectTranscript(walk, '$_goldens/tab_dialog.txt', path);
    // Tab never left the dialog: no stop is a control of the window or of the
    // tab behind it.
    const behind = [
      'Open Project',
      'Run All Engines',
      'Settings',
      'Hide Panel',
      'Filter preset',
      'Close demo',
    ];
    expect(
      walk.stops.where((s) => behind.any(s.line.contains)),
      isEmpty,
      reason: 'a stop outside the dialog:\n${walk.transcript}',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SearchDialog), findsNothing);
    expect(describeFocus(tester).line, opener);
    handle.dispose();
  });

  testWidgets('keys pressed in a tab dialog do not reach the window-level '
      'shortcuts; the same keys do outside it', (tester) async {
    var cancelled = 0;
    var ran = 0;
    await _pumpTab(
      tester,
      tempDir,
      handlers: {
        LintcruxAction.cancelRun: () => cancelled++,
        LintcruxAction.runAllEngines: () => ran++,
      },
    );

    // Outside any dialog, with focus in the window: bare Escape and F5 fire.
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(ran, 1);

    final context = tester.element(find.byType(ViolationTable));
    unawaited(showViolationSearchDialog(context));
    await tester.pumpAndSettle();
    expect(find.byType(SearchDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(ran, 1, reason: 'F5 in the dialog must not run the engines');

    // Escape closes the dialog and is not also the cancel-run action.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SearchDialog), findsNothing);
    expect(cancelled, 0, reason: 'the Escape that closed the dialog');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(cancelled, 1, reason: 'Escape outside a dialog still cancels');
  });
}
