// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/severity.dart';
import 'package:meta/meta.dart';

/// Metadata describing a single named lint rule.
///
/// Populated from the per-engine rule database so the
/// inspector can render a helpful description and a "learn more" URL
/// alongside each [Violation]. Rules cross-reference SARIF's
/// `reportingDescriptor` (§3.49) — `id` corresponds to
/// `reportingDescriptor.id`, `helpUri` to `helpUri`, and `tags` to
/// `defaultConfiguration.properties.tags`.
///
/// The `id` is the engine-namespaced rule identifier (e.g.
/// `"verilator/UNUSEDSIGNAL"`). Engine-local IDs without the
/// `<engine>/` prefix are not unique across engines and must be
/// promoted to the namespaced form before storage.
@immutable
class Rule {
  /// Creates a [Rule]. `id` and `defaultSeverity` are required; other
  /// fields are optional and default to localized placeholders rendered
  /// by the inspector when the rule database has no entry for [id].
  const Rule({
    required this.id,
    required this.defaultSeverity,
    this.shortDescription = '',
    this.fullDescription = '',
    this.helpUri,
    this.tags = const <String>[],
  });

  /// Engine-namespaced identifier — `"<engineId>/<ruleId>"`.
  final String id;

  /// One-line summary suitable for the violation row's rule column.
  /// English; the rule database localizes per-locale at lookup time.
  final String shortDescription;

  /// Multi-paragraph description shown in the inspector panel.
  final String fullDescription;

  /// External URL with more context (engine docs, RFC, methodology
  /// guide). Opened in the user's browser via `url_launcher`.
  final Uri? helpUri;

  /// The severity the engine emits by default. Per-project overrides
  /// (stored in `.lintcrux`) can demote/promote individual rules; the
  /// runtime value lives on the [Violation], not here.
  final Severity defaultSeverity;

  /// Free-form classification tags from the rule database — e.g.
  /// `['synthesis', 'unused']`, `['style', 'naming']`. Surfaced as
  /// filter chips.
  final List<String> tags;

  /// Returns a copy with overridden fields.
  Rule copyWith({
    String? id,
    String? shortDescription,
    String? fullDescription,
    Uri? helpUri,
    Severity? defaultSeverity,
    List<String>? tags,
  }) {
    return Rule(
      id: id ?? this.id,
      shortDescription: shortDescription ?? this.shortDescription,
      fullDescription: fullDescription ?? this.fullDescription,
      helpUri: helpUri ?? this.helpUri,
      defaultSeverity: defaultSeverity ?? this.defaultSeverity,
      tags: tags ?? this.tags,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Rule) return false;
    if (other.id != id) return false;
    if (other.shortDescription != shortDescription) return false;
    if (other.fullDescription != fullDescription) return false;
    if (other.helpUri != helpUri) return false;
    if (other.defaultSeverity != defaultSeverity) return false;
    if (other.tags.length != tags.length) return false;
    for (var i = 0; i < tags.length; i++) {
      if (other.tags[i] != tags[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    shortDescription,
    fullDescription,
    helpUri,
    defaultSeverity,
    Object.hashAll(tags),
  );

  @override
  String toString() =>
      'Rule(id: $id, defaultSeverity: $defaultSeverity, tags: $tags)';
}
