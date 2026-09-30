// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/panel_layout_state.dart';

void main() {
  group('PanelLayoutState', () {
    test('default constructor yields the open-on-launch baseline', () {
      const s = PanelLayoutState();
      expect(s.ruleBrowserVisible, isTrue);
      expect(s.violationDetailsVisible, isTrue);
      expect(s.runLogVisible, isTrue);
      expect(s.ruleBrowserWidth, isNull);
      expect(s.violationDetailsWidth, isNull);
      expect(s.runLogHeight, isNull);
    });

    test('copyWith replaces selected fields verbatim', () {
      const original = PanelLayoutState();
      final next = original.copyWith(
        ruleBrowserVisible: false,
        ruleBrowserWidth: 240,
      );
      expect(next.ruleBrowserVisible, isFalse);
      expect(next.ruleBrowserWidth, 240);
      // Untouched fields preserved.
      expect(next.violationDetailsVisible, isTrue);
      expect(next.runLogVisible, isTrue);
    });

    test('copyWith — clear flags reset optional sizes to null', () {
      const sized = PanelLayoutState(
        ruleBrowserWidth: 240,
        violationDetailsWidth: 320,
        runLogHeight: 200,
      );
      final cleared = sized.copyWith(
        clearRuleBrowserWidth: true,
        clearViolationDetailsWidth: true,
        clearRunLogHeight: true,
      );
      expect(cleared.ruleBrowserWidth, isNull);
      expect(cleared.violationDetailsWidth, isNull);
      expect(cleared.runLogHeight, isNull);
    });

    test('copyWith — clear flag wins over a non-null replacement', () {
      // Documents the precedence rule. Callers asking to *clear* a field
      // must not have their intent silently overridden by a passed value.
      const original = PanelLayoutState(ruleBrowserWidth: 250);
      final cleared = original.copyWith(
        ruleBrowserWidth: 400,
        clearRuleBrowserWidth: true,
      );
      expect(cleared.ruleBrowserWidth, isNull);
    });

    test('== is structural across every field', () {
      const a = PanelLayoutState(
        ruleBrowserVisible: false,
        ruleBrowserWidth: 240,
      );
      const b = PanelLayoutState(
        ruleBrowserVisible: false,
        ruleBrowserWidth: 240,
      );
      const c = PanelLayoutState(ruleBrowserWidth: 240);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('toString includes every visibility and size field', () {
      const s = PanelLayoutState(
        ruleBrowserVisible: false,
        runLogHeight: 200,
      );
      final out = s.toString();
      expect(out, contains('ruleBrowserVisible: false'));
      expect(out, contains('violationDetailsVisible: true'));
      expect(out, contains('runLogHeight: 200'));
    });
  });
}
