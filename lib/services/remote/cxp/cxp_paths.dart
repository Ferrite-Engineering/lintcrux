// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';

/// Resolves the cross-suite CXP manifest directory.
///
/// Every Crux product writes its discovery manifest into (and scans) the
/// SAME suite-shared directory so peers see each other without any
/// per-product configuration. Resolved by `sharedCxpManifestDirectory()`
/// (crux_cxp):
///   * macOS: `~/Library/Application Support/crux/cxp/peers/`
///   * Windows: `%APPDATA%\crux\cxp\peers\`
///   * Linux: `${XDG_DATA_HOME:-~/.local/share}/crux/cxp/peers/`
///
/// Resolution deliberately avoids `getApplicationSupportDirectory()`: that
/// API is bundle-/app-id-scoped on every desktop platform, so using it here
/// would publish into LintCrux's own private container instead of the
/// shared location above — no peer would ever scan it, making cross-product
/// discovery structurally impossible.
///
/// The layout is shared by every suite product; peer discovery is
/// described at https://edacrux.app/cxp.
class CxpPaths {
  /// Const constructor — there is no state.
  const CxpPaths();

  /// Returns the absolute path of the suite-shared manifest directory and
  /// ensures it exists. Created recursively if missing. Kept async for
  /// call-site compatibility even though resolution is now synchronous.
  Future<String> manifestDirectory() async {
    final dir = Directory(sharedCxpManifestDirectory());
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }
}
