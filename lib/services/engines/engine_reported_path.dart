// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Containment for file paths that arrive from an engine's own output.
///
/// Every engine parser lifts a "filename" out of a subprocess's stdout or
/// stderr, and every one of those strings is **attacker-reachable**: a
/// design file can make Verilator and Verible report a filename of its
/// author's choosing via a `` `line `` directive, and the lifted string
/// then travels all the way into `Process.start`'s argv when the user
/// clicks the violation (`ClickToSourceService`). A LintCrux user who
/// opens somebody else's RTL is running that RTL's choice of argument.
///
/// The five parsers used to share this hand-rolled resolver:
///
/// ```dart
/// if (file.startsWith('/') || (file.length >= 2 && file[1] == ':')) {
///   return file;                       // "already absolute"
/// }
/// return '$root$file';                 // no normalization, no containment
/// ```
///
/// Two defects, both load-bearing:
///
/// 1. **`file[1] == ':'` is not an absoluteness test.** It admits *any*
///    string whose second character is a colon — `+:!sh -c …` among
///    them — and returns it verbatim, so a value that is not a path at
///    all reaches the editor argv unchanged. Under the `vim` / `emacs`
///    presets (`['+{line}', '{file}']`) an argv element starting with
///    `+` is an editor *command*, not a filename.
/// 2. **No normalization and no containment.** `'$root$file'` happily
///    builds `…/proj/../../../etc/shadow` out of a relative path the
///    engine reported, and string-concatenates rather than joining.
///
/// [resolveEngineReportedPath] is the single replacement. It answers
/// `null` for anything it will not vouch for, and every caller treats
/// `null` as "this line did not parse" — which routes through the
/// parsers' existing log-and-continue contract (`onUnrecognized`), so a
/// refused path is reported to the user as a SARIF
/// `toolExecutionNotifications` entry rather than silently dropped.
library;

import 'package:path/path.dart' as p;

/// Matches a Windows-absolute path (`C:\…`, `C:/…`, or a `\\server\share`
/// UNC prefix) in *any* host context.
///
/// Deliberately not `p.isAbsolute`, which follows the host platform: a
/// macOS CI run must still recognize the `C:\Users\…\top.v` that Verilator
/// prints on a contributor's Windows box, because those transcripts are
/// what the parser corpus is made of.
final RegExp _windowsAbsolute = RegExp(r'^(?:[A-Za-z]:[\\/]|[\\/][\\/])');

/// Resolves [reported] — a path an engine printed on its own output — to
/// an absolute path, or returns `null` when it must be refused.
///
/// The contract, in the order the checks apply:
///
/// * An empty path, or one carrying a NUL, is refused. Neither is a file.
/// * A **Windows-absolute** or **POSIX-absolute** path is normalized and
///   kept, even when it sits outside [rootPath]. Out-of-tree absolutes are
///   ordinary and legitimate — a violation in a system header, or in a
///   `-I`-supplied library the project references by absolute path — and
///   an absolute path can never be mistaken for an editor option, which is
///   the thing that makes a reported path dangerous.
/// * Anything else is **relative**, and a relative path from an engine is
///   relative to the engine's working directory, which LintCrux always
///   sets to the project root. It is joined to [rootPath], normalized, and
///   then required to still be *inside* [rootPath]. A relative path that
///   climbs out (`../../../etc/shadow`) is refused: the engine has
///   contradicted the working directory LintCrux gave it, which is either
///   a bug or a `` `line `` directive written to escape.
/// * A relative path with no [rootPath] to resolve against is refused
///   rather than turned into a bare relative argv element.
///
/// Refusal is *not* silent at any call site: it makes the line
/// unparseable, and unparseable lines go to `onUnrecognized`.
///
/// Every path it returns is absolute in the sense of `crux_io`'s
/// `isAbsoluteSpawnPath`, which `ClickToSourceService` checks again before a
/// location becomes an editor argv element: an absolute path is the one
/// shape no editor's option parser mistakes for a flag.
String? resolveEngineReportedPath(String reported, String rootPath) {
  if (reported.isEmpty) return null;
  // A NUL cannot occur in a filename on any platform LintCrux ships to,
  // and `Process.start` would truncate the argv element there.
  if (reported.contains('\u0000')) return null;

  if (_windowsAbsolute.hasMatch(reported)) {
    return p.windows.normalize(reported);
  }
  if (reported.startsWith('/')) {
    return p.posix.normalize(reported);
  }

  if (rootPath.isEmpty) return null;
  // Pick the context from the *root*, not from the host: a Windows
  // transcript replayed on a POSIX CI box must still join with `\`.
  final context = _windowsAbsolute.hasMatch(rootPath) ? p.windows : p.posix;
  final root = context.normalize(rootPath);
  final resolved = context.normalize(context.join(root, reported));
  // `isWithin` is false for the root itself, which is correct — a
  // violation located *at* a directory is not a violation in a file.
  if (!context.isWithin(root, resolved)) return null;
  return resolved;
}
