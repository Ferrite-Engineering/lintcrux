// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/engine_watchdog.dart';
import 'package:lintcrux/services/engines/timeout_engine_watchdog.dart';

/// Default per-engine wall-clock budget for a single lint run.
/// A hung engine is killed once this elapses with no
/// output; a progressing engine resets the budget on every violation it
/// streams (the watchdog uses an inactivity timer — see
/// [TimeoutEngineWatchdog]).
///
/// 120 s is generous: Verilator on a large SoC can take 30+ s, so the
/// default never fires for a healthy run. The value is exposed as a
/// provider so Settings → Engines can make it user-configurable and tests
/// can shorten it.
const Duration kDefaultEngineTimeout = Duration(seconds: 120);

/// The wall-clock budget the [engineWatchdogProvider] enforces per engine.
///
/// Override this provider (in Settings or in tests) to change the timeout
/// without swapping the watchdog implementation.
final Provider<Duration> engineTimeoutProvider = Provider<Duration>(
  (ref) => kDefaultEngineTimeout,
);

/// The app-wide [EngineWatchdog] consumed by [ParallelEngineRunner].
///
/// Defaults to the active [TimeoutEngineWatchdog]; the open-core build
/// already bounds engine wall-clock time without any Pro override.
final Provider<EngineWatchdog> engineWatchdogProvider =
    Provider<EngineWatchdog>((ref) => const TimeoutEngineWatchdog());
