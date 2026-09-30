// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Where the engine binary lives, and how to invoke it.
///
/// Three sources, in increasing user-override priority:
/// 1. **Bundled** — `null` `path`, `EngineBinarySource.bundled`. The
///    LintCrux distribution ships a vendored copy per platform.
/// 2. **System** — `null` `path`, `EngineBinarySource.system`. Resolved
///    from `PATH` at run time (`which verilator`, etc.).
/// 3. **Custom** — `path` set, `EngineBinarySource.custom`. Absolute
///    path to an admin-vetted or user-built binary.
///
/// The resolver, the per-engine version detector and the Settings →
/// Engines UI consume this model.
@immutable
class EngineBinaryConfig {
  /// Creates an [EngineBinaryConfig]. `path` is required when [source]
  /// is [EngineBinarySource.custom] and ignored otherwise.
  const EngineBinaryConfig({
    required this.source,
    this.path,
    this.extraArgs = const <String>[],
  }) : assert(
         source != EngineBinarySource.custom || path != null,
         'custom source requires an explicit path',
       );

  /// Convenience constructor for the bundled binary (the default).
  const EngineBinaryConfig.bundled({List<String> extraArgs = const []})
    : this(source: EngineBinarySource.bundled, extraArgs: extraArgs);

  /// Convenience constructor for the system-resolved binary.
  const EngineBinaryConfig.system({List<String> extraArgs = const []})
    : this(source: EngineBinarySource.system, extraArgs: extraArgs);

  /// Where the binary comes from.
  final EngineBinarySource source;

  /// Absolute path when [source] is [EngineBinarySource.custom];
  /// `null` otherwise. The resolver populates the effective path at
  /// runtime from the chosen [source].
  final String? path;

  /// Engine-specific extra command-line arguments appended to the
  /// default invocation. Use sparingly — the engine plugins are
  /// expected to construct correct command lines on their own. Power
  /// users may opt into experimental flags here.
  final List<String> extraArgs;

  /// Returns a copy with overridden fields.
  EngineBinaryConfig copyWith({
    EngineBinarySource? source,
    String? path,
    List<String>? extraArgs,
  }) {
    return EngineBinaryConfig(
      source: source ?? this.source,
      path: path ?? this.path,
      extraArgs: extraArgs ?? this.extraArgs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EngineBinaryConfig) return false;
    if (other.source != source) return false;
    if (other.path != path) return false;
    if (other.extraArgs.length != extraArgs.length) return false;
    for (var i = 0; i < extraArgs.length; i++) {
      if (other.extraArgs[i] != extraArgs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(source, path, Object.hashAll(extraArgs));

  @override
  String toString() =>
      'EngineBinaryConfig($source${path != null ? ', $path' : ''}'
      '${extraArgs.isNotEmpty ? ', extraArgs: $extraArgs' : ''})';
}

/// Where a [EngineBinaryConfig] resolves its executable from.
enum EngineBinarySource {
  /// Use the binary shipped inside the LintCrux distribution. Default
  /// for first-run with zero friction.
  bundled,

  /// Resolve from the user's `PATH`. Lets engineers point at custom
  /// builds with `verilator` plugins, etc.
  system,

  /// Absolute path explicitly configured (Settings → Engines).
  /// Enterprise compliance teams pin all engines to vetted internal
  /// builds here.
  custom,
}
