// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/auto_reload/providers/auto_reload_controller.dart';
import 'package:lintcrux/features/auto_reload/widgets/auto_reload_host.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import '../../../support/telemetry_test_store.dart';

/// Records every path the controller watches and lets a test fire a
/// modification on it.
class _FakeWatch {
  final List<String> requested = <String>[];
  final Map<String, StreamController<FileSystemEvent>> _streams =
      <String, StreamController<FileSystemEvent>>{};

  Stream<FileSystemEvent> call(String path) {
    requested.add(path);
    return (_streams[path] = StreamController<FileSystemEvent>.broadcast())
        .stream;
  }

  void modify(String path) =>
      _streams[path]?.add(FileSystemModifyEvent(path, false, true));
}

const _project = LintProject(
  name: 'demo',
  rootPath: '/proj',
  sourceFiles: <String>['/proj/a.sv'],
);

void main() {
  late _FakeWatch watch;

  setUp(() => watch = _FakeWatch());

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    AutoReloadMode mode = AutoReloadMode.prompt,
    Locale locale = const Locale('en'),
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...telemetryDeclinedOverrides(),
        engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        autoReloadWatchFactoryProvider.overrideWithValue(watch.call),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentProjectProvider.notifier).load(_project);
    container.read(appSettingsProvider.notifier).setAutoReloadMode(mode);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: const Scaffold(body: AutoReloadHost(child: SizedBox())),
        ),
      ),
    );
    return container;
  }

  /// Advances past the watcher's debounce and the controller's coalesce
  /// window, then lets the resulting frame build.
  Future<void> settleWatch(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
  }

  testWidgets('mounting the host starts watching the project sources', (
    tester,
  ) async {
    await pump(tester);
    expect(watch.requested, ['/proj/a.sv']);
  });

  testWidgets('Do nothing in Settings starts no watcher', (tester) async {
    await pump(tester, mode: AutoReloadMode.off);
    expect(watch.requested, isEmpty);
  });

  testWidgets('prompt mode offers Re-run now, which runs the engines', (
    tester,
  ) async {
    final container = await pump(tester);
    watch.modify('/proj/a.sv');
    await settleWatch(tester);
    // Let the snack bar finish sliding in before tapping its action.
    await tester.pump(const Duration(seconds: 1));

    final l10n = L10N.of(tester.element(find.byType(AutoReloadHost)));
    expect(find.text(l10n.autoReloadPromptMessage), findsOneWidget);
    expect(container.read(lintRunProvider).runFinishedAt, isNull);

    await tester.tap(find.text(l10n.autoReloadActionRerun));
    await tester.pumpAndSettle();
    expect(container.read(lintRunProvider).runFinishedAt, isNotNull);
    expect(container.read(pendingReloadProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto mode re-runs without asking', (tester) async {
    final container = await pump(tester, mode: AutoReloadMode.auto);
    watch.modify('/proj/a.sv');
    await settleWatch(tester);
    await tester.pumpAndSettle();
    final l10n = L10N.of(tester.element(find.byType(AutoReloadHost)));
    expect(find.text(l10n.autoReloadPromptMessage), findsNothing);
    expect(container.read(lintRunProvider).runFinishedAt, isNotNull);
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('the prompt renders in $locale', (tester) async {
        await pump(tester, locale: locale);
        watch.modify('/proj/a.sv');
        await settleWatch(tester);
        await tester.pump();
        final l10n = L10N.of(tester.element(find.byType(AutoReloadHost)));
        expect(find.text(l10n.autoReloadPromptMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Let the snackbar time out so no timer outlives the test.
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
      });
    }
  });
}
