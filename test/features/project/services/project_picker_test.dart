// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_project/crux_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';

void main() {
  test(
    'Open Project accepts .lintcrux projects and <design>.crux-project '
    'manifests',
    () {
      // The filter takes extensions without the dot; a manifest named
      // `uart_tx.crux-project` has the extension `crux-project`.
      expect(
        kProjectPickerExtensions,
        containsAll(['lintcrux', kCruxProjectExtension]),
      );
      expect(kCruxProjectExtension, 'crux-project');
    },
  );
}
