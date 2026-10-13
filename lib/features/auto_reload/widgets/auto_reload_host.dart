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
  @override
  Widget build(BuildContext context) {
    ref
      ..watch(autoReloadControllerProvider)
      ..listen<bool>(pendingReloadProvider, (_, pending) {
        if (pending) _showPrompt();
      });
    return widget.child;
  }

  /// The suite's source-changed prompt, the same banner in every product. It
  /// stays until the user chooses, and asks once however many changes land
  /// while it is up.
  void _showPrompt() {
    final l10n = L10N.of(context);
    void settle() =>
        ref.read(pendingReloadProvider.notifier).markPending(pending: false);
    showCruxReloadPrompt(
      context,
      message: l10n.autoReloadPromptMessage,
      reloadLabel: l10n.autoReloadActionRerun,
      ignoreLabel: l10n.fileWatcherIgnore,
      onReload: () {
        settle();
        final project = ref.read(currentProjectProvider);
        if (project == null) return;
        unawaited(ref.read(lintRunProvider.notifier).runAll(project));
      },
      onIgnore: settle,
    );
  }
}
