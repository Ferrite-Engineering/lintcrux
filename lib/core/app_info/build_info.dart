// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Compile-time build identifiers used by surfaces that need to
/// describe the running LintCrux build to other peers, ingestion
/// endpoints, or the user.
///
/// This is a single constant (rather than the more
/// elaborate `applicationBuildInfoProvider` WaveCrux uses) so the CXP
/// server's `PeerIdentity` can carry the product version on the wire
/// without a heavier `PackageInfo.fromPlatform()` round-trip at boot.
/// A follow-up phase wires this into a fuller About-box-style provider
/// once that surface lands; until then, the constants below are
/// updated alongside the `version:` field in `pubspec.yaml`.
abstract final class LintCruxBuildInfo {
  /// Product name component embedded in [PeerIdentity.productName] for
  /// the CXP handshake and discovery manifest.
  ///
  /// Stable identifier — matches the other Crux products' naming:
  /// `'wavecrux'`, `'netcrux'`, `'lintcrux'`, `'simcrux'`.
  static const String productName = 'lintcrux';

  /// Product version (semver, no build number) as it appears in `pubspec.yaml`.
  /// Surfaced via [PeerIdentity.productVersion] so peers can adapt to the
  /// running LintCrux version when negotiating capabilities, printed by
  /// `lintcrux --version`, and written by `package:crux_sqlite` into
  /// `schema_meta.app_version` and every `schema_migrations` row of every
  /// LintCrux database.
  ///
  /// Kept here (rather than read from `package_info_plus`) so it is available
  /// synchronously, without a platform-channel round-trip, and from pure Dart:
  /// the Pro CLI and `crux_sqlite` both need it and neither can call Flutter.
  ///
  /// **This constant said `0.1.0` for every 0.8.0 build**, for several
  /// releases, under a comment promising it was updated in lock-step. Nothing
  /// failed, so nobody looked. `test/static/build_info_matches_pubspec_test.dart`
  /// now checks it against `pubspec.yaml`, because the cost of it being wrong
  /// went up: a stale value no longer just misreports a version to a peer, it
  /// writes a false provenance record into a user's trend database on a row
  /// nothing will ever revisit.
  static const String productVersion = '1.0.1';

  /// The line `--version` prints, from the desktop app and from the
  /// headless binary alike.
  static const String versionLine = '$productName $productVersion';
}
