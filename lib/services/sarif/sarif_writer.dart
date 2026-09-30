// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';

/// Serializes a [SarifReport] to a SARIF 2.1.0 JSON document.
///
/// The writer is the inverse of [SarifReader] for the surface area
/// LintCrux owns. Field mapping is documented on the reader; severity
/// extension semantics (LintCrux fatal → SARIF `error` plus
/// `properties.lintcrux.severity = "fatal"`) are applied here.
///
/// `Violation.raw` is preserved by merging the structured fields back
/// into the raw bag. This makes the round-trip lossless for vendor
/// extensions: the typed wrapper holds the fields we use, the raw bag
/// holds everything else. Only keys the SARIF 2.1.0 `result` object
/// defines are spread into the result — the schema declares it
/// `additionalProperties: false` — and every other raw key (an engine
/// adapter's `yosys.severityRaw`, a transformer's
/// `lintcrux.pragmaWaiverSourceFile`) goes into the result's `properties`
/// bag, where SARIF allows arbitrary keys.
///
/// A suppressed violation keeps its result and gains a `suppressions`
/// entry (SARIF §3.27.23, §3.35): `kind` is `inSource` for an inline
/// pragma and `external` for a managed waiver, `status` is `accepted`,
/// `justification` is the waiver's reason, and the waiver's id, author,
/// dates and line range ride in `properties.lintcrux` so [SarifReader]
/// can restore it. The waiver id is not a GUID, so it never goes in
/// `guid`.
class SarifWriter {
  /// Creates a writer. The writer is stateless; the same instance can
  /// be reused across files.
  const SarifWriter({
    this.pretty = true,
    this.uriBaseId,
    this.originalUriBaseIds = const <String, String>{},
  });

  /// When `true` (default), the produced JSON is pretty-printed with
  /// two-space indentation. Disable for compact CI / piping output.
  final bool pretty;

  /// Symbolic base emitted as `artifactLocation.uriBaseId` on every
  /// location, or `null` (the default) to omit it.
  ///
  /// GitHub code scanning matches a result to a file in the checked-out
  /// repository by resolving `artifactLocation.uri` against the base
  /// named here. Uploading absolute developer-machine paths produces an
  /// accepted-but-useless SARIF: the alerts land with no line
  /// annotations because nothing in the repo matches
  /// `/Users/someone/work/rtl/top.sv`. The headless CLI therefore
  /// relativizes every path against the project root and declares that
  /// root as `%SRCROOT%`.
  final String? uriBaseId;

  /// The `run.originalUriBaseIds` table — symbolic base id to its
  /// absolute `file://` URI. Emitted only when non-empty.
  ///
  /// Declaring the concrete location of [uriBaseId] is what makes the
  /// relative `uri` values interpretable by a consumer that is *not*
  /// GitHub (a local viewer, GitLab SAST), so the same artifact stays
  /// useful outside the one tool that special-cases it.
  final Map<String, String> originalUriBaseIds;

  /// Serializes [report] to a SARIF JSON string.
  String write(SarifReport report) {
    final map = toMap(report);
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return jsonEncode(map);
  }

  /// Lowers [report] to a plain `Map<String, dynamic>` suitable for
  /// [jsonEncode]. Exposed separately so callers can compose SARIF
  /// documents into larger pipelines without re-parsing.
  Map<String, dynamic> toMap(SarifReport report) {
    return <String, dynamic>{
      r'$schema': report.schema,
      'version': report.version,
      'runs': report.runs.map(_runToMap).toList(),
    };
  }

  Map<String, dynamic> _runToMap(Run run) {
    return <String, dynamic>{
      'tool': <String, dynamic>{
        'driver': <String, dynamic>{
          'name': run.engineId,
          if (run.engineVersion.isNotEmpty) 'version': run.engineVersion,
        },
      },
      'invocations': <Map<String, dynamic>>[
        <String, dynamic>{
          'executionSuccessful': run.success,
          'startTimeUtc': run.startedAt.toUtc().toIso8601String(),
          'endTimeUtc': run.finishedAt.toUtc().toIso8601String(),
          if (run.exitCode != null) 'exitCode': run.exitCode,
          if (run.errorMessage != null) 'exitCodeDescription': run.errorMessage,
          // Log-and-continue contract: every engine line
          // the parser could not attribute to a violation is surfaced here
          // as a `note`-level notification instead of being dropped.
          if (run.notifications.isNotEmpty)
            'toolExecutionNotifications': <Map<String, dynamic>>[
              for (final n in run.notifications)
                <String, dynamic>{
                  'level': 'note',
                  'message': <String, dynamic>{'text': n},
                },
            ],
        },
      ],
      'automationDetails': <String, dynamic>{'id': run.id},
      if (originalUriBaseIds.isNotEmpty)
        'originalUriBaseIds': <String, dynamic>{
          for (final entry in originalUriBaseIds.entries)
            entry.key: <String, dynamic>{'uri': entry.value},
        },
      'results': run.violations.map(_violationToMap).toList(),
    };
  }

  /// The properties SARIF 2.1.0 defines on a `result` object (§3.27). The
  /// schema forbids any other key there.
  static const Set<String> sarifResultKeys = <String>{
    'guid',
    'correlationGuid',
    'ruleId',
    'ruleIndex',
    'rule',
    'kind',
    'level',
    'message',
    'analysisTarget',
    'locations',
    'webRequest',
    'webResponse',
    'fingerprints',
    'partialFingerprints',
    'codeFlows',
    'graphs',
    'graphTraversals',
    'stacks',
    'relatedLocations',
    'suppressions',
    'baselineState',
    'rank',
    'attachments',
    'hostedViewerUri',
    'workItemUris',
    'provenance',
    'fixes',
    'taxa',
    'properties',
  };

  Map<String, dynamic> _violationToMap(Violation v) {
    // Start from the preserved raw bag so vendor extensions survive the
    // round-trip; overwrite the structured fields with the current values
    // so user mutations on the typed wrapper win over the cached raw.
    final extensions = <String, dynamic>{
      for (final entry in v.raw.entries)
        if (!sarifResultKeys.contains(entry.key)) entry.key: entry.value,
    };
    final out = <String, dynamic>{
      for (final entry in v.raw.entries)
        if (sarifResultKeys.contains(entry.key)) entry.key: entry.value,
      'ruleId': _localRuleId(v.engineId, v.ruleId),
      'level': _severityToLevel(v.severity),
      'message': <String, dynamic>{'text': v.message},
      'locations': <Map<String, dynamic>>[_locationToMap(v.location)],
    };
    if (extensions.isNotEmpty) {
      out['properties'] = <String, dynamic>{
        ...extensions,
        if (out['properties'] is Map<String, dynamic>)
          ...out['properties'] as Map<String, dynamic>,
      };
    }
    if (v.relatedLocations.isNotEmpty) {
      out['relatedLocations'] = v.relatedLocations.map(_locationToMap).toList();
    } else {
      out.remove('relatedLocations');
    }
    final waiver = v.suppression;
    if (waiver != null) {
      out['suppressions'] = <Map<String, dynamic>>[suppressionToMap(waiver)];
    } else {
      // The typed wrapper wins: a violation no longer waived must not keep
      // a suppression it was read with.
      out.remove('suppressions');
    }

    if (v.severity == Severity.fatal) {
      final props = <String, dynamic>{
        if (out['properties'] is Map<String, dynamic>)
          ...out['properties'] as Map<String, dynamic>,
      };
      final lcrux = <String, dynamic>{
        if (props['lintcrux'] is Map<String, dynamic>)
          ...props['lintcrux'] as Map<String, dynamic>,
        'severity': 'fatal',
      };
      props['lintcrux'] = lcrux;
      out['properties'] = props;
    } else if (out['properties'] is Map<String, dynamic>) {
      // Remove a stale fatal marker for non-fatal severities.
      final props = Map<String, dynamic>.from(
        out['properties'] as Map<String, dynamic>,
      );
      final lcrux = props['lintcrux'];
      if (lcrux is Map<String, dynamic> && lcrux['severity'] is String) {
        final cleaned = Map<String, dynamic>.from(lcrux)..remove('severity');
        if (cleaned.isEmpty) {
          props.remove('lintcrux');
        } else {
          props['lintcrux'] = cleaned;
        }
      }
      if (props.isEmpty) {
        out.remove('properties');
      } else {
        out['properties'] = props;
      }
    }

    return out;
  }

  /// The SARIF `suppression` object for [waiver].
  static Map<String, dynamic> suppressionToMap(Waiver waiver) {
    final expiresAt = waiver.expiresAt;
    return <String, dynamic>{
      'kind': isInSourceWaiver(waiver) ? 'inSource' : 'external',
      'status': 'accepted',
      if (waiver.reason.isNotEmpty) 'justification': waiver.reason,
      'properties': <String, dynamic>{
        'lintcrux': <String, dynamic>{
          'waiverId': waiver.id,
          if (waiver.author.isNotEmpty) 'author': waiver.author,
          'createdAt': waiver.createdAt.toUtc().toIso8601String(),
          if (expiresAt != null)
            'expiresAt': expiresAt.toUtc().toIso8601String(),
          if (waiver.lineStart != null) 'lineStart': waiver.lineStart,
          if (waiver.lineEnd != null) 'lineEnd': waiver.lineEnd,
        },
      },
    };
  }

  /// Whether [waiver] is an inline source pragma rather than a managed
  /// waiver kept outside the RTL. The pragma transformer marks its waivers
  /// with the author `source` and a `pragma:` id.
  static bool isInSourceWaiver(Waiver waiver) =>
      waiver.author == inSourceWaiverAuthor || waiver.id.startsWith('pragma:');

  /// The author recorded on a waiver that comes from the source itself.
  static const String inSourceWaiverAuthor = 'source';

  Map<String, dynamic> _locationToMap(SourceLocation loc) {
    final region = <String, dynamic>{
      'startLine': loc.line,
      'startColumn': loc.column,
      if (loc.endLine != null) 'endLine': loc.endLine,
      if (loc.endColumn != null) 'endColumn': loc.endColumn,
    };
    return <String, dynamic>{
      'physicalLocation': <String, dynamic>{
        'artifactLocation': <String, dynamic>{
          'uri': loc.file,
          if (uriBaseId != null) 'uriBaseId': uriBaseId,
        },
        'region': region,
      },
    };
  }

  /// Strips the `<engineId>/` prefix from `ruleId` for the SARIF
  /// representation — SARIF's `runs[*].tool.driver.name` already
  /// identifies the engine.
  static String _localRuleId(String engineId, String fullRuleId) {
    final prefix = '$engineId/';
    if (fullRuleId.startsWith(prefix)) {
      return fullRuleId.substring(prefix.length);
    }
    return fullRuleId;
  }

  static String _severityToLevel(Severity s) {
    switch (s) {
      case Severity.fatal:
        // SARIF 2.1.0 has no `fatal`; we surface the LintCrux extension
        // via properties.lintcrux.severity (handled in `_violationToMap`).
        return 'error';
      case Severity.error:
        return 'error';
      case Severity.warning:
        return 'warning';
      case Severity.note:
        return 'note';
      case Severity.none:
        return 'none';
    }
  }
}
