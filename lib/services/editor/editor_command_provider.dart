// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';

/// Holds the user's current click-to-source editor command.
///
/// This is a plain in-memory notifier; persistence lands
/// when the editor preference gets routed through `crux_settings`'s
/// `WaveCruxSettingsCodec`-equivalent for LintCrux. Until then the
/// provider holds [EditorCommand.defaultPreset] (VS Code) at startup
/// and the user's Settings → Editors choice for the remainder of the
/// session.
class EditorCommandNotifier extends Notifier<EditorCommand> {
  @override
  EditorCommand build() => EditorCommand.defaultPreset;

  /// Sets the active editor command. Used by Settings → Editors.
  set value(EditorCommand cmd) => state = cmd;

  /// Current setting (alias of [state], for symmetry with [value=]).
  EditorCommand get value => state;

  /// Restores the [EditorCommand.defaultPreset] (VS Code).
  void resetToDefault() {
    state = EditorCommand.defaultPreset;
  }
}

/// Provider exposing the active [EditorCommand].
final NotifierProvider<EditorCommandNotifier, EditorCommand>
editorCommandProvider = NotifierProvider<EditorCommandNotifier, EditorCommand>(
  EditorCommandNotifier.new,
);

/// Provider exposing the [ClickToSourceService] that consumes the
/// active editor command. Tests override this provider with a service
/// backed by a fake [EditorLauncher].
final Provider<ClickToSourceService> clickToSourceServiceProvider =
    Provider<ClickToSourceService>(
      (ref) => ClickToSourceService(
        commandFor: () => ref.read(editorCommandProvider),
        // `editor.launched` — "click-to-source reliability + editor
        // mix". Bound here, at the single service every surface goes through
        // (the inspector's location row, the related-locations list, the
        // table's double-tap, and the inbound CXP `request_open_source`), so
        // no surface can be added without being counted. Neither the file nor
        // the line is sent: the preset and the success bit are the whole
        // question.
        onLaunched: (preset, {required ok}) => ref
            .read(telemetryServiceProvider)
            .record(
              TelemetryEvent(
                'editor.launched',
                properties: <String, Object?>{
                  'preset': telemetryEnumToken(preset),
                  'ok': ok,
                },
              ),
            ),
      ),
    );
