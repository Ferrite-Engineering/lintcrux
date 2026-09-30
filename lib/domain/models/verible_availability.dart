// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/verible_availability_status.dart';
import 'package:meta/meta.dart';

/// Capability tags reported by [VeribleAvailability]. Each tag
/// corresponds to a capability LintCrux's `ProVeribleFixService`
/// invokes on the binary; absence of a tag marks the installed
/// Verible build as too old for the corresponding feature.
enum VeribleCapability {
  /// The binary supports the structured JSON output mode required by
  /// the dry-run path. Without this capability LintCrux cannot parse
  /// the fix-proposal stream and degrades to "old version" status.
  structuredJsonOutput,

  /// The binary supports the `--dry-run` (or equivalent) flag the
  /// dry-run path invokes.
  dryRunMode,

  /// The binary supports the explicit-rule selection flag the
  /// per-violation "Suggest fix" surface invokes (so we can scope
  /// the dry-run to just the offending rule rather than scanning the
  /// whole project).
  perRuleScoping,
}

/// Snapshot of the local Verible install. Returned by
/// [VeribleFixService.checkAvailability]; cached by the
/// `veribleAvailabilityProvider` for the session.
@immutable
class VeribleAvailability {
  /// Creates a [VeribleAvailability].
  const VeribleAvailability({
    required this.status,
    this.binaryPath,
    this.version,
    this.capabilities = const <VeribleCapability>{},
    this.missingHint,
  });

  /// Convenience constructor for the "not installed" case.
  const VeribleAvailability.notInstalled({this.missingHint})
    : status = VeribleAvailabilityStatus.notInstalled,
      binaryPath = null,
      version = null,
      capabilities = const <VeribleCapability>{};

  /// Status bucket.
  final VeribleAvailabilityStatus status;

  /// Absolute path to the resolved Verible binary. `null` when
  /// [status] is `notInstalled`.
  final String? binaryPath;

  /// Parsed version string (e.g. `v0.0-3608-g4ca4e1c4`). `null` when
  /// [status] is `notInstalled` or when version parsing failed (the
  /// install is still treated as `installedButOldVersion` in that
  /// case — opaque versions can't satisfy the capability check).
  final String? version;

  /// Capabilities the installed build declares. Empty when
  /// [status] is `notInstalled`.
  final Set<VeribleCapability> capabilities;

  /// Human-readable hint for the "not installed" / "old version"
  /// cases. Typically reads "Install Verible from
  /// https://github.com/chipsalliance/verible" or "Upgrade Verible
  /// to version 0.0-3500 or newer to use this feature." Surfaced by
  /// the Settings entry tooltip and the toolbar action's disabled
  /// tooltip.
  final String? missingHint;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VeribleAvailability) return false;
    if (other.status != status) return false;
    if (other.binaryPath != binaryPath) return false;
    if (other.version != version) return false;
    if (other.missingHint != missingHint) return false;
    if (other.capabilities.length != capabilities.length) return false;
    for (final cap in capabilities) {
      if (!other.capabilities.contains(cap)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    status,
    binaryPath,
    version,
    missingHint,
    Object.hashAllUnordered(capabilities),
  );

  @override
  String toString() =>
      'VeribleAvailability(${status.name}'
      '${binaryPath != null ? ', $binaryPath' : ''}'
      '${version != null ? ', $version' : ''}'
      ')';
}
