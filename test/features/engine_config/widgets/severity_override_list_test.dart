// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/rule.dart';
import 'package:lintcrux/features/engine_config/widgets/severity_override_list.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/rules/rule_database.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';
import 'package:path/path.dart' as p;

final RuleDatabase _db = RuleDatabase({
  'verilator': const RuleEngineEntry(
    engineId: 'verilator',
    displayName: 'Verilator',
    rules: [
      Rule(id: 'verilator/UNUSEDSIGNAL', defaultSeverity: Severity.warning),
    ],
  ),
});

void main() {
  late Directory tmp;
  late String projectFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_override_list_');
    projectFile = p.join(tmp.path, 'soc.lintcrux');
    File(projectFile).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'name': 'soc',
        'rootPath': '.',
      }),
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final container = ProviderContainer(
      overrides: [ruleDatabaseProvider.overrideWith((_) async => _db)],
    );
    addTearDown(container.dispose);
    container
        .read(currentProjectProvider.notifier)
        .load(
          LintProject(name: 'soc', rootPath: tmp.path),
          projectFilePath: projectFile,
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: const Scaffold(body: SeverityOverrideList()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('choosing a severity saves it to the project file', (
    tester,
  ) async {
    final container = await pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('severityOverride-verilator/UNUSEDSIGNAL')),
    );
    await tester.pumpAndSettle();
    final l10n = L10N.of(tester.element(find.byType(SeverityOverrideList)));
    await tester.tap(find.text(l10n.severityNote).last);
    await tester.pumpAndSettle();

    expect(
      container.read(currentProjectProvider)!.severityOverrides,
      {'verilator/UNUSEDSIGNAL': Severity.note},
    );
    // Wait for the save to finish, not for its bytes to appear: the new
    // contents are readable before the write closes its handle, and Windows
    // refuses to delete a directory holding an open file, so tearDown would
    // fail. Project-file writes are serialized, so an unchanged update
    // queued behind the save completes only once the save has closed. The
    // IO completes on the real event loop; alternate real time with pumps.
    var saved = false;
    unawaited(
      container
          .read(currentProjectProvider.notifier)
          .updateProjectFile((authored) => authored)
          .whenComplete(() => saved = true),
    );
    for (var i = 0; i < 100 && !saved; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(saved, isTrue, reason: 'the save never completed');
    final onDisk =
        jsonDecode(File(projectFile).readAsStringSync())
            as Map<String, dynamic>;
    expect(onDisk['severityOverrides'], {'verilator/UNUSEDSIGNAL': 'note'});
    expect(tester.takeException(), isNull);
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        await pump(tester, locale: locale);
        expect(find.text('verilator/UNUSEDSIGNAL'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
