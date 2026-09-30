// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:lintcrux/core/theme/lintcrux_colors.dart';

/// Category id for the severity palette in `.crux-theme.json` packs.
const String kLintcruxSeverityCategoryId = 'severity';

/// Category id for the trend palette in `.crux-theme.json` packs.
const String kLintcruxTrendCategoryId = 'trend';

/// The severity palette.
///
/// The highest-stakes tokens in the product. Engineers scan the violation
/// table by color before they read a word of it, and whether a palette is
/// "noisy" or "actionable" is a per-person, per-monitor judgement — which is
/// exactly why it belongs in a theme pack rather than in a constant. A team
/// standardising on one severity palette can now ship it as a file.
///
/// Defaults mirror [LintcruxColors] so an unthemed build renders exactly as
/// before. Dark defaults are lightened: the light-mode reds and blues are
/// tuned against a white table and lose contrast on a dark surface.
const ThemeTokenCategory lintcruxSeverityTokens = ThemeTokenCategory(
  id: kLintcruxSeverityCategoryId,
  displayName: 'Severity',
  tokens: <ThemeTokenDescriptor>[
    ThemeTokenDescriptor(
      id: 'fatal',
      displayName: 'Fatal',
      description:
          'Engine could not continue. Deliberately darker than '
          'error so a fatal stands out amid many errors.',
      lightDefault: LintcruxColors.severityFatal,
      darkDefault: Color(0xFFEF5350),
    ),
    ThemeTokenDescriptor(
      id: 'error',
      displayName: 'Error',
      lightDefault: LintcruxColors.severityError,
      darkDefault: Color(0xFFE57373),
    ),
    ThemeTokenDescriptor(
      id: 'warning',
      displayName: 'Warning',
      lightDefault: LintcruxColors.severityWarning,
      darkDefault: Color(0xFFFFD54F),
    ),
    ThemeTokenDescriptor(
      id: 'note',
      displayName: 'Note',
      lightDefault: LintcruxColors.severityNote,
      darkDefault: Color(0xFF64B5F6),
    ),
    ThemeTokenDescriptor(
      id: 'none',
      displayName: 'None',
      description: 'Clean / passing rows.',
      lightDefault: LintcruxColors.severityNone,
      darkDefault: Color(0xFF9E9E9E),
    ),
  ],
);

/// The trend palette.
///
/// Consumed by the Pro trend charts and the run-delta indicators. The
/// catalog lives in open core with the rest of the theming chrome — a theme
/// pack has to be able to name every token the suite defines, whether or not
/// the build that reads it can render the surface those tokens paint.
///
/// Improving is green and worsening red by default, but both are tokens
/// precisely because that pairing is unreadable for the most common form of
/// color blindness; a deuteranopia-safe pack is a supported customisation
/// rather than a fork.
const ThemeTokenCategory lintcruxTrendTokens = ThemeTokenCategory(
  id: kLintcruxTrendCategoryId,
  displayName: 'Trend',
  tokens: <ThemeTokenDescriptor>[
    ThemeTokenDescriptor(
      id: 'improving',
      displayName: 'Improving',
      description: 'Violation count fell against the comparison run.',
      lightDefault: Color(0xFF2E7D32),
      darkDefault: Color(0xFF81C784),
    ),
    ThemeTokenDescriptor(
      id: 'worsening',
      displayName: 'Worsening',
      description: 'Violation count rose against the comparison run.',
      lightDefault: Color(0xFFC62828),
      darkDefault: Color(0xFFE57373),
    ),
    ThemeTokenDescriptor(
      id: 'flat',
      displayName: 'Unchanged',
      lightDefault: Color(0xFF616161),
      darkDefault: Color(0xFFBDBDBD),
    ),
    ThemeTokenDescriptor(
      id: 'baseline',
      displayName: 'Baseline',
      description: 'The reference series a comparison is drawn against.',
      lightDefault: Color(0xFF1565C0),
      darkDefault: Color(0xFF90CAF9),
    ),
  ],
);

/// Registers LintCrux's themable-token catalogs with the shared
/// [ThemeRegistry]. Called once from [bootstrap]; idempotent so a
/// second bootstrap (test hot-restart, doubled init) is a no-op.
///
/// Registers the suite-shared `chrome` catalog plus LintCrux's own
/// `severity` and `trend` palettes, so the Settings → Appearance per-token
/// editor and `.crux-theme.json` pack imports both recognise them.
void registerLintcruxThemeTokens() {
  registerCruxThemeChromeTokens();
  final registry = ThemeRegistry.instance;
  for (final category in <ThemeTokenCategory>[
    lintcruxSeverityTokens,
    lintcruxTrendTokens,
  ]) {
    if (!registry.hasCategory(category.id)) {
      registry.registerCategory(category);
    }
  }
}
