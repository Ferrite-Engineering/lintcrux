// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';

/// Announces every violation the user selects to connected CXP peers as a
/// `NotifySelection`, while Settings > CXP Cross-Probe > "Broadcast
/// selection automatically" is on.
///
/// Every tier, as in WaveCrux, NetCrux and SimCrux: live selection
/// broadcast is suite infrastructure, and the setting that controls it is
/// shown in every build.
///
/// Behavior:
/// * Listens to [selectedViolationProvider]. On every non-null transition,
///   broadcasts a `NotifySelection` carrying the violation as a CXP
///   `ElementKind.rule` element with `lintcrux.violation_severity` and
///   `lintcrux.message` metadata (message truncated to
///   [kMessageTruncationLimit] characters to keep wire payloads bounded).
/// * Reads the broadcast setting on each selection, so turning it off takes
///   effect immediately; explicit sends are unaffected.
/// * Broadcasts through `cxpServerLifecycleProvider`; when the server is not
///   running the broadcast is a no-op.
///
/// Realized PER TAB: re-bound in `lintcruxTabOverridesFactory` and watched
/// from `ProjectTabContent`, so the listener observes the tab's own
/// selection. A root-realized emitter would listen to the root-scope
/// selection notifier, which no table click writes. The broadcast still goes
/// through the one root CXP server.
class ViolationSelectionEmitter {
  /// Builds the emitter against [ref] and installs its selection listener,
  /// which Riverpod owns and disposes with the provider.
  ViolationSelectionEmitter(this._ref) {
    _ref.listen<Violation?>(selectedViolationProvider, (previous, next) {
      if (next == null) return;
      if (previous == next) return;
      _maybeEmit(next);
    });
  }

  final Ref _ref;

  /// Maximum number of characters of [Violation.message] propagated
  /// over CXP. Truncated payloads end with an ellipsis so receivers
  /// know the original was longer.
  static const int kMessageTruncationLimit = 200;

  void _maybeEmit(Violation v) {
    if (!_ref.read(appSettingsProvider).broadcastSelectionOnCrossProbe) return;

    final lifecycle = _ref.read(cxpServerLifecycleProvider.notifier);
    final element = ElementId(kind: ElementKind.rule, path: cxpPathFor(v));
    // Tag the selection with this design's `crux.design_id` so a receiver
    // with none of this design open can resolve and open it from the shared
    // workspace. `currentProjectProvider` is per-tab, like this emitter.
    final project = _ref.read(currentProjectProvider);
    final designId = project == null ? null : cxpLintcruxDesignId(project);
    lifecycle.broadcast(
      NotifySelection(
        elements: [element],
        displayName: v.ruleId,
        metadata: <String, Object?>{
          'lintcrux.violation_severity': v.severity.name,
          'lintcrux.message': _truncateMessage(v.message),
          cxpDesignIdMetadataKey: ?designId,
        },
      ),
    );
  }

  static String _truncateMessage(String message) {
    if (message.length <= kMessageTruncationLimit) return message;
    return '${message.substring(0, kMessageTruncationLimit - 1)}…';
  }
}

/// CXP path format for a [Violation]:
/// `<ruleId>@<file>:<line>[:<column>]`.
///
/// Public so resolvers in the other suite products can parse incoming
/// references the same way the emitter formats them.
String cxpPathFor(Violation v) {
  final loc = v.location;
  return '${v.ruleId}@${loc.file}:${loc.line}:${loc.column}';
}

/// The per-tab [ViolationSelectionEmitter]. Construction is the side effect;
/// nothing reads the value.
final Provider<ViolationSelectionEmitter> violationSelectionEmitterProvider =
    Provider<ViolationSelectionEmitter>(
      ViolationSelectionEmitter.new,
      name: 'violationSelectionEmitterProvider',
    );
