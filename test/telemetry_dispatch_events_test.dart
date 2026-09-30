// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_config.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/eula_test_acceptance.dart';
import 'support/fake_path_provider.dart';
import 'support/telemetry_test_store.dart';

/// The catalog counters that fire from `app.dart`'s action dispatch, driven
/// through the real dispatch closure the keyboard, menu bar and command
/// palette all share.
///
/// The rest of the catalog is instrumented at providers and services and is
/// covered by `test/services/telemetry/telemetry_events_test.dart`. These four
/// have no seam below the dispatch switch: `workspace.created` is the *only*
/// thing that distinguishes New Workspace from Reset Workspace (they share one
/// handler), and the export and project-open counters have to sit past a
/// picker and a write to mean what they claim.
void main() {
  // The per-tab provider graph an opened project builds resolves the
  // application-support directory; without the fake there is no plugin
  // registrant under `flutter test` and the open fails on macOS/Windows.
  useFakePathProvider();

  late Directory tempDir;
  late RecordingTelemetryService telemetry;
  late _StubPicker picker;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'lintcrux',
      packageName: 'com.ferrite.lintcrux',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
    tempDir = await Directory.systemTemp.createTemp('lintcrux_telemetry_app_');
    telemetry = RecordingTelemetryService();
    picker = _StubPicker();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // See the note in `test/widget_test.dart`: mounting `LintcruxApp`
          // outside `bootstrap()` still has to supply the beta-distribution
          // overrides.
          ...lintcruxPhase5Overrides(),
          eulaAcceptedOverride(),
          telemetryServiceProvider.overrideWithValue(telemetry),
          // Past the beta the consent surfaces are live: the product's config
          // and an installation that already said yes, whose events the
          // recorder stands in for, keep the first-launch disclosure from
          // covering the app.
          cruxTelemetryConfigProvider.overrideWithValue(
            lintcruxTelemetryConfig,
          ),
          telemetryStorageProvider.overrideWithValue(
            TelemetryTestStore.consented(),
          ),
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const LintcruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
            ),
          ),
          projectPickerProvider.overrideWithValue(picker),
          engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
          // Left enabled, boot starts a real cross-probe server: a socket, a
          // manifest in the peer directory and periodic discovery timers
          // that outlive the test. None of these cases is about cross-probe.
          cxpServerConfigProvider.overrideWithValue(
            const CxpServerConfig(enabled: false, port: 0),
          ),
          cxpManifestDirectoryProvider.overrideWith(
            (ref) async => tempDir.path,
          ),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispatch(WidgetTester tester, LintcruxAction action) {
    final manager = tester.widget<ShortcutManagerWidget>(
      find.byType(ShortcutManagerWidget),
    );
    manager.handlers[action]!();
  }

  /// Dispatches [action], then drives both event loops until [done] holds.
  ///
  /// Every handler these cases exercise touches `dart:io` — reading a
  /// `.lintcrux`, writing an export, loading a report — and the fake-async
  /// zone a `testWidgets` body runs in never advances the real event loop, so
  /// a plain `pumpAndSettle` returns before the file work has happened. This is
  /// the same trap `LintcruxWorkspaceNotifier.shouldRestoreOnLaunch` documents
  /// from the other direction.
  ///
  /// [done] names the handler's own last step — the event it records, the
  /// picker it consulted, the snack it raised — and the poll ends the moment
  /// it holds. It used to sleep a fixed 200 ms instead: when the chain ran
  /// longer the assertion ran early, and the handler finished after the test
  /// had torn the app down.
  Future<void> dispatchUntil(
    WidgetTester tester,
    LintcruxAction action,
    bool Function() done, {
    required String what,
  }) async {
    dispatch(tester, action);
    for (var i = 0; i < 600 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'the handler never reached: $what');
    await tester.pumpAndSettle();
  }

  bool recorded(String name) => telemetry.named(name).isNotEmpty;

  Map<String, Object?> propsOf(String name) =>
      Map<String, Object?>.from(telemetry.only(name).properties);

  /// Writes a minimal `.lintcrux` under [tempDir] and returns its path.
  String writeProject(String name) {
    final path = p.join(tempDir.path, '$name.lintcrux');
    File(path).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'name': name,
        'rootPath': tempDir.path,
        'enabledEngineIds': <String>[],
      }),
    );
    return path;
  }

  /// Boots the app and opens one project, so the handlers that need an active
  /// tab (the exporters) have one. Clears the counters the open itself
  /// recorded, so each case asserts only what it drove.
  Future<void> bootWithProject(WidgetTester tester) async {
    await boot(tester);
    picker.projectPath = writeProject('exported');
    await dispatchUntil(
      tester,
      LintcruxAction.openProject,
      () => recorded('project.opened'),
      what: 'project.opened',
    );
    telemetry.events.clear();
  }

  group('workspace.created', () {
    testWidgets('New Workspace records created *and* reset', (tester) async {
      // Both actions share `_handleResetWorkspace`, so the notifier's own
      // override emits `workspace.reset` for either. `workspace.created` is
      // what says the user asked for a new workspace rather than a wipe —
      // the same pair WaveCrux's new-workspace command records.
      await boot(tester);
      dispatch(tester, LintcruxAction.newWorkspace);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('workspaceResetConfirmAction')));
      await tester.pumpAndSettle();

      expect(telemetry.named('workspace.created'), hasLength(1));
      expect(telemetry.named('workspace.reset'), hasLength(1));
    });

    testWidgets('Reset Workspace records reset only', (tester) async {
      await boot(tester);
      dispatch(tester, LintcruxAction.resetWorkspace);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('workspaceResetConfirmAction')));
      await tester.pumpAndSettle();

      expect(telemetry.named('workspace.reset'), hasLength(1));
      expect(telemetry.named('workspace.created'), isEmpty);
    });

    testWidgets('cancelling the confirmation records nothing', (tester) async {
      await boot(tester);
      dispatch(tester, LintcruxAction.newWorkspace);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('workspaceResetConfirmCancel')));
      await tester.pumpAndSettle();

      expect(telemetry.named('workspace.created'), isEmpty);
      expect(telemetry.named('workspace.reset'), isEmpty);
    });
  });

  group('export.completed', () {
    testWidgets('records the format after the file is written', (tester) async {
      await bootWithProject(tester);
      picker.exportPath = p.join(tempDir.path, 'out.sarif');

      await dispatchUntil(
        tester,
        LintcruxAction.exportSarif,
        () => recorded('export.completed'),
        what: 'export.completed',
      );

      expect(propsOf('export.completed'), <String, Object?>{'format': 'sarif'});
      expect(File(picker.exportPath!).existsSync(), isTrue);
    });

    testWidgets('every format reports its own token', (tester) async {
      await bootWithProject(tester);
      for (final action in <LintcruxAction>[
        LintcruxAction.exportSarif,
        LintcruxAction.exportJson,
        LintcruxAction.exportCsv,
        LintcruxAction.exportHtml,
      ]) {
        picker.exportPath = p.join(tempDir.path, '${action.name}.out');
        final before = telemetry.named('export.completed').length;
        await dispatchUntil(
          tester,
          action,
          () => telemetry.named('export.completed').length > before,
          what: 'export.completed for ${action.name}',
        );
      }

      expect(
        telemetry
            .named('export.completed')
            .map((e) => e.properties['format'])
            .toList(),
        <String>['sarif', 'json', 'csv', 'html'],
      );
    });

    testWidgets('a cancelled picker records nothing', (tester) async {
      // The counter has to mean "an artifact exists on disk", not "a menu
      // item was clicked".
      await bootWithProject(tester);
      picker.exportPath = null;

      // Past the picker nothing is asynchronous: a null path returns.
      await dispatchUntil(
        tester,
        LintcruxAction.exportSarif,
        () => picker.calls.contains('export'),
        what: 'the export picker',
      );

      expect(telemetry.named('export.completed'), isEmpty);
    });
  });

  group('project.opened', () {
    testWidgets('the file picker reports source: picker', (tester) async {
      await boot(tester);
      picker.projectPath = writeProject('picked');

      await dispatchUntil(
        tester,
        LintcruxAction.openProject,
        () => recorded('project.opened'),
        what: 'project.opened',
      );

      expect(propsOf('project.opened'), <String, Object?>{'source': 'picker'});
    });

    testWidgets('a cancelled picker records nothing', (tester) async {
      await boot(tester);
      picker.projectPath = null;

      await dispatchUntil(
        tester,
        LintcruxAction.openProject,
        () => picker.calls.contains('project'),
        what: 'the project picker',
      );

      expect(telemetry.named('project.opened'), isEmpty);
    });

    testWidgets('a filelist import reports source: filelist', (tester) async {
      await boot(tester);
      File(
        p.join(tempDir.path, 'top.sv'),
      ).writeAsStringSync('module t;endmodule');
      final filelist = p.join(tempDir.path, 'sources.f');
      File(filelist).writeAsStringSync('top.sv\n');
      picker.filelistPath = filelist;

      await dispatchUntil(
        tester,
        LintcruxAction.importVivadoFilelist,
        () => recorded('project.opened'),
        what: 'project.opened',
      );

      expect(propsOf('project.opened'), <String, Object?>{
        'source': 'filelist',
      });
    });
  });

  group('sarif.imported', () {
    testWidgets('records a report that actually rendered', (tester) async {
      await boot(tester);
      picker.sarifPath = 'test/fixtures/sarif/verilator_basic.sarif.json';

      await dispatchUntil(
        tester,
        LintcruxAction.importSarif,
        () => recorded('sarif.imported'),
        what: 'sarif.imported',
      );

      final event = telemetry.only('sarif.imported');
      // No properties at all: the only thing a report carries that a counter
      // could take is its file name and its findings, and neither is ever
      // collected.
      expect(event.properties, isEmpty);
    });

    testWidgets('a cancelled picker records nothing', (tester) async {
      await boot(tester);
      picker.sarifPath = null;

      await dispatchUntil(
        tester,
        LintcruxAction.importSarif,
        () => picker.calls.contains('sarif'),
        what: 'the SARIF picker',
      );

      expect(telemetry.named('sarif.imported'), isEmpty);
    });

    testWidgets('a malformed report records nothing', (tester) async {
      // The counter means "a SARIF report is on screen", which is what the
      // read-only-viewer adoption question is about.
      await boot(tester);
      picker.sarifPath =
          'test/fixtures/stress/sarif_malformed/truncated.sarif.json';
      expect(find.byType(SnackBar), findsNothing);

      // The load fails on the real event loop and ends in an error snack.
      await dispatchUntil(
        tester,
        LintcruxAction.importSarif,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        what: 'the import-failed snack',
      );

      expect(telemetry.named('sarif.imported'), isEmpty);
    });
  });

  group('a handler that outlives the app', () {
    testWidgets(
      'an export that finishes after teardown neither throws nor records',
      (tester) async {
        // The ordering is forced, not raced: the handler is held at the
        // picker, the app is torn down, then the picker answers. The write
        // is captured in memory so nothing past that point waits on the real
        // event loop. `_record` used to read `ref` here, after the state
        // behind it had unmounted, and threw "Using ref when a widget is
        // about to or has been unmounted" out of the unawaited handler.
        await bootWithProject(tester);
        final answer = Completer<String?>();
        picker.exportAnswer = answer;
        final written = <String, String>{};

        IOOverrides.runZoned(
          () => dispatch(tester, LintcruxAction.exportSarif),
          createFile: (path) => _CapturedFile(path, written),
        );
        await tester.pump();
        expect(picker.calls, contains('export'), reason: 'held at the picker');

        await tester.pumpWidget(const SizedBox.shrink());
        final target = p.join(tempDir.path, 'late.sarif');
        answer.complete(target);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(written.keys, <String>[target], reason: 'the export ran on');
        expect(telemetry.named('export.completed'), isEmpty);
      },
    );
  });

  group('the workspace notifier events reach the app', () {
    testWidgets('workspace.restored fires once on launch', (tester) async {
      // The notifier's `_emittedRestored` guard, asserted through the real
      // boot path: a provider rebuild during startup must not double-count
      // the launch.
      await boot(tester);

      expect(telemetry.named('workspace.restored'), hasLength(1));
    });
  });
}

/// A [ProjectPicker] that returns whatever the test set, without a dialog.
///
/// Subclasses rather than implements: `ProjectPicker` is a concrete class, so
/// only the three pickers these cases drive need overriding and the rest keep
/// their real (dialog-opening) bodies, which nothing here calls.
class _StubPicker extends ProjectPicker {
  String? projectPath;
  String? exportPath;
  String? filelistPath;
  String? sarifPath;

  /// When set, the export picker answers with this instead of [exportPath],
  /// so a test can hold a handler at the picker.
  Completer<String?>? exportAnswer;

  /// Which pickers have been asked, in order.
  final List<String> calls = <String>[];

  @override
  Future<String?> pickProjectFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('project');
    return projectPath;
  }

  @override
  Future<String?> pickSaveExportFile({
    required String confirmButtonText,
    required String extension,
    required String label,
    String? defaultFileName,
  }) {
    calls.add('export');
    return exportAnswer?.future ?? Future<String?>.value(exportPath);
  }

  @override
  Future<String?> pickFilelistFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('filelist');
    return filelistPath;
  }

  @override
  Future<String?> pickSarifFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    calls.add('sarif');
    return sarifPath;
  }
}

/// A [File] whose `writeAsString` lands in [written] rather than on disk, so a
/// test can resume a handler past its write without the real event loop.
///
/// Only the one member the export handler calls is implemented; anything else
/// reaching it is a test defect and fails through [noSuchMethod].
class _CapturedFile implements File {
  _CapturedFile(this.path, this.written);

  @override
  final String path;

  final Map<String, String> written;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    written[path] = contents;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
