// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/services/persistence/recent_projects_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  ProviderContainer containerOver(SharedPreferences prefs) {
    final container = ProviderContainer(
      overrides: [
        recentProjectsSettingsServiceProvider.overrideWithValue(
          SettingsService<List<String>>(
            const RecentProjectsSettingsCodec(),
            prefsOverride: prefs,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('recentProjectsProvider', () {
    test('starts empty when no projects have been opened', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);
      await _settle();
      expect(container.read(recentProjectsProvider), isEmpty);
    });

    test('can be overridden for tests', () {
      final container = ProviderContainer(
        overrides: [
          recentProjectsProvider.overrideWithValue(['/tmp/foo.lintcrux']),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(recentProjectsProvider), ['/tmp/foo.lintcrux']);
    });

    test('an opened project is listed first and saved', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);
      await _settle();
      container.read(recentProjectsListProvider.notifier)
        ..markOpened('/a/one.lintcrux')
        ..markOpened('/b/two.lintcrux')
        ..markOpened('/a/one.lintcrux');
      expect(container.read(recentProjectsProvider), [
        '/a/one.lintcrux',
        '/b/two.lintcrux',
      ]);
      await _settle();
      expect(
        prefs.getStringList(RecentProjectsSettingsCodec.prefsKey),
        ['/a/one.lintcrux', '/b/two.lintcrux'],
      );
    });

    test("a previous session's list is restored", () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RecentProjectsSettingsCodec.prefsKey: <String>['/old/p.lintcrux'],
      });
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);
      expect(container.read(recentProjectsProvider), isEmpty);
      await _settle();
      await _settle();
      expect(container.read(recentProjectsProvider), ['/old/p.lintcrux']);
    });

    // With tabs restored at launch the welcome screen is never built, so the
    // first thing to touch this list is the open itself, before the stored
    // history has been read. That open used to save a one-entry list over
    // the history, and the restore then declined to touch it.
    test('an open that lands before the stored list is read keeps the '
        'history', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RecentProjectsSettingsCodec.prefsKey: <String>[
          '/a.lintcrux',
          '/b.lintcrux',
          '/c.lintcrux',
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);

      container.read(recentProjectsListProvider.notifier)
        ..markOpened('/new.lintcrux')
        ..remove('/b.lintcrux');
      await _settle();
      await _settle();

      const expected = ['/new.lintcrux', '/a.lintcrux', '/c.lintcrux'];
      expect(container.read(recentProjectsProvider), expected);
      expect(
        prefs.getStringList(RecentProjectsSettingsCodec.prefsKey),
        expected,
      );
    });

    test('the list is capped', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);
      await _settle();
      final notifier = container.read(recentProjectsListProvider.notifier);
      for (var i = 0; i < AppSettings.maxRecentProjects + 5; i++) {
        notifier.markOpened('/p$i.lintcrux');
      }
      expect(
        container.read(recentProjectsProvider),
        hasLength(AppSettings.maxRecentProjects),
      );
    });

    test('remove drops an entry', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);
      await _settle();
      container.read(recentProjectsListProvider.notifier)
        ..markOpened('/gone.lintcrux')
        ..remove('/gone.lintcrux');
      expect(container.read(recentProjectsProvider), isEmpty);
    });
  });
}
