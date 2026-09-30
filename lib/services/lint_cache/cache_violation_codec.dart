// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Compact JSON-natural codec for round-tripping [Violation] lists
/// through the lint-run cache.
///
/// The codec lives next to the cache (not in `lib/services/sarif/`)
/// because SARIF round-trip serialization is deliberately lossy on
/// the `Violation` wrapper — it preserves engine-specific data in
/// `raw` and strips structural fields the SARIF schema doesn't
/// describe (the `suppression` waiver match, for instance, lives
/// only on the wrapper). The cache needs verbatim round-trip on
/// every wrapper field so a cache hit produces a `Violation`
/// observationally equal to the engine's original output.
///
/// `suppression` is intentionally NOT round-tripped — it is the
/// output of the post-engine transformer pipeline (managed waivers,
/// pragma waivers, severity overrides), not an engine-emitted
/// field. The cache stores the *pre-transformer* engine output so
/// configuration changes to waivers / severity overrides take
/// effect immediately on the next run without invalidating the
/// underlying cached violation lists.
class CacheViolationCodec {
  CacheViolationCodec._();

  /// Encodes [violations] as a JSON-natural list of maps.
  static List<Map<String, Object?>> encode(List<Violation> violations) {
    return [
      for (final v in violations) _encodeOne(v),
    ];
  }

  /// Decodes the inverse of [encode]. Malformed entries (missing
  /// required fields, wrong types) are silently dropped — partial
  /// recovery beats a hard failure that masks the cached entry
  /// entirely.
  static List<Violation> decode(List<dynamic> json) {
    final out = <Violation>[];
    for (final entry in json) {
      if (entry is! Map<String, dynamic>) continue;
      final v = _decodeOne(entry);
      if (v != null) out.add(v);
    }
    return out;
  }

  static Map<String, Object?> _encodeOne(Violation v) {
    return <String, Object?>{
      'engineId': v.engineId,
      'ruleId': v.ruleId,
      'severity': v.severity.name,
      'message': v.message,
      'location': _encodeLocation(v.location),
      if (v.relatedLocations.isNotEmpty)
        'relatedLocations': v.relatedLocations
            .map(_encodeLocation)
            .toList(growable: false),
      if (v.raw.isNotEmpty) 'raw': v.raw,
    };
  }

  static Violation? _decodeOne(Map<String, dynamic> json) {
    final engineId = json['engineId'];
    final ruleId = json['ruleId'];
    final severityName = json['severity'];
    final message = json['message'];
    final locationJson = json['location'];
    if (engineId is! String || engineId.isEmpty) return null;
    if (ruleId is! String || ruleId.isEmpty) return null;
    if (severityName is! String) return null;
    if (message is! String) return null;
    if (locationJson is! Map<String, dynamic>) return null;
    final severity = _decodeSeverity(severityName);
    if (severity == null) return null;
    final location = _decodeLocation(locationJson);
    if (location == null) return null;

    final relatedJson = json['relatedLocations'];
    final related = <SourceLocation>[];
    if (relatedJson is List) {
      for (final r in relatedJson) {
        if (r is! Map<String, dynamic>) continue;
        final loc = _decodeLocation(r);
        if (loc != null) related.add(loc);
      }
    }

    final raw = json['raw'];
    return Violation(
      engineId: engineId,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: location,
      relatedLocations: related,
      raw: raw is Map<String, dynamic>
          ? Map<String, dynamic>.from(raw)
          : const <String, dynamic>{},
    );
  }

  static Map<String, Object?> _encodeLocation(SourceLocation loc) {
    return <String, Object?>{
      'file': loc.file,
      'line': loc.line,
      'column': loc.column,
      if (loc.endLine != null) 'endLine': loc.endLine,
      if (loc.endColumn != null) 'endColumn': loc.endColumn,
    };
  }

  static SourceLocation? _decodeLocation(Map<String, dynamic> json) {
    final file = json['file'];
    final line = json['line'];
    final column = json['column'];
    if (file is! String || file.isEmpty) return null;
    if (line is! int || line < 1) return null;
    if (column is! int || column < 1) return null;
    final endLine = json['endLine'];
    final endColumn = json['endColumn'];
    return SourceLocation(
      file: file,
      line: line,
      column: column,
      endLine: endLine is int ? endLine : null,
      endColumn: endColumn is int ? endColumn : null,
    );
  }

  static Severity? _decodeSeverity(String name) {
    for (final s in Severity.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}
