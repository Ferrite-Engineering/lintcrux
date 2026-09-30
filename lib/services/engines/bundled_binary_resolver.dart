// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// Locates engine binaries that LintCrux ships inside its distribution
/// at runtime.
///
/// Resolution order, in priority:
///
/// 1. `LINTCRUX_BUNDLED_BIN_DIR` env var — points at a directory
///    containing every engine binary by canonical name. The CI helper
///    (`.github/workflows/`) uses this to point the integration suite
///    at the downloaded artifact cache without bundling them into the
///    Flutter binary.
/// 2. The asset path relative to the Flutter app bundle:
///    `<assetsRoot>/bin/<platform>/<engineId>`. The platform string
///    is one of `linux-x86_64`, `macos-universal`,
///    `windows-x86_64` and matches the directory layout produced by
///    `tool/bundled_engines.yaml`.
/// 3. Returns `null` — the caller falls back to PATH discovery
///    (the historical behavior).
///
/// Bundled binaries are gated to release builds at the per-engine
/// resolver layer (the resolver is asked, but the engine plugin
/// suppresses the lookup when `kDebugMode` is `true`). Debug builds
/// always shell out to `PATH` so contributors using locally-built
/// engines (with logging or experimental flags) get them automatically.
class BundledBinaryResolver {
  /// Creates a resolver. [overrideRoot] is provided in tests so the
  /// resolver can be pointed at a temp directory.
  const BundledBinaryResolver({this.overrideRoot});

  /// Test-only root directory containing per-platform binaries. When
  /// non-null, the resolver consults this directory first instead of
  /// the env var or the Flutter assets root.
  final String? overrideRoot;

  /// Resolves [engineId] (`'verilator'`, `'verible'`, `'slang'`,
  /// `'yosys'`, `'ghdl'`) to an absolute executable path, or `null`
  /// if no bundled binary is available for the current platform.
  String? resolve(String engineId) {
    final root = _bundledRoot();
    if (root == null) return null;
    final platformDir = _platformDir();
    if (platformDir == null) return null;
    final exeName = _exeName(engineId);
    final candidate =
        '$root${Platform.pathSeparator}'
        '$platformDir${Platform.pathSeparator}$exeName';
    if (File(candidate).existsSync()) return candidate;
    return null;
  }

  /// Returns the active bundled-binary root directory.
  String? _bundledRoot() {
    if (overrideRoot != null) return overrideRoot;
    final env = Platform.environment['LINTCRUX_BUNDLED_BIN_DIR'];
    if (env != null && env.isNotEmpty) return env;
    // The Flutter app's bundled-asset path is not yet
    // resolvable at compile time without a runtime probe. We keep the
    // env-var path as the primary mechanism and return null so the
    // engine falls back to PATH discovery. The asset-based path lands
    // when the per-platform bundled binaries actually ship.
    return null;
  }

  /// Returns the per-platform directory name (`linux-x86_64`, …) or
  /// `null` if the current host is unsupported.
  static String? _platformDir() {
    if (Platform.isLinux) {
      // We do not currently distinguish ARM64 vs x86_64 at the Dart
      // layer; the CI manifest will write platform-specific subdirs
      // when downloading.
      return 'linux-${_archHint()}';
    }
    if (Platform.isMacOS) return 'macos-universal';
    if (Platform.isWindows) return 'windows-${_archHint()}';
    return null;
  }

  static String _archHint() {
    // `Platform.version` does not reliably expose arch on every host.
    // The bundled-engines manifest commits one entry per platform-arch
    // pair; if the runtime arch doesn't match the bundled set, the
    // resolver returns null and the engine falls back to PATH.
    // The manifest covers x86_64 only on linux/windows.
    return 'x86_64';
  }

  /// Returns the platform-specific executable filename.
  static String _exeName(String engineId) {
    if (Platform.isWindows) return '$engineId.exe';
    return engineId;
  }
}
