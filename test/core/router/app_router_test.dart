// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lintcrux/core/router/app_router.dart';

void main() {
  group('appRouterProvider (workspace-aware)', () {
    test('returns a non-empty GoRouter configuration', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      expect(router.configuration.routes, isNotEmpty);
    });

    test('registers the viewer, settings, and imported-SARIF desktop '
        'routes', () {
      // The desktop route table has no welcome-screen route: "/" hosts
      // `ViewerScaffold`, which shows the empty-canvas state when the
      // workspace has no tabs, and the read-only imported-SARIF viewer is at
      // `/import/viewer` (navigated to by `runSarifImportFlow` via
      // `router.go(importedSarifViewerRoute)`), so the desktop table is
      // three top-level routes.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      final routes = router.configuration.routes.whereType<GoRoute>().toList();
      expect(routes, hasLength(3));
      expect(
        routes.map((r) => r.path).toSet(),
        {'/', '/settings', '/import/viewer'},
      );
      expect(
        routes.map((r) => r.name).toSet(),
        {'viewer', 'settings', 'imported-sarif-viewer'},
      );
    });

    test('initialLocation is always "/" — CLI project paths now open as '
        'tabs in the workspace rather than driving the initial route', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      expect(router.routeInformationProvider.value.uri.path, '/');
    });
  });
}
