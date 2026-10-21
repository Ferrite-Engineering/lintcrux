// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io' show Directory;

import 'package:crux_yosys/crux_yosys.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/cdc/cdc_source_span.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';
import 'package:meta/meta.dart';

// The one place a LintCrux engine that analyses a Yosys-elaborated design
// asks Yosys to elaborate it. The `cdc` and `constraints` engines both call
// [elaborateDesign]; neither keeps a second copy of the request, the process
// environment, the working directory or the failure classification.

/// How [elaborateDesign] ended, for the outcomes that are about the design.
///
/// A Yosys that could not be started, timed out, was cancelled, or ended
/// without its JSON output is a tool failure, not a property of the design,
/// and [elaborateDesign] throws the engine exception for it instead (see
/// `yosysRunException`).
sealed class DesignElaboration {
  const DesignElaboration();
}

/// Yosys elaborated the design and wrote its `write_json` document.
final class DesignElaborated extends DesignElaboration {
  /// Creates the result.
  const DesignElaborated(this.rawJson);

  /// The `write_json` document, exactly as Yosys wrote it.
  final String rawJson;
}

/// Yosys ran over the RTL and exited non-zero: its stderr describes the
/// design.
final class DesignElaborationFailed extends DesignElaboration {
  /// Creates the result.
  const DesignElaborationFailed(this.stderr);

  /// Yosys's own diagnostic text.
  final String stderr;
}

/// Elaborates the design in [request] with Yosys.
///
/// Each file is read under its own language with the project's include paths
/// and defines, the run starts from the project root, and Yosys is spawned
/// with the engine environment: the request the Yosys check engine builds, so
/// a design that elaborates there elaborates here.
///
/// [extraCommands] run after `hierarchy` and before `write_json`. `opt` must
/// not be among them for an analysis that reads structure (the CDC engine's
/// reason for passing only `flatten`).
///
/// Throws the engine exception [yosysRunException] builds for every outcome
/// that says nothing about the design.
Future<DesignElaboration> elaborateDesign(
  LintRunRequest request, {
  required String engineId,
  required ProcessRunner processRunner,
  Directory? tempDirectory,
  BundledBinaryResolver bundledBinaryResolver = const BundledBinaryResolver(),
  List<String> extraCommands = const <String>[],
}) async {
  final executable = yosysExecutableFor(
    request.binary,
    resolver: bundledBinaryResolver,
  );
  final runner = YosysRunner(
    processRunner: EngineYosysProcessRunner(
      processRunner,
      workingDirectory: yosysWorkingDirectoryFor(request),
    ),
    executable: executable,
    tempDirectory: tempDirectory,
  );
  final result = await runner.run(
    YosysRunRequest(
      sources: yosysSourcesFor(request),
      defines: yosysDefinesFor(request),
      includePaths: request.includePaths,
      topModule: request.topModule,
      extraCommands: extraCommands,
    ),
  );
  switch (result) {
    case YosysRunSuccess(:final rawJson):
      return DesignElaborated(rawJson);
    case YosysRunFailure(:final stderr) when isYosysDesignFailure(result):
      return DesignElaborationFailed(stderr);
    case YosysRunFailure() || YosysRunTimeout() || YosysRunCancelled():
      throw yosysRunException(
        engineId: engineId,
        result: result,
        executable: executable,
      );
  }
}

/// A top-level port as the Yosys JSON declares it.
///
/// `crux_netlist`'s `Port` keeps a direction and the bit ids only. The
/// declared index range and the declaration's source position live in the
/// `netnames` entry of the same name, so they are read from the raw document
/// here.
@immutable
class ElaboratedPort {
  /// Creates a port.
  const ElaboratedPort({
    required this.name,
    required this.direction,
    required this.width,
    this.offset = 0,
    this.upto = false,
    this.declaration,
  });

  /// The port's name as written in the RTL.
  final String name;

  /// `input`, `output` or `inout`.
  final String direction;

  /// How many bits the port has.
  final int width;

  /// The index of the least significant declared bit (Yosys `offset`): `0`
  /// for `[7:0]` and `[0:7]`, `1` for `[8:1]`.
  final int offset;

  /// Whether the range was declared ascending, as in `[0:7]` (Yosys `upto`).
  final bool upto;

  /// Where the port is declared, from the netname's `src` attribute, or
  /// `null` when Yosys recorded none.
  final CdcSourceSpan? declaration;

  /// Whether the port is a vector, as opposed to a scalar the netlist treats
  /// as one bit named without an index.
  bool get isBus => width > 1;

  /// The declared indexes, in the order the RTL's range lists them.
  ///
  /// `[7:0]` gives 7 down to 0, `[0:7]` gives 0 up to 7, `[8:1]` gives 8 down
  /// to 1. A scalar lists its one index.
  List<int> get indexes => <int>[
    for (var i = 0; i < width; i++) offset + (upto ? i : width - 1 - i),
  ];

  /// Whether [index] is a declared bit of this port.
  bool hasIndex(int index) => index >= offset && index < offset + width;

  /// The lowest and highest declared index.
  (int, int) get indexRange => (offset, offset + width - 1);
}

/// The ports of the top module in a Yosys `write_json` document.
///
/// The module is [topModule] when the document has it, otherwise the one
/// Yosys marked with its `top` attribute. Returns `null` when the document
/// has neither, or is not the shape `write_json` writes: a caller reports
/// that the design could not be read, never an empty port list.
List<ElaboratedPort>? readTopModulePorts(String rawJson, String? topModule) {
  final Object? doc;
  try {
    doc = jsonDecode(rawJson);
  } on FormatException {
    return null;
  }
  if (doc is! Map<String, Object?>) return null;
  final modules = doc['modules'];
  if (modules is! Map<String, Object?>) return null;

  Map<String, Object?>? module;
  if (topModule != null && modules[topModule] is Map<String, Object?>) {
    module = modules[topModule]! as Map<String, Object?>;
  } else {
    for (final candidate in modules.values) {
      if (candidate is! Map<String, Object?>) continue;
      final attributes = candidate['attributes'];
      if (attributes is Map<String, Object?> &&
          _isTopMarker(attributes['top'])) {
        module = candidate;
        break;
      }
    }
  }
  if (module == null) return null;

  final ports = module['ports'];
  if (ports is! Map<String, Object?>) return const <ElaboratedPort>[];
  final netnames = module['netnames'];
  final names = netnames is Map<String, Object?> ? netnames : null;

  final out = <ElaboratedPort>[];
  for (final entry in ports.entries) {
    final spec = entry.value;
    if (spec is! Map<String, Object?>) continue;
    final bits = spec['bits'];
    final net = names?[entry.key];
    final attributes = net is Map<String, Object?> ? net['attributes'] : null;
    final src = attributes is Map<String, Object?> ? attributes['src'] : null;
    out.add(
      ElaboratedPort(
        name: entry.key,
        direction: spec['direction'] is String
            ? spec['direction']! as String
            : 'inout',
        width: bits is List ? bits.length : 1,
        offset: net is Map<String, Object?> && net['offset'] is int
            ? net['offset']! as int
            : 0,
        upto: net is Map<String, Object?> && _isTruthy(net['upto']),
        declaration: CdcSourceSpan.parse(src is String ? src : null),
      ),
    );
  }
  return out;
}

/// Yosys writes the `top` attribute as a 32-character binary string, `1` in
/// the last place, and as a plain `1` in older releases.
bool _isTopMarker(Object? value) => switch (value) {
  final int v => v != 0,
  final String s => s.contains('1'),
  _ => false,
};

bool _isTruthy(Object? value) => switch (value) {
  final int v => v != 0,
  final bool b => b,
  _ => false,
};
