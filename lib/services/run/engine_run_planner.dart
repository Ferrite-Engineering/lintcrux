// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/engines/engine_binary_ids.dart';
import 'package:lintcrux/services/engines/engine_language_router.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/parallel_engine_runner.dart';
import 'package:meta/meta.dart';

/// Turns a [LintProject] plus an [EngineRegistry] into the list of
/// (engine, request) pairs a [ParallelEngineRunner] executes.
///
/// This is the run-planning half of what `LintRunNotifier` used to do
/// inline. It lives in `services/` and imports no Flutter, because two
/// callers need it and only one of them has a widget tree:
///
/// - `LintRunNotifier` (features layer, GUI) — reads the engine binary
///   configs out of `AppSettings` and the CLI `--<engine>-path`
///   overrides, then delegates here.
/// - `HeadlessRunner` (`bin/lintcrux.dart`) — has no settings store, so
///   it resolves binaries from `PATH` (or the CLI overrides) and
///   delegates here.
///
/// Keeping one planner is the point: a CI gate that disagrees with the
/// desktop app about *which engines ran against which files* would make
/// the two report different violation counts for the same project, and
/// the whole value of the gate is that it agrees with what the engineer
/// sees locally.
///
/// Routing rules (unchanged from the pre-extraction behavior):
///   - Candidate engines are [engineIdsOverride] when non-empty, else
///     the project's `enabledEngineIds`, else every registered engine.
///   - Each engine receives only the project source files whose
///     effective language is in its
///     [EngineCapabilities.supportedLanguages].
///   - Engines left with zero compatible sources are dropped from the
///     returned pairs but remain visible in
///     [EngineRunPlan.routing] so a caller can report "ran against 0 of
///     N sources".
///   - The request's `language` is the engine's single supported
///     language when it declares exactly one, otherwise the project's
///     declared language.
class EngineRunPlanner {
  /// Creates an [EngineRunPlanner].
  const EngineRunPlanner();

  /// Plans the run for [project] against [registry].
  ///
  /// [binaryConfigFor] resolves the [EngineBinaryConfig] for an engine
  /// id — the seam that keeps `AppSettings` (a features-layer concern)
  /// out of this file. It is asked for the id whose binary the engine
  /// runs ([binaryEngineIdFor]), which is `yosys` for the CDC engine.
  /// [engineIdsOverride], when non-empty, replaces the
  /// project's engine selection. [topModuleOverride], when non-null and
  /// non-empty, replaces the project's `topModule` for this run
  /// (the `--top` flag).
  ///
  /// [unknownEngineIds] on the result reports any id in
  /// [engineIdsOverride] that the registry does not know, so a caller
  /// can fail loudly on `--engine verlator` instead of running nothing.
  EngineRunPlan plan({
    required LintProject project,
    required EngineRegistry registry,
    required EngineBinaryConfig Function(String engineId) binaryConfigFor,
    List<String> engineIdsOverride = const <String>[],
    String? topModuleOverride,
  }) {
    final requested = engineIdsOverride.isNotEmpty
        ? engineIdsOverride
        : (project.enabledEngineIds.isEmpty
              ? registry.engineIds
              : project.enabledEngineIds);

    final unknown = <String>[];
    final candidates = <LintEngine>[];
    for (final id in requested) {
      final engine = registry.get(id);
      if (engine == null) {
        // Only an explicit `--engine <id>` (or an explicit project
        // `enabledEngineIds` entry) can name an engine the registry does
        // not have; the "every registered engine" default cannot.
        unknown.add(id);
        continue;
      }
      candidates.add(engine);
    }

    const router = EngineLanguageRouter();
    final routing = router.computeRouting(
      project: project,
      engines: candidates,
    );

    final effectiveTop =
        (topModuleOverride != null && topModuleOverride.isNotEmpty)
        ? topModuleOverride
        : project.topModule;

    final pairs = <EngineRunPair>[];
    for (final engine in candidates) {
      final selection = routing.selectionFor(engine.id);
      if (selection == null || !selection.hasAnySource) continue;
      pairs.add(
        EngineRunPair(
          engine: engine,
          request: LintRunRequest(
            sourceFiles: selection.sourcesUsed,
            droppedSources: selection.sourcesDropped,
            includePaths: project.includePaths,
            defines: project.defines,
            topModule: effectiveTop,
            // An engine that runs another engine's binary (CDC runs Yosys)
            // is configured by that engine's binary settings, so a Custom
            // path and `--yosys-path` reach both from one place.
            binary: binaryConfigFor(binaryEngineIdFor(engine.id)),
            language: selection.requestLanguage,
            options: project.perEngineOptions[engine.id] ?? const {},
            projectRoot: project.rootPath,
          ),
          sourcesUsed: selection.sourcesUsed.length,
          sourcesTotal: selection.sourcesTotal,
        ),
      );
    }

    return EngineRunPlan(
      pairs: List<EngineRunPair>.unmodifiable(pairs),
      routing: routing,
      unknownEngineIds: List<String>.unmodifiable(unknown),
    );
  }
}

/// The outcome of [EngineRunPlanner.plan].
@immutable
class EngineRunPlan {
  /// Creates an [EngineRunPlan].
  const EngineRunPlan({
    required this.pairs,
    required this.routing,
    required this.unknownEngineIds,
  });

  /// Engines that have at least one compatible source file, paired with
  /// the request each should receive. Feed straight to
  /// [ParallelEngineRunner.runAll].
  final List<EngineRunPair> pairs;

  /// The full routing snapshot, including engines dropped for having no
  /// compatible source files. Drives the "ran against N of M sources"
  /// indicator in the GUI and the corresponding CLI diagnostic line.
  final EngineLanguageRouting routing;

  /// Requested engine ids the registry does not know about. Non-empty
  /// means the caller should fail rather than run a narrower set than
  /// the user asked for.
  final List<String> unknownEngineIds;

  /// Ids of engines that were candidates but received zero compatible
  /// source files — e.g. GHDL in a SystemVerilog-only project.
  List<String> get enginesWithoutSources => <String>[
    for (final entry in routing.perEngine.entries)
      if (!entry.value.hasAnySource) entry.key,
  ];
}
