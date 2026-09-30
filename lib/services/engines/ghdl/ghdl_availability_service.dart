// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';

/// Binary availability probe for GHDL.
///
/// Reports whether a `ghdl` executable is reachable at runtime via
/// either the bundled-binary cache or the system `PATH`. The
/// `GhdlEngine` (the actual lint adapter) constructor takes this
/// service as a dependency so the engine can short-circuit to
/// `EngineNotAvailableException` without spawning a subprocess.
///
/// It pairs with the GHDL bundled-binary manifest entry
/// (`tool/bundled_engines.yaml`), which the CI workflow uses to fetch
/// the binary.
class GhdlAvailabilityService {
  /// Creates a [GhdlAvailabilityService].
  const GhdlAvailabilityService({
    this.bundledBinaryResolver = const BundledBinaryResolver(),
  });

  /// Bundled-binary resolver. Tests inject one with `overrideRoot`
  /// pointing at a temp directory.
  final BundledBinaryResolver bundledBinaryResolver;

  /// Returns the absolute path of the resolved `ghdl` binary, or
  /// `null` if the binary cannot be located via either source.
  ///
  /// The lookup order matches the rest of LintCrux:
  /// 1. Bundled binary at `<LINTCRUX_BUNDLED_BIN_DIR>/<platform>/ghdl`.
  /// 2. `ghdl` on PATH.
  /// 3. Returns `null`.
  String? resolveBinaryPath() {
    final bundled = bundledBinaryResolver.resolve('ghdl');
    if (bundled != null) return bundled;
    if (_onPath('ghdl')) return 'ghdl';
    return null;
  }

  /// Convenience boolean — `true` if [resolveBinaryPath] returns a
  /// non-null value.
  bool get isAvailable => resolveBinaryPath() != null;

  /// Cheap PATH probe — walks PATH segments and stats each candidate.
  /// Mirrors the `_onPath` helper used by the integration tests.
  static bool _onPath(String binary) {
    final pathVar = Platform.environment['PATH'] ?? '';
    final exeName = Platform.isWindows ? '$binary.exe' : binary;
    for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final candidate = File('$dir${Platform.pathSeparator}$exeName');
      if (candidate.existsSync()) return true;
    }
    return false;
  }
}
