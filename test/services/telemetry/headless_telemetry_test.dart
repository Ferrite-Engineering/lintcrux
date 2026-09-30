// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lintcrux/core/cli/lintcrux_cli.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_storage.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_outcome.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/telemetry/headless_telemetry.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';
import 'package:path/path.dart' as p;

import '../../support/telemetry_test_store.dart';

/// THE HEADLESS CONSENT RULE.
///
/// The rule: "`lintcrux --ci` and other headless invocations send
/// nothing unless the GUI app on the same machine has stored an affirmative
/// consent state; a machine that has never shown the first-launch dialog never
/// transmits."
///
/// The three assertions that make that sentence real are the first three tests
/// below, and they are asserted against **traffic** rather than against a flag:
/// a `MockClient` that records every request it is handed, and an empty
/// recording list. A future refactor that reads consent correctly and then
/// posts anyway would pass a flag check and fail this one.
///
/// The `unset` case is the important one. A CI container has never run the GUI
/// and never will, so `unset` is its permanent state — treating it as consent
/// would opt in every CI fleet in the world by accident, and prompting would
/// hang the job on a dialog nobody can answer.
class _SilentEngine implements LintEngine {
  @override
  String get id => 'verilator';
  @override
  String get displayName => 'Verilator';
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog, HdlLanguage.verilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';
  @override
  Stream<Violation> run(LintRunRequest request) => const Stream.empty();
  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => const Stream.empty();
  @override
  void cancel() {}
}

void main() {
  late Directory tmp;
  late List<http.Request> requests;
  late List<String> out;
  late List<String> err;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_headless_telemetry_');
    requests = <http.Request>[];
    out = <String>[];
    err = <String>[];
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A client that records every request and always accepts.
  MockClient recordingClient() => MockClient((request) async {
    requests.add(request);
    return http.Response('{"accepted":1,"dropped":0}', 202);
  });

  /// A one-file SystemVerilog project the silent engine can "lint".
  String project() {
    File(p.join(tmp.path, 'top.sv')).writeAsStringSync('module top;endmodule');
    final path = p.join(tmp.path, 'p.lintcrux');
    File(path).writeAsStringSync('''
{"version":1,"name":"p","rootPath":".","sourceFiles":["top.sv"],
 "language":"systemverilog","enabledEngineIds":["verilator"]}
''');
    return path;
  }

  /// `LintcruxCli` wired to the recording transport and to [storage], with the
  /// signal reaper off (it attaches process-wide SIGINT/SIGTERM handlers and a
  /// suite that installs one per case fights the test runner for them).
  LintcruxCli cli(TelemetryStorage storage, {bool dev = false}) => LintcruxCli(
    registry: EngineRegistry(<LintEngine>[_SilentEngine()]),
    installSignalReaper: false,
    telemetryResolver: () => HeadlessTelemetry.resolve(
      appVersion: '0.6.0',
      storage: storage,
      dev: dev,
      client: recordingClient(),
    ),
  );

  Future<int> run(TelemetryStorage storage, {bool dev = false}) =>
      cli(storage, dev: dev).run(
        <String>[project()],
        stdoutSink: out.add,
        stderrSink: err.add,
      );

  group('THE HEADLESS CONSENT RULE', () {
    test('consent `unset` performs zero HTTP and never prompts', () async {
      // A machine whose GUI has never shown the disclosure. The store is
      // empty, which is exactly what a fresh CI container looks like.
      final storage = TelemetryTestStore();

      await run(storage);

      expect(
        requests,
        isEmpty,
        reason:
            'a headless run on a machine that never answered the disclosure '
            'must transmit nothing at all',
      );
      // And it must not have *asked*, which here means: it must not have
      // written anything either. Minting an installation id for a machine
      // that never consented is the file-level shape of asking.
      expect(storage.values, isEmpty);
    });

    test('consent `disabled` performs zero HTTP', () async {
      final storage = TelemetryTestStore(<String, String>{
        kTelemetryConsentKey: TelemetryConsentState.disabled.name,
        kTelemetryInstallationIdKey: '00000000-0000-4000-8000-000000000001',
      });

      await run(storage);

      expect(requests, isEmpty);
    });

    test('consent `enabled` queues the run and posts it before exit', () async {
      final storage = TelemetryTestStore.consented();

      await run(storage);

      expect(requests, hasLength(1));
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['product'], 'lintcrux');
      expect(body['app_version'], '0.6.0');
      expect(
        body['installation_id'],
        storage.values[kTelemetryInstallationIdKey],
      );
      expect(body['form_factor'], 'desktop');
      expect(kTelemetryOperatingSystems, contains(body['os']));

      final events = (body['events'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final names = events.map((e) => e['name']).toSet();
      expect(names, contains('run.completed'));
      expect(names, contains('engine.run'));

      final completed = events.firstWhere(
        (e) => e['name'] == 'run.completed',
      );
      expect(
        (completed['properties'] as Map<String, dynamic>)['trigger'],
        'cli',
        reason: 'the CLI is the only source of the `cli` trigger',
      );
      expect(
        (completed['properties'] as Map<String, dynamic>)['engines'],
        1,
      );
    });

    test('TELEMETRY_DEV in headless routes to the dev endpoint', () async {
      // The dark-launch switch works headlessly too, so an end-to-end staging
      // verification can be driven from a CI job rather than only from the
      // desktop app. The path selects the dataset — nothing in the body can.
      final storage = TelemetryTestStore.consented();

      await run(storage, dev: true);

      expect(requests, hasLength(1));
      expect(
        requests.single.url.toString(),
        'https://telemetry.edacrux.app/dev/v1/events',
      );

      requests.clear();
      await run(storage);
      expect(
        requests.single.url.toString(),
        'https://telemetry.edacrux.app/v1/events',
      );
    });

    test('the dev flag does not relax the consent rule', () async {
      // In the GUI, `unset` counts as enabled under the dev flag so staging
      // verification needs no UI. Headless has no UI to skip, and the rule it
      // would be skipping is the headless-consent rule itself.
      await run(TelemetryTestStore(), dev: true);
      expect(requests, isEmpty);
    });
  });

  group('HeadlessTelemetry', () {
    HeadlessTelemetry consented({http.Client? client}) => HeadlessTelemetry(
      consent: TelemetryConsentState.enabled,
      installationId: '00000000-0000-4000-8000-000000000001',
      appVersion: '0.6.0',
      endpoint: Uri.parse('https://telemetry.edacrux.app/v1/events'),
      clientOverride: client,
    );

    test('a non-consenting reporter never even builds an event', () {
      final reporter = HeadlessTelemetry(
        consent: TelemetryConsentState.unset,
        installationId: null,
        appVersion: '0.6.0',
        endpoint: Uri.parse('https://telemetry.edacrux.app/v1/events'),
      )..recordRunCompleted(engines: 3);

      expect(reporter.transmits, isFalse);
      expect(reporter.pending, isEmpty);
    });

    test('a stored `enabled` with no installation id does not transmit', () {
      // The envelope's `installation_id` is not optional, and inventing one
      // here would create an identity the user never agreed to. The GUI mints
      // it; a headless run only ever reads it.
      final reporter = HeadlessTelemetry(
        consent: TelemetryConsentState.enabled,
        installationId: null,
        appVersion: '0.6.0',
        endpoint: Uri.parse('https://telemetry.edacrux.app/v1/events'),
      )..recordRunCompleted(engines: 1);

      expect(reporter.transmits, isFalse);
      expect(reporter.pending, isEmpty);
    });

    test('resolve() reads the same store the desktop app writes', () async {
      // The whole reason `LintcruxTelemetryStorage` is a file rather than
      // `SharedPreferences`: this is the GUI half writing and the headless
      // half reading, through one class, at one path.
      final path = p.join(tmp.path, 'lintcrux.json');
      final gui = LintcruxTelemetryStorage(filePathOverride: path);
      await gui.write(kTelemetryConsentKey, TelemetryConsentState.enabled.name);
      await gui.write(
        kTelemetryInstallationIdKey,
        '00000000-0000-4000-8000-000000000001',
      );

      final reporter = await HeadlessTelemetry.resolve(
        appVersion: '0.6.0',
        storage: LintcruxTelemetryStorage(filePathOverride: path),
      );

      expect(reporter.consent, TelemetryConsentState.enabled);
      expect(reporter.transmits, isTrue);
    });

    test('resolve() reads an unreadable store as `unset`', () async {
      final path = p.join(tmp.path, 'broken.json');
      File(path).writeAsStringSync('{ not json');

      final reporter = await HeadlessTelemetry.resolve(
        appVersion: '0.6.0',
        storage: LintcruxTelemetryStorage(filePathOverride: path),
      );

      expect(reporter.consent, TelemetryConsentState.unset);
      expect(reporter.transmits, isFalse);
    });

    test('identical events coalesce into one row with a count', () async {
      final reporter = consented(client: recordingClient());
      for (var i = 0; i < 4; i++) {
        reporter.recordEngineOutcome('verilator', EngineRunOutcome.ok);
      }
      await reporter.flush();

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      final events = (body['events'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(events, hasLength(1));
      expect(events.single['count'], 4);
    });

    test('a network failure is swallowed and drops the events', () async {
      // There is no next launch to retry into — see the flush decision on
      // `HeadlessTelemetry`. What must never happen is the exception escaping
      // into the CI gate's exit code.
      final reporter = consented(
        client: MockClient((_) async => throw const SocketException('down')),
      )..recordRunCompleted(engines: 1);

      await expectLater(reporter.flush(), completes);
      expect(reporter.pending, isEmpty);
    });

    test('every engine outcome maps into the catalog vocabulary', () async {
      final reporter = consented(client: recordingClient());
      for (final outcome in EngineRunOutcome.values) {
        reporter.recordEngineOutcome('verilator', outcome);
      }
      await reporter.flush();

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      final statuses = (body['events'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((e) => (e['properties'] as Map<String, dynamic>)['status'])
          .toSet();
      final catalog = kLintcruxEventCatalog
          .firstWhere((e) => e.name == 'engine.run')
          .enumeratedValues['status']!;
      expect(statuses, catalog.toSet());
    });
  });

  group('headlessTelemetryOsSlug', () {
    test('every branch lands in the Worker vocabulary', () {
      for (final os in <String>[
        'macos',
        'windows',
        'linux',
        'ios',
        'android',
        'fuchsia',
        'plan9',
      ]) {
        expect(
          kTelemetryOperatingSystems,
          contains(headlessTelemetryOsSlug(operatingSystem: os)),
          reason: os,
        );
      }
    });

    test('an unknown platform falls back to linux, not to itself', () {
      // The fallback is a constant on purpose: a pass-through would put a
      // platform string the Worker does not know in the envelope, and the
      // Worker rejects the whole batch with a 400 the client never sees.
      expect(headlessTelemetryOsSlug(operatingSystem: 'fuchsia'), 'linux');
      expect(headlessTelemetryOsSlug(operatingSystem: 'plan9'), 'linux');
    });

    test('the local set agrees with the shared one', () {
      // The list is spelled out in `headless_telemetry.dart` because
      // `kTelemetryOperatingSystems` lives in a Flutter-importing library the
      // CLI cannot link. This is what keeps the copy honest.
      for (final os in kTelemetryOperatingSystems) {
        if (os == 'web') continue; // no headless web host exists
        expect(headlessTelemetryOsSlug(operatingSystem: os), os);
      }
    });
  });
}
