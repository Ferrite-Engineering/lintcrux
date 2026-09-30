// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lintcrux/core/platform/web_mode.dart';
import 'package:lintcrux/features/import_viewer/screens/imported_sarif_viewer_screen.dart';
import 'package:lintcrux/features/settings/screens/settings_screen.dart';
import 'package:lintcrux/features/web_viewer/screens/web_landing_screen.dart';
import 'package:lintcrux/features/web_viewer/screens/web_viewer_screen.dart';
import 'package:lintcrux/features/workspace/widgets/viewer_scaffold.dart';

/// Application route table.
///
/// Desktop layout (default, post-Phase-1.6):
/// - `/` → `ViewerScaffold`: hosts `crux.PaneHost`. Renders the
///   empty-canvas state when the workspace has no tabs and the
///   multi-tab project view when it does.
/// - `/settings` → [SettingsScreen]: the multi-section settings shell
///   (General / Appearance / Engines / Editors).
///
/// Web layout (when [isWebMode] is true):
/// - `/` → [WebLandingScreen]: SARIF file picker + URL field, plus
///   auto-fetch of the `?sarif=<url>` query parameter.
/// - `/web/viewer` → [WebViewerScreen]: the same `LintcruxIdeLayout`
///   shell as desktop, with the read-only chrome (no run controls,
///   no settings shortcut, no project file menu).
///
/// CLI initial-project handling moves from a router redirect to a
/// workspace `openTab` call in `LintcruxApp._maybeLoadCliProject`;
/// every `.lintcrux` path on the command line opens as its own tab in
/// the workspace.
///
/// Initial route selection (web): always the landing screen, because
/// the `?sarif=<url>` auto-fetch happens *after* the landing screen
/// renders so the user sees the loading indicator and any failure
/// message in context.
/// Root [ScaffoldMessengerState] key. Held outside the widget tree so
/// app-lifecycle callbacks (workspace hydration, missing-file recovery) can
/// surface snackbars without owning a [BuildContext]. Wired into
/// [MaterialApp.router]'s `scaffoldMessengerKey`.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'lintcrux_root_messenger');

/// Route name of the web viewer screen (`/web/viewer`). Actions that only
/// make sense with a report on screen — Find in Violations — check the
/// current route against it.
const String kWebViewerRouteName = 'web-viewer';

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>(
  (ref) {
    if (isWebMode) {
      return GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            name: 'web-landing',
            builder: (context, state) => const WebLandingScreen(),
          ),
          GoRoute(
            path: '/web/viewer',
            name: kWebViewerRouteName,
            builder: (context, state) => const WebViewerScreen(),
          ),
        ],
      );
    }

    // Post-Phase-1.6 the desktop route table collapses to a single
    // top-level `/` route hosting the `ViewerScaffold` which itself
    // shows either the empty-canvas state (when the workspace has no
    // tabs) or the multi-tab project view (when it does). The CLI-
    // driven project-load is now an "openTab in workspace" call from
    // `LintcruxApp._maybeLoadCliProject` rather than a router redirect.
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          name: 'viewer',
          builder: (context, state) => const ViewerScaffold(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        // Read-only viewer for a SARIF report imported via
        // `LintcruxAction.importSarif`. Renders the shared four-pane IDE
        // layout over an isolated imported-report violation store.
        GoRoute(
          path: '/import/viewer',
          name: 'imported-sarif-viewer',
          builder: (context, state) => const ImportedSarifViewerScreen(),
        ),
      ],
    );
  },
);
