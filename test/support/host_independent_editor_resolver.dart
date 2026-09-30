// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/services/editor/click_to_source_service.dart';

/// An editor resolver that answers the same on every host: nothing is on
/// `PATH`, no app-bundle CLI exists, and the host is neither macOS nor
/// Windows, so `resolve` hands back the configured command unchanged.
///
/// The production resolver consults the real platform. On Windows it turns
/// a bare `code` into an absolute path found on `PATH`, and throws when
/// nothing answers, so a missing editor is a failed launch rather than a
/// search of the launch folder. A CI runner has no `code` on `PATH`, so a
/// test that builds a `ClickToSourceService` with the default resolver and
/// a fake launcher sees every launch fail on Windows before the launcher is
/// reached. Tests about something other than resolution inject this one;
/// the resolution rules themselves are pinned in
/// `test/services/editor/click_to_source_service_test.dart`.
const MacOsBundleEditorResolver hostIndependentEditorResolver =
    MacOsBundleEditorResolver(
      isMacOs: false,
      isWindows: false,
      fileExists: _nothingExists,
    );

bool _nothingExists(String _) => false;
