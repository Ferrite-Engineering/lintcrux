// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/waiver_store.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/providers/waived_violation_count_provider.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_status_bar.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/transformers/managed_waiver_transformer.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:lintcrux/services/waivers/waiver_store_provider.dart';

/// A waiver store that holds waivers in memory and matches by rule id, the
/// way the Pro store does for a whole-file waiver.
class _MemoryWaiverStore implements WaiverStore {
  final List<Waiver> _waivers = <Waiver>[];
  final StreamController<WaiverStoreEvent> _events =
      StreamController<WaiverStoreEvent>.broadcast(sync: true);

  @override
  List<Waiver> get all => List<Waiver>.unmodifiable(_waivers);

  @override
  Waiver? match(Violation v) {
    for (final w in _waivers) {
      if (w.ruleId == v.ruleId) return w;
    }
    return null;
  }

  @override
  Future<void> add(Waiver w) async {
    _waivers.add(w);
    _events.add(WaiverAdded(w));
  }

  @override
  Future<void> update(Waiver w) async {
    _waivers
      ..removeWhere((e) => e.id == w.id)
      ..add(w);
    _events.add(WaiverUpdated(w));
  }

  @override
  Future<void> delete(String id) async {
    _waivers.removeWhere((e) => e.id == id);
    _events.add(WaiverDeleted(id));
  }

  @override
  Future<void> loadFrom(List<String> paths) async {}

  @override
  Future<void> save() async {}

  Future<void> close() => _events.close();

  @override
  Stream<WaiverStoreEvent> get events => _events.stream;
}

Violation _violation(String rule, {Waiver? suppression, bool managed = false}) {
  return Violation(
    engineId: 'verilator',
    ruleId: rule,
    severity: Severity.warning,
    message: 'm',
    location: const SourceLocation(file: '/w/top.sv', line: 1, column: 1),
    suppression: suppression,
    raw: managed
        ? const <String, dynamic>{ManagedWaiverTransformer.managedRawKey: true}
        : const <String, dynamic>{},
  );
}

Waiver _waiver(String id, String rule) => Waiver(
  id: id,
  ruleId: rule,
  filePath: '/w/top.sv',
  reason: 'r',
  author: 'a',
  createdAt: DateTime.utc(2026),
);

void main() {
  late InMemoryViolationStore violations;
  late _MemoryWaiverStore waivers;
  late ProviderContainer container;

  setUp(() {
    violations = InMemoryViolationStore();
    waivers = _MemoryWaiverStore();
    container = ProviderContainer.test(
      overrides: [
        violationStoreProvider.overrideWith((ref) => violations),
        waiverStoreProvider.overrideWith((ref) => waivers),
      ],
    );
  });

  tearDown(() async {
    await waivers.close();
    await violations.dispose();
  });

  test('adding a waiver counts what it covers; removing it counts 0', () async {
    violations.replaceFromEngine('verilator', [
      _violation('verilator/A'),
      _violation('verilator/B'),
    ]);
    final sub = container.listen(waivedViolationCountProvider, (_, _) {});
    expect(sub.read(), 0);

    await waivers.add(_waiver('w1', 'verilator/A'));
    expect(sub.read(), 1);
    // The table never lists the waived row, so the tally cannot come from it.
    expect(container.read(visibleViolationsProvider), hasLength(2));

    await waivers.delete('w1');
    expect(sub.read(), 0);
  });

  test('a managed suppression stamped by the last run is re-judged by the '
      'store as it is now', () async {
    final w = _waiver('w1', 'verilator/A');
    await waivers.add(w);
    violations.replaceFromEngine('verilator', [
      _violation('verilator/A', suppression: w, managed: true),
    ]);
    final sub = container.listen(waivedViolationCountProvider, (_, _) {});
    expect(sub.read(), 1);

    await waivers.delete('w1');
    expect(sub.read(), 0);
  });

  test('a pragma or imported suppression counts without any managed '
      'waiver', () {
    violations.replaceFromEngine('verilator', [
      _violation('verilator/A', suppression: _waiver('pragma:x', 'A')),
      _violation('verilator/B'),
    ]);
    expect(container.read(waivedViolationCountProvider), 1);
  });

  testWidgets('the status bar tally reads 1 after a waiver, 0 after its '
      'removal', (tester) async {
    violations.replaceFromEngine('verilator', [
      _violation('verilator/A'),
      _violation('verilator/B'),
    ]);
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
          home: Scaffold(body: LintcruxStatusBarBody()),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('· 0 waived'), findsOneWidget);

    await waivers.add(_waiver('w1', 'verilator/A'));
    await tester.pump();
    expect(find.textContaining('· 1 waived'), findsOneWidget);

    await waivers.delete('w1');
    await tester.pump();
    expect(find.textContaining('· 0 waived'), findsOneWidget);
  });

  test('a new run recounts', () async {
    final sub = container.listen(waivedViolationCountProvider, (_, _) {});
    expect(sub.read(), 0);
    violations.replaceFromEngine('verilator', [
      _violation('verilator/A', suppression: _waiver('pragma:x', 'A')),
    ]);
    // The violation store's events are asynchronous.
    await Future<void>.delayed(Duration.zero);
    expect(sub.read(), 1);
  });
}
