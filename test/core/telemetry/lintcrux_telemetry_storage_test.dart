// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_storage.dart';
import 'package:path/path.dart' as p;

/// LintCrux's one deliberate deviation from the WaveCrux telemetry template.
///
/// WaveCrux keeps consent and the installation id in `SharedPreferences`.
/// LintCrux keeps them in a JSON file, because it has a **second, Flutter-free
/// surface** — the `lintcrux --ci` binary — and the rule that the headless
/// runner transmits only on a stored affirmative consent is worthless if the
/// headless runner cannot read the consent the GUI wrote. The keys, the class
/// shape and the fail-soft contract are unchanged; only the backing store is
/// different, and these tests pin the parts of it a reviewer would want proof
/// of.
void main() {
  late Directory tmp;

  setUp(
    () => tmp = Directory.systemTemp.createTempSync('lintcrux_tstore_'),
  );
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  LintcruxTelemetryStorage storeAt(String name) =>
      LintcruxTelemetryStorage(filePathOverride: p.join(tmp.path, name));

  group('the suite-fixed keys', () {
    test('are exactly the ones every product agrees on', () {
      // Not a detail to tidy: the four products and any future migration
      // tooling agree on these strings, and LintCrux's headless half looks
      // them up by name in a file the GUI half wrote.
      expect(kTelemetryConsentKey, 'telemetry.consent');
      expect(kTelemetryInstallationIdKey, 'telemetry.installationId');
    });
  });

  group('round trip', () {
    test('a written value reads back', () async {
      final store = storeAt('a.json');

      await store.write(kTelemetryConsentKey, 'enabled');

      expect(await store.read(kTelemetryConsentKey), 'enabled');
    });

    test('both values live in one document', () async {
      // Read-modify-write rather than a file per key: the two are written
      // seconds apart on a first launch, and one document keeps them from
      // disagreeing about whether this installation exists.
      final store = storeAt('b.json');

      await store.write(kTelemetryConsentKey, 'enabled');
      await store.write(kTelemetryInstallationIdKey, 'abc');

      final decoded =
          jsonDecode(File(store.filePath).readAsStringSync())
              as Map<String, dynamic>;
      expect(decoded, <String, Object?>{
        kTelemetryConsentKey: 'enabled',
        kTelemetryInstallationIdKey: 'abc',
      });
    });

    test('a second process reads what the first wrote', () async {
      // The whole point of the file: two *different* instances, one path.
      // This is the GUI and `lintcrux --ci`.
      final gui = storeAt('c.json');
      await gui.write(kTelemetryConsentKey, 'enabled');

      final cli = storeAt('c.json');
      expect(await cli.read(kTelemetryConsentKey), 'enabled');
    });

    test('the parent directory is created on demand', () async {
      final store = LintcruxTelemetryStorage(
        filePathOverride: p.join(tmp.path, 'deep', 'nested', 'd.json'),
      );

      await store.write(kTelemetryConsentKey, 'disabled');

      expect(await store.read(kTelemetryConsentKey), 'disabled');
    });
  });

  group('fail-soft', () {
    test('a missing file reads null, never a throw', () async {
      expect(await storeAt('missing.json').read(kTelemetryConsentKey), isNull);
    });

    test('unparseable content reads null', () async {
      final store = storeAt('broken.json');
      File(store.filePath).writeAsStringSync('{ not json');

      expect(await store.read(kTelemetryConsentKey), isNull);
    });

    test('a non-object document reads null', () async {
      final store = storeAt('array.json');
      File(store.filePath).writeAsStringSync('[1,2,3]');

      expect(await store.read(kTelemetryConsentKey), isNull);
    });

    test('a non-string value reads null rather than coercing', () async {
      final store = storeAt('typed.json');
      File(store.filePath).writeAsStringSync('{"telemetry.consent": true}');

      // `true` is not `enabled`, and an unreadable value can never be
      // mistaken for consent.
      expect(await store.read(kTelemetryConsentKey), isNull);
    });

    test('an unwritable path drops the write instead of throwing', () async {
      // A directory where the file should be: the write cannot succeed.
      final path = p.join(tmp.path, 'as_a_dir');
      Directory(path).createSync();
      final store = LintcruxTelemetryStorage(filePathOverride: path);

      await expectLater(
        store.write(kTelemetryConsentKey, 'enabled'),
        completes,
      );
    });
  });

  group('the path derivation', () {
    // Mirrors `crux_cxp`'s `sharedCxpManifestDirectory()`: environment-derived
    // and `path_provider`-free, so the desktop app and the CLI binary resolve
    // the same absolute path. The `crux/` parent is the suite-shared
    // application-data root; the `lintcrux.json` leaf is what keeps consent a
    // per-product answer.
    test('macOS resolves under Application Support', () {
      expect(
        lintcruxTelemetryStorePath(
          environment: <String, String>{'HOME': '/Users/x'},
          operatingSystem: 'macos',
        ),
        '/Users/x/Library/Application Support/crux/telemetry/lintcrux.json',
      );
    });

    test('Windows resolves under APPDATA', () {
      // `p.windows.join`, not `p.join`: these tests name the OS explicitly, so
      // the expectation must too. `p.join` follows the HOST, which made this
      // suite assert POSIX separators on macOS and backslashes on Windows —
      // passing on whichever machine wrote it and failing on the other.
      expect(
        lintcruxTelemetryStorePath(
          environment: <String, String>{'APPDATA': r'C:\Users\x\AppData'},
          operatingSystem: 'windows',
        ),
        r'C:\Users\x\AppData\crux\telemetry\lintcrux.json',
      );
    });

    test('the derivation does not depend on the host it runs on', () {
      // The guard for the whole group. Every expectation above is a literal in
      // the target OS's own separator style, which is only meaningful if the
      // function ignores the host — and it did not, until it took a path
      // context chosen by the `operatingSystem` argument.
      expect(
        lintcruxTelemetryStorePath(
          environment: <String, String>{'HOME': '/Users/x'},
          operatingSystem: 'macos',
        ),
        isNot(contains(r'\')),
      );
      expect(
        lintcruxTelemetryStorePath(
          environment: <String, String>{'APPDATA': r'C:\Users\x\AppData'},
          operatingSystem: 'windows',
        ),
        isNot(contains('/')),
      );
    });

    test('Linux honours XDG_DATA_HOME', () {
      expect(
        lintcruxTelemetryStorePath(
          environment: <String, String>{
            'HOME': '/home/x',
            'XDG_DATA_HOME': '/home/x/.share',
          },
          operatingSystem: 'linux',
        ),
        '/home/x/.share/crux/telemetry/lintcrux.json',
      );
    });

    test('Linux falls back to ~/.local/share', () {
      expect(
        lintcruxTelemetryStorePath(
          environment: <String, String>{'HOME': '/home/x'},
          operatingSystem: 'linux',
        ),
        '/home/x/.local/share/crux/telemetry/lintcrux.json',
      );
    });

    test('a missing home variable throws rather than guessing', () {
      // Callers treat this as "no store", which reads as `unset` — never as
      // consent. Guessing a path would be the one failure that could invent
      // an installation.
      expect(
        () => lintcruxTelemetryStorePath(
          environment: const <String, String>{},
          operatingSystem: 'linux',
        ),
        throwsStateError,
      );
    });

    test('the leaf is per product, not per suite', () {
      // Consent is answered once per product. A shared leaf would mean
      // answering WaveCrux's disclosure silently answered LintCrux's.
      expect(
        lintcruxTelemetryStorePath(
          environment: <String, String>{'HOME': '/home/x'},
          operatingSystem: 'linux',
        ),
        endsWith('lintcrux.json'),
      );
    });
  });
}
