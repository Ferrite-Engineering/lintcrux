// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Frozen-violation record stored in a [LintBaseline].
///
/// A baseline carries one [BaselineViolation] per active violation at
/// the moment the baseline was set. The full [Violation] record is
/// **not** stored — only the identity-bearing fields needed to match
/// a violation in a future run, plus a stable [fingerprint] hash that
/// shifts only when the violation's semantic meaning shifts, not when
/// surrounding code reshuffles line numbers.
///
/// The fingerprint is a stable hash of `(ruleId, filePath, context)`
/// where `filePath` is the file **relative to the project root** and
/// `context` is the engine-reported message with the project root
/// stripped out (see [BaselineFingerprint.forProject]). Crucially, the
/// fingerprint does **not** include the line number — that is what lets
/// a violation shift down by a few lines (because a preceding `import`
/// was added) and still count as "the same" violation against the
/// baseline — and it does not include where the checkout lives, so a
/// baseline set on one machine matches a CI runner, a teammate's clone,
/// or a Windows checkout of the same project.
///
/// File-path matching is exact within the project: a refactor that
/// moves a file is treated as a baseline-resolved violation in the old
/// location and a new violation in the new location. This is
/// intentional — automatic renames-as-moves would surface false matches.
@immutable
class BaselineViolation {
  /// Creates a [BaselineViolation].
  const BaselineViolation({
    required this.fingerprint,
    required this.ruleId,
    required this.filePath,
    required this.line,
    required this.message,
  });

  /// Computes a [BaselineViolation] for a live [Violation] at the
  /// moment of snapshot, in the project rooted at [projectRoot] (the
  /// open project's `LintProject.rootPath`).
  factory BaselineViolation.fromViolation(
    Violation v, {
    required String projectRoot,
  }) {
    return BaselineViolation(
      fingerprint: BaselineFingerprint.forProject(
        ruleId: v.ruleId,
        filePath: v.location.file,
        message: v.message,
        projectRoot: projectRoot,
      ),
      ruleId: v.ruleId,
      filePath: v.location.file,
      line: v.location.line,
      message: v.message,
    );
  }

  /// Parses a JSON entry. Throws [FormatException] when a required
  /// field is missing or has the wrong type.
  factory BaselineViolation.fromJson(Map<String, dynamic> json) {
    final fingerprint = json['fingerprint'];
    final ruleId = json['ruleId'];
    final filePath = json['filePath'];
    final line = json['line'];
    final message = json['message'];
    if (fingerprint is! String || fingerprint.isEmpty) {
      throw const FormatException(
        "BaselineViolation missing required 'fingerprint' field",
      );
    }
    if (ruleId is! String || ruleId.isEmpty) {
      throw const FormatException(
        "BaselineViolation missing required 'ruleId' field",
      );
    }
    if (filePath is! String || filePath.isEmpty) {
      throw const FormatException(
        "BaselineViolation missing required 'filePath' field",
      );
    }
    if (line is! int || line < 1) {
      throw const FormatException(
        "BaselineViolation 'line' field must be a positive integer",
      );
    }
    if (message is! String) {
      throw const FormatException(
        "BaselineViolation 'message' field must be a string",
      );
    }
    return BaselineViolation(
      fingerprint: fingerprint,
      ruleId: ruleId,
      filePath: filePath,
      line: line,
      message: message,
    );
  }

  /// Stable hash of `(ruleId, root-relative filePath, normalized-context)`.
  /// Two violations with the same fingerprint represent the same defect
  /// even if their surrounding code changed enough to shift line
  /// numbers, and wherever the project is checked out. The hash is
  /// computed by [BaselineFingerprint.forProject]; tests rely on its
  /// determinism.
  final String fingerprint;

  /// Engine-namespaced rule id, e.g. `verilator/UNUSEDSIGNAL`.
  final String ruleId;

  /// The source file as the engine reported it — an absolute path on
  /// the machine the baseline was set on (or a signal context when the
  /// violation is signal-scoped rather than file-scoped). Recorded for
  /// display; matching uses the root-relative [fingerprint].
  final String filePath;

  /// 1-based line at the time the baseline was set. Recorded for
  /// display in the comparison screen — line shifts are tolerated by
  /// the fingerprint match.
  final int line;

  /// Engine-reported message at the time the baseline was set.
  /// Recorded so the comparison screen can show "resolved violations"
  /// even though the live run no longer reports them.
  final String message;

  /// Round-trippable JSON view.
  Map<String, Object?> toJson() => <String, Object?>{
    'fingerprint': fingerprint,
    'ruleId': ruleId,
    'filePath': filePath,
    'line': line,
    'message': message,
  };

  /// A copy whose [fingerprint] is recomputed from the stored fields
  /// against [projectRoot].
  ///
  /// The migration path for a record written before fingerprints were
  /// root-relative: every input the new fingerprint needs — the rule, the
  /// absolute file, the message — was stored alongside the old hash, so
  /// the upgrade loses nothing.
  BaselineViolation withProjectFingerprint(String projectRoot) =>
      BaselineViolation(
        fingerprint: BaselineFingerprint.forProject(
          ruleId: ruleId,
          filePath: filePath,
          message: message,
          projectRoot: projectRoot,
        ),
        ruleId: ruleId,
        filePath: filePath,
        line: line,
        message: message,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BaselineViolation &&
        other.fingerprint == fingerprint &&
        other.ruleId == ruleId &&
        other.filePath == filePath &&
        other.line == line &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(fingerprint, ruleId, filePath, line, message);

  @override
  String toString() =>
      'BaselineViolation($ruleId, $filePath:$line, $fingerprint)';
}

/// Static helper for computing the stable fingerprint hash used by
/// [BaselineViolation].
///
/// Implementation notes:
///
/// * The hash is FNV-1a 64-bit on a normalized input string. FNV-1a is
///   the right tool here — well-known, dependency-free, fast, and
///   stable across Dart releases. We don't need cryptographic
///   strength; we need determinism and forward-compatibility.
/// * The normalized input is `'<ruleId>|<filePath>|<normalized-message>'`
///   where `normalized-message` collapses runs of whitespace to a
///   single space and strips leading / trailing whitespace. This means
///   reflowing a wrapped error message or trimming trailing newlines
///   doesn't move the fingerprint.
/// * The hash is rendered as an unsigned 16-character lowercase hex
///   string — the same width as a Git short SHA so logs and JSON files
///   read consistently.
class BaselineFingerprint {
  const BaselineFingerprint._();

  // FNV-1a 64-bit computed as two unsigned 32-bit halves (`hi`, `lo`) rather
  // than [BigInt]. BigInt was ~34x slower in the hot "Only new" derive path
  // (per-violation, per keystroke). A web (dart2js) `int` is a 53-bit JS
  // double so a naive 64-bit multiply would lose precision; the multiply below
  // decomposes into 16-bit limbs so every partial product stays < 2^32 (and
  // every running sum < 2^53) — exact on both the VM and dart2js. The output
  // is byte-for-byte identical to the old BigInt form (pinned by
  // `test/domain/models/baseline_fingerprint_migration_test.dart`).

  // Offset basis 0xcbf29ce484222325, split into high / low 32-bit halves.
  static const int _offsetHi = 0xcbf29ce4;
  static const int _offsetLo = 0x84222325;

  // Prime 0x100000001b3 == 0x0000_0100_0000_01b3, as four 16-bit
  // little-endian limbs. Two are zero (kept explicit so the multiply reads as
  // the general schoolbook form).
  static const int _primeLimb0 = 0x01b3;
  static const int _primeLimb1 = 0x0000;
  static const int _primeLimb2 = 0x0100;
  static const int _primeLimb3 = 0x0000;

  // Compiled once, not per call — constructing `RegExp(r'\s+')` per invocation
  // dominated the normalize cost. Kept as a regex (not a hand loop) so the
  // exact Unicode `\s` set is preserved and fingerprints stay stable.
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  static int _computeCount = 0;

  /// Test / diagnostic instrumentation: how many times [compute] has hashed
  /// an input since the process started. Never reset; callers read it before
  /// and after the work they measure and assert on the difference.
  ///
  /// This is the deterministic, CPU-contention-immune proxy the "Only new"
  /// guard asserts on instead of wall-clock time. At the 50,000-violation
  /// design point one uncached pass hashes every live violation — about
  /// 150 million limb operations — so a filter keystroke that reached
  /// [compute] instead of [baselineFingerprintFor]'s cache would read off
  /// this counter as 50,000 rather than 0.
  @visibleForTesting
  static int get computeCount => _computeCount;

  /// Computes the stable fingerprint hash: an unsigned FNV-1a 64-bit of
  /// `'<ruleId>|<filePath>|<normalized-message>'`, rendered as a 16-character
  /// lowercase hex string.
  static String compute({
    required String ruleId,
    required String filePath,
    required String message,
  }) {
    _computeCount++;
    final normalized = '$ruleId|$filePath|${_normalize(message)}';
    var hi = _offsetHi;
    var lo = _offsetLo;
    for (final unit in normalized.codeUnits) {
      // FNV-1a step: XOR the code unit (0..0xFFFF) into the low 16 bits.
      // Done arithmetically so dart2js never runs a bitwise op wider than the
      // 16-bit `loLow ^ unit`.
      final loLow = lo % 0x10000;
      lo = (lo - loLow) + (loLow ^ unit);

      // Multiply the 64-bit hash (hi:lo) by the prime, mod 2^64, via 16-bit
      // limbs.
      final a0 = lo % 0x10000;
      final a1 = lo ~/ 0x10000;
      final a2 = hi % 0x10000;
      final a3 = hi ~/ 0x10000;
      final p0 = a0 * _primeLimb0;
      final p1 = a0 * _primeLimb1 + a1 * _primeLimb0;
      final p2 = a0 * _primeLimb2 + a1 * _primeLimb1 + a2 * _primeLimb0;
      final p3 =
          a0 * _primeLimb3 +
          a1 * _primeLimb2 +
          a2 * _primeLimb1 +
          a3 * _primeLimb0;
      final r0 = p0 % 0x10000;
      final c1 = p1 + p0 ~/ 0x10000;
      final r1 = c1 % 0x10000;
      final c2 = p2 + c1 ~/ 0x10000;
      final r2 = c2 % 0x10000;
      final c3 = p3 + c2 ~/ 0x10000;
      final r3 = c3 % 0x10000; // carry out of bit 63 is dropped (mod 2^64)
      lo = r0 + r1 * 0x10000;
      hi = r2 + r3 * 0x10000;
    }
    // hi occupies the high 8 hex digits, lo the low 8 — concatenating the two
    // zero-padded halves is identical to `(hi<<32 | lo).toRadixString(16)`
    // padded to 16.
    return hi.toRadixString(16).padLeft(8, '0') +
        lo.toRadixString(16).padLeft(8, '0');
  }

  static String _normalize(String s) =>
      s.replaceAll(_whitespaceRun, ' ').trim();

  /// The fingerprint of a finding in the project rooted at [projectRoot].
  ///
  /// This is the identity baselines and bookmarks match on. It is
  /// [compute] over checkout-independent inputs: [filePath] made relative
  /// to [projectRoot] ([projectRelativePath]) and [message] with the root
  /// stripped out ([projectRelativeMessage]). Engines report absolute
  /// paths, and hashing those made a baseline set at `/Users/alice/soc`
  /// match nothing in a CI job checked out at `/home/runner/work/soc/soc`.
  static String forProject({
    required String ruleId,
    required String filePath,
    required String message,
    required String projectRoot,
  }) => compute(
    ruleId: ruleId,
    filePath: projectRelativePath(filePath, projectRoot),
    message: projectRelativeMessage(message, projectRoot),
  );

  /// [filePath] relative to [projectRoot], `/`-separated, when the file
  /// lies inside the root; otherwise [filePath] unchanged (a source
  /// outside the project, or a synthetic location such as
  /// `<module:top>`).
  ///
  /// The path style follows [projectRoot] rather than the host, so a
  /// baseline written on Windows is read identically on Linux and back.
  static String projectRelativePath(String filePath, String projectRoot) {
    if (projectRoot.isEmpty) return filePath;
    final context = _contextFor(projectRoot);
    if (!context.isWithin(projectRoot, filePath)) return filePath;
    return p.posix.joinAll(
      context.split(context.relative(filePath, from: projectRoot)),
    );
  }

  /// [message] with every `<projectRoot><separator>` prefix removed, so a
  /// message that quotes a path in the project (a Yosys elaboration
  /// error, a multiply-driven net's other driver) hashes the same in any
  /// checkout.
  static String projectRelativeMessage(String message, String projectRoot) {
    if (projectRoot.isEmpty) return message;
    final context = _contextFor(projectRoot);
    final root = context.normalize(projectRoot);
    var out = message.replaceAll('$root${context.separator}', '');
    if (context.style == p.Style.windows) {
      out = out.replaceAll('${root.replaceAll(r'\', '/')}/', '');
    }
    return out;
  }

  static final RegExp _windowsRoot = RegExp(r'^([A-Za-z]:[\\/]|\\\\)');

  static p.Context _contextFor(String projectRoot) {
    if (_windowsRoot.hasMatch(projectRoot)) return p.windows;
    if (projectRoot.startsWith('/')) return p.posix;
    return p.context;
  }
}

/// Per-[Violation] identity-memoized view of [BaselineFingerprint.forProject].
///
/// The "Only new" view mode needs the fingerprint of every live violation on
/// every derive — each applied filter change and every store event (see
/// `violation_table_provider`) — and the same violation instances persist
/// across those derives. Caching by instance identity means each instance is
/// hashed once, on the first derive that sees it; every later derive is a
/// lookup (at 50,000 violations: ~2 ms instead of 170-370 ms). The cache is an [Expando] (weak on its key), so
/// it never keeps a [Violation] alive and needs no invalidation — a new lint
/// run produces new instances that fall out of the cache with the old ones.
/// The entry records the root it was computed against, so the same instance
/// asked about a different root is recomputed rather than answered stale.
final Expando<(String, String)> _fingerprintCache = Expando<(String, String)>(
  'baselineFingerprint',
);

/// Returns the baseline fingerprint of [v] in the project rooted at
/// [projectRoot], memoized per instance. Prefer this over calling
/// [BaselineFingerprint.forProject] directly on live violations in hot
/// paths.
String baselineFingerprintFor(Violation v, {required String projectRoot}) {
  final cached = _fingerprintCache[v];
  if (cached != null && cached.$1 == projectRoot) return cached.$2;
  final fingerprint = BaselineFingerprint.forProject(
    ruleId: v.ruleId,
    filePath: v.location.file,
    message: v.message,
    projectRoot: projectRoot,
  );
  _fingerprintCache[v] = (projectRoot, fingerprint);
  return fingerprint;
}
