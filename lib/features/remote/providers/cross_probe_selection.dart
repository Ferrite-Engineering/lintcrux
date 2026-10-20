// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';
import 'package:lintcrux/services/workspace/active_tab_container_handle.dart';
import 'package:path/path.dart' as p;

/// The violation [violation] as a cross-probe selection: every element kind it
/// can be named in, most precise first.
///
/// * a `rule` element, which LintCrux itself shows;
/// * a `scope` element, the module the source file declares by name, which
///   NetCrux shows;
/// * a `source` element, `file:line:column`, which WaveCrux shows.
///
/// The shared target table picks the one each peer prefers and can show. A
/// candidate with no usable path (a violation with no source line) is left
/// out. [project] attaches the design id, so a peer with none of this design
/// open can resolve and open it.
CrossProbeSelection crossProbeSelectionForViolation(
  Violation violation, {
  LintProject? project,
}) {
  final loc = violation.location;
  final rulePath = LintCruxNameResolver.encodeViolationAsRulePath(violation);
  final module = p.basenameWithoutExtension(loc.file);
  final designId = project == null ? null : cxpLintcruxDesignId(project);
  return CrossProbeSelection(
    candidates: <ElementId>[
      if (rulePath != null) ElementId(kind: ElementKind.rule, path: rulePath),
      if (module.isNotEmpty) ElementId(kind: ElementKind.scope, path: module),
      if (loc.line >= 1)
        ElementId(
          kind: ElementKind.source,
          path: '${loc.file}:${loc.line}:${loc.column}',
        ),
    ],
    displayName: violation.message,
    metadata: <String, Object?>{
      'lintcrux.violation_severity': violation.severity.name,
      cxpDesignIdMetadataKey: ?designId,
    },
  );
}

/// The selection of the ACTIVE tab: its selected violation, or null when none
/// is selected.
///
/// The selection and the project are per-tab, and the callers (the docked
/// panel, the command) live in the root scope, so the active tab's container
/// is resolved through [activeTabContainerHandleProvider] at the moment the
/// selection is needed. With no active tab the root scope answers, which has
/// no selection.
CrossProbeSelection? activeTabCrossProbeSelection(CruxCxpReader read) {
  final container = read(activeTabContainerHandleProvider).activeContainer;
  final violation = container == null
      ? read(selectedViolationProvider)
      : container.read(selectedViolationProvider);
  if (violation == null) return null;
  final project = container == null
      ? read(currentProjectProvider)
      : container.read(currentProjectProvider);
  return crossProbeSelectionForViolation(violation, project: project);
}
