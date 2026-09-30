// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'support/telemetry_test_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lintcrux_widget_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('LintcruxApp boots and renders the empty-canvas state', (
    tester,
  ) async {
    // With an empty workspace, the app renders the
    // empty-canvas content composed into `crux.PaneHost`'s shell.
    // Override `workspaceServiceProvider` so the test's workspace
    // document lives in an isolated temp dir.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          // The beta-distribution wiring (`crux_updates` /
          // `crux_issue_reporter` / beta-expiry clock) is part of
          // `LintcruxApp`'s contract: the update banner mounted in
          // `MaterialApp.builder` reads `cruxUpdateConfigProvider`, which has
          // no default binding by design. A harness that mounts the app widget
          // directly rather than through `bootstrap()` has to supply the same
          // list.
          ...lintcruxPhase5Overrides(),
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const LintcruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
            ),
          ),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('LintCrux'), findsWidgets);
    // Empty-canvas state shows the recent-projects empty placeholder.
    expect(find.text('No recent projects yet.'), findsOneWidget);
  });

  testWidgets('LintcruxApp wires the high-contrast accessibility themes', (
    tester,
  ) async {
    // Accessibility parity with WaveCrux: MaterialApp must carry both
    // high-contrast themes so the OS "increase contrast" setting has an
    // effect instead of silently falling back to the standard palette.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          // The beta-distribution wiring (`crux_updates` /
          // `crux_issue_reporter` / beta-expiry clock) is part of
          // `LintcruxApp`'s contract: the update banner mounted in
          // `MaterialApp.builder` reads `cruxUpdateConfigProvider`, which has
          // no default binding by design. A harness that mounts the app widget
          // directly rather than through `bootstrap()` has to supply the same
          // list.
          ...lintcruxPhase5Overrides(),
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const LintcruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
            ),
          ),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.highContrastTheme, isNotNull);
    expect(app.highContrastDarkTheme, isNotNull);
    expect(app.highContrastTheme!.brightness, Brightness.light);
    expect(app.highContrastDarkTheme!.brightness, Brightness.dark);
  });
}
