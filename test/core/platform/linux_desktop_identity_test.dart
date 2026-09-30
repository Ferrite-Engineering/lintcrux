// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/platform/linux_desktop_identity.dart';

String _cmakeSet(String name) {
  final cmake = File('linux/CMakeLists.txt').readAsStringSync();
  final match = RegExp('set\\($name "([^"]+)"\\)').firstMatch(cmake);
  if (match == null) fail('linux/CMakeLists.txt sets no $name');
  return match.group(1)!;
}

void main() {
  test('the open-core identity matches the Linux runner it launches', () {
    expect(kLintcruxLinuxDesktopApp.appId, _cmakeSet('APPLICATION_ID'));
    expect(kLintcruxLinuxDesktopApp.execName, _cmakeSet('BINARY_NAME'));
    expect(kLintcruxLinuxDesktopApp.name, isNot(contains('Pro')));
  });
}
