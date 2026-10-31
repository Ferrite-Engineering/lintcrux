// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/interfaces/waiver_store.dart';
import 'package:lintcrux/services/transformers/managed_waiver_transformer.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:lintcrux/services/waivers/waiver_store_provider.dart';

/// How many of the findings in [store] the current waivers suppress.
///
/// The same notion the headless summary and the SARIF export report: a
/// finding is waived when it carries a suppression. Two sources feed it:
///
///  * a suppression that does not come from the managed waiver store (an
///    inline source pragma, or one read from an imported SARIF report) counts
///    as it stands, because nothing the user can do in the waiver store
///    changes it;
///  * a managed waiver is re-matched against [waivers] now, so adding a waiver
///    counts the findings it covers before the next run stamps them, and
///    removing one stops counting them. A finding that already carries a
///    managed suppression from the last run is judged by the store as it is
///    today, not by that stale stamp.
int countWaivedViolations(ViolationStore store, WaiverStore waivers) {
  var waived = 0;
  for (final v in store.all) {
    if (v.isSuppressed && !ManagedWaiverTransformer.isManaged(v)) {
      waived++;
    } else if (waivers.match(v) != null) {
      waived++;
    }
  }
  return waived;
}

/// Notifier behind [waivedViolationCountProvider]: recounts when the run's
/// findings change and when a waiver is added, changed or removed.
class WaivedViolationCountNotifier extends Notifier<int> {
  @override
  int build() {
    final violations = ref.watch(violationStoreProvider);
    final waivers = ref.watch(waiverStoreProvider);
    // A streamed row is followed by `RunCompleted`; recounting on each of
    // 50,000 rows would make a run quadratic.
    final violationSub = violations.events.listen((event) {
      if (event is! ViolationAdded) _recount();
    });
    final waiverSub = waivers.events.listen((_) => _recount());
    ref.onDispose(() {
      unawaited(violationSub.cancel());
      unawaited(waiverSub.cancel());
    });
    return countWaivedViolations(violations, waivers);
  }

  void _recount() {
    state = countWaivedViolations(
      ref.read(violationStoreProvider),
      ref.read(waiverStoreProvider),
    );
  }
}

/// The number of findings the current waivers suppress for the current run.
///
/// Per tab, like `visibleViolationsProvider`: it reads the tab's violation
/// and waiver stores, so a tab binds its own instance (see
/// `lintcruxTabOverridesFactory`).
final NotifierProvider<WaivedViolationCountNotifier, int>
waivedViolationCountProvider =
    NotifierProvider<WaivedViolationCountNotifier, int>(
      WaivedViolationCountNotifier.new,
    );
