// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/license/lintcrux_edition_line_strings.dart';
import 'package:lintcrux/core/shortcuts/action_category.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/action_tier_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptor.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/core/shortcuts/menu_layout.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:lintcrux/features/workspace/providers/lintcrux_action_context_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/shared/widgets/lintcrux_icon_image.dart';

/// LintCrux's binding of the shared [CruxDesktopMenuBar] to its own action
/// catalog.
///
/// Everything structural — the two renderers (native macOS [PlatformMenuBar]
/// vs. the in-window VS Code-style menu bar on Windows/Linux), separator
/// grouping, the platform-idiomatic placement of About / Check for Updates /
/// Settings / Quit, the standard macOS application-menu tail and Window menu,
/// and the guard that keeps typing-hostile accelerators out of native key
/// equivalents — lives in `crux_menu_bar`. This widget supplies only what is
/// LintCrux's own: [kMenuLayout] for order and grouping, the descriptor table
/// for membership and enablement, and the localized labels.
///
/// Enablement is new here. Every item used to be live regardless of state, so
/// with no project open `Run All Engines`, the exports, `Set Baseline…` and
/// `Close Pane` were all clickable and silently did nothing; the doc comment
/// on the old widget admitted as much. The descriptor table now greys them.
class DesktopMenuBar extends ConsumerWidget {
  /// Creates the LintCrux desktop menu bar.
  const DesktopMenuBar({
    required this.onAction,
    required this.child,
    super.key,
  });

  /// Called when the user selects a menu item.
  final void Function(LintcruxAction) onAction;

  /// The widget tree below the menu bar.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final ctx = ref.watch(lintcruxActionContextProvider);
    final bindings = ref.watch(shortcutBindingsProvider);
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;

    return CruxDesktopMenuBar<LintcruxAction>(
      layout: kMenuLayout,
      appActions: kAppMenuActions,
      categoryLabel: (category) => category.label(l10n),
      categoryAcceleratorLabel: (category) => category.acceleratorLabel(l10n),
      windowMenuLabel: l10n.menuWindow,
      labelOf: (action) =>
          _label(action, l10n, isMacOS: isMacOS) +
          tierLabelSuffix(action.requiredTier, l10n),
      shortcutOf: (action) => bindings[action],
      isVisible: (action) =>
          isActionVisibleIn(action, LintcruxActionSurface.menu, ctx),
      isEnabled: (action) => isActionEnabled(action, ctx),
      onAction: onAction,
      // States the edition in force, disabled, above `About LintCrux`.
      // Null at Open Core, so this is safe to pass unconditionally: the
      // Pro overlay supplies the licence status that gives it a value.
      editionLine: cruxLicenseEditionLine(
        ref.watch(licenseStatusProvider),
        LintCruxEditionLineStrings(l10n),
      ),
      logo: const LintcruxIconImage(size: 18),
      child: child,
    );
  }

  /// The action's localized label, with the one platform-dependent override.
  ///
  /// Quit reads "Quit LintCrux" in the macOS application menu and "Exit" at
  /// the bottom of the Windows/Linux File menu — the native wording on each,
  /// and what VS Code does.
  static String _label(
    LintcruxAction action,
    L10N l10n, {
    required bool isMacOS,
  }) => action == LintcruxAction.quit && !isMacOS
      ? l10n.actionExit
      : action.label(l10n);
}
