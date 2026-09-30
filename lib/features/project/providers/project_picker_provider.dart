// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/project/services/project_picker.dart';

/// Riverpod provider exposing the [ProjectPicker]. Default returns the
/// real platform-backed picker; tests override with a fake.
final Provider<ProjectPicker> projectPickerProvider = Provider<ProjectPicker>(
  (ref) => const ProjectPicker(),
);
