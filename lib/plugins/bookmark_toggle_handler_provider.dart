// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Extension point that, when invoked, toggles a bookmark for [violation]
/// in the Pro overlay's bookmark store.
///
/// Declared in the open core, read only by the Pro overlay's bookmark column
/// icon. The Toggle Bookmark action does not come through here: it
/// dispatches through `toggleBookmarkOpenerProvider`, and the overlay points
/// both at the same bookmark dialog. The handler inspects
/// `violationBookmarkStoreProvider` to decide whether to create or edit the
/// bookmark, opening the Pro bookmark dialog so the user can attach a note
/// and color tag.
///
/// The default is a no-op — the bookmark feature is Pro.
typedef BookmarkToggleHandler =
    FutureOr<void> Function(
      BuildContext context,
      WidgetRef ref,
      Violation violation,
    );

/// Seam through which the Pro overlay registers its bookmark toggle handler.
/// The default is a no-op; nothing in the open core reads it.
final Provider<BookmarkToggleHandler> bookmarkToggleHandlerProvider =
    Provider<BookmarkToggleHandler>(
      (_) => (_, _, _) {},
    );
