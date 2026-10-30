// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/models/rohd_dart_source.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/rohd/rohd_source_index.dart';
import 'package:path/path.dart' as p;

/// Adds the Dart source to a finding on ROHD-generated SystemVerilog
/// (ROHD 0.7 or later, source tracing).
///
/// The location is stored on the violation under [RohdDartSource.rawKey] and
/// the finding's own location is left alone, so the SystemVerilog position is
/// still what the table, the baselines and waivers use. A finding in a file
/// with no source map passes through untouched.
class RohdSourceTransformer implements ViolationTransformer {
  /// Creates a transformer over [indexes], keyed by normalized absolute path
  /// (see `loadRohdSourceMaps`).
  const RohdSourceTransformer(this.indexes);

  /// Applied when no linted file has a source map.
  static const RohdSourceTransformer empty = RohdSourceTransformer(
    <String, RohdFileIndex>{},
  );

  /// The per-file source maps.
  final Map<String, RohdFileIndex> indexes;

  @override
  Violation transform(Violation v) {
    if (indexes.isEmpty) return v;
    final file = v.location.file;
    if (file.isEmpty) return v;
    final index = indexes[p.normalize(p.absolute(file))];
    if (index == null) return v;
    final source = index.lookup(v.location.line, message: v.message);
    if (source == null) return v;
    return v.copyWith(
      raw: <String, dynamic>{...v.raw, RohdDartSource.rawKey: source.toJson()},
    );
  }
}
