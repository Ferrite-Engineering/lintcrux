// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/rohd_dart_source.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/inspector/widgets/rohd_dart_source_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';

import '../../../support/host_independent_editor_resolver.dart';

class _Launcher implements EditorLauncher {
  final List<RenderedEditorCommand> launched = [];

  @override
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    launched.add(
      RenderedEditorCommand(executable: executable, arguments: arguments),
    );
    throw ProcessException(executable, arguments, 'recorded');
  }
}

Violation _violation({RohdDartSource? source}) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'unused',
  location: const SourceLocation(file: '/p/top.sv', line: 54, column: 1),
  raw: {if (source != null) RohdDartSource.rawKey: source.toJson()},
);

const RohdDartSource _exact = RohdDartSource(
  primary: RohdDartLocation(file: '/p/lib/design.dart', line: 21, column: 29),
  kind: RohdDartSourceKind.exact,
  calledFrom: [
    RohdDartLocation(file: '/p/lib/design.dart', line: 58, column: 19),
  ],
);

Future<_Launcher> _pump(
  WidgetTester tester,
  Violation v, {
  Locale locale = const Locale('en'),
}) async {
  final launcher = _Launcher();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: RohdDartSourceSection(violation: v)),
      ),
    ),
  );
  await tester.pump();
  return launcher;
}

void main() {
  testWidgets('shows the Dart location, the note and the callers', (
    tester,
  ) async {
    await _pump(tester, _violation(source: _exact));
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.inspectorDartSourceHeader), findsOneWidget);
    expect(find.text('/p/lib/design.dart:21:29'), findsOneWidget);
    expect(find.text(l10n.inspectorDartSourceExact), findsOneWidget);
    expect(find.text(l10n.inspectorDartSourceCalledFrom), findsOneWidget);
    expect(find.text('/p/lib/design.dart:58:19'), findsOneWidget);
  });

  testWidgets('says when the location is the enclosing block', (tester) async {
    await _pump(
      tester,
      _violation(
        source: const RohdDartSource(
          primary: RohdDartLocation(file: '/p/a.dart', line: 5, column: 1),
          kind: RohdDartSourceKind.enclosing,
        ),
      ),
    );
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.inspectorDartSourceEnclosing), findsOneWidget);
    expect(find.text(l10n.inspectorDartSourceCalledFrom), findsNothing);
  });

  testWidgets('says when it came from the inline comment', (tester) async {
    await _pump(
      tester,
      _violation(
        source: const RohdDartSource(
          primary: RohdDartLocation(file: '/p/a.dart', line: 5, column: 1),
          kind: RohdDartSourceKind.exact,
          fromInlineComment: true,
        ),
      ),
    );
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.inspectorDartSourceInline), findsOneWidget);
  });

  testWidgets('Go to Dart source opens the editor at the Dart line', (
    tester,
  ) async {
    final launcher = await _pump(tester, _violation(source: _exact));
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.text(l10n.inspectorDartSourceOpen));
    await tester.pump();
    await tester.pump();
    expect(launcher.launched, hasLength(1));
    expect(
      launcher.launched.single.arguments.join(' '),
      contains('/p/lib/design.dart:21:29'),
    );
  });

  testWidgets('a caller opens the editor at the call site', (tester) async {
    final launcher = await _pump(tester, _violation(source: _exact));
    await tester.tap(find.text('/p/lib/design.dart:58:19'));
    await tester.pump();
    await tester.pump();
    expect(
      launcher.launched.single.arguments.join(' '),
      contains('/p/lib/design.dart:58:19'),
    );
  });

  testWidgets('renders nothing for a finding with no Dart source', (
    tester,
  ) async {
    await _pump(tester, _violation());
    expect(find.byKey(const ValueKey('rohdDartSource')), findsNothing);
  });

  testWidgets('locale sweep renders without exceptions', (tester) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await _pump(tester, _violation(source: _exact), locale: locale);
      expect(tester.takeException(), isNull, reason: '$locale');
      expect(find.byKey(const ValueKey('rohdDartSource')), findsOneWidget);
    }
  });
}
