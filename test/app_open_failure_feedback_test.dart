// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
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

/// Open Session and Open Workspace, reached from the menu, the command palette
/// or a shortcut, report a file that will not open.
///
/// The welcome screen's buttons always did. The app-level handlers the menu,
/// palette and shortcuts share awaited the open and dropped its outcome, so a
/// corrupt, moved or newer-version file did nothing, with no word why.
void main() {
  useFakePathProvider();

  late Directory tempDir;
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
    tempDir = await Directory.systemTemp.createTemp('lintcrux_open_failure_');
    picker = _StubPicker();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          ...lintcruxPhase5Overrides(),
          eulaAcceptedOverride(),
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const LintcruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
            ),
          ),
          projectPickerProvider.overrideWithValue(picker),
          engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Dispatches [action] through the handler the menu, palette and shortcuts
  /// share, letting the real event loop run the file reads.
  Future<void> dispatchAndSettle(
    WidgetTester tester,
    LintcruxAction action,
  ) async {
    await tester.runAsync(() async {
      tester
          .widget<ShortcutManagerWidget>(find.byType(ShortcutManagerWidget))
          .handlers[action]!();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  String writeGarbage(String name) {
    final path = p.join(tempDir.path, name);
    File(path).writeAsStringSync('not json {');
    return path;
  }

  testWidgets('a workspace that will not load says so', (tester) async {
    await boot(tester);
    picker.workspacePath = writeGarbage('broken.lintcrux-workspace');

    await dispatchAndSettle(tester, LintcruxAction.openWorkspace);

    expect(find.textContaining('Failed to load workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a session that will not open says so', (tester) async {
    await boot(tester);
    picker.sessionPath = writeGarbage('broken.lintcrux-session');

    await dispatchAndSettle(tester, LintcruxAction.openSession);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// A [ProjectPicker] that answers the session and workspace pickers with
/// whatever the test set, without a dialog.
class _StubPicker extends ProjectPicker {
  String? sessionPath;
  String? workspacePath;

  @override
  Future<String?> pickSessionFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async => sessionPath;

  @override
  Future<String?> pickWorkspaceFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async => workspacePath;
}
