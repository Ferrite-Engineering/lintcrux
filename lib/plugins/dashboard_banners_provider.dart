// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builder signature for a dashboard banner contributed via the
/// [dashboardBannersProvider] open-core seam.
///
/// `ViolationTable` stacks each returned widget, full width, between the
/// top-action row and the filter chips, in list order. Each builder is
/// responsible for its own dismissal logic and tier badging.
typedef DashboardBannerBuilder =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Open-core extension point through which the Pro
/// overlay contributes additional non-blocking banners atop the
/// dashboard / violations panel.
///
/// Distinct from [violationTableTopActionsProvider]
/// (`lib/plugins/violation_table_top_actions_provider.dart`):
///   - **Top actions** are inline `Row` widgets (baseline toolbar,
///     view-mode toggle, status chip) rendered above the filter
///     chip row.
///   - **Banners** are full-width `MaterialBanner`-style notices
///     rendered between the toolbar and the table (waiver
///     expiration warnings, trend alert dashboard, future
///     license-expiration messages).
///
/// Default returns an empty list so the open-core build renders no banners. The
/// Pro overlay overrides this provider with its contributions (the trend
/// alerts, Verible auto-run and waiver expiration banners), which stack
/// vertically in list order.
///
/// Each contribution should be a thin `ConsumerWidget` that reads
/// its own providers (the alerts provider, the acknowledgment
/// repository, the license tier provider, …) and renders nothing
/// when there's nothing to show — banners that are "always
/// visible" defeat the purpose.
final Provider<List<DashboardBannerBuilder>> dashboardBannersProvider =
    Provider<List<DashboardBannerBuilder>>(
      (_) => const <DashboardBannerBuilder>[],
    );
