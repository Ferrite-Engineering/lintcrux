// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/app.dart';

/// Open-core `lintcrux` entry point. A Pro/Enterprise overlay re-enters via
/// the same `runLintcrux` function exported from `package:lintcrux/app.dart`,
/// layering its overrides on top of the open-core `ProviderScope`. See
/// `docs/ARCHITECTURE.md` (Extension Points) and the WaveCrux reference
/// implementation in `wavecrux/lib/app.dart` for the canonical pattern.
///
/// `runLintcrux`, not `bootstrap`: it exits after `--help`, `--version` or an
/// argument error, which a desktop runner otherwise never does.
Future<void> main(List<String> args) => runLintcrux(args: args);
