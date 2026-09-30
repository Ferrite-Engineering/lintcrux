// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/yosys/yosys_diagnostics_provider.dart';

/// Riverpod provider exposing the app-wide [EngineRegistry].
///
/// Default binding registers the seven open-core engines of
/// [defaultEngineRegistry]: Verilator, Verible, Slang, Yosys check, GHDL,
/// Svlint and CDC. The Pro overlay rebuilds the registry with its own CDC
/// engine.
///
/// Every registered engine runs for a project whose `enabledEngineIds` is
/// empty (the default for a new or imported project); a project lists the
/// engines it wants to narrow that set.
///
/// Tests override this provider to inject a registry of fake engines.
/// The engine list itself lives in the Flutter-free
/// [defaultEngineRegistry] so the headless CI binary
/// (`bin/lintcrux.dart`) ships exactly the same set. What stays here is
/// the one GUI-only wire: forwarding every parsed `YosysDiagnostic` to
/// the sidecar `yosysDiagnosticsProvider` so the Tab Diagnostics drawer
/// can render them alongside the unified violations.
final Provider<EngineRegistry> engineRegistryProvider =
    Provider<EngineRegistry>(
      (ref) => defaultEngineRegistry(
        onYosysDiagnostics: (diagnostics) {
          ref.read(yosysDiagnosticsProvider.notifier).replace(diagnostics);
        },
      ),
    );
