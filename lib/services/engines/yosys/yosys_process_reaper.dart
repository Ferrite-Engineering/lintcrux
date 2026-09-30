// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/widgets.dart';

/// Kills every Yosys process this app spawned when the app is tearing
/// down.
///
/// `crux_yosys` records each spawned process in a [ProcessRegistry] but
/// deliberately does not depend on Flutter, so it cannot observe the app
/// lifecycle itself — draining the registry is the host's job. Nothing
/// fails to compile if a product skips this, which is exactly why it is
/// easy to miss: the symptom only shows up in the wild, as a `yosys`
/// process left consuming a core after a hard quit or a parent crash.
///
/// ### Why `detached` only
///
/// [AppLifecycleState.detached] is the one state that means the app is
/// going away. `paused` / `hidden` / `inactive` all occur while the app
/// is still alive — on desktop merely minimising the window can produce
/// them — and a lint run legitimately continues in the background there.
/// Reaping on those states would cancel work the user is waiting for.
/// This is why the reaper does not simply ride
/// `WorkspaceLifecycleObserver.additionalFlushes`, which fires on
/// `paused` as well.
///
/// Mount one of these for the lifetime of the app; [YosysProcessReaper]
/// is the widget that does so.
class YosysProcessLifecycleObserver with WidgetsBindingObserver {
  /// Creates an observer draining [registry] on teardown. Defaults to the
  /// process-wide registry `DefaultProcessRunner` writes into.
  YosysProcessLifecycleObserver({ProcessRegistry? registry})
    : _registry = registry ?? ProcessRegistry.instance;

  final ProcessRegistry _registry;

  /// Number of processes signalled by the most recent reap. Zero until a
  /// teardown has happened. Exposed for tests and diagnostics.
  int get lastKillCount => _lastKillCount;
  int _lastKillCount = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) return;
    _lastKillCount = _registry.killAll();
  }
}

/// Installs a [YosysProcessLifecycleObserver] for as long as this widget
/// is mounted, then passes [child] straight through.
///
/// Mounted high in the tree (see `WorkspaceRoot`) so it covers the whole
/// app session.
class YosysProcessReaper extends StatefulWidget {
  /// Creates a reaper wrapping [child].
  const YosysProcessReaper({
    required this.child,
    this.registry,
    super.key,
  });

  /// The subtree this reaper wraps.
  final Widget child;

  /// Registry to drain. Defaults to `ProcessRegistry.instance`; tests
  /// inject their own so they never signal real processes.
  final ProcessRegistry? registry;

  @override
  State<YosysProcessReaper> createState() => _YosysProcessReaperState();
}

class _YosysProcessReaperState extends State<YosysProcessReaper> {
  late final YosysProcessLifecycleObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = YosysProcessLifecycleObserver(registry: widget.registry);
    WidgetsBinding.instance.addObserver(_observer);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
