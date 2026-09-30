// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/engine_config/providers/engine_versions_provider.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';

/// Opens the shared beta issue reporter with LintCrux's session state
/// attached.
///
/// Two things have to happen before the package dialog is useful here, and
/// neither belongs in `crux_issue_reporter`:
///
/// 1. **Warm the engine-version probe.** `cruxIssueSessionContextProvider` is
///    synchronous, but engine versions come from a subprocess per engine.
///    Awaiting `engineVersionsProvider` first means the Session State category
///    reports `verilator 5.022` rather than `verilator (not detected)` — and
///    engine versions are the single most valuable line in a LintCrux bug
///    report, because rule ids and their meanings drift between engine
///    releases (the reason `RuleAliasTable` exists at all).
///
/// 2. **Mount the dialog inside the ACTIVE TAB's `ProviderContainer`.** The
///    session contributor reads `currentProjectProvider`,
///    `violationStoreProvider` and the table state, all of which are per-tab.
///    `CruxIssueReporterDialog.openAdaptive` resolves its container from the
///    context it is handed — which, from an action dispatch, is the router's
///    navigator context in the ROOT scope, where every one of those providers
///    reads empty. The report would faithfully record "no project loaded, 0
///    violations" while the user is staring at a full violations table.
///
/// The per-tab binding is a plain `Provider` that `ref.watch`es its inputs, so
/// it recomputes on its own; the package's `openAdaptive` invalidation (aimed
/// at `ref.read`-based contributors) is not needed here.
///
/// LintCrux ships on desktop plus a read-only web viewer and has no mobile
/// target, so only the modal presentation is reachable; the screenshot step is
/// skipped on web, where there is no temp-dir reveal.
abstract final class LintcruxIssueReporter {
  /// Width of the reporter modal, matching the package's desktop presentation.
  static const double _dialogWidth = CruxIssueReporterDialog.desktopWidth;

  /// Height of the reporter modal, matching the package's desktop
  /// presentation.
  static const double _dialogHeight = CruxIssueReporterDialog.desktopHeight;

  /// Shows the reporter over [context], which must have `WorkspaceRoot` in its
  /// ancestor chain (the router's navigator context qualifies).
  ///
  /// Re-entrancy guarded ([ModalGuard]) inside the opener: a repeated gesture
  /// while the reporter is open (or while the engine-version probe /
  /// screenshot capture is still running) must not stack a second copy.
  static Future<void> open(BuildContext context) =>
      ModalGuard.run('issueReporter', () => _open(context));

  static Future<void> _open(BuildContext context) async {
    final rootContainer = ProviderScope.containerOf(context, listen: false);
    final tabContainer = activeTabContainerOf(context);
    final container = tabContainer ?? rootContainer;

    // Engine version probe. A failure here is not worth blocking a bug report
    // over — the contributor renders "(not detected)" and the user still gets
    // to file the issue.
    try {
      await container.read(engineVersionsProvider.future);
    } on Object {
      // Intentionally swallowed: see above.
    }
    if (!context.mounted) return;

    final screenshot = await _captureScreenshot(rootContainer);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: _dialogWidth,
            height: _dialogHeight,
            child: CruxIssueReporterDialog(screenshotPng: screenshot),
          ),
        ),
      ),
    );
  }

  /// Captures the app-window screenshot from the root `RepaintBoundary`, or
  /// `null` on web / when the boundary is not mounted.
  ///
  /// Read from the ROOT container: the boundary key wraps the whole
  /// `MaterialApp` content child, above every tab scope.
  static Future<Uint8List?> _captureScreenshot(
    ProviderContainer rootContainer,
  ) async {
    if (kIsWeb || !isCruxDesktopPlatform) return null;
    final service = rootContainer.read(cruxIssueReporterServiceProvider);
    final boundaryKey = rootContainer.read(
      cruxAppScreenshotBoundaryKeyProvider,
    );
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    return await service.captureScreenshot(
      renderObject is RenderRepaintBoundary ? renderObject : null,
    );
  }
}
