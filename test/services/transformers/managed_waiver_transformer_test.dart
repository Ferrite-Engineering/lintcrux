// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/waiver_store.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/transformers/managed_waiver_transformer.dart';
import 'package:lintcrux/services/waivers/noop_waiver_store.dart';

class _FakeStore implements WaiverStore {
  _FakeStore(this.matchers);

  /// Map of "ruleId|filePath" -> Waiver returned by match.
  final Map<String, Waiver> matchers;

  @override
  List<Waiver> get all => matchers.values.toList(growable: false);

  @override
  Waiver? match(Violation v) => matchers['${v.ruleId}|${v.location.file}'];

  @override
  Future<void> add(Waiver w) async => throw UnimplementedError();

  @override
  Future<void> update(Waiver w) async => throw UnimplementedError();

  @override
  Future<void> delete(String id) async => throw UnimplementedError();

  @override
  Future<void> loadFrom(List<String> paths) async {}

  @override
  Future<void> save() async {}

  @override
  Stream<WaiverStoreEvent> get events => const Stream<WaiverStoreEvent>.empty();
}

const _location = SourceLocation(file: '/proj/cpu.sv', line: 42, column: 7);

const _violation = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'Signal is never used',
  location: _location,
);

Waiver _waiver({String id = 'w-1'}) => Waiver(
  id: id,
  ruleId: 'verilator/UNUSEDSIGNAL',
  filePath: '/proj/cpu.sv',
  reason: 'pending refactor',
  author: 'mfink',
  createdAt: DateTime.utc(2026, 5, 2),
);

void main() {
  group('ManagedWaiverTransformer', () {
    test('passes through when the store has no match', () {
      final store = NoopWaiverStore();
      addTearDown(store.dispose);
      final transformer = ManagedWaiverTransformer(store);
      expect(transformer.transform(_violation), _violation);
    });

    test('marks suppression when the store finds a match', () {
      final waiver = _waiver();
      final store = _FakeStore({
        'verilator/UNUSEDSIGNAL|/proj/cpu.sv': waiver,
      });
      final transformer = ManagedWaiverTransformer(store);
      final result = transformer.transform(_violation);
      expect(result.isSuppressed, isTrue);
      expect(result.suppression, waiver);
    });

    test(
      'pre-existing suppression (e.g. inline pragma) wins over the store '
      "— source pragmas express the engineer's intent more directly than "
      'a project-level waiver',
      () {
        final pragmaWaiver = _waiver(id: 'pragma:/proj/cpu.sv:40-50:UNUSED');
        final managedWaiver = _waiver(id: 'managed-1');
        final preSuppressed = _violation.copyWith(suppression: pragmaWaiver);
        final store = _FakeStore({
          'verilator/UNUSEDSIGNAL|/proj/cpu.sv': managedWaiver,
        });
        final transformer = ManagedWaiverTransformer(store);
        final result = transformer.transform(preSuppressed);
        expect(
          result.suppression,
          pragmaWaiver,
          reason: 'transformer must not overwrite an existing suppression',
        );
      },
    );

    test('open-core NoopWaiverStore yields a permanent no-op transformer', () {
      final store = NoopWaiverStore();
      addTearDown(store.dispose);
      final transformer = ManagedWaiverTransformer(store);
      expect(transformer.transform(_violation), _violation);
    });
  });
}
