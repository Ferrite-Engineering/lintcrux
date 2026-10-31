// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show File, FileSystemException;

import 'package:lintcrux/domain/enums/elaboration_time_limit.dart';

/// The watchdog budget of an engine that elaborates the design with Yosys
/// (`EngineCapabilities.elaboratesWithYosys`).
///
/// Before a run only the size of the sources is known, so the budget scales
/// linearly with it at [bytesPerSecond]: a throughput well below what Yosys
/// reaches, so a design that is merely large is never stopped, while a
/// wedged Yosys still is. Yosys read and elaborated a 660 MB structural
/// netlist of five million gates in 403 s on a fast desktop (1.6 MB/s); at
/// 256 KB/s that source is given 44 minutes, six and a half times as long,
/// which leaves room for a machine several times slower. The ceiling is a
/// sanity bound far above any design; the user can remove the limit
/// altogether, and Cancel always stops a run.
///
/// The floor is [floor] or the engine timeout the caller already applies to
/// every engine, whichever is longer, so a small design never gets less time
/// than it had before the budget scaled.
abstract final class YosysEngineBudget {
  /// The least budget, before the caller's engine timeout raises it.
  static const Duration floor = Duration(seconds: 30);

  /// Largest automatic budget. A source this large would be about 11 GB.
  static const Duration ceiling = Duration(hours: 12);

  /// Throughput the budget is computed from.
  static const int bytesPerSecond = 256 * 1024;

  /// The budget for [sourceBytes] of source under [limit], or `null` for
  /// [ElaborationTimeLimit.none]: no timer.
  ///
  /// [minimum] raises [floor]: the engine timeout the other engines get.
  static Duration? forSourceBytes(
    int sourceBytes, {
    ElaborationTimeLimit limit = ElaborationTimeLimit.automatic,
    Duration minimum = Duration.zero,
  }) {
    if (limit == ElaborationTimeLimit.none) return null;
    final least = minimum > floor ? minimum : floor;
    final scaledMs = sourceBytes / bytesPerSecond * 1000;
    var base = Duration(milliseconds: scaledMs.round());
    if (base < least) base = least;
    if (base > ceiling) base = ceiling;
    return base * limit.factor;
  }

  /// The total size of [paths] in bytes. A file that cannot be read counts
  /// as empty: the engine reports it in its own words.
  static Future<int> sourceBytesOf(Iterable<String> paths) async {
    var total = 0;
    for (final path in paths) {
      try {
        total += await File(path).length();
      } on FileSystemException {
        // Missing or unreadable; see above.
      }
    }
    return total;
  }
}
