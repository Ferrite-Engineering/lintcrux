// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;
import 'dart:io' show exit;

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/features/beta_expiry/beta_expiry_metrics.dart';
import 'package:lintcrux/features/beta_expiry/lintcrux_beta_expiry_strings.dart';
import 'package:lintcrux/features/beta_expiry/widgets/beta_expiry_blocking_overlay.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Seam for opening the "download the latest build" page. Overridable in
/// tests so the banner and modal actions can be exercised without the
/// `url_launcher` platform channel.
Future<bool> Function(Uri uri) betaExpiryLaunchUrl = launchUrl;

/// Seam for terminating the process from the expired modal's quit action.
/// Overridable in tests — calling the real `exit` would kill the test runner.
///
/// The expired modal only ever renders on a native desktop beta build (no
/// `BETA_EXPIRY` is injected for the web viewer), so the `dart:io`
/// stub-on-web caveat never fires in practice.
void Function() betaExpiryExitApp = () => exit(0);

/// Startup/resume gate enforcing the per-release hard beta build expiry.
///
/// Wraps the routed app content ([child]) and switches on
/// `betaExpiryStatusProvider`:
///
/// * [BetaExpiryStatus.expiringSoon] → a dismissible `CruxBetaExpiryBanner` above
///   [child].
/// * [BetaExpiryStatus.expired] → the blocking, non-dismissable
///   [BetaExpiryBlockingOverlay] over [child].
/// * [BetaExpiryStatus.active] / [BetaExpiryStatus.notApplicable] → [child]
///   unchanged. That is the common case and covers every developer build and
///   every post-beta build, where `kBetaExpiry` is `null`.
///
/// The status is read at startup (first build) and re-evaluated on app resume:
/// [didChangeAppLifecycleState] invalidates the expiry providers so they
/// re-read the clock, and clears the session dismissal so a warning the user
/// dismissed earlier resurfaces when they return. The check never runs
/// mid-session, so work in progress is never interrupted.
///
/// The expiry clock is hardened against a device-clock rollback: the providers
/// reckon against `trustedBetaExpiryNow`, which takes the later of the device
/// clock and the persisted `observedServerTimeProvider` watermark that the
/// update-manifest check feeds (see
/// `lib/services/updates/observed_server_time_store.dart`).
///
/// Mounted inside `MaterialApp` (so `L10N.of` resolves) but above the routed
/// content — see `app.dart`'s `MaterialApp.builder` — and *outside* the update
/// banner, so an expired-beta modal covers it.
class BetaExpiryGate extends ConsumerStatefulWidget {
  /// Creates the gate wrapping [child].
  const BetaExpiryGate({required this.child, super.key});

  /// The routed app content the gate wraps.
  final Widget child;

  @override
  ConsumerState<BetaExpiryGate> createState() => _BetaExpiryGateState();
}

class _BetaExpiryGateState extends ConsumerState<BetaExpiryGate>
    with WidgetsBindingObserver {
  /// Whether the user dismissed the "expires soon" banner this session. Reset
  /// on app resume so a returning user is reminded again.
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Re-evaluate expiry against the latest clock reading. The providers
    // capture the instant when first read, so invalidation forces a fresh
    // one — a build still inside its window at launch can cross into
    // expiringSoon / expired while the app was suspended.
    ref
      ..invalidate(betaExpiryStatusProvider)
      ..invalidate(betaExpiryDaysRemainingProvider);
    if (_bannerDismissed && mounted) {
      setState(() => _bannerDismissed = false);
    }
  }

  void _download() {
    unawaited(betaExpiryLaunchUrl(Uri.parse(HelpUrls.download)));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(betaExpiryStatusProvider);

    switch (status) {
      case BetaExpiryStatus.expired:
        return BetaExpiryBlockingOverlay(
          onDownload: _download,
          onQuit: betaExpiryExitApp,
          child: widget.child,
        );
      case BetaExpiryStatus.expiringSoon:
        if (_bannerDismissed) return widget.child;
        final days = ref.watch(betaExpiryDaysRemainingProvider) ?? 0;
        return Column(
          children: [
            CruxBetaExpiryBanner(
              daysRemaining: days,
              onDownload: _download,
              onDismiss: () => setState(() => _bannerDismissed = true),
              strings: LintcruxBetaExpiryStrings(L10N.of(context)),
              // Icon and touch target already equal the shared defaults;
              // only the 13 pt body size is LintCrux's own, shared with the
              // blocking overlay via `BetaExpiryMetrics`. Passing it keeps
              // the strip rendering exactly as it did before the widget
              // moved into crux_license.
              sizing: const CruxBetaExpirySizing(
                bodyTextSize: BetaExpiryMetrics.bodyText,
              ),
            ),
            Expanded(child: widget.child),
          ],
        );
      case BetaExpiryStatus.active:
      case BetaExpiryStatus.notApplicable:
        return widget.child;
    }
  }
}
