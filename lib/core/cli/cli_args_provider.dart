// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/cli/cli_args.dart';

/// Exposes the parsed CLI arguments to the running app.
///
/// `bootstrap()` parses the process's command-line args once on startup
/// and overrides this provider in the root `ProviderScope` with the
/// resulting [CliArgs] snapshot. Screens, services, and the workspace
/// restoration pipeline `ref.watch` it to decide their startup state —
/// for example, whether to open a specific project, whether to write a
/// SARIF report on first run, and whether the process should exit
/// non-zero after run completion.
///
/// The default value is [CliArgs.empty] so widget tests that construct
/// their own `ProviderScope` don't need to override the provider
/// explicitly.
final Provider<CliArgs> cliArgsProvider = Provider<CliArgs>(
  (ref) => CliArgs.empty,
);
