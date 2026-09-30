// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/widgets/severity_chip.dart';
import 'package:lintcrux/features/violations/widgets/violation_row_focus.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/violation_context_menu_provider.dart';
import 'package:lintcrux/plugins/violation_row_leading_cells_provider.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/shared/widgets/lintcrux_feature_tier_badge.dart';

/// Stable row height used by the virtualized list.
const double kViolationRowHeight = 28;

/// One row in the violation table.
///
/// The keyboard does what the pointer does. Focus arriving on the row selects
/// the violation, as a click does, so the Details pane follows the arrow
/// keys; Enter opens it in the editor, as a double-click does; Shift+F10 or
/// the Menu key opens the context menu, as a right-click does; Space toggles
/// the check box.
class ViolationTableRow extends ConsumerStatefulWidget {
  /// Creates a [ViolationTableRow].
  const ViolationTableRow({required this.violation, this.focus, super.key});

  /// The violation to render.
  final Violation violation;

  /// The table's roving focus, which keeps the list to one Tab stop and
  /// moves between rows. Null for a row rendered outside a table, which is
  /// then an ordinary Tab stop.
  final ViolationRowFocus? focus;

  @override
  ConsumerState<ViolationTableRow> createState() => _ViolationTableRowState();
}

class _ViolationTableRowState extends ConsumerState<ViolationTableRow> {
  late final FocusNode _node = FocusNode(
    debugLabel: 'Violation row',
    onKeyEvent: _onKeyEvent,
  );

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChange);
    widget.focus?.attach(widget.violation, _node);
  }

  @override
  void didUpdateWidget(ViolationTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus ||
        oldWidget.violation != widget.violation) {
      oldWidget.focus?.detach(oldWidget.violation, _node);
      widget.focus?.attach(widget.violation, _node);
    }
  }

  @override
  void dispose() {
    widget.focus?.detach(widget.violation, _node);
    _node
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  /// Whether the row held primary focus when its node last notified.
  bool _hadPrimaryFocus = false;

  void _onFocusChange() {
    // A node also notifies when one of its properties changes — including
    // the Tab stop moving off it while it is still focused, as an arrow key
    // does — so only the arrival of focus counts.
    final hasPrimaryFocus = _node.hasPrimaryFocus;
    if (hasPrimaryFocus == _hadPrimaryFocus) return;
    _hadPrimaryFocus = hasPrimaryFocus;
    if (!hasPrimaryFocus) return;
    // Deferred: focus listeners run while the focus manager is still
    // iterating its dirty nodes, and moving the Tab stop changes
    // `skipTraversal`, which marks nodes dirty and throws there.
    scheduleMicrotask(() {
      if (!mounted || !_node.hasPrimaryFocus) return;
      widget.focus?.moveTabStopTo(widget.violation);
      ref.read(selectedViolationProvider.notifier).select(widget.violation);
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final keyboard = HardwareKeyboard.instance;
      final modified =
          keyboard.isControlPressed ||
          keyboard.isMetaPressed ||
          keyboard.isAltPressed;
      final key = event.logicalKey;
      if (!modified &&
          !keyboard.isShiftPressed &&
          (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter)) {
        unawaited(_openInEditor());
        return KeyEventResult.handled;
      }
      if (!modified &&
          ((key == LogicalKeyboardKey.f10 && keyboard.isShiftPressed) ||
              key == LogicalKeyboardKey.contextMenu)) {
        _showContextMenuFromKeyboard();
        return KeyEventResult.handled;
      }
    }
    return widget.focus?.handleKey(event) ?? KeyEventResult.ignored;
  }

  /// Selects the violation and opens it in the editor — the double-click
  /// action — reporting a launch failure the way the Details pane's Open in
  /// editor button does.
  Future<void> _openInEditor() async {
    final l10n = L10N.of(context);
    ref.read(selectedViolationProvider.notifier).select(widget.violation);
    final result = await ref
        .read(clickToSourceServiceProvider)
        .openInEditor(widget.violation.location);
    if (!mounted || result.success) return;
    showCruxErrorSnack(context, l10n.editorLaunchFailed('${result.command}'));
  }

  void _showContextMenuFromKeyboard() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    unawaited(
      _showContextMenu(box.localToGlobal(Offset(40, box.size.height))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final violation = widget.violation;
    final l10n = L10N.of(context);
    final id = ViolationTableState.idOf(violation);
    final selected = ref.watch(
      violationTableStateProvider.select(
        (s) => s.selectedRuleIds.contains(id),
      ),
    );
    final isInspected = ref.watch(
      selectedViolationProvider.select((v) => v == violation),
    );
    final notifier = ref.read(violationTableStateProvider.notifier);
    final selectionNotifier = ref.read(selectedViolationProvider.notifier);
    final leadingCells = ref.watch(violationRowLeadingCellsProvider);
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodySmall;
    // ONE announcement per row, not five.
    //
    // The cells are five separate `Text` widgets, which a screen reader reads
    // as five disconnected fragments with no column context — "verible",
    // "line-length", "top.sv", "42", "Line too long". Each is technically
    // labelled and the row is unusable. So the cells are excluded from
    // semantics and the row is read as this sentence instead.
    //
    // The sentence is the name of the row's check box, because the check box
    // is the row's one keyboard focus stop: a label anywhere else left Tab
    // landing on a bare "check box not checked" while the sentence sat on a
    // node focus never reaches. Severity resolves through `severityLabel`
    // rather than `.name` so the reader hears "Warning", not "warning"
    // spelled from an enum.
    final spoken = l10n.accessibilityViolationRow(
      severityLabel(l10n, violation.severity),
      violation.ruleId,
      violation.location.file,
      violation.location.line,
      violation.message,
    );
    final row = SizedBox(
      height: kViolationRowHeight,
      child: DecoratedBox(
        key: const ValueKey('violationRowBackground'),
        decoration: BoxDecoration(
          color: isInspected
              ? scheme.primaryContainer
              : (selected ? scheme.secondaryContainer : null),
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withAlpha(96)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Checkbox(
                key: ValueKey('violationRowCheckbox-$id'),
                focusNode: _node,
                value: selected,
                semanticLabel: spoken,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => notifier.toggleSelection(id),
              ),
            ),
            if (leadingCells.isNotEmpty)
              _LeadingCells(
                focus: widget.focus,
                violation: violation,
                children: [
                  for (final cell in leadingCells)
                    SizedBox(
                      width: cell.width,
                      child: Builder(
                        builder: (ctx) => cell.bodyBuilder(ctx, ref, violation),
                      ),
                    ),
                ],
              ),
            Expanded(
              // Shared "long-press = right-click" wrapper (crux_ide_layout).
              // isTouchLayout is false: LintCrux ships only desktop and a
              // desktop-class read-only web viewer and has no touch device
              // class, so long-press is auto-enabled only on genuine
              // iOS/Android hosts (which LintCrux does not target) — desktop
              // and web get right-click without the 500 ms long-press delay.
              //
              // Excluded from semantics as a whole: the check box already
              // speaks the row, and the only semantics action this gesture
              // area could contribute is the long-press menu on touch hosts,
              // which would otherwise surface as a second, nameless node.
              child: ExcludeSemantics(
                child: PlatformContextMenu(
                  onContextMenu: (position) =>
                      unawaited(_showContextMenu(position)),
                  // Select on primary-button pointer-down rather than through
                  // `GestureDetector.onTap`. `onTap` only fires once the tap
                  // recognizer WINS the gesture arena, and the `onDoubleTap`
                  // handler below keeps that arena open for the whole
                  // `kDoubleTapTimeout` (~300 ms). The observable result was
                  // the "left-click doesn't select" beta bug: a single click
                  // looked dead for a third of a second, and any second click
                  // inside that window was consumed as a double-tap — which
                  // opens the editor and never selects — so a normal
                  // click-a-row → see-source flow never produced a highlight,
                  // a rule-details pane or a source preview. Selecting on
                  // pointer-down is also what VS Code / IntelliJ do, and it
                  // makes double-click select AND open.
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (event) {
                      if (event.buttons == kPrimaryButton) {
                        selectionNotifier.select(violation);
                        // A later Tab into the list returns to the row the
                        // user clicked.
                        widget.focus?.moveTabStopTo(violation);
                      }
                    },
                    // Inner detector must NOT be opaque: opaque hit-testing
                    // claims long-press and would shadow the wrapper's context
                    // menu on touch hosts (the suite gesture-bubbling rule).
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: () async {
                        final svc = ref.read(clickToSourceServiceProvider);
                        await svc.openInEditor(violation.location);
                      },
                      // The visual cells stay exactly as they are: excluding
                      // them changes what is announced, not what is drawn.
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: SeverityIcon(
                                severity: violation.severity,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _cell(violation.engineId, textStyle),
                          ),
                          Expanded(
                            flex: 2,
                            child: _cell(violation.ruleId, textStyle),
                          ),
                          Expanded(
                            flex: 3,
                            child: _cell(violation.location.file, textStyle),
                          ),
                          Expanded(
                            child: _cell(
                              '${violation.location.line}',
                              textStyle,
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: Tooltip(
                              message: violation.message,
                              child: _cell(violation.message, textStyle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // The keyboard focus highlight: a ring around the whole row, not only the
    // check box's small focus overlay, so a sighted keyboard user can see
    // which row the arrow keys are on.
    return ListenableBuilder(
      listenable: _node,
      builder: (context, child) => DecoratedBox(
        key: const ValueKey('violationRowFocusRing'),
        position: DecorationPosition.foreground,
        decoration: _node.hasFocus
            ? BoxDecoration(border: Border.all(color: scheme.primary, width: 2))
            : const BoxDecoration(),
        child: child,
      ),
      child: row,
    );
  }

  Future<void> _showContextMenu(Offset position) async {
    final violation = widget.violation;
    final entries = ref.read(violationContextMenuEntriesProvider);
    if (entries.isEmpty) return;
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    // Select the row so the menu acts on the right-clicked violation,
    // not whatever was previously focused. Mirrors VS Code / IntelliJ.
    ref.read(selectedViolationProvider.notifier).select(violation);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final entry in entries)
          PopupMenuItem<String>(
            value: entry.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(child: Text(entry.labelBuilder(context))),
                if (entry.requiredTier != LicenseTier.openCore) ...[
                  const SizedBox(width: 8),
                  LintCruxFeatureTierBadge(requiredTier: entry.requiredTier),
                ],
              ],
            ),
          ),
      ],
    );
    if (selected == null) return;
    final entry = entries.firstWhere(
      (e) => e.id == selected,
      orElse: () => entries.first,
    );
    if (!mounted) return;
    await Future.sync(() => entry.onActivate(context, ref, violation));
  }

  Widget _cell(String text, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: style,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The overlay-contributed cells beside the check box, in the Tab order only
/// while their row holds the table's Tab stop. Without this, a per-row
/// control there (the Pro bookmark toggle) put one Tab stop per violation
/// back into a list that is meant to be one.
class _LeadingCells extends StatelessWidget {
  const _LeadingCells({
    required this.focus,
    required this.violation,
    required this.children,
  });

  final ViolationRowFocus? focus;
  final Violation violation;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final focus = this.focus;
    final cells = Row(mainAxisSize: MainAxisSize.min, children: children);
    if (focus == null) return cells;
    return ListenableBuilder(
      listenable: focus,
      builder: (context, child) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        descendantsAreTraversable: focus.isTabStop(violation),
        child: child!,
      ),
      child: cells,
    );
  }
}
