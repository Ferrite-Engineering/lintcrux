// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:meta/meta.dart';

/// User-wide per-engine binary override.
///
/// Stores the user's chosen [EngineBinarySource] (auto-detect /
/// bundled / custom) and the optional explicit path for the custom
/// case. Persisted in `AppSettings.engineBinaryOverrides` keyed by
/// [LintEngine.id] (so each engine carries its own override). Used by
/// the run-orchestration layer to construct
/// [EngineBinaryConfig] for every invocation.
///
/// `auto-detect` is the same as not having an override: the engine
/// resolves through its standard `system → PATH` chain (bundled
/// resolver consulted by engines that opt into it). We keep it as an
/// explicit value (not a nullable absence) so the UI can render it as
/// a positive choice (matching VS Code's "User → Default" affordance).
@immutable
class EngineBinaryOverride {
  /// Creates an [EngineBinaryOverride].
  const EngineBinaryOverride({
    required this.source,
    this.path,
  });

  /// The default — `EngineBinarySource.system` with no custom path.
  /// Equivalent to "no override stored" but explicit.
  static const EngineBinaryOverride autoDetect = EngineBinaryOverride(
    source: EngineBinarySource.system,
  );

  /// Where the binary comes from.
  final EngineBinarySource source;

  /// Absolute path when [source] is [EngineBinarySource.custom];
  /// `null` otherwise.
  final String? path;

  /// Projects this override onto an [EngineBinaryConfig] suitable for
  /// `LintRunRequest.binary`. Custom overrides with an empty or null
  /// path fall back to system resolution so a half-configured
  /// override doesn't blow up at run time.
  EngineBinaryConfig toEngineBinaryConfig() {
    switch (source) {
      case EngineBinarySource.custom:
        final p = path;
        if (p == null || p.isEmpty) {
          return const EngineBinaryConfig.system();
        }
        return EngineBinaryConfig(source: EngineBinarySource.custom, path: p);
      case EngineBinarySource.bundled:
        return const EngineBinaryConfig.bundled();
      case EngineBinarySource.system:
        return const EngineBinaryConfig.system();
    }
  }

  /// Returns a copy with overridden fields. When [source] changes to
  /// anything other than [EngineBinarySource.custom], the [path] is
  /// cleared unless explicitly passed.
  EngineBinaryOverride copyWith({
    EngineBinarySource? source,
    String? path,
    bool clearPath = false,
  }) {
    final nextSource = source ?? this.source;
    return EngineBinaryOverride(
      source: nextSource,
      path: clearPath
          ? null
          : (path ??
                (nextSource == EngineBinarySource.custom ? this.path : null)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EngineBinaryOverride &&
      other.source == source &&
      other.path == path;

  @override
  int get hashCode => Object.hash(source, path);

  @override
  String toString() =>
      'EngineBinaryOverride($source${path != null ? ", $path" : ""})';
}
