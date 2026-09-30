// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;

/// The text a failed project open shows the user.
///
/// A design-manifest conflict is explained in the user's language; every other
/// failure keeps the service's own message.
String openProjectFailureText(L10N l10n, OpenProjectFailure failure) =>
    switch (failure) {
      OpenProjectManifestAmbiguous(:final error) =>
        l10n.openProjectAmbiguousManifests(
          error.directory,
          error.candidates.map(p.basename).join(', '),
        ),
      _ => failure.message,
    };

/// Tells the user how a project open went: an announced error snackbar for a
/// failure, and — once per open — an announced info snackbar asking them to
/// rename a design manifest that still has the legacy bare `.crux-project`
/// name. A plain success shows nothing; the new tab is the feedback.
void showOpenProjectOutcome(BuildContext context, OpenProjectResult result) {
  if (!context.mounted) return;
  final l10n = L10N.of(context);
  switch (result) {
    case OpenProjectFailure():
      showCruxErrorSnack(context, openProjectFailureText(l10n, result));
    case OpenProjectSuccess(legacyManifestRenameTo: final String renameTo):
      showCruxInfoSnack(context, l10n.openProjectLegacyManifestName(renameTo));
    case OpenProjectSuccess():
      break;
  }
}
