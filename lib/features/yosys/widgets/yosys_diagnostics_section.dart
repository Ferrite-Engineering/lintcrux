// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/yosys/yosys_diagnostics_provider.dart';

/// "Yosys Diagnostics" section for the Tab Diagnostics
/// drawer.
///
/// Renders the raw `YosysDiagnostic` list captured during the most
/// recent run. Each entry shows a severity icon, the
/// module/file:line citation, and the verbatim Yosys message. The
/// caller passes `onJump` so the row can wire its tap handler to the
/// click-to-source path that the drawer already uses for the
/// violation rows.
///
/// Severity filter chips (Errors / Warnings / Info) narrow the
/// rendered subset. "Show all" is implicit when every chip is
/// deselected, matching the violation-table filter convention.
class YosysDiagnosticsSection extends ConsumerStatefulWidget {
  /// Creates a [YosysDiagnosticsSection].
  const YosysDiagnosticsSection({
    super.key,
    this.onJump,
  });

  /// Called when the user taps a diagnostic row. Receives the file
  /// path and 1-indexed line; widgets that don't wire click-to-source
  /// can omit this and the rows render as static text.
  final void Function(String filePath, int line)? onJump;

  @override
  ConsumerState<YosysDiagnosticsSection> createState() =>
      _YosysDiagnosticsSectionState();
}

class _YosysDiagnosticsSectionState
    extends ConsumerState<YosysDiagnosticsSection> {
  Set<YosysDiagnosticSeverity> _selected = const {};

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final state = ref.watch(yosysDiagnosticsProvider);
    final filtered = state.filtered(_selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.yosysDiagnosticsSectionTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        if (state.diagnostics.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l10n.yosysDiagnosticsEmpty,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else ...[
          Wrap(
            spacing: 6,
            children: [
              for (final severity in YosysDiagnosticSeverity.values)
                FilterChip(
                  selected: _selected.contains(severity),
                  label: Text(_severityLabel(severity, l10n)),
                  onSelected: (on) {
                    setState(() {
                      _selected = {
                        ..._selected,
                        if (on) severity,
                      }..removeWhere((s) => !on && s == severity);
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final d in filtered)
            _DiagnosticRow(diagnostic: d, onJump: widget.onJump),
        ],
      ],
    );
  }

  String _severityLabel(YosysDiagnosticSeverity s, L10N l10n) {
    switch (s) {
      case YosysDiagnosticSeverity.error:
        return l10n.yosysDiagnosticsSeverityError;
      case YosysDiagnosticSeverity.warning:
        return l10n.yosysDiagnosticsSeverityWarning;
      case YosysDiagnosticSeverity.info:
        return l10n.yosysDiagnosticsSeverityInfo;
    }
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.diagnostic, this.onJump});

  final YosysDiagnostic diagnostic;
  final void Function(String filePath, int line)? onJump;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canJump = onJump != null && diagnostic.filePath != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: canJump
            ? () => onJump!(diagnostic.filePath!, diagnostic.line ?? 1)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _iconFor(diagnostic.severity),
                size: 14,
                color: _colorFor(diagnostic.severity, scheme),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _citation(diagnostic),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [],
                      ),
                    ),
                    Text(
                      diagnostic.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(YosysDiagnosticSeverity s) {
    switch (s) {
      case YosysDiagnosticSeverity.error:
        return Icons.error_outline;
      case YosysDiagnosticSeverity.warning:
        return Icons.warning_amber_outlined;
      case YosysDiagnosticSeverity.info:
        return Icons.info_outline;
    }
  }

  static Color _colorFor(YosysDiagnosticSeverity s, ColorScheme scheme) {
    switch (s) {
      case YosysDiagnosticSeverity.error:
        return scheme.error;
      case YosysDiagnosticSeverity.warning:
        return scheme.tertiary;
      case YosysDiagnosticSeverity.info:
        return scheme.onSurfaceVariant;
    }
  }

  static String _citation(YosysDiagnostic d) {
    final file = d.filePath;
    if (file == null || file.isEmpty) {
      return '<yosys>';
    }
    final line = d.line;
    final col = d.column;
    if (line == null) return file;
    if (col == null) return '$file:$line';
    return '$file:$line:$col';
  }
}
