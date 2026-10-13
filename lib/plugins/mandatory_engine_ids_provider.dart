// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Engine ids the desktop run pipeline adds to every run, whatever the
/// project's `enabledEngineIds` say.
///
/// Open core ships the seam with an empty list. The Pro overlay re-binds it
/// to the organization's `mandatoryEngines` from the signed policy file,
/// read live against the tier, so a mandate that arrives or lapses
/// mid-session takes effect on the next run with nothing rebuilt.
///
/// The headless runner has the same seam as an argument
/// (`CliArgs.mandatoryEngineIds`), and the two must agree: the planner adds
/// the mandated ids to both surfaces' runs in the same way. What differs is
/// what a missing mandated engine does. The headless runner refuses the run,
/// because a CI gate that silently omits a mandated engine is the failure
/// the mandate exists to prevent; the desktop app reports the engine as
/// unavailable in its run status and lets the other engines run, because
/// blocking every run on a developer's machine would stop work rather than
/// enforce policy.
final Provider<List<String>> mandatoryEngineIdsProvider =
    Provider<List<String>>((ref) => const <String>[]);
