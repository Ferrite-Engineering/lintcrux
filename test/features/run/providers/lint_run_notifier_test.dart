// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_args_provider.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/run/lint_run_lifecycle.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import '../../../support/telemetry_test_store.dart';

class _ScriptedEngine implements LintEngine {
  _ScriptedEngine(this.id, this._violations);
  @override
  final String id;
  final List<Violation> _violations;
  final List<LintRunRequest> seenRequests = <LintRunRequest>[];
  @override
  String get displayName => 'Scripted $id';
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';
  @override
  Stream<Violation> run(LintRunRequest request) async* {
    seenRequests.add(request);
    for (final v in _violations) {
      yield v;
    }
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {}
}

class _VhdlOnlyEngine implements LintEngine {
  @override
  String get id => 'ghdl';
  @override
  String get displayName => 'GHDL';
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.vhdl},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '4.0.0';
  @override
  Stream<Violation> run(LintRunRequest request) async* {}
  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);
  @override
  void cancel() {}
}

/// Fake engine that declares incremental support and exposes whether
/// the orchestrator routed an invocation through [run] vs
/// [runIncremental].
class _IncrementalEngine implements LintEngine {
  _IncrementalEngine(this.id, this._violations);
  @override
  final String id;
  final List<Violation> _violations;
  int fullRuns = 0;
  int incrementalRuns = 0;
  Set<String>? lastChangedFiles;
  List<String>? lastIncrementalSources;
  @override
  String get displayName => 'Inc $id';
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
    supportsIncrementalPerFile: true,
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0';
  @override
  Stream<Violation> run(LintRunRequest request) async* {
    fullRuns++;
    for (final v in _violations) {
      yield v;
    }
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) async* {
    incrementalRuns++;
    lastChangedFiles = changedFiles;
    lastIncrementalSources = List<String>.from(request.sourceFiles);
    final scoped = changedFiles.where(request.sourceFiles.contains).toSet();
    for (final v in _violations) {
      if (scoped.contains(v.location.file)) yield v;
    }
  }

  @override
  void cancel() {}
}

/// Fake engine that declares NO incremental support. Used to verify
/// the orchestrator's fallback to a full run.
class _NonIncrementalEngine implements LintEngine {
  _NonIncrementalEngine(this.id);
  @override
  final String id;
  int fullRuns = 0;
  int incrementalRuns = 0;
  @override
  String get displayName => id;
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0';
  @override
  Stream<Violation> run(LintRunRequest request) async* {
    fullRuns++;
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) async* {
    incrementalRuns++;
  }

  @override
  void cancel() {}
}

Violation _v(String engineId, String rule) => Violation(
  engineId: engineId,
  ruleId: '$engineId/$rule',
  severity: Severity.warning,
  message: 'msg',
  location: const SourceLocation(file: '/x/y.sv', line: 1, column: 1),
);

/// A violation store that fails when an engine's results are committed.
class _FailingStore extends InMemoryViolationStore {
  @override
  void completeStreaming(String engineId) =>
      throw StateError('store rejected $engineId');
}

const _project = LintProject(
  name: 'test',
  rootPath: '/x',
  sourceFiles: ['/x/y.sv'],
  enabledEngineIds: ['a', 'b'],
);

ProviderContainer _makeContainer({
  required EngineRegistry registry,
  required InMemoryViolationStore store,
}) {
  return ProviderContainer(
    overrides: [
      ...telemetryDeclinedOverrides(),
      engineRegistryProvider.overrideWithValue(registry),
      violationStoreProvider.overrideWithValue(store),
    ],
  );
}

void main() {
  group('LintRunNotifier', () {
    test('initial state is idle with empty statuses', () {
      final container = _makeContainer(
        registry: EngineRegistry([_ScriptedEngine('a', const [])]),
        store: InMemoryViolationStore(),
      );
      addTearDown(container.dispose);
      expect(container.read(lintRunProvider).isRunning, isFalse);
      expect(container.read(lintRunProvider).statuses, isEmpty);
    });

    // A throw inside the engine pass, a failed cache lookup in the case that
    // was seen, left isRunning set for the rest of the tab's life: Run said
    // "already running", Cancel did nothing and auto-reload was ignored.
    test('a run that throws still ends', () async {
      final container = _makeContainer(
        registry: EngineRegistry([
          _ScriptedEngine('a', [_v('a', 'r1')]),
        ]),
        store: _FailingStore(),
      );
      addTearDown(container.dispose);
      const project = LintProject(
        name: 'test',
        rootPath: '/x',
        sourceFiles: ['/x/y.sv'],
        enabledEngineIds: ['a'],
      );

      await expectLater(
        container.read(lintRunProvider.notifier).runAll(project),
        throwsA(isA<StateError>()),
      );

      expect(container.read(lintRunProvider).isRunning, isFalse);
    });

    test('a second run started before the first is under way does not '
        'start', () async {
      final engine = _ScriptedEngine('a', [_v('a', 'r1')]);
      final container = _makeContainer(
        registry: EngineRegistry([engine]),
        store: InMemoryViolationStore(),
      );
      addTearDown(container.dispose);
      const project = LintProject(
        name: 'test',
        rootPath: '/x',
        sourceFiles: ['/x/y.sv'],
        enabledEngineIds: ['a'],
      );
      final notifier = container.read(lintRunProvider.notifier);

      await Future.wait([notifier.runAll(project), notifier.runAll(project)]);

      expect(engine.seenRequests, hasLength(1));
      expect(container.read(lintRunProvider).isRunning, isFalse);
    });

    test('runAll runs every enabled engine and updates the store', () async {
      final store = InMemoryViolationStore();
      final container = _makeContainer(
        registry: EngineRegistry([
          _ScriptedEngine('a', [_v('a', 'r1')]),
          _ScriptedEngine('b', [_v('b', 'r1'), _v('b', 'r2')]),
        ]),
        store: store,
      );
      addTearDown(container.dispose);
      await container.read(lintRunProvider.notifier).runAll(_project);
      expect(store.byEngine['a'], hasLength(1));
      expect(store.byEngine['b'], hasLength(2));
      final state = container.read(lintRunProvider);
      expect(state.isRunning, isFalse);
      expect(state.statusFor('a')?.phase, EngineRunPhase.completed);
      expect(state.statusFor('b')?.phase, EngineRunPhase.completed);
    });

    test('empty enabledEngineIds defaults to all registered engines', () async {
      final store = InMemoryViolationStore();
      final container = _makeContainer(
        registry: EngineRegistry([
          _ScriptedEngine('a', [_v('a', 'r')]),
          _ScriptedEngine('b', [_v('b', 'r')]),
        ]),
        store: store,
      );
      addTearDown(container.dispose);
      const project = LintProject(
        name: 'p',
        rootPath: '/x',
        sourceFiles: ['/x/y.sv'],
      );
      await container.read(lintRunProvider.notifier).runAll(project);
      expect(store.byEngine['a'], hasLength(1));
      expect(store.byEngine['b'], hasLength(1));
    });

    test('engines whose capability does not match the project language are '
        'filtered out', () async {
      final store = InMemoryViolationStore();
      final container = _makeContainer(
        registry: EngineRegistry([
          _ScriptedEngine('a', [_v('a', 'r')]),
          _VhdlOnlyEngine(),
        ]),
        store: store,
      );
      addTearDown(container.dispose);
      const project = LintProject(
        name: 'p',
        rootPath: '/x',
        sourceFiles: ['/x/y.sv'],
        enabledEngineIds: ['a', 'ghdl'],
      );
      await container.read(lintRunProvider.notifier).runAll(project);
      // GHDL is enabled but VHDL-only; the SV project skips it.
      expect(container.read(lintRunProvider).statuses.keys, ['a']);
    });

    test(
      'unregistered engineId in enabledEngineIds is silently skipped',
      () async {
        final store = InMemoryViolationStore();
        final container = _makeContainer(
          registry: EngineRegistry([
            _ScriptedEngine('a', [_v('a', 'r')]),
          ]),
          store: store,
        );
        addTearDown(container.dispose);
        const project = LintProject(
          name: 'p',
          rootPath: '/x',
          sourceFiles: ['/x/y.sv'],
          enabledEngineIds: ['a', 'doesnt-exist'],
        );
        await container.read(lintRunProvider.notifier).runAll(project);
        expect(container.read(lintRunProvider).statuses.keys, ['a']);
      },
    );

    test('runStatusFor returns the live status for an engine', () async {
      final store = InMemoryViolationStore();
      final container = _makeContainer(
        registry: EngineRegistry([
          _ScriptedEngine('a', [_v('a', 'r')]),
        ]),
        store: store,
      );
      addTearDown(container.dispose);
      await container.read(lintRunProvider.notifier).runAll(_project);
      final status = container.read(lintRunProvider.notifier).runStatusFor('a');
      expect(status, isNotNull);
      expect(status!.phase, EngineRunPhase.completed);
      expect(status.violationCount, 1);
    });

    test('runAll on an empty project completes immediately', () async {
      final store = InMemoryViolationStore();
      final container = _makeContainer(
        registry: EngineRegistry(const []),
        store: store,
      );
      addTearDown(container.dispose);
      const project = LintProject(
        name: 'p',
        rootPath: '/x',
        sourceFiles: ['/x/y.sv'],
      );
      await container.read(lintRunProvider.notifier).runAll(project);
      expect(container.read(lintRunProvider).isRunning, isFalse);
      expect(container.read(lintRunProvider).statuses, isEmpty);
    });

    test(
      'a run with no engine pairs still emits the running -> idle '
      'lifecycle edge',
      () async {
        // The lifecycle bus edge is what every run-completion observer
        // keys on (trend ingestion, bookmark stale-detection, Verible
        // auto-run). A project whose violations come only from
        // custom-regex rules routes zero engine pairs; without the
        // `isRunning: true` transition on that path its runs complete
        // invisibly and no trend point is ever recorded.
        final container = _makeContainer(
          registry: EngineRegistry(const []),
          store: InMemoryViolationStore(),
        );
        addTearDown(container.dispose);
        final seen = <bool>[];
        final sub = container
            .read(lintRunLifecycleBusProvider)
            .events
            .listen((e) => seen.add(e.isRunning));
        addTearDown(sub.cancel);
        // Realize the notifier so its state-mirror listener is installed.
        final keepAlive = container.listen(lintRunProvider, (_, _) {});
        addTearDown(keepAlive.close);

        const project = LintProject(
          name: 'p',
          rootPath: '/x',
          sourceFiles: ['/x/y.sv'],
        );
        await container.read(lintRunProvider.notifier).runAll(project);
        await pumpEventQueue();

        expect(
          seen,
          containsAllInOrder(<bool>[true, false]),
          reason:
              'no running -> idle transition reached the lifecycle bus, so '
              'no run-completion observer can see this run',
        );
        expect(container.read(lintRunProvider).isRunning, isFalse);
      },
    );

    test('subsequent runAll replaces previous violations', () async {
      final store = InMemoryViolationStore();
      final firstRegistry = EngineRegistry([
        _ScriptedEngine('a', [_v('a', 'r1'), _v('a', 'r2')]),
      ]);
      var container = _makeContainer(
        registry: firstRegistry,
        store: store,
      );
      addTearDown(container.dispose);
      await container.read(lintRunProvider.notifier).runAll(_project);
      expect(store.byEngine['a'], hasLength(2));

      // Re-run with the same engine but only one violation; the
      // previous two must be replaced wholesale.
      container.dispose();
      container = _makeContainer(
        registry: EngineRegistry([
          _ScriptedEngine('a', [_v('a', 'r3')]),
        ]),
        store: store,
      );
      addTearDown(container.dispose);
      await container.read(lintRunProvider.notifier).runAll(_project);
      expect(store.byEngine['a'], hasLength(1));
    });

    test('CLI engineBinaryPaths shadow Settings overrides', () async {
      final store = InMemoryViolationStore();
      final engine = _ScriptedEngine('a', [_v('a', 'r')]);
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          engineRegistryProvider.overrideWithValue(EngineRegistry([engine])),
          violationStoreProvider.overrideWithValue(store),
          cliArgsProvider.overrideWithValue(
            const CliArgs(engineBinaryPaths: {'a': '/cli/override/path'}),
          ),
        ],
      );
      addTearDown(container.dispose);
      // The user also has a Settings override; the CLI should win.
      container
          .read(appSettingsProvider.notifier)
          .setEngineBinaryOverride(
            'a',
            const EngineBinaryOverride(
              source: EngineBinarySource.custom,
              path: '/settings/path',
            ),
          );
      await container.read(lintRunProvider.notifier).runAll(_project);
      expect(engine.seenRequests.single.binary.path, '/cli/override/path');
    });

    test(
      'appSettings engine binary override flows into LintRunRequest',
      () async {
        final store = InMemoryViolationStore();
        final engine = _ScriptedEngine('a', [_v('a', 'r')]);
        final container = _makeContainer(
          registry: EngineRegistry([engine]),
          store: store,
        );
        addTearDown(container.dispose);
        // Configure a custom binary path before running.
        container
            .read(appSettingsProvider.notifier)
            .setEngineBinaryOverride(
              'a',
              const EngineBinaryOverride(
                source: EngineBinarySource.custom,
                path: '/opt/custom/a',
              ),
            );
        await container.read(lintRunProvider.notifier).runAll(_project);
        expect(engine.seenRequests, hasLength(1));
        expect(
          engine.seenRequests.single.binary.source,
          EngineBinarySource.custom,
        );
        expect(engine.seenRequests.single.binary.path, '/opt/custom/a');
      },
    );
  });

  group('LintRunNotifier.runIncremental', () {
    const incProject = LintProject(
      name: 'inc',
      rootPath: '/x',
      sourceFiles: <String>['/x/y.sv', '/x/z.sv'],
      enabledEngineIds: <String>['inc'],
    );

    test('routes to runIncremental for incremental-capable engines', () async {
      final engine = _IncrementalEngine('inc', [
        _v('inc', 'A')..hashCode, // touch to suppress noise
      ]);
      final store = InMemoryViolationStore();
      final container = _makeContainer(
        registry: EngineRegistry([engine]),
        store: store,
      );
      addTearDown(container.dispose);

      await container.read(lintRunProvider.notifier).runIncremental(
        incProject,
        {'/x/y.sv'},
      );

      expect(engine.fullRuns, 0);
      expect(engine.incrementalRuns, 1);
      expect(engine.lastChangedFiles, {'/x/y.sv'});
    });

    test(
      'falls back to runAll when any engine lacks incremental support',
      () async {
        final incEngine = _IncrementalEngine('inc', const []);
        final nonInc = _NonIncrementalEngine('nonInc');
        final container = _makeContainer(
          registry: EngineRegistry([incEngine, nonInc]),
          store: InMemoryViolationStore(),
        );
        addTearDown(container.dispose);
        const projectWithBoth = LintProject(
          name: 'p',
          rootPath: '/x',
          sourceFiles: <String>['/x/y.sv'],
          enabledEngineIds: <String>['inc', 'nonInc'],
        );

        await container.read(lintRunProvider.notifier).runIncremental(
          projectWithBoth,
          {'/x/y.sv'},
        );

        expect(incEngine.fullRuns, 1);
        expect(incEngine.incrementalRuns, 0);
        expect(nonInc.fullRuns, 1);
        expect(nonInc.incrementalRuns, 0);
      },
    );

    test(
      'preserves violations on unchanged files via partial replacement',
      () async {
        final store = InMemoryViolationStore();
        // Seed with violations on both files.
        final engine = _IncrementalEngine('inc', const [
          // The engine will only yield for changed files (its
          // runIncremental scopes by `changedFiles`).
          Violation(
            engineId: 'inc',
            ruleId: 'inc/RULE_Z',
            severity: Severity.warning,
            message: 'z msg',
            location: SourceLocation(
              file: '/x/z.sv',
              line: 1,
              column: 1,
            ),
          ),
        ]);
        final container = _makeContainer(
          registry: EngineRegistry([engine]),
          store: store,
        );
        addTearDown(container.dispose);
        // Initial full run: seed the store with violations on /x/y.sv
        // (a violation not in the engine's _violations script, so we
        // inject manually).
        store.replaceFromEngine('inc', const [
          Violation(
            engineId: 'inc',
            ruleId: 'inc/RULE_Y',
            severity: Severity.warning,
            message: 'y msg',
            location: SourceLocation(
              file: '/x/y.sv',
              line: 1,
              column: 1,
            ),
          ),
        ]);

        // Re-lint only /x/z.sv.
        await container.read(lintRunProvider.notifier).runIncremental(
          incProject,
          {'/x/z.sv'},
        );

        // /x/y.sv's violation survives the partial replace.
        expect(store.byFile['/x/y.sv'], hasLength(1));
        expect(
          store.byFile['/x/y.sv']!.single.ruleId,
          'inc/RULE_Y',
        );
        // /x/z.sv now has the new violation.
        expect(store.byFile['/x/z.sv'], hasLength(1));
        expect(
          store.byFile['/x/z.sv']!.single.ruleId,
          'inc/RULE_Z',
        );
      },
    );

    test('no-op when changedFiles is empty', () async {
      final engine = _IncrementalEngine('inc', const []);
      final container = _makeContainer(
        registry: EngineRegistry([engine]),
        store: InMemoryViolationStore(),
      );
      addTearDown(container.dispose);
      await container
          .read(lintRunProvider.notifier)
          .runIncremental(incProject, const <String>{});
      expect(engine.fullRuns, 0);
      expect(engine.incrementalRuns, 0);
    });

    test(
      'drops engines whose routed sources do not intersect change set',
      () async {
        final engine = _IncrementalEngine('inc', const []);
        final container = _makeContainer(
          registry: EngineRegistry([engine]),
          store: InMemoryViolationStore(),
        );
        addTearDown(container.dispose);
        // A path outside the project's source list should be a no-op.
        await container.read(lintRunProvider.notifier).runIncremental(
          incProject,
          {'/elsewhere/foo.sv'},
        );
        expect(engine.incrementalRuns, 0);
      },
    );
  });
}
