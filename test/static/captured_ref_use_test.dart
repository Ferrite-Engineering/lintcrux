// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail against a `Ref` captured by a closure that outlives
// the build which created it, scanning `lib/`. See
// `captured_ref_scanner.dart` for the detection rules and for what is
// deliberately not flagged.
//
// THE BUG CLASS IN ONE LINE:
// `supplier: () => ref.watch(x).value` handed to an object that calls it
// later, from a provider that can rebuild or be disposed, throws
// `UnmountedRefException` out of whatever path invoked the closure. Two
// instances were found and fixed in the Pro overlay before this guard
// existed; one killed a lint run in flight when a project was opened.
//
// The allowed shape, a `ref.read`-only body on a root provider, rests on an
// invariant nobody had written down: adding a single `ref.watch` to such a
// body turns it into the bug. This guard is what notices.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'captured_ref_scanner.dart';

/// `file:line` entries that are intentionally exempt, each with the reason
/// the provider cannot be disposed while the closure is live. Keep this
/// empty if at all possible: caching through `ref.listen` is always the
/// better fix.
const Map<String, String> allowlist = <String, String>{};

void main() {
  group('captured Ref scanner', () {
    final fixture = File('test/static/captured_ref_shapes/shapes.dart');

    test('flags every positive shape in the shapes fixture', () {
      expect(
        fixture.existsSync(),
        isTrue,
        reason: 'run this test from the package root (flutter test)',
      );
      final found = scanCapturedSource(
        fixture.readAsStringSync(),
        fixture.path,
      );
      final violations = found.where((f) => f.violation).toList();
      final details = violations.map((f) => f.detail).join('\n');

      expect(details, contains('`Holder` in `constructorArgProvider`'));
      expect(details, contains('`holder.supplier =` in `storedFieldProvider`'));
      expect(details, contains('`return` in `returnedProvider`'));
      expect(details, contains('in `otherProvider.overrideWith`'));
      expect(violations, hasLength(4), reason: details);
    });

    test('reports the read-only root shape as allowed, not a violation', () {
      final found = scanCapturedSource(
        fixture.readAsStringSync(),
        fixture.path,
      );
      final allowed = found.where((f) => !f.violation).toList();
      expect(allowed, hasLength(1));
      expect(allowed.single.provider, 'readOnlyRootProvider');
      expect(allowed.single.detail, contains('adding a single ref.watch'));
    });

    test('leaves the control shapes clean', () {
      final src = fixture.readAsStringSync();
      final found = scanCapturedSource(src, fixture.path);
      final lines = src.split('\n');
      final negativeStart =
          lines.indexWhere((l) => l.contains('=== NEGATIVE')) + 1;
      expect(negativeStart, greaterThan(0));
      final flagged = found.where(
        (f) => f.violation && f.line >= negativeStart,
      );
      expect(
        flagged.map((f) => '${f.line}: ${f.detail}'),
        isEmpty,
        reason: 'the control shapes are legitimate and must not be flagged',
      );
    });
  });

  test('no closure captures a Ref it can outlive in lib/', () {
    final libDir = Directory('lib');
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'run this test from the package root (flutter test)',
    );
    final found = scanCapturedRefClosures([libDir]).where((f) {
      return f.violation && !allowlist.containsKey('${f.path}:${f.line}');
    }).toList();
    expect(found, isEmpty, reason: formatCapturedRefReport(found));
  });
}
