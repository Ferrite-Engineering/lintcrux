// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:lintcrux/features/beta_expiry/beta_expiry_metrics.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Blocking, non-dismissable modal rendered over the routed app content once
/// the public-beta build has reached or passed its hard expiry date
/// (`BetaExpiryStatus.expired`).
///
/// Stacks a non-dismissable [ModalBarrier] over [child] and centers a card
/// carrying the expiry message, a "Download latest build" action and a
/// "Quit LintCrux" action. A [PopScope] with `canPop: false` blocks the system
/// back gesture so the modal cannot be escaped.
///
/// The quit action is load-bearing on Windows and Linux: the app close
/// affordance there sits behind the [ModalBarrier], so without it the modal
/// would leave no visible way out of the application. A dumb leaf widget — the
/// hosting `BetaExpiryGate` owns the status provider, the URL launch and the
/// process exit.
class BetaExpiryBlockingOverlay extends StatelessWidget {
  /// Creates the blocking beta-expiry modal wrapping [child].
  const BetaExpiryBlockingOverlay({
    required this.child,
    required this.onDownload,
    required this.onQuit,
    super.key,
  });

  /// The routed app content rendered — dimmed and input-blocked — behind the
  /// modal.
  final Widget child;

  /// Invoked when the user taps "Download latest build".
  final VoidCallback onDownload;

  /// Invoked when the user taps "Quit LintCrux".
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          child,
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: SafeArea(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_disabled_outlined,
                          size: BetaExpiryMetrics.iconSize * 2,
                          color: scheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.betaExpiryExpiredTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.betaExpiryExpiredBody,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: BetaExpiryMetrics.bodyText,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: BetaExpiryMetrics.touchTarget,
                          child: FilledButton.icon(
                            onPressed: onDownload,
                            icon: const Icon(Icons.download_outlined),
                            label: Text(l10n.betaExpiryExpiredAction),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: BetaExpiryMetrics.touchTarget,
                          child: TextButton(
                            onPressed: onQuit,
                            child: Text(l10n.betaExpiryExpiredQuit),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
