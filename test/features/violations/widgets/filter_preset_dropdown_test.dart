// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/features/violations/models/saved_filter_presets_state.dart';
import 'package:lintcrux/features/violations/providers/saved_filter_presets_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/widgets/filter_preset_dropdown.dart';
import 'package:lintcrux/features/workspace/providers/tab_overrides_factory.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import '../../../support/telemetry_test_store.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return ProviderScope(
    overrides: telemetryDeclinedOverrides(),
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('FilterPresetDropdown', () {
    testWidgets('renders the label and "None" placeholder when empty', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const FilterPresetDropdown()));
      await tester.pumpAndSettle();
      expect(find.text('Filter preset'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
    });

    testWidgets('renders each saved preset by name', (tester) async {
      const presets = [
        NamedFilterPreset(name: 'WIDTHs', severities: {Severity.error}),
        NamedFilterPreset(name: 'Verilator-only'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...telemetryDeclinedOverrides(),
            savedFilterPresetsProvider.overrideWith(() {
              return _SeededNotifier()
                ..seed = const SavedFilterPresetsState(presets: presets);
            }),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: FilterPresetDropdown()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Open the dropdown to render every item.
      await tester.tap(find.byKey(const ValueKey('filterPresetDropdown')));
      await tester.pumpAndSettle();
      expect(find.text('WIDTHs'), findsWidgets);
      expect(find.text('Verilator-only'), findsWidgets);
      // Save / manage entries are always present.
      expect(find.text('Save current filters as preset…'), findsOneWidget);
      expect(find.text('Manage presets…'), findsOneWidget);
    });

    testWidgets(
      'selecting a saved preset activates it: the dropdown value updates '
      'and the violation table state is overlaid from the preset',
      (tester) async {
        const presets = [
          NamedFilterPreset(
            name: 'Errors only',
            severities: {Severity.error},
            ruleSubstring: 'UNUSED',
          ),
        ];
        final container = ProviderContainer(
          overrides: [
            ...telemetryDeclinedOverrides(),
            savedFilterPresetsProvider.overrideWith(() {
              return _SeededNotifier()
                ..seed = const SavedFilterPresetsState(presets: presets);
            }),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: FilterPresetDropdown()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('filterPresetDropdown')));
        await tester.pumpAndSettle();
        // Two matches expected: one in the closed dropdown button (button
        // child) is not present yet since nothing is active, so the menu
        // item is the only occurrence.
        await tester.tap(find.text('Errors only').last);
        await tester.pumpAndSettle();

        expect(
          container.read(savedFilterPresetsProvider).activePresetName,
          'Errors only',
        );
        expect(
          container.read(violationTableStateProvider).severities,
          {Severity.error},
        );
        expect(
          container.read(violationTableStateProvider).ruleSubstring,
          'UNUSED',
        );
        // The dropdown's closed-state button now shows the active name.
        expect(find.text('Errors only'), findsOneWidget);
      },
    );

    testWidgets(
      'selecting "Save current filters as preset…" opens a dialog; '
      'submitting a name saves and activates a new preset from the '
      'current table state',
      (tester) async {
        final container = ProviderContainer(
          overrides: telemetryDeclinedOverrides(),
        );
        addTearDown(container.dispose);
        container.read(violationTableStateProvider.notifier)
          ..toggleSeverity(Severity.fatal)
          ..setFileGlob('*.sv');

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: FilterPresetDropdown()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('filterPresetDropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save current filters as preset…'));
        await tester.pumpAndSettle();

        expect(find.text('Save filter preset'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'My preset');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final state = container.read(savedFilterPresetsProvider);
        expect(state.activePresetName, 'My preset');
        expect(state.presets, hasLength(1));
        final saved = state.presets.single;
        expect(saved.name, 'My preset');
        expect(saved.severities, {Severity.fatal});
        expect(saved.fileGlob, '*.sv');
      },
    );

    testWidgets(
      'cancelling the save dialog does not create a preset',
      (tester) async {
        final container = ProviderContainer(
          overrides: telemetryDeclinedOverrides(),
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: FilterPresetDropdown()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('filterPresetDropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save current filters as preset…'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(container.read(savedFilterPresetsProvider).presets, isEmpty);
      },
    );

    testWidgets(
      'opening "Manage presets…" with an empty list shows the empty-state '
      'message; with presets it lists each and deletes on tap',
      (tester) async {
        const presets = [
          NamedFilterPreset(name: 'Alpha'),
          NamedFilterPreset(name: 'Beta'),
        ];
        final container = ProviderContainer(
          overrides: [
            ...telemetryDeclinedOverrides(),
            savedFilterPresetsProvider.overrideWith(() {
              return _SeededNotifier()
                ..seed = const SavedFilterPresetsState(presets: presets);
            }),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: FilterPresetDropdown()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('filterPresetDropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manage presets…'));
        await tester.pumpAndSettle();

        expect(find.text('Manage filter presets'), findsOneWidget);
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);

        // Delete "Alpha" via its row's trailing delete icon.
        final alphaRow = find.ancestor(
          of: find.text('Alpha'),
          matching: find.byType(ListTile),
        );
        await tester.tap(
          find.descendant(
            of: alphaRow,
            matching: find.byIcon(Icons.delete_outline),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(savedFilterPresetsProvider).presets.map((p) => p.name),
          ['Beta'],
        );
        expect(find.text('Alpha'), findsNothing);
        expect(find.text('Beta'), findsOneWidget);
      },
    );

    testWidgets(
      'the manage dialog shows the empty-state message with no presets',
      (tester) async {
        await tester.pumpWidget(_wrap(const FilterPresetDropdown()));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('filterPresetDropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manage presets…'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            "No saved presets yet. Configure filters and choose 'Save "
            "current filters as preset…' to add one.",
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Manage filter presets'), findsNothing);
      },
    );

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exception in locale $locale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(const FilterPresetDropdown(), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ==========================================================================
  // ROUTE-MOUNTED PER-TAB SCOPE LEAK (crux-shared route_mounted_scope_leak_test)
  // ==========================================================================
  //
  // Every test above pumps a SINGLE `ProviderScope`, so the dropdown and the
  // dialog it pushes share one container and the defect below is invisible.
  // This group builds the REAL two-container shape: a root container, a
  // per-tab child produced by the same `TabContainerManager` the app uses,
  // the `MaterialApp` (and therefore the Navigator dialogs are pushed onto)
  // at ROOT, and the dropdown inside the tab's `UncontrolledProviderScope`.
  group('manage dialog resolves the ACTIVE TAB container, not the root', () {
    testWidgets("lists the tab's presets, not the root's empty list", (
      tester,
    ) async {
      final paneId = crux.PaneId.generate();
      final tabId = crux.TabId.generate();
      final workspace = Workspace(
        tabs: [
          WorkspaceTab(
            id: tabId,
            displayName: 'demo',
            paneId: paneId,
            payload: const LintcruxTabPayload(
              projectPath: '/proj/demo.lintcrux',
            ),
          ),
        ],
        panes: [crux.WorkspacePane(id: paneId, activeTabId: tabId)],
        activePaneId: paneId,
      );

      final root = ProviderContainer(
        overrides: [
          ...telemetryDeclinedOverrides(),
          workspaceProvider.overrideWith(
            () => _SeededWorkspaceNotifier(workspace),
          ),
        ],
      );
      addTearDown(root.dispose);
      await root.read(workspaceProvider.future);

      final tabs = crux.TabContainerManager(
        rootContainer: root,
        overridesFactory: lintcruxTabOverridesFactory,
      );
      addTearDown(tabs.dispose);
      final panes = crux.PaneContainerManager(rootContainer: root);
      addTearDown(panes.dispose);
      final tabContainer = tabs.containerFor(tabId);

      // Seed the preset in the TAB container only. The root container's
      // `savedFilterPresetsProvider` stays empty — exactly as it is in the
      // real app, where nothing ever writes presets at root scope.
      tabContainer
          .read(savedFilterPresetsProvider.notifier)
          .save(const NamedFilterPreset(name: 'TabOnly'));
      expect(root.read(savedFilterPresetsProvider).presets, isEmpty);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: root,
          child: MaterialApp(
            localizationsDelegates: const [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: WorkspaceRootScope(
              tabs: tabs,
              panes: panes,
              child: Scaffold(
                body: UncontrolledProviderScope(
                  container: tabContainer,
                  child: const FilterPresetDropdown(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('filterPresetDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage presets…'));
      await tester.pumpAndSettle();

      // Mutation-verified: drop `wrapInActiveTabScope` from
      // `_showManageDialog` and this fails with the dialog showing the
      // empty state instead of the tab's preset.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('TabOnly'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('No saved presets yet.'),
        findsNothing,
      );

      // The delete affordance must write to the TAB notifier too.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(tabContainer.read(savedFilterPresetsProvider).presets, isEmpty);
    });
  });
}

/// Workspace notifier stub returning a fixed, already-hydrated document so
/// `activeTabContainerOf` can resolve an active tab without touching disk.
class _SeededWorkspaceNotifier extends LintcruxWorkspaceNotifier {
  _SeededWorkspaceNotifier(this._seed);

  final Workspace _seed;

  @override
  Future<Workspace> build() async => _seed;
}

class _SeededNotifier extends SavedFilterPresetsNotifier {
  SavedFilterPresetsState seed = SavedFilterPresetsState.empty;

  @override
  SavedFilterPresetsState build() => seed;
}
