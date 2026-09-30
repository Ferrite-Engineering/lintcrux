// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/auto_reload/providers/auto_reload_controller.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// Runs auto-reload for the project tab it wraps.
///
/// Watching [autoReloadControllerProvider] from here is what spawns the
/// tab's source watchers: the controller does nothing until something
/// watches it, and it must bind to the tab's own container so it watches
/// that tab's project. (It is deliberately not a per-tab startup hook: the
/// Pro overlay replaces that list wholesale.)
///
/// In prompt mode the controller raises [pendingReloadProvider]; this host
/// answers with an announced snackbar offering **Re-run now**, and clears
/// the flag when the snackbar closes, whether by the action or by timing
/// out.
class AutoReloadHost extends ConsumerStatefulWidget {
  /// Creates an [AutoReloadHost] around [child].
  const AutoReloadHost({required this.child, super.key});

  /// The tab content.
  final Widget child;

  @override
  ConsumerState<AutoReloadHost> createState() => _AutoReloadHostState();
}

class _AutoReloadHostState extends ConsumerState<AutoReloadHost> {
  bool _promptShowing = false;

  @override
  Widget build(BuildContext context) {
    ref
      ..watch(autoReloadControllerProvider)
      ..listen<bool>(pendingReloadProvider, (_, pending) {
        if (pending && !_promptShowing) _showPrompt();
      });
    return widget.child;
  }

  void _showPrompt() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final l10n = L10N.of(context);
    _promptShowing = true;
    announceCrux(context, l10n.autoReloadPromptMessage);
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.autoReloadPromptMessage),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: l10n.autoReloadActionRerun,
          onPressed: () {
            final project = ref.read(currentProjectProvider);
            if (project == null) return;
            unawaited(ref.read(lintRunProvider.notifier).runAll(project));
          },
        ),
      ),
    );
    unawaited(
      controller.closed.whenComplete(() {
        _promptShowing = false;
        if (!mounted) return;
        ref.read(pendingReloadProvider.notifier).markPending(pending: false);
      }),
    );
  }
}
