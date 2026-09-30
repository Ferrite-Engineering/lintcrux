// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/beta_expiry/widgets/beta_expiry_gate.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/update/lintcrux_update_config.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/tab_overrides_factory.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/updates/observed_server_time_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'support/telemetry_test_store.dart';

/// A licence tier a test can change mid-session, the way entering a key does.
class _MutableTier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get value => state;

  set value(LicenseTier tier) => state = tier;
}

final _mutableTierProvider = NotifierProvider<_MutableTier, LicenseTier>(
  _MutableTier.new,
);

/// Structural coverage of the beta-distribution wiring in `lib/app.dart`: the
/// override list `bootstrap()` spreads, and the three widgets mounted in
/// `MaterialApp.builder`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lintcruxPhase5Overrides', () {
    ProviderContainer wired() {
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          ...lintcruxPhase5Overrides(),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('binds the update config — the package default throws', () {
      // `cruxUpdateConfigProvider` has no default binding on purpose: a
      // product that forgets it should fail at wiring, not silently stop
      // shipping updates. This asserts LintCrux does not forget.
      expect(wired().read(cruxUpdateConfigProvider), lintcruxUpdateConfig);
    });

    test('binds the issue reporter to the beta repository', () {
      final config = wired().read(cruxIssueReporterConfigProvider);
      expect(config.productName, 'LintCrux');
      expect(config.repositorySlug, 'Ferrite-Engineering/lintcrux');
      expect(config.issueTemplate, 'bug_report.yml');
      expect(
        config.newIssueUrl.toString(),
        'https://github.com/Ferrite-Engineering/lintcrux/issues/new',
      );
    });

    test('binds localized strings for both packages', () {
      final container = wired();
      expect(
        container.read(cruxUpdateStringsProvider).updateNowAction,
        isNotEmpty,
      );
      expect(
        container.read(cruxIssueReporterStringsProvider).dialogTitle,
        isNotEmpty,
      );
    });

    test('binds the auto-check setting to the settings model', () async {
      final container = wired();
      expect(
        await container.read(autoUpdateCheckEnabledProvider.future),
        isTrue,
      );
      container
          .read(appSettingsProvider.notifier)
          .setAutoCheckForUpdates(enabled: false);
      container.invalidate(autoUpdateCheckEnabledProvider);
      expect(
        await container.read(autoUpdateCheckEnabledProvider.future),
        isFalse,
      );
    });

    test('binds the beta-expiry clock to the persisted watermark', () async {
      final container = wired();
      expect(container.read(observedServerTimeProvider), isNull);
      final observed = DateTime.utc(2026, 9, 15, 12);
      await container
          .read(observedServerTimeStoreProvider.notifier)
          .record(observed);
      expect(container.read(observedServerTimeProvider), observed);
    });

    test('the server-time sink advances the persisted store', () async {
      final container = wired();
      final observed = DateTime.utc(2026, 9, 15, 12);
      container.read(observedServerTimeSinkProvider)(observed);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(observedServerTimeStoreProvider), observed);
    });

    test('binds the session-state contributor', () {
      // Without this override the reporter omits the Session State category
      // entirely, and every LintCrux bug report arrives with no engine
      // versions and no violation counts.
      expect(
        wired().read(cruxIssueSessionContextProvider).isNotEmpty,
        isTrue,
      );
    });

    test('leaves the overlay seam at its open-core default', () {
      // The Pro overlay replaces this to contribute its "Pro
      // State" category; open-core must not pre-empt it.
      expect(
        wired().read(cruxIssueReporterDataProviderProvider),
        isA<NoopCruxIssueReporterDataProvider>(),
      );
    });
  });

  group('updateEditionProvider binding', () {
    // Decides whether a release that changed only paid features is offered
    // (the manifest's `open_core_version`). Left unbound, the package default
    // offers every release to every seat — silently.
    ProviderContainer seat(LicenseTier tier, {bool betaPeriod = false}) {
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          ...lintcruxPhase5Overrides(),
          betaPeriodProvider.overrideWithValue(betaPeriod),
          licenseTierProvider.overrideWithValue(tier),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a seat without a licence is an open-core seat', () {
      expect(
        seat(LicenseTier.openCore).read(updateEditionProvider),
        UpdateEdition.openCore,
      );
    });

    test('every paid tier unlocks', () {
      for (final tier in [
        LicenseTier.edu,
        LicenseTier.pro,
        LicenseTier.enterprise,
      ]) {
        expect(
          seat(tier).read(updateEditionProvider),
          UpdateEdition.unlocked,
          reason: '$tier',
        );
      }
    });

    test('a beta period unlocks every seat, as it opens every gate', () {
      expect(
        seat(
          LicenseTier.openCore,
          betaPeriod: true,
        ).read(updateEditionProvider),
        UpdateEdition.unlocked,
      );
    });

    test('follows a licence entered mid-session', () {
      final container = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          ...lintcruxPhase5Overrides(),
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith(
            (ref) => ref.watch(_mutableTierProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(updateEditionProvider), UpdateEdition.openCore);

      container.read(_mutableTierProvider.notifier).value = LicenseTier.pro;

      expect(container.read(updateEditionProvider), UpdateEdition.unlocked);
    });
  });

  group('session snapshot resolves in the container it is read from', () {
    test(
      'a populated tab reports NON-ZERO counts through the production '
      'root + per-tab container shape',
      () {
        // Guards the failure mode a sibling product hit: a session contributor
        // registered only in a container that cannot see the per-tab state
        // reports an all-zero session, and a privacy test asserting "no file
        // paths" passes just as happily against an all-zero body. So this
        // asserts the counts are REAL.
        //
        // LintCrux's shape: `bootstrap()` builds one root `ProviderScope` with
        // `lintcruxPhase5Overrides()`, and `WorkspaceRoot` builds each tab's
        // container as a CHILD of that root via `lintcruxTabOverridesFactory`.
        // Both containers bind the contributor; the child binding shadows the
        // root one, which is what makes a tab's report describe that tab.
        final root = ProviderContainer(overrides: lintcruxPhase5Overrides());
        addTearDown(root.dispose);
        final tabs = crux.TabContainerManager(
          rootContainer: root,
          overridesFactory: lintcruxTabOverridesFactory,
        );
        addTearDown(tabs.dispose);

        final tab = tabs.containerFor(crux.TabId.generate());
        tab
            .read(currentProjectProvider.notifier)
            .load(
              const LintProject(
                name: 'soc',
                rootPath: '/p/soc',
                sourceFiles: ['/p/soc/a.sv', '/p/soc/b.sv'],
                enabledEngineIds: ['verilator'],
              ),
            );
        tab.read(violationStoreProvider).replaceFromEngine('verilator', const [
          Violation(
            engineId: 'verilator',
            ruleId: 'verilator/UNUSEDSIGNAL',
            severity: Severity.warning,
            message: 'unused',
            location: SourceLocation(file: '/p/soc/a.sv', line: 3, column: 1),
          ),
          Violation(
            engineId: 'verilator',
            ruleId: 'verilator/WIDTHTRUNC',
            severity: Severity.error,
            message: 'width',
            location: SourceLocation(file: '/p/soc/b.sv', line: 9, column: 1),
          ),
        ]);
        tab.read(violationTableStateProvider.notifier).setRuleSubstring('WID');

        String valueOf(String label) => tab
            .read(cruxIssueSessionContextProvider)
            .fields
            .firstWhere((f) => f.label == label)
            .value;

        expect(valueOf('Project loaded'), 'yes');
        expect(valueOf('Violations total'), '2');
        expect(valueOf('Source files'), '2');
        expect(valueOf('Distinct rules firing'), '2');
        expect(valueOf('Violations by severity'), contains('error 1'));
        expect(valueOf('Rule text filter set'), 'yes');

        // …and the filter text itself still never reaches the report.
        expect(valueOf('Rule text filter set'), isNot(contains('WID')));
      },
    );
  });

  group('MaterialApp.builder mounts', () {
    testWidgets('the screenshot boundary, expiry gate and update banner', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...telemetryDeclinedOverrides(),
            ...lintcruxPhase5Overrides(),
            betaExpiryStatusProvider.overrideWithValue(
              BetaExpiryStatus.notApplicable,
            ),
          ],
          child: const LintcruxApp(),
        ),
      );
      await tester.pump();

      expect(find.byType(BetaExpiryGate), findsOneWidget);
      expect(find.byType(UpdateBanner), findsOneWidget);
      // The reporter's screenshot source: the boundary carrying the key the
      // package resolves.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BetaExpiryGate)),
        listen: false,
      );
      final key = container.read(cruxAppScreenshotBoundaryKeyProvider);
      expect(find.byKey(key), findsOneWidget);
    });

    testWidgets('the expiry gate sits OUTSIDE the update banner', (
      tester,
    ) async {
      // Nesting order is load-bearing: an expired-beta modal has to cover the
      // update banner, not sit under it.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...telemetryDeclinedOverrides(),
            ...lintcruxPhase5Overrides(),
            betaExpiryStatusProvider.overrideWithValue(
              BetaExpiryStatus.notApplicable,
            ),
          ],
          child: const LintcruxApp(),
        ),
      );
      await tester.pump();

      final gate = find.byType(BetaExpiryGate);
      final banner = find.byType(UpdateBanner);
      expect(
        find.ancestor(of: banner, matching: gate),
        findsOneWidget,
        reason: 'UpdateBanner must be a descendant of BetaExpiryGate',
      );
    });
  });
}
