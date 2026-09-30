// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The subset of `crux_telemetry` a **Flutter-free** entry point can link.
///
/// LintCrux is the first product in the suite with two surfaces: the desktop
/// app, and the headless `lintcrux` binary that `dart build cli` compiles from
/// `bin/lintcrux.dart`. That binary has no `dart:ui`, so it can import neither
/// `package:flutter/...` nor any Flutter plugin — and `crux_telemetry`'s barrel
/// pulls in both (`flutter_riverpod` for the providers and the consent widgets,
/// `path_provider` for the on-disk queue, `flutter/foundation` for the `os`
/// derivation). Importing the barrel from anything the CLI reaches would fail
/// the CLI build outright.
///
/// So the CLI-reachable half of LintCrux imports **this** file instead. It
/// re-exports only the libraries inside `crux_telemetry` that are pure Dart:
/// the event and envelope models, the consent state, the coalescing batcher,
/// the persistence seam, and the endpoint constants. Every one of them is
/// checked by `test/services/telemetry/headless_telemetry_test.dart`, which is
/// itself a `flutter test` and so cannot prove the Flutter-freeness on its own —
/// `tool/build_cli.sh` is what actually proves it, and `verification/` runs it.
///
/// The `src/` imports are deliberate and are the reason this file exists rather
/// than the imports being spread across the CLI tree: `crux_telemetry` has one
/// entry point, that entry point is Flutter-bound, and reaching past it is a
/// thing that should happen in exactly one place, with this comment on it. If
/// the package ever grows a `crux_telemetry_core.dart` barrel of its own, this
/// file collapses into a single re-export of it and nothing else changes.
library;

export 'package:crux_telemetry/src/models/telemetry_consent_state.dart';
export 'package:crux_telemetry/src/models/telemetry_envelope.dart';
export 'package:crux_telemetry/src/models/telemetry_event.dart';
export 'package:crux_telemetry/src/services/telemetry_batch.dart';
export 'package:crux_telemetry/src/storage/telemetry_storage.dart';
export 'package:crux_telemetry/src/telemetry_endpoint.dart';
export 'package:crux_telemetry/src/telemetry_enum_token.dart';
