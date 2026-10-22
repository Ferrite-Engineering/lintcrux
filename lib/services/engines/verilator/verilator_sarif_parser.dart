// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_reported_path.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';

/// Parser for the SARIF 2.1.0 document Verilator writes for
/// `--diagnostics-sarif-output <file>` (Verilator 5.038 and later).
///
/// It produces the same [Violation]s [VerilatorParser] produces from the
/// stderr transcript of the same run: same rule ids, severities, messages,
/// locations and related locations, and the same `verilator.continuation`
/// block (rebuilt from each result's `message.markdown`, which Verilator
/// fills with the exact text it printed). What SARIF adds on top is the
/// `fixes` array some Verilator builds attach to a result; it is carried in
/// [Violation.raw] under `fixes` so it survives a load and export round trip.
///
/// [parse] answers `null`, never throws, for anything that is not a usable
/// Verilator SARIF document (a truncated file, a JSON syntax error, a
/// document with no `runs[0].results`). The engine reads `null` as "use the
/// text path": Verilator 5.052 and earlier can write a document with a
/// missing comma, and a crash can leave a half-written file.
class VerilatorSarifParser {
  /// Creates a [VerilatorSarifParser].
  ///
  /// [rootPath] resolves relative paths and is the path form every result is
  /// reported in. [rootRealPath] is the same directory with symbolic links
  /// resolved: Verilator writes `realpath`-ed URIs, so a project under a
  /// symlinked directory (macOS `/var` to `/private/var`) is mapped back to
  /// [rootPath], as the text path reports it.
  VerilatorSarifParser({required this.rootPath, this.rootRealPath});

  /// Absolute project root; see [VerilatorParser.rootPath].
  final String rootPath;

  /// [rootPath] with symbolic links resolved, or `null` when unknown.
  final String? rootRealPath;

  late final VerilatorParser _textParser = VerilatorParser(rootPath: rootPath);

  /// Key under which a result's SARIF `fixes` array is kept in
  /// [Violation.raw].
  static const String fixesKey = 'fixes';

  /// Parses [source], or returns `null` when it is not usable.
  List<Violation>? parse(String source) {
    final Object? doc;
    try {
      doc = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (doc is! Map<String, dynamic>) return null;
    final runs = doc['runs'];
    if (runs is! List || runs.isEmpty) return null;
    final run = runs.first;
    if (run is! Map<String, dynamic>) return null;
    final results = run['results'];
    if (results is! List) return null;

    final out = <Violation>[];
    for (final result in results) {
      if (result is! Map<String, dynamic>) continue;
      final v = _violation(result);
      if (v != null) out.add(v);
    }
    return out;
  }

  Violation? _violation(Map<String, dynamic> result) {
    final locations = result['locations'];
    if (locations is! List || locations.isEmpty) {
      // Verilator's end-of-run tally (`Exiting due to N warning(s)`) and
      // every other message without a position: the text path drops these
      // too, because it only starts a violation at a `file:line:col`.
      return null;
    }
    final location = _location(locations.first);
    if (location == null) return null;

    final message = result['message'];
    final text = message is Map<String, dynamic> ? message['text'] : null;
    if (text is! String) return null;
    final newline = text.indexOf('\n');
    final headline = (newline < 0 ? text : text.substring(0, newline)).trim();

    final continuation = _continuation(
      message is Map<String, dynamic> ? message['markdown'] : null,
    );

    // The locations the text path lifts out of the printed lines come first:
    // Verilator's `relatedLocations` does not list them all (the second
    // location of a MULTIDRIVEN, for one, is printed but not listed), and a
    // finding must not change with the channel it arrived on. Whatever
    // `relatedLocations` adds beyond them follows.
    final related = <SourceLocation>[];
    for (final line in continuation) {
      final loc = _textParser.extractEmbeddedLocation(line);
      if (loc != null && loc != location && !related.contains(loc)) {
        related.add(loc);
      }
    }
    final relatedRaw = result['relatedLocations'];
    if (relatedRaw is List) {
      for (final entry in relatedRaw) {
        final loc = _location(entry);
        if (loc != null && loc != location && !related.contains(loc)) {
          related.add(loc);
        }
      }
    }
    final fixes = result[fixesKey];

    final ruleId = result['ruleId'];
    final rule = ruleId is String && ruleId.isNotEmpty
        ? ruleId
        : 'UNCLASSIFIED';
    return Violation(
      engineId: VerilatorParser.engineId,
      ruleId: '${VerilatorParser.engineId}/$rule',
      severity: _severity(result['level']),
      message: headline,
      location: location,
      relatedLocations: List<SourceLocation>.unmodifiable(related),
      raw: <String, dynamic>{
        if (continuation.isNotEmpty) 'verilator.continuation': continuation,
        if (fixes is List && fixes.isNotEmpty) fixesKey: fixes,
      },
    );
  }

  /// The lines Verilator printed under the header, from the markdown block
  /// `` ```\n<header>\n<lines>\n\n``` ``. Blank lines are dropped, as the text
  /// path drops them.
  List<String> _continuation(Object? markdown) {
    if (markdown is! String) return const <String>[];
    final lines = markdown.split('\n');
    final out = <String>[];
    var seenHeader = false;
    for (final line in lines) {
      if (line == '```') continue;
      if (!seenHeader) {
        seenHeader = true;
        continue;
      }
      if (line.isNotEmpty) out.add(line);
    }
    return out;
  }

  Severity _severity(Object? level) {
    switch (level) {
      case 'error':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'note':
      case 'none':
        return Severity.note;
      default:
        return Severity.warning;
    }
  }

  SourceLocation? _location(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    final physical = entry['physicalLocation'];
    if (physical is! Map<String, dynamic>) return null;
    final artifact = physical['artifactLocation'];
    final region = physical['region'];
    if (artifact is! Map<String, dynamic> || region is! Map<String, dynamic>) {
      return null;
    }
    final uri = artifact['uri'];
    final line = region['startLine'];
    if (uri is! String || line is! int || line < 1) return null;
    final column = region['startColumn'];
    final path = _resolve(_filePath(uri));
    if (path == null) return null;
    return SourceLocation(
      file: path,
      line: line,
      column: column is int && column >= 1 ? column : 1,
    );
  }

  /// Verilator builds the URI as `file://` plus the path, or `file:` plus a
  /// relative path, without percent-encoding, so the path is read back by
  /// stripping the prefix rather than by decoding.
  String _filePath(String uri) {
    if (uri.startsWith('file://')) return uri.substring('file://'.length);
    if (uri.startsWith('file:')) return uri.substring('file:'.length);
    return uri;
  }

  String? _resolve(String reported) {
    var path = reported;
    final real = rootRealPath;
    if (real != null && real.isNotEmpty && real != rootPath) {
      if (path.startsWith(real) &&
          (path.length == real.length ||
              path[real.length] == '/' ||
              path[real.length] == r'\')) {
        path = rootPath + path.substring(real.length);
      }
    }
    return resolveEngineReportedPath(path, rootPath);
  }
}
