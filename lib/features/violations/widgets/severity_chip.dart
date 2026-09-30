// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:lintcrux/core/theme/lintcrux_colors.dart';
import 'package:lintcrux/core/theme/lintcrux_theme_tokens.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Localized display label for a [Severity], driven by ARB strings.
String severityLabel(L10N l10n, Severity s) {
  switch (s) {
    case Severity.fatal:
      return l10n.severityFatal;
    case Severity.error:
      return l10n.severityError;
    case Severity.warning:
      return l10n.severityWarning;
    case Severity.note:
      return l10n.severityNote;
    case Severity.none:
      return l10n.severityNone;
  }
}

/// Icon that visualizes a [Severity] in the violation table.
class SeverityIcon extends StatelessWidget {
  /// Creates a [SeverityIcon].
  const SeverityIcon({required this.severity, super.key});

  /// The severity to render.
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(context, severity);
    return Icon(
      _icon(severity),
      color: color,
      size: 16,
      semanticLabel: severityLabel(L10N.of(context), severity),
    );
  }

  static IconData _icon(Severity s) {
    switch (s) {
      case Severity.fatal:
        return Icons.dangerous;
      case Severity.error:
        return Icons.error;
      case Severity.warning:
        return Icons.warning_amber;
      case Severity.note:
        return Icons.info_outline;
      case Severity.none:
        return Icons.help_outline;
    }
  }
}

/// Resolves a [Severity] to its display color.
///
/// Reads the active theme's `severity.*` tokens first, so an imported
/// `.crux-theme.json` pack retunes the violation table — the palette users
/// scan by eye is the one they are most likely to want to change.
/// [LintcruxColors] supplies the fallback, so an unthemed build and a pack
/// that omits a token both render the built-in palette.
Color severityColor(BuildContext context, Severity s) {
  final tokens = Theme.of(context).extension<CruxThemeExtension>();
  final fallback = _builtInSeverityColor(s);
  if (tokens == null) return fallback;
  return tokens.colorOr(
    kLintcruxSeverityCategoryId,
    _severityTokenId(s),
    fallback,
  );
}

/// The token id for [s]; matches the descriptors in
/// [lintcruxSeverityTokens].
String _severityTokenId(Severity s) {
  switch (s) {
    case Severity.fatal:
      return 'fatal';
    case Severity.error:
      return 'error';
    case Severity.warning:
      return 'warning';
    case Severity.note:
      return 'note';
    case Severity.none:
      return 'none';
  }
}

Color _builtInSeverityColor(Severity s) {
  switch (s) {
    case Severity.fatal:
      return LintcruxColors.severityFatal;
    case Severity.error:
      return LintcruxColors.severityError;
    case Severity.warning:
      return LintcruxColors.severityWarning;
    case Severity.note:
      return LintcruxColors.severityNote;
    case Severity.none:
      return LintcruxColors.severityNone;
  }
}
