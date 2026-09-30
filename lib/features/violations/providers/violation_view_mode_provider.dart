// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';

/// Riverpod notifier for the active [ViolationViewMode] on the
/// violation table.
class ViolationViewModeNotifier extends Notifier<ViolationViewMode> {
  @override
  ViolationViewMode build() => ViolationViewMode.allViolations;

  /// Replace the active view mode.
  ///
  /// Records `view_mode.changed` — the baseline-delta adoption signal.
  /// The notifier is the only writer of this state and the Pro
  /// `BaselineViewModeToggle` is its only caller, so one counter here covers
  /// the feature without the open-core repo having to know the toggle exists.
  /// A no-op re-selection of the current mode is not recorded: the segmented
  /// button can be tapped on its already-selected segment, and that is not a
  /// mode change.
  void setMode(ViolationViewMode mode) {
    if (state == mode) return;
    state = mode;
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'view_mode.changed',
            properties: <String, Object?>{'mode': telemetryEnumToken(mode)},
          ),
        );
  }
}

/// Active view mode for the violation table.
///
/// Open-core default is [ViolationViewMode.allViolations] so the
/// table renders every violation when no Pro view-mode toggle is
/// active. The Pro overlay's `BaselineViewModeToggle` writes to this
/// notifier to switch between *All violations* / *Only new* / *Only
/// resolved*; the open-core `visibleViolationsProvider` then applies
/// the corresponding post-filter (consulting
/// `currentBaselineSnapshotProvider`).
final NotifierProvider<ViolationViewModeNotifier, ViolationViewMode>
violationViewModeProvider =
    NotifierProvider<ViolationViewModeNotifier, ViolationViewMode>(
      ViolationViewModeNotifier.new,
    );
