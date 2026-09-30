// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/run.dart';
import 'package:meta/meta.dart';

/// A SARIF 2.1.0 document, modeled as an ergonomic Dart wrapper.
///
/// `SarifReader` parses and `SarifWriter` serializes it. The round-trip target:
/// load a SARIF file, construct a [SarifReport], serialize it back, and assert
/// structural equality modulo non-semantic ordering of `properties` bag
/// entries.
///
/// One [SarifReport] contains one or more [Run]s — typically one per
/// engine invoked during the current LintCrux session. The
/// [ViolationStore] is the consumer; the report itself is an
/// export/import artifact, not a runtime data structure.
@immutable
class SarifReport {
  /// Creates a [SarifReport].
  const SarifReport({
    required this.runs,
    this.version = '2.1.0',
    this.schema = 'https://json.schemastore.org/sarif-2.1.0.json',
  });

  /// SARIF spec version. Always `"2.1.0"` for documents LintCrux
  /// produces; documents loaded from other tools may declare older
  /// versions; the reader records the declared value as-is.
  final String version;

  /// JSON Schema URL (the `$schema` field at the top level of a SARIF
  /// document). Optional in the spec; we always emit it.
  final String schema;

  /// One [Run] per engine invocation. Order is preserved — the file
  /// open order doubles as the column order in the per-engine tab
  /// strip.
  final List<Run> runs;

  /// Returns a copy with overridden fields.
  SarifReport copyWith({
    String? version,
    String? schema,
    List<Run>? runs,
  }) {
    return SarifReport(
      version: version ?? this.version,
      schema: schema ?? this.schema,
      runs: runs ?? this.runs,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SarifReport) return false;
    if (other.version != version) return false;
    if (other.schema != schema) return false;
    if (other.runs.length != runs.length) return false;
    for (var i = 0; i < runs.length; i++) {
      if (other.runs[i] != runs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(version, schema, Object.hashAll(runs));

  @override
  String toString() => 'SarifReport(version: $version, runs: ${runs.length})';
}
