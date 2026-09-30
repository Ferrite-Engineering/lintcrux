// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Keyboard focus across the rows of the violation table: one Tab stop for
/// the whole list, with Up, Down, Home and End moving between rows.
///
/// A report can hold tens of thousands of violations, and a Tab stop per row
/// put every one of them between the filters and the Details pane. The table
/// owns one controller; each built row attaches its focus node, and only the
/// row holding the Tab stop is in the traversal order. The list is
/// virtualized, so moving to a row that has not been built scrolls it into
/// view first and focuses it once it has been laid out.
///
/// Listeners are notified when the Tab stop moves outside a build, so a row
/// can keep its other controls (the Pro overlay's leading cells) in the Tab
/// order only while it holds the stop.
class ViolationRowFocus extends ChangeNotifier {
  /// Creates the controller for a list scrolled by [scrollController] whose
  /// rows are all [rowExtent] logical pixels tall.
  ViolationRowFocus({required this.scrollController, required this.rowExtent});

  /// The list's scroll controller, used to bring a target row into view.
  final ScrollController scrollController;

  /// The fixed height of one row.
  final double rowExtent;

  List<Violation> _order = const <Violation>[];
  int _stopIndex = 0;
  final Map<Violation, FocusNode> _nodes = <Violation, FocusNode>{};

  /// A row focus was requested for before it was built; attaching rows do
  /// not adopt the Tab stop while it is pending.
  Violation? _pendingFocus;

  bool _disposed = false;

  /// The violation whose row holds the list's Tab stop, or null when the
  /// list is empty.
  Violation? get tabStop => _order.isEmpty ? null : _order[_stopIndex];

  /// Whether [violation]'s row holds the Tab stop.
  bool isTabStop(Violation violation) => tabStop == violation;

  /// Records the rows in on-screen order.
  ///
  /// The Tab stop stays on the same violation when it is still listed, and
  /// otherwise on the row at the same position. Called from the table's
  /// build, so listeners are not notified: every row rebuilds anyway.
  void sync(List<Violation> order) {
    final previous = tabStop;
    _order = order;
    if (order.isEmpty) {
      _stopIndex = 0;
      return;
    }
    var index = -1;
    if (previous != null) {
      index = _stopIndex < order.length && order[_stopIndex] == previous
          ? _stopIndex
          : order.indexOf(previous);
    }
    _stopIndex = index == -1 ? _stopIndex.clamp(0, order.length - 1) : index;
    _updateTraversal(previous, notify: false);
  }

  /// Registers the focus node of [violation]'s row.
  ///
  /// When the row holding the Tab stop is not built, the first row built
  /// afterwards takes the stop, so Tab still has a way into the list.
  void attach(Violation violation, FocusNode node) {
    _nodes[violation] = node;
    final stop = tabStop;
    if (stop != null &&
        stop != violation &&
        _pendingFocus == null &&
        _nodes[stop] == null) {
      final index = _order.indexOf(violation);
      if (index != -1) {
        _stopIndex = index;
        _notifySoon();
      }
    }
    node.skipTraversal = !isTabStop(violation);
  }

  /// Unregisters [node] if it is still the node registered for [violation].
  ///
  /// When that row held the Tab stop — it scrolled out of the built range,
  /// or a new sort moved its violation there — the built row nearest to it
  /// takes the stop, so Tab still has a way into the list.
  void detach(Violation violation, FocusNode node) {
    if (!identical(_nodes[violation], node)) return;
    _nodes.remove(violation);
    if (violation != tabStop || _pendingFocus != null) return;
    var nearest = -1;
    for (final built in _nodes.keys) {
      final index = _order.indexOf(built);
      if (index == -1) continue;
      if (nearest == -1 ||
          (index - _stopIndex).abs() < (nearest - _stopIndex).abs()) {
        nearest = index;
      }
    }
    if (nearest == -1) return;
    _stopIndex = nearest;
    _nodes[_order[nearest]]?.skipTraversal = false;
    _notifySoon();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Notifies listeners after the current build or unmount pass, where a
  /// listener's rebuild request would be rejected.
  void _notifySoon() {
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  /// Moves the Tab stop to [violation] without moving focus: after a pointer
  /// selection, or once focus has arrived on the row by other means.
  void moveTabStopTo(Violation violation) {
    if (tabStop == violation) return;
    final index = _order.indexOf(violation);
    if (index == -1) return;
    final previous = tabStop;
    _stopIndex = index;
    _updateTraversal(previous);
  }

  /// Handles the row-movement keys for the focused row. Modified presses
  /// are left alone, so Ctrl+Shift+Arrow still resizes the pane.
  KeyEventResult handleKey(KeyEvent event) {
    if (event is KeyUpEvent || _order.isEmpty) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final int target;
    if (key == LogicalKeyboardKey.arrowDown) {
      target = _stopIndex + 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      target = _stopIndex - 1;
    } else if (key == LogicalKeyboardKey.home) {
      target = 0;
    } else if (key == LogicalKeyboardKey.end) {
      target = _order.length - 1;
    } else {
      return KeyEventResult.ignored;
    }
    focusRow(target);
    return KeyEventResult.handled;
  }

  /// Moves the Tab stop to the row at [index], scrolls it into view and
  /// focuses it — at once when the row is built, otherwise after the frame
  /// that builds it.
  void focusRow(int index) {
    if (_order.isEmpty) return;
    final previous = tabStop;
    _stopIndex = index.clamp(0, _order.length - 1);
    final target = _order[_stopIndex];
    _updateTraversal(previous);
    _reveal(_stopIndex);
    final node = _nodes[target];
    if (node != null && node.context != null) {
      node.requestFocus();
      return;
    }
    _pendingFocus = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingFocus != target) return;
      _pendingFocus = null;
      if (tabStop == target) _nodes[target]?.requestFocus();
    });
  }

  void _reveal(int index) {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final top = index * rowExtent;
    final bottom = top + rowExtent;
    double? offset;
    if (top < position.pixels) {
      offset = top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      offset = bottom - position.viewportDimension;
    }
    if (offset == null) return;
    scrollController.jumpTo(
      offset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _updateTraversal(Violation? previous, {bool notify = true}) {
    final stop = tabStop;
    if (previous == stop) return;
    if (previous != null) _nodes[previous]?.skipTraversal = true;
    if (stop != null) _nodes[stop]?.skipTraversal = false;
    if (notify) notifyListeners();
  }
}
