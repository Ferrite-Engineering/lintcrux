// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/verible_fix_confidence.dart';
import 'package:meta/meta.dart';

/// One textual replacement proposed by Verible's auto-fix engine.
///
/// A [VeribleFixProposal] captures everything the UI needs to render
/// a side-by-side diff and apply (or skip) the change atomically:
/// the file + line range to replace, the original text, the
/// replacement text, the rule that prompted the fix, a human-readable
/// description, and the confidence band Verible assigned.
///
/// Identity is the synthetic [id] (UUID); two proposals targeting
/// the same lines but with different replacement text are distinct
/// proposals, so the UI's checkbox-per-proposal selection model
/// stays unambiguous.
@immutable
class VeribleFixProposal {
  /// Creates a [VeribleFixProposal].
  const VeribleFixProposal({
    required this.id,
    required this.filePath,
    required this.lineRangeBegin,
    required this.lineRangeEnd,
    required this.originalText,
    required this.replacementText,
    required this.description,
    required this.ruleId,
    required this.confidence,
  }) : assert(lineRangeBegin >= 1, 'lineRangeBegin must be 1-based'),
       assert(
         lineRangeEnd >= lineRangeBegin,
         'lineRangeEnd must be >= lineRangeBegin',
       );

  /// Parses [json] into a [VeribleFixProposal]. Throws
  /// [FormatException] on missing fields, wrong-typed fields, or an
  /// unknown confidence enum value.
  factory VeribleFixProposal.fromJson(Map<String, dynamic> json) {
    final id = _string(json, 'id');
    final filePath = _string(json, 'filePath');
    final lineRangeBegin = _int(json, 'lineRangeBegin');
    final lineRangeEnd = _int(json, 'lineRangeEnd');
    final originalText = _string(json, 'originalText');
    final replacementText = _string(json, 'replacementText');
    final description = _string(json, 'description');
    final ruleId = _string(json, 'ruleId');
    final confidenceRaw = _string(json, 'confidence');
    final confidence = VeribleFixConfidence.values.firstWhere(
      (c) => c.name == confidenceRaw,
      orElse: () => throw FormatException(
        "Unknown VeribleFixConfidence value '$confidenceRaw'",
      ),
    );
    return VeribleFixProposal(
      id: id,
      filePath: filePath,
      lineRangeBegin: lineRangeBegin,
      lineRangeEnd: lineRangeEnd,
      originalText: originalText,
      replacementText: replacementText,
      description: description,
      ruleId: ruleId,
      confidence: confidence,
    );
  }

  /// Stable UUID — used as the in-memory selection key in the
  /// `FixReviewDialog` and the apply-batch identifier the Pro service
  /// matches against on disk-write.
  final String id;

  /// Absolute path to the file the fix targets.
  final String filePath;

  /// 1-based inclusive begin line of the range to replace.
  final int lineRangeBegin;

  /// 1-based inclusive end line of the range to replace.
  final int lineRangeEnd;

  /// The exact text being replaced (line range from the source file).
  /// Used by the diff preview to render the "before" side.
  final String originalText;

  /// The replacement text Verible proposes. Used by the diff preview
  /// to render the "after" side and by the apply path to write to
  /// disk.
  final String replacementText;

  /// Human-readable explanation of the fix (Verible's own description).
  final String description;

  /// Engine-namespaced rule id (e.g. `verible/no-trailing-spaces`).
  /// Drives the per-rule filter chip and the "Suggest fix" row action.
  final String ruleId;

  /// Confidence band Verible assigned to this fix.
  final VeribleFixConfidence confidence;

  /// Round-trippable JSON view. Deterministic key order so committed
  /// fixtures diff cleanly.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'filePath': filePath,
    'lineRangeBegin': lineRangeBegin,
    'lineRangeEnd': lineRangeEnd,
    'originalText': originalText,
    'replacementText': replacementText,
    'description': description,
    'ruleId': ruleId,
    'confidence': confidence.name,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VeribleFixProposal &&
        other.id == id &&
        other.filePath == filePath &&
        other.lineRangeBegin == lineRangeBegin &&
        other.lineRangeEnd == lineRangeEnd &&
        other.originalText == originalText &&
        other.replacementText == replacementText &&
        other.description == description &&
        other.ruleId == ruleId &&
        other.confidence == confidence;
  }

  @override
  int get hashCode => Object.hash(
    id,
    filePath,
    lineRangeBegin,
    lineRangeEnd,
    originalText,
    replacementText,
    description,
    ruleId,
    confidence,
  );

  @override
  String toString() =>
      'VeribleFixProposal($id, $ruleId, '
      '$filePath:$lineRangeBegin-$lineRangeEnd, ${confidence.name})';
}

String _string(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! String || v.isEmpty) {
    throw FormatException("VeribleFixProposal missing string field '$key'");
  }
  return v;
}

int _int(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! int) {
    throw FormatException("VeribleFixProposal missing int field '$key'");
  }
  return v;
}
