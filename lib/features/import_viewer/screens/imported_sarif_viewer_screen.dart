// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lintcrux/features/import_viewer/providers/imported_sarif_providers.dart';
import 'package:lintcrux/features/import_viewer/services/sarif_import_flow.dart';
import 'package:lintcrux/features/inspector/widgets/inspector_pane.dart';
import 'package:lintcrux/features/rules/widgets/rules_panel.dart';
import 'package:lintcrux/features/source_preview/widgets/source_preview_pane.dart';
import 'package:lintcrux/features/viewer/widgets/lintcrux_ide_layout.dart';
import 'package:lintcrux/features/violations/widgets/violation_table.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_status_bar.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Desktop read-only viewer for an imported SARIF report.
///
/// Renders the same four-pane [LintcruxIdeLayout] as the desktop
/// `ProjectTabContent` and the web `WebViewerScreen` — the virtualized
/// [ViolationTable] in the center, the [InspectorPane] on the right, the
/// [SourcePreviewPane] on the bottom — but reads its violations from the
/// isolated imported-report store rather than any open project's store.
///
/// Isolation is achieved by [importedSarifViewerOverrides], which re-binds
/// `violationStoreProvider` (and the store-derived table / chip / selection
/// providers) to the imported-report slot for this subtree. A bare
/// `activeProjectIdProvider` override is NOT enough — those providers
/// declare no Riverpod `dependencies`, so they hoist to the root container
/// and ignore a descendant scope's active-id override; see
/// [importedSarifViewerOverrides] for the full rationale. The user's open
/// project (if any) keeps its own violations untouched — the import never
/// replaces the active project's store.
class ImportedSarifViewerScreen extends StatelessWidget {
  /// Creates an [ImportedSarifViewerScreen].
  const ImportedSarifViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: importedSarifViewerOverrides(),
      child: const _ImportedSarifViewerBody(),
    );
  }
}

class _ImportedSarifViewerBody extends ConsumerWidget {
  const _ImportedSarifViewerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final source = ref.watch(importedSarifSourceProvider);
    final appBar = AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.importSarifViewerTitle),
          Text(
            source ?? l10n.importSarifViewerNoSource,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => unawaited(runSarifImportFlow(context, ref)),
          icon: const Icon(Icons.file_download_outlined),
          label: Text(l10n.importSarifViewerImportAnotherButton),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => GoRouter.of(context).go('/'),
          icon: const Icon(Icons.arrow_back),
          label: Text(l10n.importSarifViewerBackButton),
        ),
        const SizedBox(width: 8),
      ],
    );
    // Keyboard regions (F6 / Shift+F6) and lost-focus recovery, as on the
    // workspace screen: the app bar and the status bar are regions here, and
    // the four `LintcruxIdeLayout` panes are regions of their own. Without
    // the scope a keyboard user had no way past the rule browser's list to
    // the violations but Tab.
    return CruxFocusRegionScope(
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: appBar.preferredSize,
          child: CruxFocusRegion(
            semanticLabel: l10n.accessibilityToolbarRegion,
            child: appBar,
          ),
        ),
        // This route is its own window: the workspace's LintcruxStatusBar is not
        // above it, and the violation table no longer carries a footer summary
        // of its own. It mounts the status-bar *body* directly — the same
        // segments the workspace bar renders for the active tab — so the
        // imported report gets the same tally, in the same chrome, at the same
        // place as every other product's window bottom. The screen's provider
        // overrides put the imported store in the ambient scope, which is
        // exactly what the body reads.
        body: Column(
          children: [
            Expanded(
              child: LintcruxIdeLayout(
                ruleBrowserBuilder: (context, _) => const RulesPanel(),
                violationsBuilder: (context, _) => const ViolationTable(),
                violationDetailsBuilder: (context, _) => const InspectorPane(),
                runLogBuilder: (context, _) => const SourcePreviewPane(),
              ),
            ),
            const CruxFocusRegion(child: LintcruxStatusBarBody()),
          ],
        ),
      ),
    );
  }
}
