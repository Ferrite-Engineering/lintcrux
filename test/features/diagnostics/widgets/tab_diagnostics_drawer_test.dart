// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/diagnostics/diagnostics_report.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/open_project_in_workspace.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:lintcrux/services/yosys/yosys_diagnostics_provider.dart';
import 'package:path/path.dart' as p;
import '../../../support/telemetry_test_store.dart';

/// Seeds [YosysDiagnosticsNotifier] with a fixed snapshot for a widget
/// test — mirrors the `_SeedProjectNotifier extends CurrentProjectNotifier`
/// pattern used throughout this repo's provider-backed widget tests.
class _SeededYosysDiagnosticsNotifier extends YosysDiagnosticsNotifier {
  _SeededYosysDiagnosticsNotifier(this._seed);

  final YosysDiagnosticsState _seed;

  @override
  YosysDiagnosticsState build() => _seed;
}

const _report = TabDiagnosticsReport(
  projectPath: '/proj/demo.lintcrux',
  sourceFileCount: 3,
  lastRunWallMs: 42,
  engines: [
    EngineDiagnostics(
      engineId: 'verilator',
      binary: 'custom: /opt/verilator/bin/verilator',
      version: '5.0',
      durationMs: 42,
      severityCounts: {Severity.warning: 2, Severity.error: 1},
    ),
    EngineDiagnostics(
      engineId: 'verible',
      binary: 'PATH',
      version: '0.1',
      durationMs: 10,
    ),
  ],
);

/// A tab whose engines have not run and whose version probe has not
/// answered: nothing measured beyond the project itself.
const _unmeasuredReport = TabDiagnosticsReport(
  projectPath: '/proj/demo.lintcrux',
  sourceFileCount: 3,
  engines: [EngineDiagnostics(engineId: 'verilator')],
);

void main() {
  Widget harness({
    TabDiagnosticsReport? report,
    YosysDiagnosticsState yosys = const YosysDiagnosticsState(),
    Locale locale = const Locale('en'),
  }) {
    return ProviderScope(
      overrides: [
        ...telemetryDeclinedOverrides(),
        tabDiagnosticsReportProvider.overrideWithValue(report),
        yosysDiagnosticsProvider.overrideWith(
          () => _SeededYosysDiagnosticsNotifier(yosys),
        ),
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
        home: const Scaffold(body: TabDiagnosticsDrawer()),
      ),
    );
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(TabDiagnosticsDrawer)));

  group('TabDiagnosticsDrawer — empty state', () {
    testWidgets(
      'shows the no-project-loaded message and disables the copy button '
      'when there is no report',
      (tester) async {
        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        expect(find.text(l10n.diagnosticsNoProjectLoaded), findsOneWidget);
        final button = tester.widget<IconButton>(find.byType(IconButton));
        expect(button.onPressed, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('TabDiagnosticsDrawer — populated state', () {
    testWidgets(
      'renders project info, per-engine rows, and per-severity violation '
      'counts from the report',
      (tester) async {
        await tester.pumpWidget(harness(report: _report));
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        expect(find.text(l10n.diagnosticsTabDrawerTitle), findsOneWidget);
        expect(find.text(l10n.diagnosticsSectionProjectInfo), findsOneWidget);
        expect(find.text('/proj/demo.lintcrux'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('42 ms'), findsWidgets);

        expect(find.text(l10n.diagnosticsSectionEngines), findsOneWidget);
        expect(
          find.text('custom: /opt/verilator/bin/verilator'),
          findsOneWidget,
        );
        expect(find.text('PATH'), findsOneWidget);
        expect(find.text('5.0'), findsOneWidget);
        expect(find.text('0.1'), findsOneWidget);

        expect(
          find.text(l10n.diagnosticsSectionViolationStats),
          findsOneWidget,
        );
        expect(find.text('verilator'), findsOneWidget);
        expect(find.text('verible'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);

        // The nested Yosys Diagnostics section always renders alongside
        // the standard report sections.
        expect(find.text(l10n.yosysDiagnosticsSectionTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a value the report did not measure gets no row: no last-run time, '
      'binary, version or duration, and no zero or placeholder in its place',
      (tester) async {
        await tester.pumpWidget(harness(report: _unmeasuredReport));
        await tester.pumpAndSettle();

        expect(find.text('last run'), findsNothing);
        expect(find.text('verilator binary'), findsNothing);
        expect(find.text('verilator version'), findsNothing);
        expect(find.text('verilator duration'), findsNothing);
        expect(find.text('0 ms'), findsNothing);
        expect(find.text('system PATH'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the copy button is enabled and copies the report (plus any Yosys '
      'diagnostics) as plain text to the clipboard',
      (tester) async {
        final clipboardCalls = <MethodCall>[];
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboardCalls.add(call);
              }
              return null;
            });
        addTearDown(() {
          TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        const yosys = YosysDiagnosticsState(
          diagnostics: [
            YosysDiagnostic(
              severity: YosysDiagnosticSeverity.warning,
              message: 'unused wire',
              filePath: '/proj/top.v',
              line: 12,
            ),
          ],
        );
        await tester.pumpWidget(harness(report: _report, yosys: yosys));
        await tester.pumpAndSettle();

        final button = tester.widget<IconButton>(find.byType(IconButton));
        expect(button.onPressed, isNotNull);

        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();

        expect(clipboardCalls, hasLength(1));
        final callArgs =
            clipboardCalls.single.arguments as Map<Object?, Object?>;
        final copied = callArgs['text']! as String;
        expect(copied, contains('# LintCrux Tab Diagnostics'));
        expect(copied, contains('/proj/demo.lintcrux'));
        expect(copied, contains('## Yosys Diagnostics'));
        expect(copied, contains('unused wire'));
        expect(copied, contains('/proj/top.v:12'));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the copy button omits the Yosys section when there are no Yosys '
      'diagnostics',
      (tester) async {
        final clipboardCalls = <MethodCall>[];
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboardCalls.add(call);
              }
              return null;
            });
        addTearDown(() {
          TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpWidget(harness(report: _report));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();

        expect(clipboardCalls, hasLength(1));
        final callArgs =
            clipboardCalls.single.arguments as Map<Object?, Object?>;
        final copied = callArgs['text']! as String;
        expect(copied, isNot(contains('## Yosys Diagnostics')));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('TabDiagnosticsDrawer.open', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lintcrux_tdd_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'mounts the drawer scoped to the ACTIVE tab so an opened project '
      'renders its real report instead of the no-project empty state — '
      'the exact scope-leak this helper documents itself as preventing',
      (tester) async {
        final projectPath = p.join(tempDir.path, 'demo.lintcrux');
        // Real disk I/O directly in a `testWidgets` body only resolves
        // inside `tester.runAsync` — the fake-clock test binding never
        // delivers the underlying real Future's completion on its own.
        await tester.runAsync(
          () => File(projectPath).writeAsString(
            jsonEncode({
              'version': 1,
              'name': 'demo',
              'rootPath': tempDir.path,
              'enabledEngineIds': <String>[],
            }),
          ),
        );

        final tree = ProviderScope(
          overrides: [
            ...telemetryDeclinedOverrides(),
            workspaceServiceProvider.overrideWithValue(
              WorkspaceService(
                codec: const LintcruxWorkspaceCodec(),
                directoryFactory: () async => tempDir,
              ),
            ),
            engineRegistryProvider.overrideWithValue(
              EngineRegistry(const []),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: WorkspaceRoot(
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => TabDiagnosticsDrawer.open(context),
                    child: const Text('open drawer'),
                  ),
                ),
              ),
            ),
          ),
        );
        // `WorkspaceRoot` now eagerly reads `workspaceProvider.notifier`
        // at mount to register its scope reconcilers, which kicks off the
        // workspace's real-disk load. That load future only advances on
        // the real clock, so the mount itself has to run inside
        // `runAsync`; under the fake test clock the workspace would stay
        // `AsyncLoading` forever and the drawer would stall.
        await tester.runAsync(() => tester.pumpWidget(tree));
        // Poll the real-disk workspace load to completion instead of a
        // fixed sleep that raced it: advance real time in small steps
        // (inside `runAsync`) until the workspace provider leaves
        // `AsyncLoading`, then settle the tree. A fixed delay went red
        // under load when the load had not resolved in time.
        final loadContainer = ProviderScope.containerOf(
          tester.element(find.byType(WorkspaceRoot)),
          listen: false,
        );
        final loadDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (loadContainer.read(workspaceProvider).isLoading) {
          if (DateTime.now().isAfter(loadDeadline)) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pumpAndSettle();

        final buttonContext = tester.element(find.byType(ElevatedButton));
        final rootContainer = ProviderScope.containerOf(
          buttonContext,
          listen: false,
        );
        final scope = WorkspaceRoot.of(buttonContext);
        final opener = rootContainer.read(openProjectInWorkspaceProvider)(
          scope.tabs.containerFor,
        );
        // Same real-I/O-needs-runAsync reasoning as the fixture write
        // above: `openProject` reads the project file from real disk.
        final result = await tester.runAsync(
          () => opener.openProject(projectPath),
        );
        expect(result, isA<OpenProjectSuccess>());
        await tester.pump();

        final l10n = L10N.of(buttonContext);
        await tester.runAsync(() => tester.tap(find.text('open drawer')));
        // Poll the drawer open (its title renders) instead of a fixed
        // sleep: advance real time in steps inside `runAsync`, pump the
        // fake-clock tree OUTSIDE it (pump asserts when called from within
        // a `runAsync` callback) until the title appears or the bound
        // elapses.
        final drawerDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (find.text(l10n.diagnosticsTabDrawerTitle).evaluate().isEmpty) {
          if (DateTime.now().isAfter(drawerDeadline)) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }

        expect(find.text(l10n.diagnosticsTabDrawerTitle), findsOneWidget);
        // Proves the report is the ACTIVE tab's real report (rootPath ==
        // tempDir.path), not the null "no project loaded" fallback.
        expect(find.text(l10n.diagnosticsNoProjectLoaded), findsNothing);
        expect(find.text(tempDir.path), findsOneWidget);

        // Non-modal overlay entry (WaveCrux parity): opening the drawer
        // must not have pushed a barrier route on top of the launcher.
        expect(find.text('open drawer'), findsOneWidget);

        // Escape closes the drawer (host-level DismissIntent binding).
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        final closeDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (find.byType(TabDiagnosticsDrawer).evaluate().isNotEmpty) {
          if (DateTime.now().isAfter(closeDeadline)) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.byType(TabDiagnosticsDrawer), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('TabDiagnosticsDrawer — locale sweep', () {
    testWidgets(
      'renders the populated report without exceptions in every '
      'supported locale',
      (tester) async {
        for (final locale in L10N.supportedLocales) {
          await tester.pumpWidget(harness(report: _report, locale: locale));
          await tester.pumpAndSettle();
          final l10n = l10nOf(tester);
          expect(
            find.text(l10n.diagnosticsTabDrawerTitle),
            findsOneWidget,
            reason: 'drawer title missing for $locale',
          );
          expect(tester.takeException(), isNull, reason: 'failed for $locale');
        }
      },
    );
  });
}
