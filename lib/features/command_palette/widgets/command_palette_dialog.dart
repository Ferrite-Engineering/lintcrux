// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_keybindings/crux_keybindings.dart'
    show formatShortcutLabel;
import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:lintcrux/features/workspace/providers/lintcrux_action_context_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/shared/widgets/lintcrux_feature_tier_badge.dart';

/// Trailing per-row widget for the command palette: a [LintCruxFeatureTierBadge] on
/// Pro / Enterprise actions, `null` (no badge) on open-core actions. Tier is
/// declared once on the action via [LintcruxActionRequiredTier.requiredTier]
/// (the single source of truth); this renders it. Mirrors WaveCrux's palette.
Widget? _tierBadgeFor(LintcruxAction action) {
  final tier = action.requiredTier;
  return tier == LicenseTier.openCore
      ? null
      : LintCruxFeatureTierBadge(requiredTier: tier);
}

/// LintCrux-specific wrapper around the cross-suite
/// [CommandPalette]<[LintcruxAction]> widget.
///
/// Responsibilities:
/// - Pick the visible action list.
/// - Resolve action labels through lintcrux's [L10N] class.
/// - Pass the active key bindings so each row can render its shortcut.
/// - Dispatch the selected action by invoking [onAction], leaving the
///   actual handler logic to the caller (typically the app-level
///   [ShortcutManagerWidget] dispatch in `lib/app.dart`).
class CommandPaletteDialog extends ConsumerWidget {
  /// Creates a lintcrux command palette wrapper.
  const CommandPaletteDialog({required this.onAction, super.key});

  /// Called when the user picks an action. The dialog has already closed
  /// itself by the time this fires.
  final ValueChanged<LintcruxAction> onAction;

  /// Shows the palette as a modal dialog over [context].
  ///
  /// Re-entrancy guarded ([ModalGuard]): Cmd/Ctrl+Shift+P auto-repeat or a
  /// double-press must not stack multiple palettes. Guarded inside the
  /// opener so every caller is covered.
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<LintcruxAction> onAction,
  }) {
    return ModalGuard.run(
      'commandPalette',
      () => CommandPalette.show<LintcruxAction>(
        context,
        // The descriptor table is the single source of truth for every
        // surface. `paletteActionsFor` returns visible AND enabled actions:
        // the palette has no greyed state, so a command that would be inert
        // is omitted rather than shown and silently doing nothing.
        actions: paletteActionsFor(
          ProviderScope.containerOf(
            context,
            listen: false,
          ).read(lintcruxActionContextProvider),
        ),
        labelFor: (a) => a.label(L10N.of(context)),
        onAction: onAction,
        hintText: L10N.of(context).commandPaletteSearchHint,
        noResultsLabel: L10N.of(context).commandPaletteNoResults,
        bindings: _readBindings(context),
        activatorLabel: formatShortcutLabel,
        trailingBuilder: _tierBadgeFor,
      ),
    );
  }

  /// Reads the active bindings via a one-shot `ProviderScope.containerOf`
  /// lookup so [show] can be invoked from anywhere without a `WidgetRef`
  /// in hand.
  static Map<LintcruxAction, ShortcutActivator?> _readBindings(
    BuildContext context,
  ) {
    final container = ProviderScope.containerOf(context, listen: false);
    return container.read(shortcutBindingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    return CommandPalette<LintcruxAction>(
      actions: paletteActionsFor(ref.watch(lintcruxActionContextProvider)),
      labelFor: (a) => a.label(l10n),
      onAction: onAction,
      hintText: l10n.commandPaletteSearchHint,
      noResultsLabel: l10n.commandPaletteNoResults,
      bindings: bindings,
      activatorLabel: formatShortcutLabel,
      trailingBuilder: _tierBadgeFor,
    );
  }
}
