// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Synthetic shapes exercising the detection rules in
// `../captured_ref_use_test.dart`.
//
// The POSITIVE shapes each hand a closure that captures `ref` to something
// that outlives the build; the scanner must flag every one. The NEGATIVE
// shapes are the control: legitimate patterns, and the one allowed shape,
// that must stay clean.
//
// This file is deliberately outside `lib/`, so the production scan never
// sees it; the shape test resolves it on its own. It is never executed,
// only read as text, so the shapes need not be runnable providers.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

final Provider<int> tabProvider = Provider<int>((ref) => 0);
final Provider<int> otherProvider = Provider<int>((ref) => 1);

class Holder {
  Holder({this.supplier});
  int Function()? supplier;
}

// === POSITIVE: must be flagged =============================================

// --- Shape 1: closure passed as a constructor argument, in a body that
// watches. The provider rebuilds whenever `tabProvider` changes; a `Holder`
// handed out before that still calls the old closure.
final constructorArgProvider = Provider<Holder>((ref) {
  ref.watch(tabProvider);
  return Holder(supplier: () => ref.watch(otherProvider));
});

// --- Shape 2: closure stored in a field after construction.
final storedFieldProvider = Provider<Holder>((ref) {
  final holder = Holder();
  ref.watch(tabProvider);
  holder.supplier = () => ref.read(otherProvider);
  return holder;
});

// --- Shape 3: closure returned from the build of a disposable provider.
final Provider<int Function()> returnedProvider =
    Provider.autoDispose<int Function()>((ref) {
      return () => ref.read(otherProvider);
    });

// --- Shape 4: an override binding builder, which is installed in a scope
// and disposed with it.
final Override overrideShape = otherProvider.overrideWith((ref) {
  return Holder(supplier: () => ref.read(tabProvider)).supplier!();
});

// === NEGATIVE: must stay clean ============================================

// --- Control A: the allowed shape. A root provider whose body only reads
// never rebuilds, so its Ref lives as long as the container. Reported as
// allowed, never as a violation.
final readOnlyRootProvider = Provider<Holder>(
  (ref) => Holder(supplier: () => ref.read(otherProvider)),
);

// --- Control B: a listener. Riverpod cancels it with the provider.
final listenerProvider = Provider<int>((ref) {
  ref.listen(tabProvider, (previous, next) {
    ref.read(otherProvider);
  });
  return 0;
});

// --- Control C: a lifecycle hook, owned by the sibling scanner.
final hookProvider = Provider<int>((ref) {
  ref.watch(tabProvider);
  ref.onDispose(() {
    ref.read(otherProvider);
  });
  return 0;
});

// --- Control D: synchronous iteration runs the closure in place.
final iterationProvider = Provider<List<int>>((ref) {
  ref.watch(tabProvider);
  return <int>[1, 2].map<int>((n) => n + ref.read(otherProvider)).toList();
});

// --- Control E: a closure that does not touch `ref`.
final plainClosureProvider = Provider<Holder>((ref) {
  ref.watch(tabProvider);
  return Holder(supplier: () => 42);
});
