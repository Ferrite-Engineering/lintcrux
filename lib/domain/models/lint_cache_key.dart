// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Composite key identifying one cached lint result.
///
/// The cache stores per-(engine × source file × config) lint outputs.
/// A cache hit requires all four fields to match a previously-stored
/// entry exactly. Any mismatch is a cache miss and the engine is
/// re-invoked.
///
/// Fingerprint construction (see `LintRunCacheService` integration in
/// `ParallelEngineRunner`):
///
/// * [sourceFingerprint] — SHA-256 of the source file's bytes read
///   from disk, hex-encoded. Files normalized to LF line endings
///   before hashing so a `git autocrlf` checkout flip does not
///   spuriously invalidate the cache.
/// * [configFingerprint] — SHA-256 of a canonical JSON encoding of
///   the resolved engine configuration: the engine's enabled-rule
///   set, severity overrides, the engine-options bag, the include-
///   path list, the defines map, the top-module choice, and the
///   resolved binary path. Canonicalization sorts map keys and
///   normalizes list ordering where order does not affect output.
/// * [engineVersion] — the engine's reported `--version` string at
///   the time of the run. Invalidates cached entries the moment the
///   user upgrades a lint engine.
///
/// Key equality is structural: same composite tuple => same key =>
/// cache hit. `==` and `hashCode` use the documented fields verbatim.
@immutable
class LintCacheKey {
  /// Creates a [LintCacheKey]. All fields are required and must be
  /// non-empty strings — the cache deliberately refuses to store a
  /// key with an empty fingerprint.
  const LintCacheKey({
    required this.engineId,
    required this.sourceFingerprint,
    required this.configFingerprint,
    required this.engineVersion,
  }) : assert(engineId != '', 'engineId must be non-empty'),
       assert(
         sourceFingerprint != '',
         'sourceFingerprint must be non-empty',
       ),
       assert(
         configFingerprint != '',
         'configFingerprint must be non-empty',
       ),
       assert(engineVersion != '', 'engineVersion must be non-empty');

  /// Stable lint-engine identifier (matches [LintEngine.id]).
  final String engineId;

  /// SHA-256 hex digest of the source file (LF-normalized).
  final String sourceFingerprint;

  /// SHA-256 hex digest of the canonical engine config snapshot.
  final String configFingerprint;

  /// Engine version string at the time the entry was produced.
  final String engineVersion;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LintCacheKey) return false;
    return other.engineId == engineId &&
        other.sourceFingerprint == sourceFingerprint &&
        other.configFingerprint == configFingerprint &&
        other.engineVersion == engineVersion;
  }

  @override
  int get hashCode => Object.hash(
    engineId,
    sourceFingerprint,
    configFingerprint,
    engineVersion,
  );

  @override
  String toString() =>
      'LintCacheKey('
      'engineId: $engineId, '
      'sourceFingerprint: ${sourceFingerprint.substring(0, 8)}…, '
      'configFingerprint: ${configFingerprint.substring(0, 8)}…, '
      'engineVersion: $engineVersion)';
}
