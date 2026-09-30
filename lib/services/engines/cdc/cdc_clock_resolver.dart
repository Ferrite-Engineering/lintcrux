// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart';
import 'package:meta/meta.dart';

/// Decides, for one register, which clock domain it belongs to — and whether
/// two domains are asynchronous to each other.
///
/// **The seam where the tier split actually lives.** Clock inference is the
/// hardest part on real designs and the main driver of false positives: everything else in
/// CDC analysis is bookkeeping over a graph, but deciding *what counts as a
/// clock* is where a tool either earns trust or loses it.
///
/// Open core resolves a clock to the literal net bit driving `CLK` and treats
/// every distinct net as its own asynchronous domain. That is the safe, noisy
/// setting: it cannot miss a crossing, and it will report crossings that are
/// not real whenever a clock passes through a buffer, a gate, or a divider,
/// because the far side looks like a different net.
///
/// The Pro implementation traces the clock tree and consults declared
/// constraints, which is what turns the noisy-but-safe answer into a usable
/// one. Both live behind this interface so the analysis itself never branches
/// on tier.
@immutable
abstract class CdcClockResolver {
  /// Const constructor for subclasses.
  const CdcClockResolver();

  /// The canonical domain key for a register clocked by [clockBit].
  ///
  /// Two registers are in the same domain iff this returns equal keys, so a
  /// resolver that traces `clk` through a buffer to the same root collapses
  /// what open core would report as a crossing.
  Object domainKeyFor(int clockBit, Module module);

  /// Human-facing name for a domain key.
  String domainNameFor(Object key, Map<int, String> netNames);

  /// Whether a transfer between two distinct domain keys is a genuine
  /// asynchronous crossing worth reporting.
  ///
  /// Open core answers `true` for every distinct pair — it has no clock
  /// relationship model, so it must assume the worst. A resolver with
  /// constraints can answer `false` for clocks the user declared synchronous,
  /// which is the single largest false-positive reduction available.
  bool isAsynchronous(CdcDomainQuery query);
}

/// The question [CdcClockResolver.isAsynchronous] answers.
///
/// A record rather than three positional parameters because deciding whether
/// two clocks are related needs more than their keys: the Pro resolver walks
/// the clock tree in [module] to see whether they share a root, and reads
/// [netNames] to match them against user-declared relationships. Open core uses
/// neither. Bundling them keeps the open-core implementation a one-liner while
/// leaving the richer implementation room to work.
@immutable
class CdcDomainQuery {
  /// Creates a query.
  const CdcDomainQuery({
    required this.sourceKey,
    required this.destKey,
    required this.module,
    required this.netNames,
  });

  /// Domain key of the driving register.
  final Object sourceKey;

  /// Domain key of the sampling register.
  final Object destKey;

  /// The module both live in.
  final Module module;

  /// Net bit -> name, for matching against declared clock names.
  final Map<int, String> netNames;
}

/// The open-core resolver: one net bit, one domain, everything asynchronous.
///
/// Deliberately the pessimistic answer. A CDC tool that under-reports is
/// dangerous in a way one that over-reports is not, and open core has no
/// constraints input with which to safely narrow anything. The honesty is in
/// saying so — see the engine's rule messages: this is structural CDC lint,
/// not sign-off.
class LiteralCdcClockResolver extends CdcClockResolver {
  /// Creates the resolver.
  const LiteralCdcClockResolver();

  @override
  Object domainKeyFor(int clockBit, Module module) => clockBit;

  @override
  String domainNameFor(Object key, Map<int, String> netNames) =>
      key is int ? netNames[key] ?? 'net\$$key' : key.toString();

  @override
  bool isAsynchronous(CdcDomainQuery query) => query.sourceKey != query.destKey;
}
