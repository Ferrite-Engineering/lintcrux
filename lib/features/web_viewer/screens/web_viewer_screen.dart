// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lintcrux/features/inspector/widgets/inspector_pane.dart';
import 'package:lintcrux/features/rules/widgets/rules_panel.dart';
import 'package:lintcrux/features/source_preview/widgets/source_preview_pane.dart';
import 'package:lintcrux/features/viewer/widgets/lintcrux_ide_layout.dart';
import 'package:lintcrux/features/violations/widgets/violation_table.dart';
import 'package:lintcrux/features/web_viewer/providers/web_sarif_source_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Web-mode read-only viewer screen.
///
/// Renders the same four-pane [LintcruxIdeLayout] as the desktop
/// `ProjectTabContent` — virtualized [ViolationTable] in the center, the
/// [InspectorPane] on the right, the [SourcePreviewPane] in the bottom
/// — but skips desktop-only chrome (run controls, project status,
/// settings shortcut). The app bar gains an "Open another" action that
/// returns the user to the landing screen.
///
/// The screen makes no assumptions about how the violations got there.
/// Whatever was injected into `violationStoreProvider` by the SARIF
/// file loader is what renders; if the store is empty the viewer
/// renders the standard table empty state. The reactive store →
/// violation table pipeline is shared with the desktop dashboard.
class WebViewerScreen extends ConsumerWidget {
  /// Creates a [WebViewerScreen].
  const WebViewerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(webSarifSourceProvider);
    final subtitle = _subtitleFor(state.source, l10n);
    final appBar = AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.webViewerAppBarTitle),
          if (subtitle != null)
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => GoRouter.of(context).go('/'),
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(l10n.webViewerOpenAnotherButton),
        ),
        const SizedBox(width: 8),
      ],
    );
    // Keyboard regions (F6 / Shift+F6), as on the desktop screens: the app
    // bar is a region, and the four `LintcruxIdeLayout` panes are regions of
    // their own. The scope does not restore lost focus on the web, where the
    // browser owns focus outside the page.
    return CruxFocusRegionScope(
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: appBar.preferredSize,
          child: CruxFocusRegion(
            semanticLabel: l10n.accessibilityToolbarRegion,
            child: appBar,
          ),
        ),
        body: LintcruxIdeLayout(
          ruleBrowserBuilder: (context, _) => const RulesPanel(),
          violationsBuilder: (context, _) => const ViolationTable(),
          violationDetailsBuilder: (context, _) => const InspectorPane(),
          runLogBuilder: (context, _) => const SourcePreviewPane(),
        ),
      ),
    );
  }

  String? _subtitleFor(WebSarifSource source, L10N l10n) {
    return switch (source) {
      WebSarifSourceEmpty() => l10n.webViewerNoSource,
      WebSarifSourceFile(:final name) => name,
      WebSarifSourceUrl(:final url) => url.toString(),
    };
  }
}
