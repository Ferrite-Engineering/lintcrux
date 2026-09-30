// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart';

/// Parses a SARIF 2.1.0 JSON document into a [SarifReport].
///
/// The reader implements just enough of the SARIF surface to round-trip
/// LintCrux's own output and to ingest the documents produced by the
/// engines we wrap. The full SARIF 2.1.0 schema is very wide; the
/// preserved-in-`Violation.raw` map keeps everything we don't surface
/// in the typed wrapper so a load → write produces a structurally
/// equivalent document.
///
/// Field mapping (SARIF spec section in parentheses):
///
/// | SARIF path                                          | LintCrux                |
/// |-----------------------------------------------------|-------------------------|
/// | `version` (§3.13.2)                                 | [SarifReport.version]   |
/// | `$schema` (§3.13.3)                                 | [SarifReport.schema]    |
/// | `runs[]` (§3.13.4)                                  | [SarifReport.runs]      |
/// | `runs[*].tool.driver.name` (§3.18.2)                | [Run.engineId]          |
/// | `runs[*].tool.driver.version` (§3.19.13)            | [Run.engineVersion]     |
/// | `runs[*].invocations[0].startTimeUtc` (§3.20.7)     | [Run.startedAt]         |
/// | `runs[*].invocations[0].endTimeUtc` (§3.20.8)       | [Run.finishedAt]        |
/// | `runs[*].invocations[0].exitCode` (§3.20.11)        | [Run.exitCode]          |
/// | `runs[*].invocations[0].executionSuccessful`        | [Run.success]           |
/// | `runs[*].results[]` (§3.14.23)                      | [Run.violations]        |
/// | `results[*].ruleId` (§3.27.5)                       | [Violation.ruleId]      |
/// | `results[*].level` (§3.27.10)                       | [Violation.severity]    |
/// | `results[*].message.text` (§3.27.11)                | [Violation.message]     |
/// | `results[*].locations[0].physicalLocation`          | [Violation.location]    |
/// | `results[*].relatedLocations[]` (§3.27.22)          | [Violation.relatedLocations] |
/// | `results[*].suppressions[]` (§3.27.23)              | [Violation.suppression] (the first accepted entry) |
///
/// Severity mapping (LintCrux → SARIF):
///
/// | Severity | level   | LintCrux extension                     |
/// |----------|---------|----------------------------------------|
/// | fatal    | error   | `properties.lintcrux.severity = fatal` |
/// | error    | error   | (no extension)                         |
/// | warning  | warning | (no extension)                         |
/// | note     | note    | (no extension)                         |
/// | none     | none    | (no extension)                         |
///
/// On read, the inverse map applies: if `properties.lintcrux.severity` is
/// `fatal`, the [Severity] is `fatal`; otherwise the SARIF `level` selects.
class SarifReader {
  /// Creates a reader. The reader is stateless; the same instance can
  /// be reused across files.
  const SarifReader();

  /// Parses [jsonString] as a SARIF 2.1.0 document.
  ///
  /// Throws [SarifReadException] if the document is structurally invalid
  /// (top-level not a JSON object, missing `runs`, malformed result, etc.).
  /// Unknown fields are silently preserved in [Violation.raw] so a
  /// round-trip is lossless for vendor-specific extensions.
  SarifReport read(String jsonString) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e) {
      throw SarifReadException('document is not valid JSON: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SarifReadException(
        'top-level value must be a JSON object',
      );
    }
    return readMap(decoded);
  }

  /// Parses an already-decoded [json] map as a SARIF document.
  SarifReport readMap(Map<String, dynamic> json) {
    final version = (json['version'] as String?) ?? '2.1.0';
    final schema =
        (json[r'$schema'] as String?) ??
        'https://json.schemastore.org/sarif-2.1.0.json';
    final runsRaw = json['runs'];
    if (runsRaw is! List) {
      throw const SarifReadException('`runs` must be a JSON array');
    }
    final runs = <Run>[];
    for (var i = 0; i < runsRaw.length; i++) {
      final entry = runsRaw[i];
      if (entry is! Map<String, dynamic>) {
        throw SarifReadException('`runs[$i]` must be a JSON object');
      }
      runs.add(_readRun(entry, i));
    }
    return SarifReport(version: version, schema: schema, runs: runs);
  }

  Run _readRun(Map<String, dynamic> json, int index) {
    final driver = _expectMap(json, 'tool.driver', () {
      final tool = json['tool'];
      if (tool is! Map<String, dynamic>) return null;
      final d = tool['driver'];
      return d is Map<String, dynamic> ? d : null;
    });
    final engineId = (driver['name'] as String?)?.toLowerCase() ?? 'unknown';
    final engineVersion = (driver['version'] as String?) ?? '';

    DateTime startedAt;
    DateTime finishedAt;
    int? exitCode;
    var success = true;
    String? errorMessage;
    final notifications = <String>[];
    final invocations = json['invocations'];
    if (invocations is List && invocations.isNotEmpty) {
      final first = invocations.first;
      if (first is Map<String, dynamic>) {
        startedAt =
            _readUtc(first['startTimeUtc']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        finishedAt = _readUtc(first['endTimeUtc']) ?? startedAt;
        final exit = first['exitCode'];
        if (exit is int) exitCode = exit;
        final ok = first['executionSuccessful'];
        if (ok is bool) success = ok;
        final err = first['exitCodeDescription'];
        if (err is String) errorMessage = err;
        // Log-and-continue contract: recover the
        // unrecognized-line notifications so a load → write is lossless.
        final notes = first['toolExecutionNotifications'];
        if (notes is List) {
          for (final n in notes) {
            if (n is Map<String, dynamic>) {
              final msg = n['message'];
              if (msg is Map<String, dynamic> && msg['text'] is String) {
                notifications.add(msg['text'] as String);
              }
            }
          }
        }
      } else {
        startedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        finishedAt = startedAt;
      }
    } else {
      startedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      finishedAt = startedAt;
    }

    final resultsRaw = json['results'];
    final violations = <Violation>[];
    if (resultsRaw is List) {
      for (var i = 0; i < resultsRaw.length; i++) {
        final r = resultsRaw[i];
        if (r is! Map<String, dynamic>) {
          throw SarifReadException(
            '`runs[$index].results[$i]` must be a JSON object',
          );
        }
        violations.add(_readResult(r, engineId, index, i));
      }
    }

    return Run(
      id:
          (json['automationDetails'] is Map<String, dynamic> &&
              (json['automationDetails'] as Map<String, dynamic>)['id']
                  is String)
          ? (json['automationDetails'] as Map<String, dynamic>)['id'] as String
          : 'run-$engineId-$index',
      engineId: engineId,
      engineVersion: engineVersion,
      startedAt: startedAt,
      finishedAt: finishedAt,
      violations: violations,
      success: success,
      exitCode: exitCode,
      errorMessage: errorMessage,
      notifications: notifications,
    );
  }

  Violation _readResult(
    Map<String, dynamic> json,
    String engineId,
    int runIndex,
    int resultIndex,
  ) {
    return parseResult(
      json,
      engineId,
      pathHint: 'runs[$runIndex].results[$resultIndex]',
    );
  }

  /// Promotes a single SARIF `results[*]` map [json] into a [Violation].
  ///
  /// Exposed as a static entry point so the streaming reader (and
  /// other consumers that hand-extract individual result objects from
  /// a larger document) can reuse the same field-mapping logic without
  /// constructing a full [Run] / [SarifReport].
  ///
  /// [engineId] is the lowercased `tool.driver.name` from the
  /// containing run; it is used to namespace [Violation.ruleId] when
  /// the raw `ruleId` field doesn't already carry an explicit
  /// `engine/` prefix.
  ///
  /// [pathHint] is an optional path label used in error messages — set
  /// to e.g. `runs[2].results[17]` so callers see a meaningful
  /// location on malformed input. Falls back to a generic label when
  /// omitted.
  static Violation parseResult(
    Map<String, dynamic> json,
    String engineId, {
    String pathHint = 'results[*]',
  }) {
    final rawRuleId = (json['ruleId'] as String?) ?? 'UNKNOWN';
    // Engine-namespace if not already namespaced.
    final ruleId = rawRuleId.contains('/') ? rawRuleId : '$engineId/$rawRuleId';

    final levelStr = (json['level'] as String?) ?? 'warning';
    var severity = _levelToSeverity(levelStr);
    // Honor LintCrux's `properties.lintcrux.severity` for the fatal
    // extension if present.
    final props = json['properties'];
    if (props is Map<String, dynamic>) {
      final lcrux = props['lintcrux'];
      if (lcrux is Map<String, dynamic>) {
        final overrideStr = lcrux['severity'];
        if (overrideStr is String) {
          severity = _lintcruxSeverity(overrideStr) ?? severity;
        }
      }
    }

    final messageObj = json['message'];
    final message = messageObj is Map<String, dynamic>
        ? (messageObj['text'] as String?) ?? ''
        : '';

    final locationsRaw = json['locations'];
    final SourceLocation primary;
    final related = <SourceLocation>[];
    if (locationsRaw is List && locationsRaw.isNotEmpty) {
      primary =
          _readPhysicalLocation(
            locationsRaw.first,
            '$pathHint.locations[0]',
          ) ??
          _placeholderLocation();
    } else {
      primary = _placeholderLocation();
    }

    final relatedRaw = json['relatedLocations'];
    if (relatedRaw is List) {
      for (final r in relatedRaw) {
        final loc = _readPhysicalLocation(r, null);
        if (loc != null) related.add(loc);
      }
    }

    return Violation(
      engineId: engineId,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: primary,
      relatedLocations: List<SourceLocation>.unmodifiable(related),
      suppression: _readSuppression(json['suppressions'], ruleId, primary),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  /// The [Waiver] for a result's `suppressions` array, or `null` when the
  /// result is not suppressed.
  ///
  /// Per SARIF §3.35.3 a result is suppressed by an entry whose `status` is
  /// absent or `accepted`; an `underReview` or `rejected` entry does not
  /// suppress it. The waiver's id, author, dates and line range are read
  /// from `properties.lintcrux` where [SarifWriter] records them; a
  /// suppression written by another tool gets a synthetic id and an author
  /// that says which kind it was.
  static Waiver? _readSuppression(
    Object? suppressions,
    String ruleId,
    SourceLocation location,
  ) {
    if (suppressions is! List) return null;
    for (final entry in suppressions) {
      if (entry is! Map<String, dynamic>) continue;
      final status = entry['status'];
      if (status != null && status != 'accepted') continue;
      final kind = entry['kind'];
      final props = entry['properties'];
      final lintcrux = props is Map<String, dynamic> ? props['lintcrux'] : null;
      final meta = lintcrux is Map<String, dynamic>
          ? lintcrux
          : const <String, dynamic>{};
      final justification = entry['justification'];
      final id = meta['waiverId'];
      final author = meta['author'];
      final createdAt = DateTime.tryParse('${meta['createdAt']}');
      final expiresAt = DateTime.tryParse('${meta['expiresAt']}');
      final lineStart = meta['lineStart'];
      final lineEnd = meta['lineEnd'];
      return Waiver(
        id: id is String && id.isNotEmpty
            ? id
            : 'sarif:$kind:${location.file}:${location.line}:$ruleId',
        ruleId: ruleId,
        filePath: location.file,
        lineStart: lineStart is int ? lineStart : null,
        lineEnd: lineEnd is int ? lineEnd : null,
        reason: justification is String ? justification : '',
        author: author is String
            ? author
            : (kind == 'inSource' ? SarifWriter.inSourceWaiverAuthor : ''),
        createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        expiresAt: expiresAt,
      );
    }
    return null;
  }

  static SourceLocation? _readPhysicalLocation(dynamic node, String? path) {
    if (node is! Map<String, dynamic>) return null;
    final phys = node['physicalLocation'];
    if (phys is! Map<String, dynamic>) return null;
    final art = phys['artifactLocation'];
    final uri = (art is Map<String, dynamic>) ? art['uri'] as String? : null;
    if (uri == null) return null;
    final region = phys['region'];
    var line = 1;
    var column = 1;
    int? endLine;
    int? endColumn;
    if (region is Map<String, dynamic>) {
      final sl = region['startLine'];
      if (sl is int && sl >= 1) line = sl;
      final sc = region['startColumn'];
      if (sc is int && sc >= 1) column = sc;
      final el = region['endLine'];
      if (el is int && el >= 1) endLine = el;
      final ec = region['endColumn'];
      if (ec is int && ec >= 1) endColumn = ec;
    }
    return SourceLocation(
      file: uri,
      line: line,
      column: column,
      endLine: endLine,
      endColumn: endColumn,
    );
  }

  static SourceLocation _placeholderLocation() {
    return const SourceLocation(file: '', line: 1, column: 1);
  }

  static Severity _levelToSeverity(String level) {
    switch (level) {
      case 'error':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'note':
        return Severity.note;
      case 'none':
        return Severity.none;
      default:
        return Severity.warning;
    }
  }

  static Severity? _lintcruxSeverity(String s) {
    switch (s) {
      case 'fatal':
        return Severity.fatal;
      case 'error':
        return Severity.error;
      case 'warning':
        return Severity.warning;
      case 'note':
        return Severity.note;
      case 'none':
        return Severity.none;
      default:
        return null;
    }
  }

  static DateTime? _readUtc(dynamic value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static Map<String, dynamic> _expectMap(
    Map<String, dynamic> root,
    String path,
    Map<String, dynamic>? Function() pick,
  ) {
    final v = pick();
    if (v == null) {
      throw SarifReadException('missing or non-object at `$path`');
    }
    return v;
  }
}

/// Raised by [SarifReader.read] when the document is structurally
/// invalid. The message is suitable for surfacing to the user verbatim.
class SarifReadException implements Exception {
  /// Creates an exception with a human-readable [message].
  const SarifReadException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'SarifReadException: $message';
}
