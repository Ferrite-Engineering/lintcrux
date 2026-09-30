// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/dashboard_banners_provider.dart';

void main() {
  group('dashboardBannersProvider', () {
    test('default open-core list is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(dashboardBannersProvider), isEmpty);
    });

    test('overrideWithValue supplies banners to consumers', () {
      Widget banner(BuildContext context, WidgetRef ref) =>
          const SizedBox(key: ValueKey('test-banner'));
      final container = ProviderContainer(
        overrides: [
          dashboardBannersProvider.overrideWithValue(
            <DashboardBannerBuilder>[banner],
          ),
        ],
      );
      addTearDown(container.dispose);
      final banners = container.read(dashboardBannersProvider);
      expect(banners, hasLength(1));
      expect(banners.first, banner);
    });
  });
}
