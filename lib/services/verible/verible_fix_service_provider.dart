// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/verible_fix_service.dart';

/// Open-core extension point through which the Pro
/// overlay contributes a Pro-grade [VeribleFixService] implementation.
///
/// Open Core ships [NoopVeribleFixService] — `checkAvailability`
/// reports `notInstalled`; `dryRun` returns an empty batch; `apply`
/// returns an empty result list. The Pro overlay's `proOverrides`
/// replaces this provider with `ProVeribleFixService` which shells
/// out to the installed `verible-verilog-lint` / `verible-verilog-format`
/// binaries.
final Provider<VeribleFixService> veribleFixServiceProvider =
    Provider<VeribleFixService>(
      (_) => const NoopVeribleFixService(),
    );
