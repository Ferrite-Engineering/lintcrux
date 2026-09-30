// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard: the hosted web app names itself LintCrux, not the Flutter
/// template's placeholders.
///
/// `flutter create` writes `<title>` and the PWA manifest's `name` as the
/// package name (`lintcrux`) and the description as "A new Flutter project.".
/// The web app is linked from the product site, so the tab title and the
/// search-result snippet are the first text a visitor reads. A regenerated
/// `web/` directory reintroduces every one of those defaults without a
/// compile error or a failing widget test, which is why this is a static
/// check.
///
/// MUTATION: restore any one template value — the description, a title equal
/// to the package name, or the manifest `name` — and a test below fails,
/// naming the field.
void main() {
  const templateDescription = 'A new Flutter project.';
  const packageName = 'lintcrux';
  const displayName = 'LintCrux';

  group('web/index.html', () {
    late String html;

    setUpAll(() {
      final file = File('web/index.html');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run from the package root (cwd = lintcrux/)',
      );
      html = file.readAsStringSync();
    });

    test('has a product <title>, not the package name', () {
      final title = _match(html, '<title>([^<]*)</title>');
      expect(title, isNotNull, reason: 'web/index.html has no <title>.');
      expect(
        title!.trim(),
        isNot(packageName),
        reason:
            'The <title> is the Flutter template default (the package '
            'name). It is the browser tab text for every visitor.',
      );
      expect(title, contains(displayName));
    });

    test('has a product description, not the template one', () {
      final description = _metaContent(html, 'description');
      expect(
        description,
        isNotNull,
        reason:
            'web/index.html has no <meta name="description">; search '
            'engines then invent a snippet.',
      );
      expect(
        description,
        isNot(templateDescription),
        reason: 'The description meta is the Flutter template default.',
      );
      expect(description, contains(displayName));
    });

    test('names the home-screen shortcut LintCrux', () {
      expect(_metaContent(html, 'apple-mobile-web-app-title'), displayName);
    });

    test('carries no Flutter template placeholder anywhere', () {
      expect(html, isNot(contains(templateDescription)));
    });
  });

  group('web/manifest.json', () {
    late Map<String, Object?> manifest;

    setUpAll(() {
      final file = File('web/manifest.json');
      expect(file.existsSync(), isTrue);
      manifest = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    });

    for (final field in const ['name', 'short_name']) {
      test('"$field" is the product name', () {
        expect(
          manifest[field],
          displayName,
          reason:
              'manifest.json "$field" is what an installed PWA shows '
              'under its icon; the Flutter template writes the package name.',
        );
      });
    }

    test('"description" is not the template one', () {
      final description = manifest['description'];
      expect(description, isA<String>());
      expect(description, isNot(templateDescription));
      expect((description! as String).trim(), isNotEmpty);
    });
  });
}

/// The first capture group of [pattern] in [source], or null.
String? _match(String source, String pattern) =>
    RegExp(pattern, caseSensitive: false).firstMatch(source)?.group(1);

/// The `content` of the `<meta name="[name]">` tag in [html], or null.
String? _metaContent(String html, String name) => _match(
  html,
  '<meta\\s+name="${RegExp.escape(name)}"\\s+content="([^"]*)"',
);
