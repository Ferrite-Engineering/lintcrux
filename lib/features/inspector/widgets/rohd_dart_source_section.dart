// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/rohd_dart_source.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_row.dart'
    show displayPath;
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// The Dart source of a finding on ROHD-generated SystemVerilog (ROHD 0.7 or
/// later, source tracing), shown beside the SystemVerilog location.
///
/// Renders nothing for a finding with no Dart source. The button is the Go to
/// Source for the Dart side; the location section above it keeps the
/// SystemVerilog one.
class RohdDartSourceSection extends ConsumerWidget {
  /// Creates the section for [violation].
  const RohdDartSourceSection({required this.violation, super.key});

  /// The selected finding.
  final Violation violation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = RohdDartSource.fromRaw(violation.raw);
    if (source == null) return const SizedBox.shrink();
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final projectRoot = ref.watch(
      currentProjectProvider.select((p) => p?.rootPath),
    );
    String shown(RohdDartLocation l) =>
        '${displayPath(l.file, projectRoot)}:${l.line}:${l.column}';
    final note = source.fromInlineComment
        ? l10n.inspectorDartSourceInline
        : switch (source.kind) {
            RohdDartSourceKind.exact => l10n.inspectorDartSourceExact,
            RohdDartSourceKind.enclosing => l10n.inspectorDartSourceEnclosing,
          };
    return Padding(
      key: const ValueKey('rohdDartSource'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.inspectorDartSourceHeader,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelectableText(
                shown(source.primary),
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
              ),
              OutlinedButton.icon(
                key: const ValueKey('rohdOpenDartSource'),
                onPressed: () => _open(context, ref, source.primary),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(
                  l10n.inspectorDartSourceOpen,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(note, style: theme.textTheme.bodySmall),
          if (source.calledFrom.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.inspectorDartSourceCalledFrom,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            for (final caller in source.calledFrom)
              Semantics(
                button: true,
                label: l10n.inspectorDartSourceOpenCaller(shown(caller)),
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => _open(context, ref, caller),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      shown(caller),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    RohdDartLocation at,
  ) async {
    final result = await ref
        .read(clickToSourceServiceProvider)
        .openInEditor(
          SourceLocation(file: at.file, line: at.line, column: at.column),
        );
    if (!context.mounted || result.success) return;
    showCruxErrorSnack(
      context,
      L10N.of(context).editorLaunchFailed(result.command.toString()),
    );
  }
}
