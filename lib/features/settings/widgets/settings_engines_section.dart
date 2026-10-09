// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/features/engine_config/widgets/severity_override_list.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/widgets/settings_section_card.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/engines/engine_binary_ids.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';

/// Settings → Engines section.
///
/// Renders, for every registered [LintEngine]:
///
/// * A SegmentedButton choosing Auto-detect / Custom. There is no Bundled
///   choice: no engine binaries ship with LintCrux, so it would resolve
///   exactly as Auto-detect does. A setting saved as Bundled still resolves
///   that way and shows as Auto-detect.
/// * When **Custom** is active, an editable path field plus a
///   live-validation "Probe" button that runs `<binary> --version`
///   via the engine's own `detectVersion` and surfaces the detected
///   version string (or the error).
/// * Below the per-engine controls, the historical severity-override
///   list is still surfaced — it has nothing to do with binary paths
///   but lives under "Engines" semantically.
class SettingsEnginesSection extends ConsumerWidget {
  /// Creates a [SettingsEnginesSection].
  const SettingsEnginesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final registry = ref.watch(engineRegistryProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsSectionCard(
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    l10n.engineConfigBinaryOverridesHeader,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                CruxHelpLink(
                  url: HelpUrls.engineBinaries,
                  tooltip: l10n.helpLinkLearnMore,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.engineConfigBinaryOverridesHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            // One row per binary: CDC runs Yosys, so the Yosys row
            // configures it and a CDC row would offer a path nothing reads.
            for (final engine in registry.engines)
              if (hasOwnBinary(engine.id)) _EngineRow(engine: engine),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const SeverityOverrideList(),
          ],
        ),
      ],
    );
  }
}

class _EngineRow extends ConsumerStatefulWidget {
  const _EngineRow({required this.engine});

  final LintEngine engine;

  @override
  ConsumerState<_EngineRow> createState() => _EngineRowState();
}

class _EngineRowState extends ConsumerState<_EngineRow> {
  late TextEditingController _pathController;
  String? _detectedVersion;
  String? _probeError;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    final override = ref
        .read(appSettingsProvider)
        .engineBinaryOverrideFor(widget.engine.id);
    _pathController = TextEditingController(text: override.path ?? '');
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _probe(EngineBinaryConfig config) async {
    setState(() {
      _probing = true;
      _detectedVersion = null;
      _probeError = null;
    });
    final l10n = L10N.of(context);
    try {
      final version = await widget.engine.detectVersion(config);
      if (!mounted) return;
      setState(() {
        _probing = false;
        if (version == null || version.isEmpty) {
          _probeError = l10n.engineConfigBinaryProbeFailure;
        } else {
          _detectedVersion = version;
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final override = ref.watch(
      appSettingsProvider.select(
        (s) => s.engineBinaryOverrideFor(widget.engine.id),
      ),
    );
    final notifier = ref.read(appSettingsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.engine.displayName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<EngineBinarySource>(
            segments: [
              ButtonSegment(
                value: EngineBinarySource.system,
                label: Text(l10n.engineConfigBinarySourceAuto),
              ),
              ButtonSegment(
                value: EngineBinarySource.custom,
                label: Text(l10n.engineConfigBinarySourceCustom),
              ),
            ],
            selected: {
              if (override.source == EngineBinarySource.bundled)
                EngineBinarySource.system
              else
                override.source,
            },
            onSelectionChanged: (next) {
              final source = next.first;
              notifier.setEngineBinaryOverride(
                widget.engine.id,
                EngineBinaryOverride(
                  source: source,
                  path: source == EngineBinarySource.custom
                      ? _pathController.text
                      : null,
                ),
              );
              setState(() {
                _detectedVersion = null;
                _probeError = null;
              });
            },
          ),
          if (override.source == EngineBinarySource.custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      labelText: l10n.engineConfigBinaryPathLabel,
                      hintText:
                          '/opt/${widget.engine.id}/bin/'
                          '${widget.engine.id}',
                    ),
                    onSubmitted: (value) {
                      notifier.setEngineBinaryOverride(
                        widget.engine.id,
                        EngineBinaryOverride(
                          source: EngineBinarySource.custom,
                          path: value,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _probing
                      ? null
                      : () {
                          // Persist the typed path first, then probe.
                          final next = EngineBinaryOverride(
                            source: EngineBinarySource.custom,
                            path: _pathController.text,
                          );
                          notifier.setEngineBinaryOverride(
                            widget.engine.id,
                            next,
                          );
                          unawaited(_probe(next.toEngineBinaryConfig()));
                        },
                  child: Text(l10n.engineConfigBinaryProbeButton),
                ),
              ],
            ),
            if (_probing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.engineConfigBinaryProbing,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else if (_detectedVersion != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.engineConfigBinaryProbeSuccess(_detectedVersion!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              )
            else if (_probeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _probeError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
