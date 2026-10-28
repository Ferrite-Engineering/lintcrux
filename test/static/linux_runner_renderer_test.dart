// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Linux runner must draw on a display that has no OpenGL.
///
/// Flutter's GTK embedder presents frames through a GDK OpenGL context, and
/// on a remote X display without GLX (VNC, X forwarding, ETX or NX) or a
/// virtual machine without 3D acceleration it logs "Failed to create OpenGL
/// context" and never shows the window. The runner probes for a context
/// before the view exists and selects the software renderer when there is
/// none; the software renderer draws through Skia, so Impeller has to be off
/// whenever it is selected, or the engine aborts at the first line of text.
///
/// A launch on such a display is what proves the behaviour; these checks
/// keep the pieces from being lost in an edit of the runner.
void main() {
  final runner = File('linux/runner/my_application.cc').readAsStringSync();

  String activateBody() {
    final start = runner.indexOf(
      'static void my_application_activate(GApplication* application) {',
    );
    expect(start, isNonNegative, reason: 'no my_application_activate');
    final end = runner.indexOf('\n}\n', start);
    return runner.substring(start, end);
  }

  test('the probe runs before the Flutter view is created', () {
    final body = activateBody();
    final probe = body.indexOf('select_renderer_for_display();');
    final view = body.indexOf('fl_view_new(');
    expect(probe, isNonNegative, reason: 'activate never probes the display');
    expect(view, isNonNegative);
    expect(
      probe,
      lessThan(view),
      reason: 'the engine reads FLUTTER_LINUX_RENDERER inside fl_view_new',
    );
  });

  test('the probe leaves a renderer the user chose alone', () {
    expect(
      runner,
      contains('if (g_getenv("FLUTTER_LINUX_RENDERER") != nullptr) {'),
    );
    // FALSE: never overwrite a value that is already set.
    expect(
      runner,
      contains('g_setenv("FLUTTER_LINUX_RENDERER", "software", FALSE);'),
    );
    expect(runner, contains('gdk_window_create_gl_context('));
    expect(runner, contains('gdk_gl_context_realize('));
  });

  test('the fallback says so on stderr', () {
    // The launch smoke looks for this phrase to tell an automatic fallback
    // from a display that simply had OpenGL.
    // Adjacent C string literals are one string to the compiler.
    final joined = runner.replaceAll(RegExp(r'"\s*\n\s*"'), '');
    expect(
      joined,
      contains(
        '"LintCrux: OpenGL is unavailable on this display (%s); falling back '
        'to the software renderer.',
      ),
    );
  });

  test('Impeller is off whenever the software renderer is selected', () {
    final body = activateBody();
    final guard = body.indexOf(
      'if (g_strcmp0(g_getenv("FLUTTER_LINUX_RENDERER"), "software") == 0) {',
    );
    final off = body.indexOf(
      'fl_dart_project_set_enable_impeller(project, FALSE);',
    );
    final view = body.indexOf('fl_view_new(');
    expect(guard, isNonNegative);
    expect(off, greaterThan(guard));
    expect(off, lessThan(view));
  });
}
