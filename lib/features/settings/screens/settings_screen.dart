// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/platform/desktop_platform.dart';
import 'package:lintcrux/features/settings/widgets/settings_appearance_section.dart';
import 'package:lintcrux/features/settings/widgets/settings_editors_section.dart';
import 'package:lintcrux/features/settings/widgets/settings_engines_section.dart';
import 'package:lintcrux/features/settings/widgets/settings_general_section.dart';
import 'package:lintcrux/features/settings/widgets/settings_remote_control_section.dart';
import 'package:lintcrux/features/settings/widgets/shortcuts_settings_section.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/settings_extra_sections_provider.dart';

/// Top-level Settings screen (mobile / full-screen route).
///
/// Navigates between **General** / **Appearance** / **Engines** / **Editors** /
/// **Remote Control** plus any Pro-contributed sections appended after the
/// built-ins via [settingsExtraSectionsProvider], using the suite-shared
/// [CruxSettingsMasterDetail] shell (category rail + detail pane, responsive
/// collapse to list→detail). Each built-in section is its own widget under
/// `lib/features/settings/widgets/`; Pro features register through
/// `settingsExtraSectionsProvider` so the overlay can contribute without
/// forking this screen.
///
/// LintCrux's section widgets are self-scrolling `ListView`s, so the shell runs
/// with `scrollableDetail: false` (each section scrolls itself rather than the
/// shell wrapping it). It still renders the shell's `icon + title` detail
/// header (`showDetailTitle: true`) for visual parity with the other Crux apps,
/// so individual sections no longer carry their own category heading.
///
/// On desktop (Linux, macOS, Windows) call [SettingsScreen.openAdaptive]
/// instead — it presents the same content inside a modal dialog so the
/// workspace stays visible behind it (Cmd+, on macOS, Ctrl+, elsewhere).
class SettingsScreen extends ConsumerWidget {
  /// Creates a [SettingsScreen].
  const SettingsScreen({super.key});

  /// Opens settings in a dialog on desktop or as a pushed route on mobile.
  ///
  /// Wrapped in [wrapInActiveTabScope] so the project-scoped sections
  /// (the Engines section's severity-override list writes
  /// `currentProjectProvider`; the Pro lint-cache stats card reads the
  /// per-tab cache service) resolve the ACTIVE tab's providers. App-wide
  /// sections are unaffected — their providers are not re-bound per tab,
  /// so reads inside the tab scope parent-delegate to the root
  /// instances as before.
  static Future<void> openAdaptive(BuildContext context) {
    final l10n = L10N.of(context);
    final launchContext = context;
    // Re-entrancy guard: Cmd/Ctrl+, auto-repeat, a double-tap on the menu
    // item, or the palette entry must not stack a second settings surface.
    // Guarded inside the opener so every caller is covered.
    return ModalGuard.run(
      'settings',
      () => openCruxSettings(
        context,
        title: l10n.settingsTitle,
        closeTooltip: l10n.settingsClose,
        asDialog: isDesktopPlatform,
        bodyBuilder: (_) => const _SettingsBody(),
        // The tab-scope wrap resolves the ACTIVE tab's providers against the
        // LAUNCHING context (the dialog/route context lives outside the tab).
        wrap: (_, shell) => wrapInActiveTabScope(launchContext, shell),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return CruxSettingsRouteShell(
      title: l10n.settingsTitle,
      closeTooltip: l10n.settingsClose,
      body: const _SettingsBody(),
    );
  }
}

// ── Body shared by the screen and the dialog ──────────────────────────────────

/// Builds the LintCrux category list (built-ins followed by Pro-contributed
/// extras) and hands it to the shared [CruxSettingsMasterDetail].
class _SettingsBody extends ConsumerWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final extras = ref.watch(settingsExtraSectionsProvider);
    // Privacy holds the telemetry toggle and nothing else, so it is offered
    // only on a build whose pipeline can actually transmit. During the beta
    // with no dev flag the Settings screen is exactly what it was before
    // telemetry existed — the telemetry dark launch, extended to the UI.
    final showPrivacySection = ref.watch(telemetryConsentUiVisibleProvider);
    return CruxSettingsMasterDetail(
      scrollableDetail: false,
      categories: [
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.general,
          icon: Icons.tune,
          title: l10n.settingsGeneralSection,
          content: const SettingsGeneralSection(),
        ),
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.appearance,
          icon: Icons.palette_outlined,
          title: l10n.settingsAppearanceSection,
          content: const SettingsAppearanceSection(),
        ),
        // Privacy sits third — as high as the suite-canonical order (General
        // first, then Appearance) allows. It holds the telemetry opt-out, and
        // an opt-out is only honest if the off switch is not buried; a section
        // the user has to scroll a rail to find is buried. Offered only when
        // this build can transmit at all.
        //
        // The section itself is `crux_telemetry`'s, so all four products'
        // opt-out is one implementation; only the placement and the localized
        // heading are LintCrux's.
        if (showPrivacySection)
          CruxSettingsCategory(
            id: CruxSettingsCategoryId.privacy,
            icon: Icons.privacy_tip_outlined,
            title: l10n.settingsPrivacySection,
            content: const TelemetrySettingsSection(),
          ),
        CruxSettingsCategory(
          // The product-defaults slot. LintCrux titles it "Engines"; the
          // other three title the same slot for their own domain. One id,
          // four titles — the shared category order fixes the slot, not the
          // wording.
          id: CruxSettingsCategoryId.productDefaults,
          icon: Icons.memory,
          title: l10n.settingsEnginesSection,
          content: const SettingsEnginesSection(),
        ),
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.editors,
          icon: Icons.edit_outlined,
          title: l10n.settingsEditorsSection,
          content: const SettingsEditorsSection(),
        ),
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.cxp,
          // hub_outlined is the suite's CXP icon (wifi_tethering is
          // WaveCrux's WCP Remote Control).
          icon: Icons.hub_outlined,
          title: l10n.settingsCxpSectionTitle,
          content: const SettingsRemoteControlSection(),
        ),
        CruxSettingsCategory(
          id: CruxSettingsCategoryId.shortcuts,
          icon: Icons.keyboard_outlined,
          title: l10n.settingsShortcutsSection,
          content: const ShortcutsSettingsSection(),
        ),
        // Pro-contributed categories via the suite-shared seam
        // (CruxSettingsExtraCategory); bodies build deferred, when opened.
        for (final extra in extras) extra.toCategory(context),
      ],
    );
  }
}
