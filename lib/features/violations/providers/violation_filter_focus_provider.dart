// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-tab [FocusNode] for the rule-substring filter text field in the
/// violation table's filter chip strip.
///
/// Owned by Riverpod so the `focusSearch` action handler in `app.dart`
/// can request focus into the active tab's filter field without
/// reaching into the widget tree. The provider is scoped per-tab — each
/// tab container constructs its own FocusNode, so focus state never
/// leaks across tabs.
///
/// The FocusNode is disposed when the per-tab provider container is
/// torn down (tab close).
final Provider<FocusNode> violationFilterRuleFocusProvider =
    Provider<FocusNode>((ref) {
      final node = FocusNode(debugLabel: 'violationFilterRuleField');
      ref.onDispose(node.dispose);
      return node;
    });
