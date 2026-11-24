// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// `lintcrux rule <engine>/<rule> --json`: what a rule is, by the
/// `engineId/ruleId` a finding gives.
///
/// The answer is the one the SARIF export's rule descriptor gives on the
/// command line: the rule's id as its title, the default severity from the
/// bundled rule database, and the engine's help page for the rule. The
/// bundled databases carry no prose, so `description` is empty and the help
/// link is where the rule is explained.
library;

import 'package:crux_mcp/crux_mcp.dart';
import 'package:lintcrux/services/rules/bundled_rule_catalogue.dart';
import 'package:lintcrux/services/rules/bundled_rule_help.dart';

/// The command's name, which is also the tool's.
const String kRuleCommand = 'rule';

/// The document `lintcrux rule <id> --json` writes, for the engines in
/// [engineIds].
///
/// A malformed id is a `usage_error`; an engine LintCrux does not have is an
/// `input_error` (`rule.unknown_engine`). A rule the bundled database does
/// not list is still answered, from its engine's help-link pattern, with a
/// `rule.not_catalogued` warning saying so: engines report rules their
/// database does not name, and the SARIF export describes those the same way.
McpDocument ruleDocument({
  required McpProgram program,
  required String id,
  required List<String> engineIds,
}) {
  final slash = id.indexOf('/');
  if (slash <= 0 || slash == id.length - 1) {
    return McpDocument.usage(
      tool: program,
      command: kRuleCommand,
      message:
          '`$id` is not a rule id: give engineId/ruleId, as a finding '
          'names it (verilator/WIDTH).',
    );
  }
  final engine = id.substring(0, slash);
  final local = id.substring(slash + 1);
  if (!engineIds.contains(engine)) {
    return McpDocument(
      tool: program,
      command: kRuleCommand,
      outcome: McpOutcome.inputError,
      diagnostics: <McpDiagnostic>[
        McpDiagnostic.error(
          'rule.unknown_engine',
          'LintCrux has no engine `$engine`. Its engines are '
              '${engineIds.join(', ')}.',
        ),
      ],
    );
  }
  final severity = kBundledRuleSeverities[id];
  return McpDocument(
    tool: program,
    command: kRuleCommand,
    outcome: McpOutcome.completed,
    body: <String, Object?>{
      'id': id,
      'engine': engine,
      'title': local,
      'description': '',
      'default_severity': severity,
      'help_uri': bundledRuleHelpUri(engine, local)?.toString(),
    },
    diagnostics: <McpDiagnostic>[
      if (severity == null)
        McpDiagnostic.warning(
          'rule.not_catalogued',
          "`$id` is not in LintCrux's rule database for $engine, so it has "
              'no default severity here, and its help link follows '
              "$engine's documentation pattern without having been checked.",
        ),
    ],
  );
}
