// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Outbound URLs LintCrux opens in the user's browser.
///
/// Kept in one place so the download destination cannot drift between the
/// update banner (`CruxUpdateConfig.downloadPageUri`) and the beta-expiry
/// gate's "download the latest build" actions, which must always point at the
/// same page.
abstract final class HelpUrls {
  /// LintCrux documentation home — the Help → Documentation target.
  static const String docs = 'https://docs.lintcrux.app';

  /// The LintCrux desktop download page. Target of the update banner's
  /// "Update Now" action and of both beta-expiry download affordances.
  static const String download = 'https://lintcrux.app/download';

  /// The public version manifest polled by the update check.
  static const String updateManifest =
      'https://updates.lintcrux.app/manifest.json';

  /// Privacy policy. One suite-wide policy, served by the EDACrux site.
  static const String privacyPolicy = 'https://edacrux.app/privacy';

  /// Terms of service. One suite-wide document, served by the EDACrux site.
  static const String termsOfService = 'https://edacrux.app/terms';

  /// Suite home — the target of the welcome screen's suite-membership line.
  ///
  /// A per-product path rather than the shared `/products` page, and that is
  /// the whole point: the site's page-view beacon records the path and
  /// deliberately drops the query string, so `?from=lintcrux` would be
  /// invisible and a desktop app sends no referrer. The path is how the visit
  /// is attributed to the app that sent it.
  static const suiteHome = 'https://edacrux.app/from/lintcrux';

  /// The suite landing path, scrolled to one peer product's card.
  ///
  /// The fragment is free: the site's beacon drops it before sending, so this
  /// is still recorded as `/from/lintcrux` and the per-product attribution is
  /// unaffected — while the reader still lands on the product the row named
  /// rather than at the top of a page listing three.
  static String suitePeer(String slug) => '$suiteHome#$slug';

  // Contextual documentation, targets of the in-app `CruxHelpLink` icons.
  // Each points at the section that answers the control it sits beside, on
  // the documentation site (served extensionless).

  /// Docs — workspaces: restoring tabs on launch, `--no-restore`, `--reset`.
  static const String workspaces =
      'https://docs.lintcrux.app/projects-and-engines#workspaces';

  /// Docs — engine binaries: Auto-detect / Bundled / Custom, and Probe.
  static const String engineBinaries =
      'https://docs.lintcrux.app/projects-and-engines#binaries';

  /// Docs — color theme presets.
  static const String themePresets =
      'https://docs.lintcrux.app/appearance-and-themes#presets';

  /// Docs — cross-probe (CXP).
  static const String crossProbe = 'https://docs.lintcrux.app/integrations#cxp';

  /// Docs — searching the violations: substring, glob and regex.
  static const String violationSearch =
      'https://docs.lintcrux.app/violations#search';
}
