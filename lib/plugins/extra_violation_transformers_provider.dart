// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/violation_transformer.dart';

/// Transformers the desktop run pipeline appends after open core's own
/// chain (severity overrides, source pragmas, managed waivers).
///
/// Open core ships the seam with an empty list. The Pro overlay re-binds it
/// per tab for the organization's rule-severity defaults from the signed
/// policy file, which apply only where the tab's project is silent, so the
/// position in the chain carries no precedence of its own: a transformer
/// placed here must not undo what the project's own `severityOverrides`
/// decided. The headless runner has the same seam as a constructor
/// argument (`HeadlessRunner.extraTransformers`); both surfaces must route
/// the same violation through the same chain or a CI gate and the desktop
/// disagree about a project.
final Provider<List<ViolationTransformer>> extraViolationTransformersProvider =
    Provider<List<ViolationTransformer>>(
      (ref) => const <ViolationTransformer>[],
    );
