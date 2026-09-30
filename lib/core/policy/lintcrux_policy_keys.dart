// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart';

/// LintCrux's namespace in `.crux-policy.json`, and its audit event kinds.
///
/// **These declare the keys; they do not implement the features the keys
/// configure.** Theme packs, workspace templates, symbol libraries, the
/// retention policy and the CI gate threshold are separate follow-ups that
/// become small once this exists. What this file buys is that a key an
/// administrator writes is a key the application honours, with the shared
/// precedence and the shared diagnostics.
///
/// The normative schema is the suite policy reference
/// (https://edacrux.app/policy-reference). Register against **its** key
/// names: it unifies keys the four products once named differently, so an
/// older product-specific spelling is not authoritative here.
abstract final class LintCruxPolicyKeys {
  /// The product id this namespace lives under.
  static const String productId = 'lintcrux';

  /// `products.lintcrux.ruleSeverityOverrides` — org-wide rule-severity overrides.
  static const String ruleSeverityOverrides = 'ruleSeverityOverrides';

  /// `products.lintcrux.mandatoryEngines` — engines every run must include.
  static const String mandatoryEngines = 'mandatoryEngines';

  /// `products.lintcrux.ciGateThreshold` — the violation count a CI run may not exceed.
  static const String ciGateThreshold = 'ciGateThreshold';

  /// `products.lintcrux.teamDatabaseSubmitter` — the name pooled runs are
  /// attributed to in the shared team trend database.
  ///
  /// Registered here rather than in the Pro overlay because the namespace is
  /// per product, not per tier: an administrator writes one file for LintCrux,
  /// and which of its keys happen to configure a licensed feature is not
  /// something they should have to know.
  static const String teamDatabaseSubmitter = 'teamDatabaseSubmitter';

  /// Every key this product registers, for the conformance test.
  static const Set<String> all = <String>{
    ruleSeverityOverrides,
    mandatoryEngines,
    ciGateThreshold,
    teamDatabaseSubmitter,
  };
}

/// The audit events LintCrux records.
///
/// **Kinds are per-product on purpose.** The envelope is shared; a shared enum
/// of kinds would need editing in `crux-shared` every time any one of four
/// products learned a new event.
abstract final class LintCruxAuditKinds {
  /// `waiver.created`
  static const String waiverCreated = 'waiver.created';

  /// `waiver.modified`
  static const String waiverModified = 'waiver.modified';

  /// `waiver.deleted`
  static const String waiverDeleted = 'waiver.deleted';

  /// `severity.overridden`
  static const String severityOverridden = 'severity.overridden';

  /// `engine.config.changed`
  static const String engineConfigChanged = 'engine.config.changed';

  /// `baseline.rebased`
  static const String baselineRebased = 'baseline.rebased';

  /// Every kind this product registers, for the conformance test.
  static const Set<String> all = <String>{
    waiverCreated,
    waiverModified,
    waiverDeleted,
    severityOverridden,
    engineConfigChanged,
    baselineRebased,
  };
}

/// A resolver scoped to this product's namespace.
///
/// A key naming a *different* product is ignored silently — one file serves a
/// mixed fleet, so a LintCrux install meeting another product's keys is the
/// normal case rather than a misconfiguration.
PolicyResolver lintcruxPolicyResolver(PolicyDocument document) =>
    PolicyResolver(document: document, productId: LintCruxPolicyKeys.productId);
