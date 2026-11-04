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
///   the entire point of an audit trail;
/// * a `.lintcrux` project file's relative source entries, which are
///   committed next to the RTL and read on every platform the team uses
///   ([portableProjectEntry] writes them, [projectEntryForReading] reads
///   the ones an earlier version wrote with `\`).
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

/// Whether a path names a location on a Windows volume: a drive letter
/// (`C:\`, `C:/`) or a UNC share (`\\host\share`).
final RegExp _windowsAbsolute = RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)');

/// [absolute] as it should be written into a `.lintcrux` project file that
/// lives in [projectDir].
///
/// A path under the project's volume is written relative to it with `/`
/// separators, whatever the host, so a project committed from Windows opens
/// on macOS and Linux (where a backslash is a file-name character) and one
/// committed from there opens on Windows (which reads `/`). A path on
/// another volume, a second Windows drive, stays absolute: no relative path
/// reaches it. A path that is already relative is returned with its
/// separators normalised and nothing else changed.
String portableProjectEntry(
  String absolute,
  String projectDir, {
  p.Context? context,
}) {
  final ctx = context ?? p.context;
  if (_windowsAbsolute.hasMatch(absolute) && !ctx.isAbsolute(absolute)) {
    // A Windows-absolute entry seen under POSIX rules: not ours to rewrite.
    return absolute;
  }
  if (!ctx.isAbsolute(absolute)) return absolute.replaceAll(r'\', '/');
  final dir = ctx.normalize(ctx.absolute(projectDir));
  final target = ctx.normalize(absolute);
  if (!ctx.equals(ctx.rootPrefix(target), ctx.rootPrefix(dir))) return target;
  return portableRelativePath(target, dir, context: ctx);
}

/// A relative entry of a `.lintcrux` project file (or a config overlay), as
/// [context] should resolve it.
///
/// A project saved on Windows by an earlier version spells its relative
/// entries with `\`. Windows reads those natively. Under POSIX rules a
/// backslash is a file-name character, so the entry is read with `/` instead,
/// which is what its author meant. An absolute POSIX path is left alone, and
/// so is a Windows-absolute entry (`C:\...`, UNC): it cannot resolve on this
/// host and keeps the not-found handling it always had.
String projectEntryForReading(String entry, {p.Context? context}) {
  final ctx = context ?? p.context;
  if (ctx.style == p.Style.windows) return entry;
  if (ctx.isAbsolute(entry) || _windowsAbsolute.hasMatch(entry)) return entry;
  return entry.replaceAll(r'\', '/');
}
