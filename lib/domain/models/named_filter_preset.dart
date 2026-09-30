// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:meta/meta.dart';

/// User-named bookmark of the full violation-table filter state.
///
/// A preset captures every filter dimension the table exposes (severity
/// multi-select, engine multi-select, rule substring, file glob, and the
/// waived/active toggle) and a human-chosen [name]. Presets live in two
/// places:
///
/// 1. **Per-project** — saved into the `.lintcrux` project file via
///    [LintProject.filterPresets] so a team commits a shared set
///    alongside the source list.
/// 2. **User-wide** — saved into `AppSettings` so engineers carry their
///    personal "Show only fatal" or "Just my files" presets across
///    projects.
///
/// The provider that owns the merged in-memory view
/// (`savedFilterPresetsProvider`) is responsible for resolving collisions
/// (per-project preset of the same name takes precedence over user-wide).
///
/// The model is immutable and round-trips to JSON via [toJson] /
/// [fromJson]; the JSON schema is forward-compatible — unknown keys are
/// silently ignored on read, so adding `tagFilter` later won't break
/// older save files.
@immutable
class NamedFilterPreset {
  /// Creates a [NamedFilterPreset].
  const NamedFilterPreset({
    required this.name,
    this.severities = const <Severity>{},
    this.engineIds = const <String>{},
    this.ruleSubstring = '',
    this.fileGlob = '',
    this.showWaived = false,
  });

  /// Decodes a [NamedFilterPreset] from a JSON map. Returns `null` if
  /// [map] is malformed in a non-recoverable way (missing name).
  static NamedFilterPreset? fromJson(Map<String, Object?> map) {
    final name = map['name'];
    if (name is! String || name.isEmpty) return null;

    final severities = <Severity>{};
    final rawSev = map['severities'];
    if (rawSev is List) {
      for (final s in rawSev) {
        if (s is String) {
          final sev = _severityFromString(s);
          if (sev != null) severities.add(sev);
        }
      }
    }

    final engineIds = <String>{};
    final rawEng = map['engineIds'];
    if (rawEng is List) {
      for (final e in rawEng) {
        if (e is String && e.isNotEmpty) engineIds.add(e);
      }
    }

    final ruleSubstring = map['ruleSubstring'];
    final fileGlob = map['fileGlob'];
    final showWaived = map['showWaived'];

    return NamedFilterPreset(
      name: name,
      severities: Set<Severity>.unmodifiable(severities),
      engineIds: Set<String>.unmodifiable(engineIds),
      ruleSubstring: ruleSubstring is String ? ruleSubstring : '',
      fileGlob: fileGlob is String ? fileGlob : '',
      showWaived: showWaived is bool && showWaived,
    );
  }

  /// User-chosen unique-within-scope name. Used in the dropdown and
  /// dialogs; presented verbatim.
  final String name;

  /// Severity multi-select; empty = all severities allowed.
  final Set<Severity> severities;

  /// Engine multi-select; empty = all engines allowed.
  final Set<String> engineIds;

  /// Case-insensitive substring matched against ruleId and message;
  /// empty = unfiltered.
  final String ruleSubstring;

  /// Glob matched against violation file path; empty = unfiltered.
  final String fileGlob;

  /// Whether waived violations are visible. Default `false` follows the
  /// table's default of hiding waived rows.
  final bool showWaived;

  /// Returns a copy with overridden fields.
  NamedFilterPreset copyWith({
    String? name,
    Set<Severity>? severities,
    Set<String>? engineIds,
    String? ruleSubstring,
    String? fileGlob,
    bool? showWaived,
  }) {
    return NamedFilterPreset(
      name: name ?? this.name,
      severities: severities ?? this.severities,
      engineIds: engineIds ?? this.engineIds,
      ruleSubstring: ruleSubstring ?? this.ruleSubstring,
      fileGlob: fileGlob ?? this.fileGlob,
      showWaived: showWaived ?? this.showWaived,
    );
  }

  /// Serializes to a stable JSON map. The order of map keys is
  /// deterministic so committed `.lintcrux` files diff cleanly.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'severities': <String>[
      for (final s in severities) _severityToString(s),
    ]..sort(),
    'engineIds': <String>[...engineIds]..sort(),
    'ruleSubstring': ruleSubstring,
    'fileGlob': fileGlob,
    'showWaived': showWaived,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NamedFilterPreset) return false;
    if (other.name != name) return false;
    if (other.ruleSubstring != ruleSubstring) return false;
    if (other.fileGlob != fileGlob) return false;
    if (other.showWaived != showWaived) return false;
    if (other.severities.length != severities.length) return false;
    if (!severities.containsAll(other.severities)) return false;
    if (other.engineIds.length != engineIds.length) return false;
    if (!engineIds.containsAll(other.engineIds)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    ruleSubstring,
    fileGlob,
    showWaived,
    Object.hashAllUnordered(severities),
    Object.hashAllUnordered(engineIds),
  );

  @override
  String toString() => 'NamedFilterPreset($name)';

  static String _severityToString(Severity s) {
    switch (s) {
      case Severity.fatal:
        return 'fatal';
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

  static Severity? _severityFromString(String s) {
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
}
