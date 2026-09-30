// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_about_dialog/crux_about_dialog.dart';
import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/about/lintcrux_about_strings.dart';
import 'package:lintcrux/core/app_info/about_providers.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/features/issue_reporter/lintcrux_issue_reporter.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/shared/widgets/glowing_app_icon.dart';
import 'package:url_launcher/url_launcher.dart';

/// The LintCrux About dialog.
///
/// A thin builder over the cross-suite [CruxAboutDialog] (from
/// `crux_about_dialog`): it maps LintCrux's branding / build-info / edition
/// providers and ARB strings onto the shared surface and supplies the
/// LintCrux-specific pieces — the glowing app icon and the canonical suite
/// action row (Visit Website, Documentation, Report Issue, Check for Updates,
/// Privacy Policy, Terms of Service, Copy Version Info). Tier and beta-period
/// chips are driven by `crux_license` providers inside the shared widget.
/// LintCrux ships no third-party attribution section.
abstract final class LintcruxAboutDialog {
  /// Opens the About box: a modal dialog on desktop, a pushed route on mobile.
  ///
  /// Re-entrancy guarded ([ModalGuard]) inside the opener so every caller —
  /// menu item, command palette, keyboard shortcut — is covered: a repeated
  /// gesture while the box is open (or while its build info is still
  /// resolving) must not stack a second copy.
  static Future<void> openAdaptive(BuildContext context, WidgetRef ref) =>
      ModalGuard.run('about', () => _openAdaptive(context, ref));

  static Future<void> _openAdaptive(BuildContext context, WidgetRef ref) async {
    final l10n = L10N.of(context);

    final branding = ref.read(aboutBrandingProvider);

    // Resolve build info up front so the version section renders data rather
    // than a perpetual spinner — the provider resolves in milliseconds. On
    // failure the shared widget hides the section.
    ApplicationBuildInfo? pkgInfo;
    AsyncValue<ApplicationBuildInfo> buildInfo;
    try {
      final resolved = await ref.read(aboutBuildInfoProvider.future);
      pkgInfo = resolved;
      buildInfo = AsyncValue.data(resolved);
    } on Object catch (error, stackTrace) {
      buildInfo = AsyncValue.error(error, stackTrace);
    }

    if (!context.mounted) return;

    final edition = aboutEditionLabel(ref, l10n);
    // A non-null capture so the Copy Version Info closure stays type-promoted.
    final info = pkgInfo;

    await CruxAboutDialog.show(
      context,
      title: l10n.aboutDialogTitle,
      tagline: l10n.aboutTagline,
      companyTagline: l10n.aboutCompanyName,
      appIcon: const GlowingAppIcon(size: 80),
      branding: branding,
      buildInfo: buildInfo,
      // Hide the edition chip for the open-core edition.
      editionLabel: edition == l10n.aboutEditionOpenCore ? '' : edition,
      strings: LintcruxAboutStrings(l10n),
      actions: [
        AboutAction(
          label: l10n.aboutButtonVisitWebsite,
          icon: Icons.language_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(branding.websiteUrl))),
        ),
        AboutAction(
          label: l10n.aboutButtonDocs,
          icon: Icons.menu_book_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(HelpUrls.docs))),
        ),
        // Beta issue reporter. Open to every tier: no badge, no
        // feature gate. Goes through the LintcruxIssueReporter wrapper (not
        // CruxIssueReporterDialog directly) so the reporter resolves its
        // ProviderContainer correctly.
        AboutAction(
          label: l10n.aboutButtonSubmitIssue,
          icon: Icons.bug_report_outlined,
          onTap: (ctx) => unawaited(LintcruxIssueReporter.open(ctx)),
        ),
        // The About box is where users look for "am I current?",
        // so the manual update check lives here as well as in the Help menu
        // and the command palette. Runs regardless of the Settings → General
        // auto-check toggle.
        AboutAction(
          label: l10n.aboutButtonCheckForUpdates,
          icon: Icons.system_update_alt_outlined,
          onTap: (ctx) => unawaited(runManualUpdateCheck(ctx, ref)),
        ),
        AboutAction(
          label: l10n.aboutButtonPrivacy,
          icon: Icons.privacy_tip_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(HelpUrls.privacyPolicy))),
        ),
        AboutAction(
          label: l10n.aboutButtonTerms,
          icon: Icons.description_outlined,
          onTap: (_) =>
              unawaited(launchUrl(Uri.parse(HelpUrls.termsOfService))),
        ),
        AboutAction(
          label: l10n.aboutButtonCopyVersionInfo,
          icon: Icons.copy_outlined,
          onTap: info == null
              ? null
              : (ctx) => unawaited(_copyVersionInfo(ctx, l10n, edition, info)),
        ),
      ],
    );
  }

  static Future<void> _copyVersionInfo(
    BuildContext context,
    L10N l10n,
    String edition,
    ApplicationBuildInfo info,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text: aboutVersionInfoText(
          appName: 'LintCrux',
          editionLabel: edition,
          info: info,
        ),
      ),
    );
    if (context.mounted) {
      showCruxInfoSnack(context, l10n.aboutCopiedConfirmation);
    }
  }
}
