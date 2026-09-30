// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/auto_reload/providers/auto_reload_controller.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

class _SeedProjectNotifier extends CurrentProjectNotifier {
  _SeedProjectNotifier(this._seed);
  final LintProject? _seed;

  @override
  LintProject? build() => _seed;
}

/// Fake [WatchFactory]: records every path [AutoReloadController] asks
/// to watch and hands back a controllable broadcast stream per path, so
/// tests can fire synthetic [FileSystemEvent]s without touching the
/// real filesystem or waiting on real `dart:io` watch latency.
class _FakeWatch {
  final List<String> requestedPaths = [];
  final Map<String, StreamController<FileSystemEvent>> _controllers = {};

  Stream<FileSystemEvent> call(String path) {
    requestedPaths.add(path);
    final controller = StreamController<FileSystemEvent>.broadcast();
    _controllers[path] = controller;
    return controller.stream;
  }

  void modify(String path) {
    _controllers[path]?.add(FileSystemModifyEvent(path, false, true));
  }

  Future<void> disposeAll() async {
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}

void main() {
  late _FakeWatch fakeWatch;
  late ProviderContainer container;

  const project = LintProject(
    name: 'demo',
    rootPath: '/proj',
    sourceFiles: ['/proj/a.sv', '/proj/b.sv'],
  );

  setUp(() {
    fakeWatch = _FakeWatch();
    container = ProviderContainer(
      overrides: [
        engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
        currentProjectProvider.overrideWith(
          () => _SeedProjectNotifier(project),
        ),
        autoReloadWatchFactoryProvider.overrideWithValue(fakeWatch.call),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() => fakeWatch.disposeAll());

  /// Realizes [autoReloadControllerProvider] the way the app shell does
  /// (a real subscription, per the house pattern for eager-hook
  /// providers) so its `build()` side effect (spawning watchers) runs.
  void mount() {
    container.listen(
      autoReloadControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
  }

  group('mode dispatch', () {
    test('off: no watchers are spawned', () {
      container
          .read(appSettingsProvider.notifier)
          .setAutoReloadMode(AutoReloadMode.off);
      mount();
      expect(fakeWatch.requestedPaths, isEmpty);
    });

    test(
      'auto: a debounced source change triggers a lint run via '
      'lintRunProvider.runIncremental',
      () async {
        container
            .read(appSettingsProvider.notifier)
            .setAutoReloadMode(AutoReloadMode.auto);
        mount();
        expect(
          fakeWatch.requestedPaths,
          unorderedEquals(['/proj/a.sv', '/proj/b.sv']),
        );
        expect(container.read(lintRunProvider).runFinishedAt, isNull);

        fakeWatch.modify('/proj/a.sv');
        // Poll the run to completion instead of a fixed 800ms sleep (the
        // FileWatcherService 500ms debounce + the controller's 50ms
        // coalesce window) that raced the real timers and went red under
        // load: wait until the run notifier stamps a finish time.
        await _pollUntil(
          () => container.read(lintRunProvider).runFinishedAt != null,
        );

        // With an empty engine registry, `runIncremental` finds no
        // enabled (engine, config) pairs and short-circuits straight to
        // an idle state stamped with a finish time — proof the mode
        // dispatch actually reached the run notifier rather than the
        // `prompt` or `off` branch.
        expect(container.read(lintRunProvider).runFinishedAt, isNotNull);
        expect(container.read(pendingReloadProvider), isFalse);
      },
    );

    test(
      'prompt: a debounced source change marks pendingReloadProvider '
      'true instead of running',
      () async {
        container
            .read(appSettingsProvider.notifier)
            .setAutoReloadMode(AutoReloadMode.prompt);
        mount();

        fakeWatch.modify('/proj/b.sv');
        // Poll for the pending-reload flag instead of racing the debounce
        // + coalesce timers with a fixed 800ms sleep.
        await _pollUntil(() => container.read(pendingReloadProvider));

        expect(container.read(pendingReloadProvider), isTrue);
        expect(container.read(lintRunProvider).runFinishedAt, isNull);
      },
    );
  });

  group('watcher teardown / rebuild', () {
    test(
      'switching from auto to off tears down without respawning new '
      'watchers',
      () {
        container
            .read(appSettingsProvider.notifier)
            .setAutoReloadMode(AutoReloadMode.auto);
        mount();
        expect(fakeWatch.requestedPaths, hasLength(2));

        container
            .read(appSettingsProvider.notifier)
            .setAutoReloadMode(AutoReloadMode.off);
        // `off` tears the watcher set down and does not spawn a
        // replacement — no additional watch requests recorded.
        expect(fakeWatch.requestedPaths, hasLength(2));
      },
    );

    test(
      'switching from off to auto spawns a fresh watcher set',
      () async {
        container
            .read(appSettingsProvider.notifier)
            .setAutoReloadMode(AutoReloadMode.off);
        mount();
        expect(fakeWatch.requestedPaths, isEmpty);

        container
            .read(appSettingsProvider.notifier)
            .setAutoReloadMode(AutoReloadMode.auto);
        // Riverpod flushes dependent-provider rebuilds on a microtask
        // in a plain `test()` zone (no Flutter binding pumping frames);
        // yield once so `AutoReloadController.build()` reruns before
        // asserting on its side effect.
        await Future<void>.delayed(Duration.zero);
        expect(
          fakeWatch.requestedPaths,
          unorderedEquals(['/proj/a.sv', '/proj/b.sv']),
        );
      },
    );

    test(
      'clearing the current project tears the watcher set down without '
      'respawning',
      () {
        container
            .read(appSettingsProvider.notifier)
            .setAutoReloadMode(AutoReloadMode.auto);
        mount();
        expect(fakeWatch.requestedPaths, hasLength(2));

        container.read(currentProjectProvider.notifier).clear();
        // No project → build() returns before `_spawnWatchers`; no new
        // watch requests recorded even though the notifier rebuilt.
        expect(fakeWatch.requestedPaths, hasLength(2));
      },
    );

    test(
      'disposing the container cancels every watcher subscription '
      '(onDispose teardown)',
      () async {
        container
            .read(appSettingsProvider.notifier)
            .setAutoReloadMode(AutoReloadMode.auto);
        mount();
        expect(fakeWatch.requestedPaths, hasLength(2));

        container.dispose();
        // Firing an event on a torn-down watcher must not throw and must
        // not mutate any provider state (the container is gone). Guard the
        // debounce + coalesce window: a surviving timer would fire within
        // it and, running against the disposed container, throw
        // asynchronously — captured here rather than raced by a fixed
        // sleep. Teardown cancelled the subscription, so the bounded poll
        // must run to its cap without recording an error.
        Object? asyncError;
        await runZonedGuarded(
          () async {
            expect(() => fakeWatch.modify('/proj/a.sv'), returnsNormally);
            await _pollUntil(
              () => asyncError != null,
              timeout: const Duration(milliseconds: 800),
            );
          },
          (error, _) => asyncError = error,
        );
        expect(asyncError, isNull);
      },
    );
  });
}

/// Polls [condition] on the real clock until it holds or [timeout] elapses.
///
/// Replaces the fixed `Future.delayed` sleeps that raced the
/// `FileWatcherService` debounce (500ms) + controller coalesce (50ms)
/// timers and turned the suite red under load. Returns as soon as
/// [condition] is true; on timeout it returns quietly so the caller's own
/// `expect` reports the failure with full context.
Future<void> _pollUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) break;
    await Future<void>.delayed(step);
  }
}
