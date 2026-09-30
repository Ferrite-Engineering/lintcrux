// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/help_urls.dart';

void main() {
  group('HelpUrls', () {
    test('privacy and terms go straight to the suite documents', () {
      expect(HelpUrls.privacyPolicy, 'https://edacrux.app/privacy');
      expect(HelpUrls.termsOfService, 'https://edacrux.app/terms');
    });

    // Every contextual link names a page of the documentation site and a
    // section anchor that page actually declares, so a renamed heading
    // cannot leave a help icon landing at the top of the wrong page.
    for (final url in const <String>[
      HelpUrls.workspaces,
      HelpUrls.engineBinaries,
      HelpUrls.themePresets,
      HelpUrls.crossProbe,
      HelpUrls.violationSearch,
    ]) {
      test('$url resolves to a docs-site section', () {
        final uri = Uri.parse(url);
        expect(uri.host, 'docs.lintcrux.app');
        expect(uri.fragment, isNotEmpty);
        final page = File('docs-site/docs${uri.path}.md');
        expect(page.existsSync(), isTrue, reason: page.path);
        expect(page.readAsStringSync(), contains('{#${uri.fragment}}'));
      });
    }
  });
}
