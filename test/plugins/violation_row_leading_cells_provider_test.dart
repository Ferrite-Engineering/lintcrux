// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/plugins/violation_row_leading_cells_provider.dart';

void main() {
  group('violationRowLeadingCellsProvider', () {
    test('default value is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(violationRowLeadingCellsProvider), isEmpty);
    });

    test('overridable with a list of leading cells', () {
      final container = ProviderContainer(
        overrides: [
          violationRowLeadingCellsProvider.overrideWithValue(
            <ViolationRowLeadingCell>[
              ViolationRowLeadingCell(
                id: 'test-cell',
                width: 24,
                bodyBuilder: (_, _, _) => const SizedBox.shrink(),
                headerBuilder: (_, _) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      final cells = container.read(violationRowLeadingCellsProvider);
      expect(cells, hasLength(1));
      expect(cells.first.id, 'test-cell');
      expect(cells.first.width, 24);
    });
  });

  group('ViolationRowLeadingCell', () {
    testWidgets(
      'bodyBuilder is invoked with the row violation',
      (tester) async {
        Violation? captured;
        final cell = ViolationRowLeadingCell(
          id: 'capture',
          width: 32,
          bodyBuilder: (context, ref, violation) {
            captured = violation;
            return const SizedBox.shrink();
          },
          headerBuilder: (_, _) => const SizedBox.shrink(),
        );
        const violation = Violation(
          engineId: 'verilator',
          ruleId: 'verilator/UNUSEDSIGNAL',
          severity: Severity.warning,
          location: SourceLocation(
            file: '/a.sv',
            line: 1,
            column: 1,
          ),
          message: 'unused',
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) =>
                    cell.bodyBuilder(context, ref, violation),
              ),
            ),
          ),
        );
        expect(captured, violation);
      },
    );

    testWidgets(
      'headerBuilder is invoked once per build',
      (tester) async {
        var headerInvocations = 0;
        final cell = ViolationRowLeadingCell(
          id: 'header-capture',
          width: 32,
          bodyBuilder: (_, _, _) => const SizedBox.shrink(),
          headerBuilder: (context, ref) {
            headerInvocations += 1;
            return const SizedBox.shrink();
          },
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) => cell.headerBuilder(context, ref),
              ),
            ),
          ),
        );
        expect(headerInvocations, 1);
      },
    );
  });
}
