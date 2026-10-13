// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/workspace/providers/recent_project_exists_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('recent_exists_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a project file on disk exists; a moved one does not', () {
    final here = File(p.join(dir.path, 'here.lintcrux'))..writeAsStringSync('');
    expect(defaultRecentProjectExists(here.path), isTrue);
    expect(
      defaultRecentProjectExists(p.join(dir.path, 'gone.lintcrux')),
      isFalse,
    );
  });

  test('the provider answers with the file-system check by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(recentProjectExistsProvider),
      same(defaultRecentProjectExists),
    );
  });
}
