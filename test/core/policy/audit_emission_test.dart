// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/policy/lintcrux_policy_keys.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

class _CapturingSink implements AuditSink {
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);

  @override
  Future<void> close() async {}

  @override
  AuditSinkHealth get health => AuditSinkHealth.healthy;
}

LintProject _project() => const LintProject(
  name: 'soc_top',
  rootPath: '/tmp/soc_top',
);

(ProviderContainer, _CapturingSink) _container() {
  final sink = _CapturingSink();
  final container = ProviderContainer(
    overrides: [
      cruxAuditSinkProvider.overrideWithValue(sink),
      cruxAuditProductIdProvider.overrideWithValue(
        LintCruxPolicyKeys.productId,
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container, sink);
}

void main() {
  group('severity overrides', () {
    test('records the rule, the previous severity and the new one', () async {
      final (container, sink) = _container();
      container.read(currentProjectProvider.notifier).load(_project());

      container
          .read(currentProjectProvider.notifier)
          .setSeverityOverride('verible:line-length', Severity.warning);
      await pumpEventQueue();

      final event = sink.events.single;
      expect(event.product, 'lintcrux');
      expect(event.kind, LintCruxAuditKinds.severityOverridden);
      expect(event.payload['ruleId'], 'verible:line-length');
      // Downgrading a rule is how a real violation stops being reported, so
      // the previous value matters as much as the new one.
      expect(event.payload['from'], isNull);
      expect(event.payload['to'], 'warning');
      expect(event.payload['project'], 'soc_top');
    });

    test(
      'a removed override records a null `to`, not a missing event',
      () async {
        final (container, sink) = _container();
        final notifier = container.read(currentProjectProvider.notifier)
          ..load(_project())
          ..setSeverityOverride('verible:line-length', Severity.warning);
        await pumpEventQueue();
        sink.events.clear();

        notifier.setSeverityOverride('verible:line-length', null);
        await pumpEventQueue();

        // Reverting to the engine's own severity is a different event from
        // setting one, and must not read as the same.
        expect(sink.events.single.payload['from'], 'warning');
        expect(sink.events.single.payload['to'], isNull);
      },
    );

    test(
      're-selecting the severity a rule already has records nothing',
      () async {
        final (container, sink) = _container();
        final notifier = container.read(currentProjectProvider.notifier)
          ..load(_project())
          ..setSeverityOverride('verible:line-length', Severity.warning);
        await pumpEventQueue();
        sink.events.clear();

        notifier.setSeverityOverride('verible:line-length', Severity.warning);
        await pumpEventQueue();

        expect(sink.events, isEmpty);
      },
    );

    test('no project open records nothing', () async {
      final (container, sink) = _container();
      container
          .read(currentProjectProvider.notifier)
          .setSeverityOverride('verible:line-length', Severity.error);
      await pumpEventQueue();
      expect(sink.events, isEmpty);
    });
  });

  group('engine config', () {
    test('repointing an engine records which one, never the path', () async {
      final (container, sink) = _container();

      container
          .read(appSettingsProvider.notifier)
          .setEngineBinaryOverride(
            'verilator',
            const EngineBinaryOverride(
              source: EngineBinarySource.custom,
              path: '/Users/dana/bin/verilator',
            ),
          );
      await pumpEventQueue();

      final event = sink.events.single;
      expect(event.kind, LintCruxAuditKinds.engineConfigChanged);
      expect(event.payload['engineId'], 'verilator');
      expect(event.payload['source'], 'custom');
      expect(event.payload['hasCustomPath'], isTrue);
      // The path routinely carries a username and this file is read by
      // whoever runs the organization's log shipper.
      expect(event.toJsonLine(), isNot(contains('martin')));
      expect(event.toJsonLine(), isNot(contains('/bin/verilator')));
    });

    test(
      'clearing every override names the engines that were cleared',
      () async {
        final (container, sink) = _container();
        final notifier = container.read(appSettingsProvider.notifier)
          ..setEngineBinaryOverride(
            'verilator',
            const EngineBinaryOverride(
              source: EngineBinarySource.custom,
              path: '/opt/verilator',
            ),
          )
          ..setEngineBinaryOverride(
            'verible',
            const EngineBinaryOverride(
              source: EngineBinarySource.custom,
              path: '/opt/verible',
            ),
          );
        await pumpEventQueue();
        sink.events.clear();

        notifier.clearEngineBinaryOverrides();
        await pumpEventQueue();

        final event = sink.events.single;
        expect(event.payload['source'], 'clearedAll');
        expect(event.payload['engines'], <String>['verible', 'verilator']);
      },
    );

    test('a no-op clear records nothing', () async {
      final (container, sink) = _container();
      container.read(appSettingsProvider.notifier).clearEngineBinaryOverrides();
      await pumpEventQueue();
      expect(sink.events, isEmpty);
    });
  });

  group('the default sink', () {
    test('emission is inert until an administrator configures a path', () async {
      // The gate is the SINK, never the emission — a product that only
      // emitted when configured would have call sites that go stale unnoticed.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(cruxAuditSinkProvider), isA<NoopAuditSink>());

      container.read(currentProjectProvider.notifier).load(_project());
      expect(
        () => container
            .read(currentProjectProvider.notifier)
            .setSeverityOverride('verible:line-length', Severity.error),
        returnsNormally,
      );
    });
  });
}
