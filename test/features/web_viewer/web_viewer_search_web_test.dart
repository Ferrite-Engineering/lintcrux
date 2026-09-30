// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_args_provider.dart';
import 'package:lintcrux/core/router/app_router.dart';
import 'package:lintcrux/core/theme/lintcrux_color_theme_bootstrap.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/search/widgets/search_dialog.dart';
import 'package:lintcrux/features/telemetry/lintcrux_telemetry_overrides.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/web_viewer/screens/web_landing_screen.dart';
import 'package:lintcrux/features/web_viewer/screens/web_viewer_screen.dart';
import 'package:lintcrux/services/rules/rule_database.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/eula_test_acceptance.dart';
import '../../support/telemetry_test_store.dart';

/// Find in Violations (Cmd/Ctrl+F) in the browser viewer.
///
/// Runs in a real browser (`tool/run_web_tests.sh`), because the web branch
/// of the app — its router, its missing `WorkspaceRoot`, the search dispatch
/// — only exists when `kIsWeb` is true; the VM suite cannot reach it. The app
/// is booted with the overrides `bootstrap` installs on the web, a report is
/// put where the SARIF loader puts one (the root violation store), and the
/// shortcut is pressed as a key chord rather than called.
Violation _make(String rule, int line) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/$rule',
  severity: Severity.warning,
  message: 'msg for $rule',
  location: SourceLocation(file: '/rtl/top.sv', line: line, column: 1),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'lintcrux',
      packageName: 'com.ferrite.lintcrux',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
  });

  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          cliArgsProvider.overrideWithValue(CliArgs.empty),
          ...lintcruxPhase5Overrides(),
          // Past the beta a first visit gets the usage-statistics disclosure
          // over the viewer. This test is about search in a viewer the user
          // has already reached, so it starts from an installation that
          // answered no, the way it seeds EULA acceptance below. The
          // disclosure's own behaviour is tested in crux_telemetry.
          for (final override in lintcruxTelemetryOverrides)
            if (override.origin != telemetryStorageProvider) override,
          telemetryStorageProvider.overrideWithValue(
            TelemetryTestStore.declined(),
          ),
          // This boots the app WITHOUT `lintcruxEulaOverrides`, so
          // `cruxEulaStorageProvider` would be the package's in-memory
          // default and `CruxEulaGate` would mount its blocking modal over
          // the viewer. The symptom is not an obvious "the agreement is in
          // the way": the tree is still there and the shortcut still opens
          // the dialog, so only the tap fails, on a barrier. The gate has its
          // own tests in `crux_eula`, and
          // `test/static/eula_gate_reachability_test.dart` is what stops this
          // seed hiding an un-mounted gate.
          eulaAcceptedOverride(),
          lintcruxCruxColorThemeOverride,
          // The rule browser spins until its database loads, and the JSON
          // assets it reads never arrive under the browser test runner. The
          // rules are not what this test is about.
          ruleDatabaseProvider.overrideWith(
            (ref) async => RuleDatabase(<String, RuleEngineEntry>{}),
          ),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(LintcruxApp)),
    );
  }

  Future<void> openViewerWithReport(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    container.read(violationStoreProvider).replaceFromEngine('verilator', [
      _make('UNUSEDSIGNAL', 3),
      _make('WIDTHTRUNC', 9),
    ]);
    container.read(appRouterProvider).go('/web/viewer');
    await tester.pumpAndSettle();
    expect(find.byType(WebViewerScreen), findsOneWidget);
  }

  Future<void> pressFind(WidgetTester tester) async {
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('Cmd/Ctrl+F on the viewer searches the loaded report', (
    tester,
  ) async {
    final container = await boot(tester);
    await openViewerWithReport(tester, container);

    await pressFind(tester);
    expect(find.byType(SearchDialog), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('searchDialogInput')),
      'UNUSED',
    );
    // Past the dialog's input debounce.
    await tester.pump(const Duration(milliseconds: 250));
    final hit = find.descendant(
      of: find.byType(SearchDialog),
      matching: find.text('verilator/UNUSEDSIGNAL'),
    );
    expect(hit, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SearchDialog),
        matching: find.text('verilator/WIDTHTRUNC'),
      ),
      findsNothing,
    );

    await tester.tap(hit);
    await tester.pumpAndSettle();
    expect(find.byType(SearchDialog), findsNothing);
    expect(
      container.read(selectedViolationProvider)?.ruleId,
      'verilator/UNUSEDSIGNAL',
    );
  });

  testWidgets('Cmd/Ctrl+F on the landing screen opens nothing', (
    tester,
  ) async {
    await boot(tester);
    expect(find.byType(WebLandingScreen), findsOneWidget);

    await pressFind(tester);
    expect(find.byType(SearchDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
