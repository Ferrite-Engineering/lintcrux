// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The shared CXP lifecycle, the cross-probe surfaces and the shared Recent
// list are built, tested and green in crux-shared. A shared widget or provider
// that nothing here binds or calls is a promise the suite is not keeping, and
// the package's own suite cannot see it. Each claim is checked against the
// sources the running app is built from.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path: run this from the root');
  return file.readAsStringSync();
}

List<String> _libSources() => <String>[
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
    if (f.path.endsWith('.dart') && !p.split(f.path).contains('generated'))
      f.readAsStringSync(),
];

void main() {
  test('bootstrap installs the CXP binding and the request handler', () {
    final app = _read('lib/app.dart');
    expect(
      app,
      contains('lintcruxCxpOverrides('),
      reason: 'bootstrap() does not install the CXP overrides',
    );
    final overrides = _read(
      'lib/features/remote/providers/lintcrux_cxp_overrides.dart',
    );
    for (final installed in const <String>[
      'cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding)',
      'cruxCxpLaunchSettingsProvider.overrideWithValue(launchSettings)',
      'cruxCxpRequestHandlerProvider.overrideWith(LintCruxCxpWrappedHandler.new)',
      'crossProbeSendObserverProvider.overrideWith',
    ]) {
      expect(overrides, contains(installed), reason: 'missing: $installed');
    }
  });

  test(
    'the app watches the shared runtime, so the server starts at launch',
    () {
      expect(_read('lib/app.dart'), contains('cruxCxpRuntimeProvider'));
    },
  );

  test('every cross-probe surface is called from lib/', () {
    final sources = _libSources().join('\n');
    for (final call in const <String>[
      'crossProbeMenuEntry(',
      'runCrossProbeSelection(',
      'clearCruxRecentList(',
      'CruxCrossProbePanel(',
      'CruxCxpSettingsSection(',
      'CruxRecentListSection(',
      'broadcastCruxCxpSelection(',
      'cruxCxpConnectedPeerCountProvider',
    ]) {
      expect(sources, contains(call), reason: 'nothing in lib/ uses $call');
    }
  });

  test('no second path: the product keeps no CXP lifecycle of its own', () {
    final sources = _libSources().join('\n');
    for (final gone in const <String>[
      'LintCruxCxpServer',
      'cxpServerLifecycleProvider',
      'cxpServerHandleProvider',
      'recentProjectsListProvider',
      'launchCxpSettingsProvider',
    ]) {
      expect(sources, isNot(contains(gone)), reason: '$gone came back');
    }
  });
}
