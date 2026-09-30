// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/foundation.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// LintCrux's [crux.ViewerTabBarStrings] implementation, delegating
/// every field to an [L10N] instance so the tab bar reads localized
/// text out of LintCrux's ARB sweep instead of the package's English
/// defaults.
///
/// Constructed once from the routed subtree's `L10N.of(context)` and
/// passed down to `crux.PaneHost.strings` (which forwards it to each
/// pane's [crux.ViewerTabBar]).
class LintcruxViewerTabBarStrings extends crux.ViewerTabBarStrings {
  /// Creates a [LintcruxViewerTabBarStrings] backed by [l10n].
  const LintcruxViewerTabBarStrings(this._l10n);

  final L10N _l10n;

  @override
  String get revealTabMenuItem {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _l10n.tabContextMenuRevealInExplorer;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return _l10n.tabContextMenuRevealInFiles;
    }
    return _l10n.tabContextMenuRevealInFinder;
  }

  @override
  String get closeTabTooltip => _l10n.viewerTabBarCloseTabTooltip;

  // Names the tab, so with several tabs open a screen reader does not hear
  // a row of identical "Close tab" buttons.
  @override
  String closeTabTooltipFor(String name) => _l10n.tabChipCloseTooltip(name);

  @override
  String get newTabTooltip => _l10n.viewerTabBarNewTabTooltip;

  @override
  String get newTabDefaultDisplayName =>
      _l10n.viewerTabBarNewTabDefaultDisplayName;

  @override
  String get unnamedTabFallback => _l10n.viewerTabBarUnnamedTabFallback;

  @override
  String get closeTabMenuItem => _l10n.viewerTabBarCloseTabMenuItem;

  @override
  String get closeOtherTabsMenuItem => _l10n.viewerTabBarCloseOtherTabsMenuItem;

  @override
  String get closeTabsToTheRightMenuItem =>
      _l10n.viewerTabBarCloseTabsToTheRightMenuItem;

  @override
  String get moveToNewWindowMenuItem =>
      _l10n.viewerTabBarMoveToNewWindowMenuItem;

  @override
  String get multiWindowUnavailableTooltip =>
      _l10n.viewerTabBarMultiWindowUnavailableTooltip;

  @override
  String get activePaneAccessibilityLabel =>
      _l10n.viewerTabBarActivePaneAccessibilityLabel;

  @override
  String get dragToPaneAccessibilityHint =>
      _l10n.viewerTabBarDragToPaneAccessibilityHint;

  @override
  String get reorderHandleTooltip => _l10n.viewerTabBarReorderHandleTooltip;

  // These two carry English defaults on the shared interface (they were added
  // after four products already subclassed it). Overriding them is what keeps
  // the chevrons out of the untranslated set.
  @override
  String get scrollTabsLeftTooltip => _l10n.viewerTabBarScrollTabsLeftTooltip;

  @override
  String get scrollTabsRightTooltip => _l10n.viewerTabBarScrollTabsRightTooltip;
}
