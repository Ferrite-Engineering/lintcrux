// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Every built-in preset paints LintCrux's shared chrome from its own chrome
// tokens where it declares them, and from the Material theme `app.dart` builds
// where it does not. The status bar, splitter, document tab bar and active
// toolbar glyph tokens reach their shared widgets through `applyChromeTokens`
// as `CruxChromeColors`; a null field there means the widget keeps its
// Material default: the status bar `surfaceContainerHighest` behind `onSurface`
// at 75 %, the pane resizers `outlineVariant` and `primary` on hover, the
// active document tab `surfaceContainerHighest` under `bodyMedium` titles on an
// unfilled strip, and a toggled toolbar glyph `primary`.
//
// This pumps those widgets under every theme `app.dart` can show for each
// preset (the normal and the high-contrast variant of its brightness), built
// the same way, and asserts each colour against the resolved token or its
// fallback. Both paths are exercised: the two default-Material presets declare
// no chrome token, and the four branded presets declare the active glyph and
// both splitter colours (High Contrast Dark every one of the ten), so a widget
// that stopped reading a token would fail on the branded presets and one that
// stopped falling back would fail on the default ones. Text reaches the engine
// as 32-bit ARGB, so text colour is compared that way.

import 'dart:io';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/theme/lintcrux_theme.dart';
import 'package:lintcrux/core/theme/lintcrux_theme_tokens.dart';

class _Layout implements IdePanelLayout {
  @override
  bool get leftVisible => true;
  @override
  bool get rightVisible => false;
  @override
  bool get bottomVisible => false;
  @override
  PaneSize? get leftSize => PaneSize.pixel(200);
  @override
  PaneSize? get rightSize => null;
  @override
  PaneSize? get bottomSize => null;
}

class _Sink implements IdePanelLayoutSink {
  @override
  void setLeftVisible({required bool visible}) {}
  @override
  void setRightVisible({required bool visible}) {}
  @override
  void setBottomVisible({required bool visible}) {}
  @override
  void setLeftSize(double pixels) {}
  @override
  void setRightSize(double pixels) {}
  @override
  void setBottomSize(double pixels) {}
}

class _StringCodec extends WorkspaceCodec<String> {
  const _StringCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'v': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['v'] as String? ?? '';

  @override
  String displayNameFor(String p) => p;
}

/// The themes `app.dart` hands MaterialApp for [preset], keyed by the
/// variant MaterialApp shows for that preset's brightness.
Map<String, ThemeData> _appThemes(CruxColorTheme preset) {
  final chromeExt = CruxThemeExtension(theme: preset);
  ThemeData build(ThemeData base) => applyChromeTokens(
    base.copyWith(extensions: <ThemeExtension<dynamic>>[chromeExt]),
    chromeExt,
  );
  return preset.brightness == Brightness.light
      ? {
          'light': build(LintcruxTheme.light()),
          'high-contrast light': build(LintcruxTheme.highContrastLight()),
        }
      : {
          'dark': build(LintcruxTheme.dark()),
          'high-contrast dark': build(LintcruxTheme.highContrastDark()),
        };
}

void main() {
  setUpAll(registerLintcruxThemeTokens);

  late Directory tempDir;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lintcrux_chrome_');
    final service = WorkspaceService<String>(
      codec: const _StringCodec(),
      directoryFactory: () async => tempDir,
      logger: (_) {},
    );
    provider =
        AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
          () => WorkspaceNotifier<String>(
            service: service,
            autoSaveDebounce: Duration.zero,
          ),
        );
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  for (final preset in builtinPresets().values) {
    for (final variant in _appThemes(preset).entries) {
      testWidgets('${preset.id} (${variant.key}) paints its declared chrome, '
          'else the Material fallback', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final ws = await container.read(provider.future);
        final notifier = container.read(provider.notifier);
        await notifier.openTab(displayName: 'alpha', payload: 'a');
        await notifier.openTab(displayName: 'beta', payload: 'b');

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: variant.value,
              home: Scaffold(
                body: Column(
                  children: [
                    CruxToolbarButton(
                      key: const ValueKey<String>('toggled'),
                      icon: Icons.sensors,
                      tooltip: 'Cross-probe',
                      onPressed: () {},
                      metrics: CruxToolbarMetrics.desktop,
                      isSelected: true,
                    ),
                    SizedBox(
                      height: 40,
                      child: ViewerTabBar<String>(
                        paneId: ws.activePaneId,
                        provider: provider,
                      ),
                    ),
                    Expanded(
                      child: CruxIdeLayout(
                        layout: _Layout(),
                        sink: _Sink(),
                        leftBuilder: (_, _) => const SizedBox.expand(),
                        centerBuilder: (_, _) => const SizedBox.expand(),
                        rightBuilder: (_, _) => const SizedBox.expand(),
                        bottomBuilder: (_, _) => const SizedBox.expand(),
                      ),
                    ),
                    const CruxStatusBar(
                      segments: [CruxStatusSegment('status')],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final theme = Theme.of(tester.element(find.byType(CruxStatusBar)));
        final scheme = theme.colorScheme;
        final resolved = theme.extension<CruxChromeColors>();
        expect(resolved, isNotNull, reason: 'applyChromeTokens did not run');
        final chrome = resolved ?? const CruxChromeColors();

        // The premise of both paths below: the branded presets declare the
        // tokens, the default-Material ones declare none.
        const branded = <String>{
          'solarized-dark',
          'high-contrast-dark',
          'oscilloscope',
          'oled-xr',
        };
        if (branded.contains(preset.id)) {
          expect(chrome.toolbarIconActive, isNotNull, reason: preset.id);
          expect(chrome.splitter, isNotNull, reason: preset.id);
          expect(chrome.splitterHover, isNotNull, reason: preset.id);
        } else {
          expect(chrome.isEmpty, isTrue, reason: preset.id);
        }

        // Toolbar: a toggled-on glyph.
        expect(
          tester
              .widget<Icon>(
                find.descendant(
                  of: find.byKey(const ValueKey<String>('toggled')),
                  matching: find.byType(Icon),
                ),
              )
              .color,
          chrome.toolbarIconActive ?? scheme.primary,
        );

        // Document tab bar: the strip fill (none unless declared), the active
        // tab, the titles.
        final strip = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(ViewerTabBar<String>),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
          (strip.decoration as BoxDecoration).color,
          chrome.tabBarBackground,
        );
        Color? chip(String title) =>
            (tester
                        .widget<Container>(
                          find
                              .ancestor(
                                of: find.text(title),
                                matching: find.byType(Container),
                              )
                              .first,
                        )
                        .decoration!
                    as BoxDecoration)
                .color;
        expect(
          chip('beta'),
          chrome.tabBarSelected ?? scheme.surfaceContainerHighest,
        );
        expect(chip('alpha'), isNull);
        final label = chrome.tabBarLabel;
        for (final title in ['alpha', 'beta']) {
          expect(
            tester.widget<Text>(find.text(title)).style,
            label == null
                ? theme.textTheme.bodyMedium
                : theme.textTheme.bodyMedium?.copyWith(color: label),
          );
        }

        // Pane resizer: the visible bar is the second of the containers
        // under the resizer's mouse region.
        final resizer = find
            .byWidgetPredicate(
              (w) =>
                  w is MouseRegion &&
                  w.cursor == SystemMouseCursors.resizeColumn,
            )
            .first;
        Color? resizerBar() => tester
            .widgetList<Container>(
              find.descendant(of: resizer, matching: find.byType(Container)),
            )
            .elementAt(1)
            .color;
        expect(resizerBar(), chrome.splitter ?? scheme.outlineVariant);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(resizer));
        await tester.pump();
        expect(resizerBar(), chrome.splitterHover ?? scheme.primary);

        // Status bar: the surface and the text. A declared foreground is
        // painted exactly as given (Solarized Dark's opaque `#93A1A1`, which
        // the 75 % blend fell short of WCAG AA on; Oscilloscope's and OLED XR's
        // translucent ones); every other preset keeps the blend.
        final bar = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(CruxStatusBar),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
          (bar.decoration as BoxDecoration).color,
          chrome.statusBarBackground ?? scheme.surfaceContainerHighest,
        );
        expect(
          tester.widget<Text>(find.text('status')).style?.color?.toARGB32(),
          (chrome.statusBarForeground ??
                  scheme.onSurface.withValues(alpha: 0.75))
              .toARGB32(),
        );
      });
    }
  }
}
