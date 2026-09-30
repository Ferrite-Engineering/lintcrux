// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_row.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/violation_context_menu_provider.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/shared/widgets/lintcrux_feature_tier_badge.dart';

import '../../../support/host_independent_editor_resolver.dart';

Violation _v() => const Violation(
  engineId: 'verilator',
  ruleId: 'verilator/WIDTH',
  severity: Severity.warning,
  message: 'width mismatch',
  location: SourceLocation(file: '/x/y.sv', line: 3, column: 1),
);

/// One open-core entry (no badge) and one Pro entry (tier-badged), so the
/// per-entry badge rendering can be asserted both ways.
List<ViolationContextMenuEntry> _entries() => <ViolationContextMenuEntry>[
  ViolationContextMenuEntry(
    id: 'test.core',
    labelBuilder: (_) => 'Copy rule id',
    onActivate: (_, _, _) {},
  ),
  ViolationContextMenuEntry(
    id: 'test.pro',
    labelBuilder: (_) => 'Waive',
    requiredTier: LicenseTier.pro,
    onActivate: (_, _, _) {},
  ),
];

/// Records the argv click-to-source was asked to spawn, so the
/// double-click path can be asserted without launching a real editor.
class _RecordingLauncher implements EditorLauncher {
  final List<List<String>> launches = <List<String>>[];

  @override
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    launches.add(<String>[executable, ...arguments]);
    throw const ProcessException('fake', <String>[], 'not launched');
  }
}

/// Lets the double-tap recognizer's pending trackers expire so the
/// binding's end-of-test "no pending timers" invariant holds. Tests that
/// assert on the FIRST frame after a tap deliberately do not advance the
/// clock themselves — that is the regression being pinned.
Future<void> _drainTapTimers(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + kDoubleTapMinTime);

Widget _harness({
  required TargetPlatform platform,
  Locale locale = const Locale('en'),
  List<ViolationContextMenuEntry>? entries,
  EditorLauncher? launcher,
}) {
  return ProviderScope(
    overrides: [
      violationContextMenuEntriesProvider.overrideWithValue(
        entries ?? _entries(),
      ),
      if (launcher != null)
        clickToSourceServiceProvider.overrideWithValue(
          ClickToSourceService(
            commandFor: () => EditorCommand.defaultPreset,
            launcher: launcher,
            resolver: hostIndependentEditorResolver,
          ),
        ),
    ],
    child: MaterialApp(
      locale: locale,
      // PlatformContextMenu reads Theme.of(context).platform to decide
      // whether long-press should fire the menu.
      theme: ThemeData(platform: platform),
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            child: ViolationTableRow(violation: _v()),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ViolationTableRow left-click selection', () {
    // Regression guard for the 2026-07-16 beta bug "left-click on a
    // violation row does not select it". Selection used to hang off
    // `GestureDetector.onTap`, which cannot fire until the tap recognizer
    // wins the gesture arena — and the sibling `onDoubleTap` keeps that
    // arena open for the whole `kDoubleTapTimeout`. Only pumping a single
    // frame after the tap (no artificial 300 ms advance) is exactly the
    // condition the old wiring failed under.
    testWidgets('a single left-click selects the row immediately', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ViolationTableRow)),
      );
      expect(container.read(selectedViolationProvider), isNull);

      await tester.tap(find.byType(ViolationTableRow));
      await tester.pump();

      expect(container.read(selectedViolationProvider), _v());
      await _drainTapTimers(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the click highlight paints on the first frame after the tap', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();
      final scheme = Theme.of(
        tester.element(find.byType(ViolationTableRow)),
      ).colorScheme;
      // The row background, not the keyboard focus ring drawn over it.
      BoxDecoration decoration() =>
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byType(ViolationTableRow),
                      matching: find.byKey(
                        const ValueKey('violationRowBackground'),
                      ),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration().color, isNull);

      await tester.tap(find.byType(ViolationTableRow));
      await tester.pump();

      expect(decoration().color, scheme.primaryContainer);
      await _drainTapTimers(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every body cell selects, including the tooltipped message', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ViolationTableRow)),
      );
      for (final cell in const <String>[
        'verilator',
        'verilator/WIDTH',
        '/x/y.sv',
        '3',
        'width mismatch',
      ]) {
        container.read(selectedViolationProvider.notifier).clear();
        await tester.pump();
        await tester.tap(find.text(cell).first);
        await tester.pump();
        expect(
          container.read(selectedViolationProvider),
          _v(),
          reason: 'clicking the "$cell" cell must select the row',
        );
        await _drainTapTimers(tester);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('double-click selects the row AND opens the editor', (
      tester,
    ) async {
      final launcher = _RecordingLauncher();
      await tester.pumpWidget(
        _harness(platform: TargetPlatform.macOS, launcher: launcher),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ViolationTableRow)),
      );

      final center = tester.getCenter(find.byType(ViolationTableRow));
      await tester.tapAt(center);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(container.read(selectedViolationProvider), _v());
      expect(launcher.launches, hasLength(1));
      expect(launcher.launches.single.join(' '), contains('/x/y.sv'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('right-click still selects the row', (tester) async {
      await tester.pumpWidget(_harness(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ViolationTableRow)),
      );

      await tester.tap(
        find.byType(ViolationTableRow),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(container.read(selectedViolationProvider), _v());
      expect(tester.takeException(), isNull);
    });

    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('selects on left-click in $locale', (tester) async {
        await tester.pumpWidget(
          _harness(platform: TargetPlatform.macOS, locale: locale),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ViolationTableRow)),
        );

        await tester.tap(find.byType(ViolationTableRow));
        await tester.pump();

        expect(container.read(selectedViolationProvider), _v());
        await _drainTapTimers(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ViolationTableRow context menu', () {
    testWidgets('opens on right-click and badges only the Pro entry', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(ViolationTableRow),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Copy rule id'), findsOneWidget);
      expect(find.text('Waive'), findsOneWidget);
      // Only the Pro entry carries a tier badge; the open-core entry does
      // not (requiredTier == openCore suppresses the badge).
      expect(find.byType(LintCruxFeatureTierBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens on long-press on a touch host', (tester) async {
      await tester.pumpWidget(_harness(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(ViolationTableRow));
      await tester.pumpAndSettle();

      expect(find.text('Waive'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop long-press does not open the menu (no 500ms delay)', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(ViolationTableRow));
      await tester.pumpAndSettle();

      // On a desktop host the wrapper wires right-click only, so long-press
      // is inert — the context menu never opens.
      expect(find.text('Waive'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty entry list opens no menu', (tester) async {
      await tester.pumpWidget(
        _harness(
          platform: TargetPlatform.macOS,
          entries: const <ViolationContextMenuEntry>[],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(ViolationTableRow),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders the menu without exceptions in $locale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(platform: TargetPlatform.macOS, locale: locale),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byType(ViolationTableRow),
          buttons: kSecondaryButton,
        );
        await tester.pumpAndSettle();

        expect(find.byType(LintCruxFeatureTierBadge), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
