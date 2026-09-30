// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// A provider the host app must keep alive for the lifetime of one
/// workspace tab — the per-tab sibling of `EagerStartupHook`.
///
/// As with the root seam, the host holds a real
/// `ProviderContainer.listen` subscription (against the TAB's container)
/// rather than issuing a one-shot `read`: a provider with no listener is
/// eligible for disposal, so a `read`-realized listener can be torn down
/// again and stop observing before the first run ever completes.
typedef PerTabStartupHook = ProviderListenable<Object?>;

/// Open-core extension point naming providers the host app realizes and
/// keeps alive once per workspace tab.
///
/// Each entry is subscribed from `ProjectTabContent`, against the tab's
/// own `ProviderContainer`. Riverpod is lazy, so an un-listened provider
/// never installs the side-effecting `ref.listen` in its constructor;
/// holding the subscription for the tab's lifetime is what keeps it
/// installed.
///
/// Use this (instead of `eagerStartupProvidersProvider`) for providers
/// that must observe PER-TAB state: realized at root, such a listener
/// resolves the empty root-scope instances of `selectedViolationProvider`,
/// `violationStoreProvider`, the per-project stores, … and its side
/// effect silently never fires for real tabs. The provider named here
/// must itself be re-bound per tab (listed in the Pro `proTabOverrides`
/// or `lintcruxTabOverridesFactory`) — otherwise the tab's subscription
/// parent-delegates to the one root instance and degenerates to root
/// scope again.
///
/// Open-core default is an empty list — nothing extra is realized per
/// tab. The Pro overlay overrides this with its per-tab
/// listener set (CXP selection emitter, bookmark stale-detection,
/// Verible auto-run).
///
/// Root-scoped by design: the LIST is app-wide configuration; only the
/// subscriptions live in tab scope.
final Provider<List<PerTabStartupHook>> perTabStartupProvidersProvider =
    Provider<List<PerTabStartupHook>>(
      (_) => const <PerTabStartupHook>[],
    );
