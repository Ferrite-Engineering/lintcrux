// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Static architecture guard for the layered import direction defined in
/// `docs/ARCHITECTURE.md` §6.2:
///
/// ```text
/// features/ → services/ → domain/
/// core/ is a shared base (importable by any layer; itself SDK-only)
/// ```
///
/// A **lower** layer must never import a **higher** one. Concretely the
/// forbidden edges are:
///
///   * `domain/`   → `services/`, `features/`, `core/`  (domain is pure)
///   * `services/` → `features/`
///   * `core/`     → `features/`, `services/`
///
/// Same-layer ("lateral") imports are allowed — the stack is about
/// vertical direction, not module isolation.
///
/// The [_sanctioned] allowlist below names the deliberate exceptions
/// (the composition root — router + bootstrap bridges + app entry —
/// which wires features together and may import any layer). Every entry
/// carries a rationale comment. A new upward import that is not in the
/// allowlist fails this test; that is the signal to either fix the seam
/// (move the shared type down / invert via a services seam) or, if it is
/// genuinely composition-root wiring, add it here with a reason.
void main() {
  // Repo-relative paths (POSIX separators) allowed to break the rule,
  // each with the reason it is sanctioned.
  const sanctioned = <String>{
    // ── Composition root: wires features together at startup and so may
    //    reach any layer (ARCHITECTURE.md §6.2 "Composition root"). ──
    'lib/core/router/app_router.dart', // routes to feature screens
    'lib/core/theme/lintcrux_color_theme_bootstrap.dart', // theme↔settings bridge spread into bootstrap
    'lib/app.dart', // bootstrap(): composes the ProviderScope + feature widgets
    'lib/main.dart', // app entry point
    // The headless composition root — `bin/lintcrux.dart` is four lines
    // around this class. It is `lib/app.dart`'s opposite number: it
    // assembles the engine registry, the run pipeline and the reporter
    // into a runnable command, and so reaches `services/` for the same
    // reason `bootstrap()` reaches `features/`. It lives under `core/cli`
    // rather than `services/` because it is a composition root, not a
    // service: nothing else in `lib/` may import it.
    'lib/core/cli/lintcrux_cli.dart',
  };

  test('no lower layer imports a higher one (ARCHITECTURE §6.2)', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'run from the package root');

    // (sourceLayer, targetLayer) pairs that are forbidden.
    const forbidden = <String, Set<String>>{
      'domain': {'services', 'features', 'core'},
      'services': {'features'},
      'core': {'features', 'services'},
    };

    String? layerOf(String topSegment) {
      const known = {'domain', 'services', 'features', 'core'};
      return known.contains(topSegment) ? topSegment : null;
    }

    final importRe = RegExp(
      r'''^\s*import\s+['"]package:lintcrux/([a-z_]+)/''',
      multiLine: true,
    );

    final violations = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(entity.path));
      // Skip generated localizations.
      if (rel.startsWith('lib/l10n/generated/')) continue;
      if (rel.endsWith('.g.dart')) continue;

      final parts = p.split(rel); // ['lib', <top>, ...]
      final sourceLayer = parts.length >= 2 ? layerOf(parts[1]) : null;
      if (sourceLayer == null) continue; // top-level lib/*.dart etc.
      final forbiddenTargets = forbidden[sourceLayer];
      if (forbiddenTargets == null) continue;

      final content = entity.readAsStringSync();
      for (final m in importRe.allMatches(content)) {
        final targetLayer = layerOf(m.group(1)!);
        if (targetLayer == null) continue;
        if (!forbiddenTargets.contains(targetLayer)) continue;
        if (sanctioned.contains(rel)) continue;
        violations.add('$rel  ($sourceLayer → $targetLayer)');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Upward imports violate the layered dependency flow '
          '(ARCHITECTURE.md §6.2). Fix the seam or, if this is genuine '
          'composition-root wiring, add the file to the `sanctioned` '
          'allowlist with a rationale:\n  ${violations.join('\n  ')}',
    );
  });
}
