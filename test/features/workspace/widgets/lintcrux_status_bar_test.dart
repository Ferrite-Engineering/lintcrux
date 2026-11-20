// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/providers/waived_violation_count_provider.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_edu_status_chip.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_status_bar.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

class _StubProject extends CurrentProjectNotifier {
  _StubProject(this._project);
  final LintProject? _project;
  @override
  LintProject? build() => _project;
}

class _StubVisible extends VisibleViolationsNotifier {
  _StubVisible(this._list);
  final List<Violation> _list;
  @override
  List<Violation> build() => _list;
}

class _StubWaived extends WaivedViolationCountNotifier {
  @override
  int build() => 0;
}

class _StubRun extends LintRunNotifier {
  _StubRun({required this.running});
  final bool running;
  @override
  LintRunState build() => LintRunState(isRunning: running);
}

/// How many violations [_DerivedVisible] derives. Changing it leaves the
/// visible list due a rebuild that Riverpod flushes from a scope's `build`,
/// which is how the real list changes when a project or filter changes.
final _derivedCount = NotifierProvider<_Count, int>(_Count.new);

class _Count extends Notifier<int> {
  @override
  int build() => 0;

  // A setter reads worse here: the tests call it like the notifier method it
  // stands in for.
  // ignore: use_setters_to_change_properties
  void set(int value) => state = value;
}

class _DerivedVisible extends VisibleViolationsNotifier {
  @override
  List<Violation> build() =>
      List<Violation>.filled(ref.watch(_derivedCount), _warning);
}

const _warning = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'unused',
  location: SourceLocation(file: '/w/top.sv', line: 1, column: 1),
);

/// [body] under a root scope, the way the workspace mounts the bar: the tab
/// containers below are separate, and the licence is read from this root.
Widget _app(Widget body, {CruxLicenseStatus? license}) {
  return ProviderScope(
    overrides: [
      if (license != null) licenseStatusProvider.overrideWithValue(license),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: body),
    ),
  );
}

CruxLicenseStatus _license(LicenseTier tier) => CruxLicenseStatus(
  activation: CruxLicenseActivation.active,
  grant: LicenseGrant(
    issuerId: kEduLicenseIssuerId,
    tier: tier,
    products: const {CruxProduct.lintCrux},
    licenseId: 'lic-1',
    email: 'student@example.edu',
    expiry: DateTime.utc(2027, 8, 2, 12),
  ),
);

ProviderContainer _tabContainer({String projectName = 'demo_soc'}) {
  return ProviderContainer.test(
    overrides: [
      currentProjectProvider.overrideWith(
        () => _StubProject(LintProject(name: projectName, rootPath: '/w')),
      ),
      visibleViolationsProvider.overrideWith(_DerivedVisible.new),
      waivedViolationCountProvider.overrideWith(_StubWaived.new),
      lintRunProvider.overrideWith(() => _StubRun(running: false)),
    ],
  );
}

Widget _harness({
  LintProject? project,
  List<Violation> violations = const <Violation>[],
  bool running = false,
  Locale? locale,
  CruxLicenseStatus? license,
}) {
  return ProviderScope(
    overrides: [
      if (license != null) licenseStatusProvider.overrideWithValue(license),
      currentProjectProvider.overrideWith(() => _StubProject(project)),
      visibleViolationsProvider.overrideWith(() => _StubVisible(violations)),
      waivedViolationCountProvider.overrideWith(_StubWaived.new),
      lintRunProvider.overrideWith(() => _StubRun(running: running)),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(
        body: Column(children: <Widget>[Spacer(), LintcruxStatusBarBody()]),
      ),
    ),
  );
}

void main() {
  group('LintcruxStatusBar', () {
    testWidgets('mounts the shared CruxStatusBar with the violation summary', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      // Mounts on the shared cross-suite chrome.
      expect(find.byType(CruxStatusBar), findsOneWidget);
      // Live violation summary segment (existing violationStatusSummary key).
      expect(
        find.text('0 total · 0 errors · 0 warnings · 0 notes · 0 waived'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the project name and a run spinner while running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          project: const LintProject(name: 'demo_soc', rootPath: '/w/demo'),
          running: true,
        ),
      );
      await tester.pump();

      expect(find.byType(CruxStatusBar), findsOneWidget);
      expect(find.text('demo_soc'), findsOneWidget);
      expect(find.byType(CruxStatusBusyIndicator), findsOneWidget);
    });

    testWidgets('the no-tab bar says so rather than rendering blank', (
      tester,
    ) async {
      // `LintcruxStatusBar` (the outer widget) resolves no active-tab
      // container outside a workspace, which is the empty-canvas path. It used
      // to render a bare `CruxStatusBar()` — a 24 dp strip of nothing — while
      // NetCrux showed "No design loaded" in the same state.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: LintcruxStatusBar()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CruxStatusBar), findsOneWidget);
      expect(find.text('No project open'), findsOneWidget);
    });

    // Both bars name their region the way every product in the suite does,
    // so a screen reader entering the bottom of the window hears "Status bar".
    testWidgets('the tab bar carries the "Status bar" region label', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(
        tester.widget<CruxStatusBar>(find.byType(CruxStatusBar)).semanticsLabel,
        'Status bar',
      );
    });

    testWidgets('the no-tab bar carries the "Status bar" region label', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: LintcruxStatusBar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CruxStatusBar>(find.byType(CruxStatusBar)).semanticsLabel,
        'Status bar',
      );
    });

    // The status bar is the suite's densest single row of text — a project
    // name, a five-part violation summary and a run indicator sharing one
    // line — which makes it the first place a longer CJK rendering overflows.
    // Additive: renders in every supported locale and asserts nothing throws,
    // without touching the assertions above, which are en-specific by design.
    for (final locale in L10N.supportedLocales) {
      testWidgets('renders without exceptions in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(locale: locale),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(CruxStatusBar), findsOneWidget);
      });
    }
  });

  group('LintcruxTabStatusBar', () {
    testWidgets('shows the tab container it is bound to', (tester) async {
      final container = _tabContainer();
      container.read(_derivedCount.notifier).set(3);

      await tester.pumpWidget(_app(LintcruxTabStatusBar(container: container)));
      await tester.pump();

      expect(find.text('demo_soc'), findsOneWidget);
      expect(
        find.text('3 total · 0 errors · 3 warnings · 0 notes · 0 waived'),
        findsOneWidget,
      );
    });

    // The tab's content mounts its own scope for the tab container. The bar
    // used to mount a second one; Riverpod flushes a container from inside
    // each of its scopes' builds, so whichever of the two built first
    // notified the other's widgets mid-build and tripped Flutter's
    // "setState() or markNeedsBuild() called during build" assertion. On CI
    // that failed "Open Workspace… skips a tab whose project file is
    // missing"; in the app it fired whenever a tab's violations changed.
    testWidgets('shares the tab container with the tab content without '
        'marking it dirty mid-build', (tester) async {
      final container = _tabContainer();

      await tester.pumpWidget(
        _app(
          Column(
            children: [
              Expanded(
                child: UncontrolledProviderScope(
                  container: container,
                  child: Consumer(
                    builder: (context, ref, _) => Text(
                      '${ref.watch(visibleViolationsProvider).length} rows',
                    ),
                  ),
                ),
              ),
              LintcruxTabStatusBar(container: container),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('0 rows'), findsOneWidget);

      container.read(_derivedCount.notifier).set(2);
      // No duration: the frame builds before the zero-delay timers Riverpod
      // also arms, so the pending rebuild is flushed from inside the tab
      // scope's build — the path the assertion fires on.
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('2 rows'), findsOneWidget);
      expect(
        find.text('2 total · 0 errors · 2 warnings · 0 notes · 0 waived'),
        findsOneWidget,
      );
    });

    testWidgets('follows a switch to another tab container', (tester) async {
      final first = _tabContainer(projectName: 'alpha');
      final second = _tabContainer(projectName: 'beta');

      await tester.pumpWidget(_app(LintcruxTabStatusBar(container: first)));
      await tester.pump();
      expect(find.text('alpha'), findsOneWidget);

      await tester.pumpWidget(_app(LintcruxTabStatusBar(container: second)));
      await tester.pump();
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);

      // The first tab's changes no longer reach the bar.
      first.read(_derivedCount.notifier).set(5);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('5 total'), findsNothing);
    });
  });
  // An educational licence says so at the right end of every bar: the tab
  // bar, the no-tab bar, and the body the imported-report window mounts. The
  // paid tiers and open core get nothing there.
  group('educational licence', () {
    const label = 'Non-commercial use · student@example.edu';

    testWidgets('the body shows the chip, last in the trailing slot', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(license: _license(LicenseTier.edu)));
      await tester.pump();

      expect(find.text(label), findsOneWidget);
      final bar = tester.widget<CruxStatusBar>(find.byType(CruxStatusBar));
      expect(bar.trailing.last, isA<LintcruxEduStatusChip>());
      expect(tester.takeException(), isNull);
    });

    for (final (name, license) in <(String, CruxLicenseStatus)>[
      ('open core', CruxLicenseStatus.openCore),
      ('Pro', _license(LicenseTier.pro)),
      ('Enterprise', _license(LicenseTier.enterprise)),
    ]) {
      testWidgets('the body shows nothing at $name', (tester) async {
        await tester.pumpWidget(_harness(license: license));
        await tester.pump();

        expect(find.textContaining('Non-commercial'), findsNothing);
        expect(find.byType(EditionBadge), findsNothing);
      });
    }

    testWidgets('the no-tab bar shows the chip', (tester) async {
      await tester.pumpWidget(
        _app(const LintcruxStatusBar(), license: _license(LicenseTier.edu)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No project open'), findsOneWidget);
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('the tab bar reads the licence from the root scope, not the '
        'tab container', (tester) async {
      // The tab container overrides no licence; the Pro overlay overrides it
      // at the root, and the bar is mounted there.
      final container = _tabContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _app(
          LintcruxTabStatusBar(container: container),
          license: _license(LicenseTier.edu),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('demo_soc'), findsOneWidget);
      expect(find.text(label), findsOneWidget);
    });

    for (final locale in L10N.supportedLocales) {
      testWidgets('fits the bar in ${locale.toLanguageTag()}', (tester) async {
        await tester.pumpWidget(
          _harness(
            project: const LintProject(name: 'demo_soc', rootPath: '/w'),
            running: true,
            locale: locale,
            license: _license(LicenseTier.edu),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('student@example.edu'), findsOneWidget);
      });
    }
  });
}
