// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// One rule for every path LintCrux writes into a file somebody else
/// reads: `/`, on every platform.
///
/// `p.relative` answers in the *host's* separator. That is right for a
/// path the process is about to open and wrong for every path it is
/// about to persist, because LintCrux's artifacts are shared across a
/// mixed-platform team:
///
/// * the SARIF `artifactLocation.uri` in a `--export sarif` upload — a
///   URI reference, which has exactly one separator, and which GitHub
///   code scanning matches against checked-out repository paths. A
///   backslashed uri produces an alert with no line annotation;
/// * the `lintcrux --ci` stdout listing, whose `file:line:col:` shape is
///   what editors and CI log scrapers key on, and which a team diffs
///   between runs;
/// * the Pro waiver audit trail, which is **committed to the team's
///   repository** — a trail that records `rtl\cpu.sv` on one developer's
///   machine and `rtl/cpu.sv` on the next is not comparable, which is
///   the entire point of an audit trail.
///
/// Windows accepts `/` in paths, so normalizing costs nothing there.
library;

import 'package:path/path.dart' as p;

/// [absolute] expressed relative to [root], always with `/` separators.
///
/// Splits on [context] — the host's by default — and re-joins on POSIX,
/// which is the idiom SimCrux's `plugin_installer.dart` uses. [context]
/// is injectable so the Windows behaviour is provable on a macOS or
/// Linux CI box rather than only on the Sunday-only Windows job.
///
/// Callers are expected to have already established that [absolute] is
/// inside [root] (`p.isWithin`); this function does not re-check, and
/// will happily answer with `../` segments if handed a path that is not.
String portableRelativePath(
  String absolute,
  String root, {
  p.Context? context,
}) {
  final ctx = context ?? p.context;
  return p.posix.joinAll(ctx.split(ctx.relative(absolute, from: root)));
}
