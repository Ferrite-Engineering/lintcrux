// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Managed waivers store the absolute path of the waived file and the matcher
/// compares it exactly, so a committed waiver file waives nothing on a CI
/// runner whose checkout is at another path. Until relative-path waivers
/// ship, both pages that promise the CI use must say so. When they ship,
/// remove the caveats and this test together.
void main() {
  const marker = 'Waivers match absolute paths today';
  for (final page in const <String>[
    'docs-site/docs/waivers.md',
    'docs-site/docs/exports-and-ci.md',
  ]) {
    test('$page carries the absolute-path waiver caveat', () {
      final text = File(page).readAsStringSync();
      expect(text, contains('!!! warning "$marker"'));
      expect(text, contains('absolute path'));
      expect(text, contains('fails safe'));
    });
  }
}
