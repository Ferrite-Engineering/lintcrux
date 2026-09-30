// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:meta/meta.dart';

/// Per-engine source-file routing by language.
///
/// Walks each engine's [EngineCapabilities.supportedLanguages] and the
/// project's per-source-file language declarations
/// ([LintProject.sourceFileLanguages]), and returns
/// the subset of [LintProject.sourceFiles] each engine should actually
/// receive. Source files whose effective language is not supported by
/// the engine are silently dropped — Verilator never sees a `.vhd`,
/// GHDL never sees a `.sv`.
///
/// The router does not invoke engines. It produces an immutable
/// [EngineLanguageRouting] snapshot the orchestration layer consumes:
///   - the per-engine source list (input to `LintRunRequest`),
///   - the request-level [HdlLanguage] each engine should declare,
///   - the per-engine total source count (for the "ran against N of M
///     sources" indicator in the run status panel).
///
/// Engines with an empty source list after routing are still emitted
/// in the routing snapshot — the caller may choose to skip them or to
/// reflect them in the UI as "no compatible sources". The run
/// orchestration layer skips them; the run status panel uses
/// `sourcesUsed: 0 / sourcesTotal: N` to make the skip visible.
class EngineLanguageRouter {
  /// Creates an [EngineLanguageRouter].
  const EngineLanguageRouter();

  /// Computes the routing snapshot for [project] and [engines].
  ///
  /// [engines] are typically the registry's enabled subset (filtered
  /// by [LintProject.enabledEngineIds] upstream). The router does not
  /// re-check enablement.
  EngineLanguageRouting computeRouting({
    required LintProject project,
    required List<LintEngine> engines,
  }) {
    final typed = project.sourceFilesTyped;
    final perEngine = <String, EngineSourceSelection>{};
    for (final engine in engines) {
      final caps = engine.capabilities;
      final supported = caps.supportedLanguages;
      final used = <String>[];
      final dropped = <String>[];
      for (final file in typed) {
        final fileLang = file.resolveLanguage();
        if (_engineAcceptsLanguage(supported, fileLang)) {
          used.add(file.path);
        } else {
          dropped.add(file.path);
        }
      }
      perEngine[engine.id] = EngineSourceSelection(
        engineId: engine.id,
        sourcesUsed: List<String>.unmodifiable(used),
        sourcesDropped: List<String>.unmodifiable(dropped),
        sourcesTotal: typed.length,
        // Engine-level request language: pick the single supported
        // language when only one is supported (GHDL → VHDL); otherwise
        // pick HdlLanguage.mixed when the project is mixed; otherwise
        // fall back to the project's declared language. The engine's
        // own capability filter has already rejected incompatible
        // source files at this point.
        requestLanguage: _languageForRequest(supported, project.language),
      );
    }
    return EngineLanguageRouting(perEngine: perEngine);
  }

  /// `true` when [engineLangs] declares support for [fileLanguage].
  /// `HdlLanguage.mixed` on either side is treated as "matches anything"
  /// because the request-level language is only meaningful for engines
  /// that branch on it; today none of them do, but the routing layer
  /// preserves the symmetry so a future engine that explicitly opts
  /// into mixed-language sources can do so by declaring it.
  static bool _engineAcceptsLanguage(
    Set<HdlLanguage> engineLangs,
    HdlLanguage fileLanguage,
  ) {
    if (engineLangs.contains(fileLanguage)) return true;
    if (engineLangs.contains(HdlLanguage.mixed)) return true;
    return false;
  }

  static HdlLanguage _languageForRequest(
    Set<HdlLanguage> engineLangs,
    HdlLanguage projectLanguage,
  ) {
    if (engineLangs.length == 1) {
      // Pick the engine's single supported language — Verilator says
      // "SystemVerilog" even when the project is `mixed`.
      return engineLangs.single;
    }
    return projectLanguage;
  }
}

/// Routing snapshot for one project run.
@immutable
class EngineLanguageRouting {
  /// Creates an [EngineLanguageRouting].
  const EngineLanguageRouting({required this.perEngine});

  /// Per-engine selection keyed by engine id.
  final Map<String, EngineSourceSelection> perEngine;

  /// Returns the selection for [engineId], or `null` if the engine was
  /// not part of the routing.
  EngineSourceSelection? selectionFor(String engineId) => perEngine[engineId];
}

/// Per-engine source-file selection produced by [EngineLanguageRouter].
@immutable
class EngineSourceSelection {
  /// Creates an [EngineSourceSelection].
  const EngineSourceSelection({
    required this.engineId,
    required this.sourcesUsed,
    required this.sourcesDropped,
    required this.sourcesTotal,
    required this.requestLanguage,
  });

  /// Engine this selection applies to.
  final String engineId;

  /// Source files this engine should receive.
  final List<String> sourcesUsed;

  /// Source files dropped because the engine doesn't accept their
  /// language. Kept for diagnostics — the run status panel does not
  /// surface the list, only the count, but the diagnostics drawer
  /// can expand it on demand.
  final List<String> sourcesDropped;

  /// Total source files in the project (== `used + dropped`).
  final int sourcesTotal;

  /// Language to declare in the engine's [LintRunRequest.language].
  final HdlLanguage requestLanguage;

  /// Whether the engine has at least one compatible source file.
  bool get hasAnySource => sourcesUsed.isNotEmpty;
}
