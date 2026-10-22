// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        FileSystemEntityType,
        FileSystemException,
        Platform;

import 'package:crux_yosys/crux_yosys.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/cdc/cdc_source_span.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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
  const DesignElaborated(this.rawJson, {this.netlistFile});

  /// The `write_json` document `crux_yosys` read back, exactly as Yosys
  /// wrote it.
  ///
  /// When [netlistFile] is set the design was cleared after it was written
  /// there, and this is the document of the empty design: read the netlist
  /// from the file.
  final String rawJson;

  /// The file holding the netlist, when the caller asked [elaborateDesign]
  /// for one (`netlistPath`) and Yosys wrote it; `null` otherwise. The caller
  /// that named the path removes it.
  final File? netlistFile;
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
/// [frontend] picks the reader; [YosysFrontend.slang] needs a Yosys that
/// `YosysAvailabilityService.probeSlang` says has it, and takes
/// [slangOptions]. A slang netlist names each `src` file relative to the
/// directory Yosys ran in: read spans through [YosysSpanPathResolver].
///
/// [netlistPath] asks for the netlist on disk rather than in memory, for an
/// analysis that reads it as a stream (see `CdcNetlistReader`). `crux_yosys`
/// reads its `write_json` output back whole, as one string: 864 MB of text
/// for a flattened OpenTitan earlgrey. So after [extraCommands] Yosys writes
/// the netlist to [netlistPath] itself and then clears the design, and the
/// document the runner reads back is the empty one. The result's
/// [DesignElaborated.netlistFile] is the file when Yosys wrote it; it stays
/// `null` (the netlist is then in [DesignElaborated.rawJson], as without
/// [netlistPath]) when the path cannot be written into a Yosys script bare,
/// because it contains whitespace, a quote, `;` or a line break, or when the
/// process that ran wrote no such file.
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
  YosysFrontend frontend = YosysFrontend.verilog,
  List<String> slangOptions = const <String>[],
  String? netlistPath,
}) async {
  final executable = yosysExecutableFor(
    request.binary,
    resolver: bundledBinaryResolver,
  );
  // `extraCommands` entries cannot carry double quotes, so the path is
  // written bare and must be one token.
  final toDisk = netlistPath != null && !_unsafeBare.hasMatch(netlistPath);
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
      extraCommands: <String>[
        ...extraCommands,
        if (toDisk) ...<String>['write_json $netlistPath', 'design -reset'],
      ],
      frontend: frontend,
      slangOptions: slangOptions,
    ),
  );
  switch (result) {
    case YosysRunSuccess(:final rawJson):
      final file = toDisk ? File(netlistPath) : null;
      return DesignElaborated(
        rawJson,
        netlistFile: file != null && file.existsSync() && file.lengthSync() > 0
            ? file
            : null,
      );
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

/// What a path written bare into a Yosys script must not contain: whitespace
/// ends the token, and a quote, `;` or line break is refused in an extra
/// command.
final RegExp _unsafeBare = RegExp(r'[\s";]');

/// Turns the file of a Yosys `src` attribute into the path the user's project
/// names, so findings, waivers and baselines key on the user's own path.
///
/// The built-in reader writes the path it was given, which is already the
/// project's (absolute) source path, and is returned unchanged. yosys-slang
/// writes the file relative to the directory Yosys ran in
/// ([yosysWorkingDirectoryFor]), with or without `--diag-abs-paths`, so
/// `rtl/top.sv` from a run in the project root would otherwise be a second
/// name for `/project/rtl/top.sv`: a waiver written against one would not
/// match the other.
///
/// A relative file is joined to that directory. When the result names one of
/// the request's sources, directly or once symbolic links are resolved
/// (Yosys's own directory is the canonical one, `/private/var` where the
/// project says `/var`), the source's own spelling is returned. Anything else,
/// an included header for instance, is returned as the joined absolute path.
/// Answers are cached per resolver, which serves one run.
class YosysSpanPathResolver {
  /// A resolver for the spans of one elaboration of [request].
  YosysSpanPathResolver(LintRunRequest request)
    : _workingDirectory = yosysWorkingDirectoryFor(request),
      _sources = request.sourceFiles;

  final String? _workingDirectory;
  final List<String> _sources;
  final Map<String, String> _resolved = <String, String>{};
  Map<String, String>? _byNormalized;
  Map<String, String>? _byCanonical;
  String? _canonicalWorkingDirectory;

  /// The project's name for [file], as described on the class.
  String resolve(String file) {
    final workingDirectory = _workingDirectory;
    if (file.isEmpty || p.isAbsolute(file) || workingDirectory == null) {
      return file;
    }
    return _resolved.putIfAbsent(
      file,
      () => _resolveRelative(workingDirectory, file),
    );
  }

  String _resolveRelative(String workingDirectory, String file) {
    final joined = p.normalize(p.join(workingDirectory, file));
    final byNormalized = _byNormalized ??= <String, String>{
      for (final source in _sources) _key(p.normalize(source)): source,
    };
    if (byNormalized[_key(joined)] case final String source) return source;

    // Yosys's own working directory is the canonical one, so the relative
    // name may have been computed from it rather than from the spelling the
    // project uses: try both, each with its links resolved.
    final canonicalDirectory = _canonicalWorkingDirectory ??= _canonical(
      workingDirectory,
    );
    final fromCanonical = p.normalize(p.join(canonicalDirectory, file));
    final byCanonical = _byCanonical ??= <String, String>{
      for (final source in _sources) _key(_canonical(source)): source,
    };
    for (final candidate in <String>[joined, fromCanonical]) {
      if (byCanonical[_key(_canonical(candidate))] case final String source) {
        return source;
      }
    }
    if (!_exists(joined) && _exists(fromCanonical)) return fromCanonical;
    return joined;
  }

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  /// [path] with its symbolic links resolved, or [path] normalized when it
  /// cannot be (it does not exist, or is not readable).
  static String _canonical(String path) {
    try {
      final type = FileSystemEntity.typeSync(path);
      final resolved = type == FileSystemEntityType.directory
          ? Directory(path).resolveSymbolicLinksSync()
          : File(path).resolveSymbolicLinksSync();
      return p.normalize(resolved);
    } on FileSystemException {
      return p.normalize(path);
    }
  }

  /// Comparison key: case-insensitive where the platform's paths are.
  static String _key(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;
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
