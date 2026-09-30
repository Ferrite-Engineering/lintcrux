// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Process-wide diagnostics dialog: the app report followed by the active
/// tab's report, plus the "Copy Full Diagnostics Report" action.
///
/// Every line is measured or absent (see `buildAppDiagnosticsReport` and
/// `buildTabDiagnosticsReport`): the text is what a user pastes into a bug
/// report.
class AppDiagnosticsDialog extends ConsumerStatefulWidget {
  /// Creates an [AppDiagnosticsDialog].
  const AppDiagnosticsDialog({super.key});

  /// Mounts the dialog as a modal rooted at [context]. Returns when
  /// dismissed.
  ///
  /// Wrapped in [wrapInActiveTabScope]: the report's violation count
  /// derives from the per-tab violation store, so a bare `showDialog`
  /// would read the empty root-scope store and always report zero.
  static Future<void> show(BuildContext context) {
    // Re-entrancy guard: shortcut auto-repeat, a double-tap on the menu
    // item, or the palette entry must not stack a second dialog. Guarded
    // inside the opener so every caller is covered.
    return ModalGuard.run(
      'appDiagnostics',
      () => showDialog<void>(
        context: context,
        builder: (_) => wrapInActiveTabScope(
          context,
          const AppDiagnosticsDialog(),
        ),
      ),
    );
  }

  @override
  ConsumerState<AppDiagnosticsDialog> createState() =>
      _AppDiagnosticsDialogState();
}

class _AppDiagnosticsDialogState extends ConsumerState<AppDiagnosticsDialog> {
  @override
  void initState() {
    super.initState();
    // The report provider is cached per tab, and its memory figure is read
    // when it builds. Rebuilding it here makes each opening a fresh reading
    // instead of the one from the first time the dialog was opened.
    ref.invalidate(appDiagnosticsReportProvider);
  }

  @override
  Widget build(BuildContext context) {
    // The gate can flip while the dialog is open (the user turns
    // diagnostics off in Settings). Closing post-frame rather than showing
    // an empty modal.
    if (!ref.watch(diagnosticsEnabledProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final l10n = L10N.of(context);
    final appReport = ref.watch(appDiagnosticsReportProvider);
    final tabReport = ref.watch(tabDiagnosticsReportProvider);
    final fullReport = StringBuffer()..writeln(appReport.toPlainText());
    if (tabReport != null) {
      fullReport.writeln(tabReport.toPlainText());
    }
    return Dialog(
      child: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.diagnosticsAppDialogTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: l10n.diagnosticsCopyFullReport,
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: fullReport.toString()),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.diagnosticsCloseTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  fullReport.toString(),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
