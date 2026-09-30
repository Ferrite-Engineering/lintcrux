// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/verible_availability.dart';
import 'package:lintcrux/services/verible/verible_fix_service_provider.dart';

/// Async snapshot of the local Verible install. Reads from the
/// active [veribleFixServiceProvider] (which the Pro overlay
/// overrides with `ProVeribleFixService`).
///
/// Cached for the session by Riverpod's natural memoization;
/// callers that need to re-probe after a Settings change call
/// `ref.invalidate(veribleAvailabilityProvider)`.
final FutureProvider<VeribleAvailability> veribleAvailabilityProvider =
    FutureProvider<VeribleAvailability>(buildVeribleAvailability);

/// Build body of [veribleAvailabilityProvider]. Top-level so
/// `lintcruxTabOverridesFactory` can re-bind the provider per tab with the
/// identical body — the probe must consult the tab's own
/// `veribleFixServiceProvider` binding (the Pro overlay scopes the fix
/// service per tab, anchored at that tab's project root), not the
/// root-scope no-op service.
Future<VeribleAvailability> buildVeribleAvailability(Ref ref) async {
  final service = ref.watch(veribleFixServiceProvider);
  return await service.checkAvailability();
}
