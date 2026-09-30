// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether the app is running in the browser.
///
/// Used by the bootstrap path and the router to swap in the web
/// read-only flow (no CLI parsing, no file watcher, no engine
/// orchestration) on web targets. Equivalent to Flutter's `kIsWeb`
/// — re-exported here so feature code reads from a `lintcrux/`
/// path rather than a Flutter foundation path, keeping the
/// browser/desktop distinction explicit at every call site.
const bool isWebMode = kIsWeb;
