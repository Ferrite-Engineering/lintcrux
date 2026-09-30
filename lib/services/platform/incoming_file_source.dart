// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('lintcrux.platform');

/// Files the operating system opens on the app's behalf: a Finder
/// double-click, `open -a LintCrux <file>`, or a file dropped on the Dock
/// icon.
///
/// `Info.plist` registers LintCrux as a handler for its document types, so
/// macOS launches or activates the app for them. It then delivers the file
/// through `application(_:open:)`, never through `argv`, so without a
/// receiver the app came up empty. The native half is `AppDelegate.swift`
/// in the macOS runner; this is the Dart half.
abstract interface class IncomingFileSource {
  /// The file that launched the app, if one did. Asked once, after the
  /// command-line arguments have been handled, and before [files].
  Future<String?> initialFile();

  /// Files opened while the app is running.
  Stream<String> get files;
}

/// The macOS receiver: a method channel for the file that caused a cold
/// launch, and an event channel for every file after it.
///
/// The native side buffers files that arrive before Dart asks, so the file
/// that launched the app is not lost to the startup race. The path arrives
/// directly readable: the app is not sandboxed, so there is no security
/// scope to hold and no copy to make.
class MacosIncomingFileSource implements IncomingFileSource {
  /// Creates the receiver over the runner's channels.
  MacosIncomingFileSource();

  /// Channel name the runner answers `getInitialFile` on.
  static const String methodChannelName = 'com.lintcrux/incoming_file';

  /// Channel name the runner streams later files on.
  static const String eventChannelName = 'com.lintcrux/incoming_file_stream';

  static const MethodChannel _method = MethodChannel(methodChannelName);
  static const EventChannel _events = EventChannel(eventChannelName);

  /// Whether [initialFile] found the runner's handler. [files] subscribes
  /// only then: subscribing to an event channel nobody implements reports
  /// an error rather than an empty stream.
  bool _runnerAnswered = false;

  @override
  Future<String?> initialFile() async {
    try {
      final path = await _method.invokeMethod<String>('getInitialFile');
      _runnerAnswered = true;
      return (path == null || path.isEmpty) ? null : path;
    } on MissingPluginException {
      // No native handler on the other end: a runner built without it, or
      // a test host. That means nobody opened anything, not a failure to
      // start.
      return null;
    } on PlatformException catch (e) {
      _log.warning(
        'Could not read the file macOS opened LintCrux with: ${e.message}',
      );
      return null;
    }
  }

  @override
  Stream<String> get files => _runnerAnswered
      ? _events
            .receiveBroadcastStream()
            .where((event) => event is String && event.isNotEmpty)
            .cast<String>()
      : const Stream<String>.empty();
}

/// The receiver for platforms whose runner has no file-open handler:
/// Windows and Linux hand files over through `argv`, and the browser gets
/// them through its own picker.
class NoIncomingFileSource implements IncomingFileSource {
  /// Creates the no-op receiver.
  const NoIncomingFileSource();

  @override
  Future<String?> initialFile() async => null;

  @override
  Stream<String> get files => const Stream<String>.empty();
}

/// The [IncomingFileSource] for this platform. Overridable so a test can
/// deliver files without a native runner.
final Provider<IncomingFileSource> incomingFileSourceProvider =
    Provider<IncomingFileSource>(
      (_) => (!kIsWeb && Platform.isMacOS)
          ? MacosIncomingFileSource()
          : const NoIncomingFileSource(),
      name: 'incomingFileSourceProvider',
    );
