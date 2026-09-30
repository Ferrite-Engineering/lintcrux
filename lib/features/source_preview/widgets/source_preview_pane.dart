// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/source_preview/source_preview_provider.dart';
import 'package:lintcrux/services/source_preview/source_preview_service.dart';

/// Read-only source preview that shows the lines surrounding the
/// currently inspected violation.
///
/// Highlights the violation's primary line with the surface's
/// primary-container color and any related-location lines that share
/// the file with a secondary highlight. Renders in a monospace font
/// with 1-indexed gutter line numbers.
///
/// Updates live as the user changes the selection in the table — this
/// feature widget watches [selectedViolationProvider] (feature-layer
/// selection state) and passes the violation into the services-layer
/// [sourcePreviewWindowProvider] family, so the rebuild is automatic.
class SourcePreviewPane extends ConsumerWidget {
  /// Creates a [SourcePreviewPane].
  const SourcePreviewPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final selected = ref.watch(selectedViolationProvider);
    final asyncWindow = ref.watch(sourcePreviewWindowProvider(selected));
    return asyncWindow.when(
      loading: () => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.sourcePreviewFileMissing('$e'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
      data: (window) {
        if (window == null) {
          return CruxPanelEmptyState(message: l10n.sourcePreviewEmpty);
        }
        if (window.isEmpty) {
          return CruxPanelEmptyState(
            message: l10n.sourcePreviewFileMissing(window.file),
          );
        }
        return _SourceListing(window: window);
      },
    );
  }
}

class _SourceListing extends StatelessWidget {
  const _SourceListing({required this.window});
  final SourceWindow window;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
      fontSize: 12,
      color: scheme.onSurface,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: scheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            window.file,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: ListView.builder(
              itemCount: window.lines.length,
              itemBuilder: (context, i) {
                final lineNumber = window.startLine + i;
                final isPrimary = lineNumber == window.highlightLine;
                final isRelated = window.highlightedRelated.contains(
                  lineNumber,
                );
                final bg = isPrimary
                    ? scheme.primaryContainer
                    : (isRelated ? scheme.secondaryContainer : null);
                return Container(
                  color: bg,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        color: scheme.surfaceContainerHighest.withAlpha(96),
                        child: Text(
                          '$lineNumber',
                          textAlign: TextAlign.right,
                          style: textStyle.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          window.lines[i],
                          style: textStyle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
