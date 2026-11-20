// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_config.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/eula_test_acceptance.dart';
import 'support/fake_path_provider.dart';
import 'support/telemetry_test_store.dart';

/// The desktop app's exports under an educational licence, driven through the
/// real dispatch closure the menu bar, palette and keyboard share: the HTML
/// report closes with the non-commercial mark, and the data formats a tool
/// reads back (SARIF, JSON, CSV) carry nothing. Open core and Pro mark
/// nothing.
void main() {
  useFakePathProvider();

  const mark = 'Made with LintCrux Educational · Non-commercial use only';

  late Directory tempDir;
  late _StubPicker picker;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'lintcrux',
      packageName: 'com.ferrite.lintcrux',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
    tempDir = await Directory.systemTemp.createTemp('lintcrux_edu_export_');
    picker = _StubPicker();
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  CruxLicenseStatus status(LicenseTier tier) => CruxLicenseStatus(
    activation: CruxLicenseActivation.active,
    grant: LicenseGrant(
      issuerId: kEduLicenseIssuerId,
      tier: tier,
      products: const {CruxProduct.lintCrux},
      email: 'student@example.edu',
    ),
  );

  Future<RecordingTelemetryService> boot(
    WidgetTester tester,
    CruxLicenseStatus license,
  ) async {
    final telemetry = RecordingTelemetryService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...lintcruxPhase5Overrides(),
          eulaAcceptedOverride(),
          telemetryServiceProvider.overrideWithValue(telemetry),
          cruxTelemetryConfigProvider.overrideWithValue(
            lintcruxTelemetryConfig,
          ),
          telemetryStorageProvider.overrideWithValue(
            TelemetryTestStore.consented(),
          ),
          workspaceServiceProvider.overrideWithValue(
            WorkspaceService(
              codec: const LintcruxWorkspaceCodec(),
              directoryFactory: () async => tempDir,
            ),
          ),
          projectPickerProvider.overrideWithValue(picker),
          engineRegistryProvider.overrideWithValue(EngineRegistry(const [])),
          cruxCxpRuntimeProvider.overrideWith((_) async => null),
          // The Pro overlay overrides this at the root from its licence
          // service; the export reads it there.
          licenseStatusProvider.overrideWithValue(license),
        ],
        child: const LintcruxApp(),
      ),
    );
    await tester.pumpAndSettle();
    return telemetry;
  }

  /// Dispatches [action] and drives both event loops until [done] holds; the
  /// handlers touch `dart:io`, which the fake-async zone never advances.
  Future<void> dispatchUntil(
    WidgetTester tester,
    LintcruxAction action,
    bool Function() done,
  ) async {
    tester
        .widget<ShortcutManagerWidget>(find.byType(ShortcutManagerWidget))
        .handlers[action]!();
    for (var i = 0; i < 600 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: '${action.name} never completed');
    await tester.pumpAndSettle();
  }

  /// Boots under [license], opens a project, and exports it in every format.
  /// Returns each file's contents by extension.
  Future<Map<String, String>> exportAll(
    WidgetTester tester,
    CruxLicenseStatus license,
  ) async {
    final telemetry = await boot(tester, license);
    final project = p.join(tempDir.path, 'exported.lintcrux');
    File(project).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'name': 'exported',
        'rootPath': tempDir.path,
        'enabledEngineIds': <String>[],
      }),
    );
    picker.projectPath = project;
    await dispatchUntil(
      tester,
      LintcruxAction.openProject,
      () => telemetry.named('project.opened').isNotEmpty,
    );

    final out = <String, String>{};
    for (final (action, ext) in const <(LintcruxAction, String)>[
      (LintcruxAction.exportSarif, 'sarif'),
      (LintcruxAction.exportJson, 'json'),
      (LintcruxAction.exportCsv, 'csv'),
      (LintcruxAction.exportHtml, 'html'),
    ]) {
      picker.exportPath = p.join(tempDir.path, 'out.$ext');
      final before = telemetry.named('export.completed').length;
      await dispatchUntil(
        tester,
        action,
        () => telemetry.named('export.completed').length > before,
      );
      out[ext] = File(picker.exportPath!).readAsStringSync();
    }
    return out;
  }

  testWidgets(
    'EDU: the HTML report carries the mark, the data formats do not',
    (
      tester,
    ) async {
      final out = await exportAll(tester, status(LicenseTier.edu));

      expect(
        out['html'],
        contains('<footer class="lc-edu-mark">$mark</footer>'),
      );
      for (final ext in const ['sarif', 'json', 'csv']) {
        expect(out[ext], isNot(contains('Educational')), reason: ext);
        expect(out[ext], isNot(contains('Non-commercial')), reason: ext);
      }
    },
  );

  for (final (name, license) in <(String, CruxLicenseStatus)>[
    ('open core', CruxLicenseStatus.openCore),
    ('Pro', status(LicenseTier.pro)),
  ]) {
    testWidgets('$name: no export carries a mark', (tester) async {
      final out = await exportAll(tester, license);
      for (final entry in out.entries) {
        expect(entry.value, isNot(contains('<footer')), reason: entry.key);
        expect(entry.value, isNot(contains('Educational')), reason: entry.key);
      }
    });
  }
}

/// A picker that answers the project and export dialogs without showing any.
class _StubPicker extends ProjectPicker {
  String? projectPath;
  String? exportPath;

  @override
  Future<String?> pickProjectFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async => projectPath;

  @override
  Future<String?> pickSaveExportFile({
    required String confirmButtonText,
    required String extension,
    required String label,
    String? defaultFileName,
  }) async => exportPath;
}
