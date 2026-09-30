// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Pro-tier named filter preset for the violations table.
///
/// A [FilterPreset] captures a violation-table filter configuration so
/// the user can switch between commonly-used filters with one click.
/// Three flavors:
///
/// * **Built-in** ([builtin] = `true`) — shipped by open-core (e.g.
///   "All Violations", "Errors Only", "New Violations"). Visible on every
///   tier; cannot be deleted. The `id` is stable across releases so a
///   user-saved active-preset reference survives upgrades.
/// * **User-authored** ([builtin] = `false`) — saved by the user via
///   "Save current as preset…". Persisted by the Pro overlay's
///   `JsonFileFilterPresetStore` to `<project-root>/.lintcrux-filter-presets.json`.
///   Editable / deletable.
/// * **Reserved for future shared-team flavor** — the structure is the
///   same; the storage backend is what differs.
///
/// Distinct from [NamedFilterPreset]: that earlier model holds typed
/// filter dimensions inline and lives in `LintProject.filterPresets`
/// (the project's `.lintcrux` file). This
/// richer model carries metadata ([id], [description], [createdAt],
/// [updatedAt], [sortOrder], [builtin]) and stores the filter state as
/// a JSON-natural map so the schema can evolve without breaking older
/// committed JSON files. The two coexist; consumers reach for whichever
/// matches their persistence surface.
///
/// The schema [version] is the source of forward-compatibility: a
/// reader that sees a `version` it does not understand throws
/// [FormatException] from [FilterPreset.fromJson] rather than silently
/// reinterpreting unknown fields.
@immutable
class FilterPreset {
  /// Creates a [FilterPreset].
  const FilterPreset({
    required this.id,
    required this.name,
    required this.filterState,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.builtin = false,
    this.sortOrder = 0,
    this.version = currentVersion,
  });

  /// Parses [json]. Throws [FormatException] for missing required
  /// fields, wrong-type fields, or an unrecognized `version`.
  factory FilterPreset.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException(
        "FilterPreset missing required 'version' field",
      );
    }
    if (version != currentVersion) {
      throw FormatException(
        'Unsupported filter preset schema version: $version '
        '(this build understands v$currentVersion only)',
      );
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
        "FilterPreset missing required 'id' field",
      );
    }
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException(
        "FilterPreset missing required 'name' field",
      );
    }
    final filterStateRaw = json['filterState'];
    if (filterStateRaw is! Map) {
      throw const FormatException(
        "FilterPreset 'filterState' field must be a map",
      );
    }
    final filterState = Map<String, Object?>.from(filterStateRaw);
    final createdAtRaw = json['createdAt'];
    if (createdAtRaw is! String) {
      throw const FormatException(
        "FilterPreset 'createdAt' field must be an ISO 8601 string",
      );
    }
    final updatedAtRaw = json['updatedAt'];
    if (updatedAtRaw is! String) {
      throw const FormatException(
        "FilterPreset 'updatedAt' field must be an ISO 8601 string",
      );
    }
    final descriptionRaw = json['description'];
    final builtinRaw = json['builtin'];
    final sortOrderRaw = json['sortOrder'];
    return FilterPreset(
      id: id,
      name: name,
      filterState: Map<String, Object?>.unmodifiable(filterState),
      createdAt: DateTime.parse(createdAtRaw),
      updatedAt: DateTime.parse(updatedAtRaw),
      description: descriptionRaw is String && descriptionRaw.isNotEmpty
          ? descriptionRaw
          : null,
      builtin: builtinRaw is bool && builtinRaw,
      sortOrder: sortOrderRaw is int ? sortOrderRaw : 0,
    );
  }

  /// Current schema version. Bumped whenever the on-disk JSON
  /// representation changes in a backward-incompatible way.
  static const int currentVersion = 1;

  /// Stable identifier (UUID for user-authored; `builtin_<slug>` for
  /// built-ins). Used as the dropdown selection key and the
  /// active-preset reference so a rename does not break activation.
  final String id;

  /// User-visible name shown in the dropdown and the manager screen.
  /// Unique per project (enforced at save time, not at construction).
  final String name;

  /// Optional descriptive text shown in the manager screen.
  final String? description;

  /// `true` for built-in presets shipped by open-core. Built-ins
  /// cannot be deleted; their `id` is stable across releases.
  final bool builtin;

  /// JSON-natural map of filter dimensions. Schema mirrors
  /// `ViolationFilter` / `NamedFilterPreset`'s exposed fields:
  ///   - `severities`: `List<String>` (severity enum names)
  ///   - `engineIds`: `List<String>`
  ///   - `ruleSubstring`: `String`
  ///   - `fileGlob`: `String`
  ///   - `showWaived`: `bool`
  ///   - `viewMode`: `String` (one of `allViolations` / `onlyNew` /
  ///     `onlyResolved` — for the "New Violations" built-in).
  /// Unknown keys are preserved on round-trip for forward compatibility.
  final Map<String, Object?> filterState;

  /// Creation timestamp (UTC). Built-ins use `DateTime.utc(2024, 1, 1)`
  /// as a stable sentinel so their JSON form does not depend on when
  /// the user first saw them.
  final DateTime createdAt;

  /// Last-modified timestamp (UTC). Equal to [createdAt] on initial
  /// save. Updated by the store on every edit.
  final DateTime updatedAt;

  /// Explicit ordering for the preset dropdown. Built-ins come first
  /// (their `sortOrder` is `0`–`99`); user presets sort by their own
  /// `sortOrder` (defaulting to insertion order × 100 so new entries
  /// land at the bottom by default but the user can reorder).
  final int sortOrder;

  /// Schema version. Always [currentVersion] on freshly constructed
  /// instances; preserved during [copyWith].
  final int version;

  /// Returns a copy with overridden fields. [filterState] is treated
  /// as a value type — pass a new map to replace it.
  FilterPreset copyWith({
    String? id,
    String? name,
    String? description,
    bool? builtin,
    Map<String, Object?>? filterState,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sortOrder,
  }) {
    return FilterPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      builtin: builtin ?? this.builtin,
      filterState: filterState ?? this.filterState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      version: version,
    );
  }

  /// Serializes to a stable JSON map. Key order is deterministic so
  /// committed JSON files diff cleanly.
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'version': version,
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'builtin': builtin,
      'filterState': filterState,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'sortOrder': sortOrder,
    };
    return json;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FilterPreset) return false;
    if (other.id != id) return false;
    if (other.name != name) return false;
    if (other.description != description) return false;
    if (other.builtin != builtin) return false;
    if (other.createdAt != createdAt) return false;
    if (other.updatedAt != updatedAt) return false;
    if (other.sortOrder != sortOrder) return false;
    if (other.version != version) return false;
    if (other.filterState.length != filterState.length) return false;
    for (final entry in filterState.entries) {
      if (!other.filterState.containsKey(entry.key)) return false;
      if (other.filterState[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    builtin,
    createdAt,
    updatedAt,
    sortOrder,
    version,
    Object.hashAll(filterState.entries.map((e) => Object.hash(e.key, e.value))),
  );

  @override
  String toString() => 'FilterPreset($id, $name, builtin=$builtin)';
}
