// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/widgets/settings_engines_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget coverage for [SettingsEnginesSection] — the Settings → Engines
/// section: per-engine binary-source segmented buttons, the custom-path
/// field + live probe (success / not-detected / thrown error), settings
/// persistence, and the standard locale sweep.
/// (`settings_screen_test.dart` only exercises the General / Appearance /
/// Editors rails; this file owns the Engines content.)
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget wrap(
    Widget child, {
    Locale locale = const Locale('en'),
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
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

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(SettingsEnginesSection)));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(SettingsEnginesSection)),
      );

  Override registryWith(LintEngine engine) =>
      engineRegistryProvider.overrideWithValue(EngineRegistry([engine]));

  /// Switches the fake engine's row to the Custom source and reveals the
  /// path field + probe button.
  Future<void> switchToCustom(WidgetTester tester) async {
    await tester.tap(find.text(l10nOf(tester).engineConfigBinarySourceCustom));
    await tester.pump();
  }

  group('SettingsEnginesSection', () {
    testWidgets(
      'renders the binary-overrides header and one row per registered '
      'engine with the three source choices',
      (tester) async {
        await tester.pumpWidget(wrap(const SettingsEnginesSection()));
        await tester.pump();
        final l10n = l10nOf(tester);
        expect(
          find.text(l10n.engineConfigBinaryOverridesHeader),
          findsOneWidget,
        );
        // The default registry ships seven open-core engines and six
        // binaries; each binary row renders the engine display name plus the
        // segmented choices.
        //
        // CDC has no row: it has no binary of its own — it runs yosys, the
        // binary the Yosys check row configures — so a CDC row would offer a
        // path nothing reads.
        expect(find.text('Verilator'), findsOneWidget);
        expect(find.text('Verible'), findsOneWidget);
        expect(find.text('Slang'), findsOneWidget);
        expect(find.text('Yosys check'), findsOneWidget);
        expect(find.text('CDC'), findsNothing);
        expect(
          find.text(l10n.engineConfigBinarySourceAuto),
          findsNWidgets(6),
        );
        expect(
          find.text(l10n.engineConfigBinarySourceBundled),
          findsNWidgets(6),
        );
        expect(
          find.text(l10n.engineConfigBinarySourceCustom),
          findsNWidgets(6),
        );
        // Regression: the severity-override list at the bottom of the
        // card must lay out inside the section's unbounded scrollable
        // once the rule database resolves (its Expanded used to throw
        // RenderFlex-unbounded here and blank the whole section).
        await tester.pump();
        expect(
          find.text(l10n.engineConfigSeverityOverridesHeader),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'selecting Custom reveals the path field and persists the override',
      (tester) async {
        final engine = _FakeEngine();
        await tester.pumpWidget(
          wrap(
            const SettingsEnginesSection(),
            overrides: [registryWith(engine)],
          ),
        );
        await tester.pump();
        final l10n = l10nOf(tester);
        expect(find.text(l10n.engineConfigBinaryPathLabel), findsNothing);

        await switchToCustom(tester);
        expect(find.text(l10n.engineConfigBinaryPathLabel), findsOneWidget);
        expect(find.text(l10n.engineConfigBinaryProbeButton), findsOneWidget);
        expect(
          containerOf(
            tester,
          ).read(appSettingsProvider).engineBinaryOverrideFor(engine.id).source,
          EngineBinarySource.custom,
        );
      },
    );

    testWidgets(
      'probing a custom path persists the path and surfaces the detected '
      'version',
      (tester) async {
        final engine = _FakeEngine();
        await tester.pumpWidget(
          wrap(
            const SettingsEnginesSection(),
            overrides: [registryWith(engine)],
          ),
        );
        await tester.pump();
        await switchToCustom(tester);

        await tester.enterText(find.byType(TextField), '/opt/fake/bin/fake');
        await tester.tap(
          find.text(l10nOf(tester).engineConfigBinaryProbeButton),
        );
        await tester.pump();
        await tester.pump();

        expect(engine.probedConfigs, hasLength(1));
        expect(
          find.text(l10nOf(tester).engineConfigBinaryProbeSuccess('5.020')),
          findsOneWidget,
        );
        final persisted = containerOf(
          tester,
        ).read(appSettingsProvider).engineBinaryOverrideFor(engine.id);
        expect(persisted.source, EngineBinarySource.custom);
        expect(persisted.path, '/opt/fake/bin/fake');
      },
    );

    testWidgets('an undetected binary surfaces the probe-failure hint', (
      tester,
    ) async {
      final engine = _FakeEngine(version: null);
      await tester.pumpWidget(
        wrap(
          const SettingsEnginesSection(),
          overrides: [registryWith(engine)],
        ),
      );
      await tester.pump();
      await switchToCustom(tester);

      await tester.tap(find.text(l10nOf(tester).engineConfigBinaryProbeButton));
      await tester.pump();
      await tester.pump();

      expect(
        find.text(l10nOf(tester).engineConfigBinaryProbeFailure),
        findsOneWidget,
      );
    });

    testWidgets('a probe that throws surfaces the thrown error text', (
      tester,
    ) async {
      final engine = _FakeEngine(throwOnDetect: true);
      await tester.pumpWidget(
        wrap(
          const SettingsEnginesSection(),
          overrides: [registryWith(engine)],
        ),
      );
      await tester.pump();
      await switchToCustom(tester);

      await tester.tap(find.text(l10nOf(tester).engineConfigBinaryProbeButton));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('probe exploded'), findsOneWidget);
    });
  });

  group('SettingsEnginesSection locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders localized chrome without exceptions in $locale', (
        tester,
      ) async {
        final engine = _FakeEngine();
        await tester.pumpWidget(
          wrap(
            const SettingsEnginesSection(),
            locale: locale,
            overrides: [registryWith(engine)],
          ),
        );
        await tester.pump();
        final l10n = l10nOf(tester);
        expect(
          find.text(l10n.engineConfigBinaryOverridesHeader),
          findsOneWidget,
        );
        expect(find.text(l10n.engineConfigBinarySourceAuto), findsOneWidget);
        expect(find.text(l10n.engineConfigBinarySourceBundled), findsOneWidget);
        expect(find.text(l10n.engineConfigBinarySourceCustom), findsOneWidget);

        await switchToCustom(tester);
        expect(find.text(l10n.engineConfigBinaryPathLabel), findsOneWidget);
        expect(find.text(l10n.engineConfigBinaryProbeButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Deterministic [LintEngine] double for the probe flows.
class _FakeEngine extends LintEngine {
  _FakeEngine({this.version = '5.020', this.throwOnDetect = false});

  final String? version;
  final bool throwOnDetect;
  final List<EngineBinaryConfig> probedConfigs = [];

  @override
  String get id => 'fakeengine';

  @override
  String get displayName => 'Fake Engine';

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async {
    probedConfigs.add(config);
    if (throwOnDetect) throw StateError('probe exploded');
    return version;
  }

  @override
  Stream<Violation> run(LintRunRequest request) =>
      const Stream<Violation>.empty();

  @override
  void cancel() {}

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
}
