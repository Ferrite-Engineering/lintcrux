// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the violation table shows the open-core [FilterPresetDropdown].
///
/// True in open core. An overlay that brings its own preset control returns
/// false while that control is shown, so the table never carries two
/// "Filter preset" pickers; the overlay's control is then responsible for
/// listing the project's own presets (`savedFilterPresetsProvider`) too, so
/// no preset saved in the project file becomes unreachable.
final Provider<bool> filterPresetDropdownVisibleProvider = Provider<bool>(
  (_) => true,
  name: 'filterPresetDropdownVisibleProvider',
);
