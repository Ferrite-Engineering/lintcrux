// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Cross-platform [PathProviderPlatform] fake backed by a real temp
/// directory.
///
/// In `flutter test` there is no plugin registrant, so
/// `PathProviderPlatform.instance` defaults to `MethodChannelPathProvider`,
/// whose method-channel calls throw
/// `MissingPluginException` on macOS and Windows (path_provider_linux is
/// pure-Dart, so Linux happens to resolve — which is exactly why an
/// unmocked path_provider dependency passes CI on Linux but is red on
/// Windows). Any test whose provider graph transitively resolves an
/// application-support / temporary / documents directory must install this
/// fake so the resolution succeeds identically on every host.
///
/// Every getter returns a fresh subdirectory under [_root] (created on
/// demand) so callers that actually write files get a usable, writable
/// location instead of a thrown plugin exception.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  /// Creates a fake rooted at [_root]. Callers normally obtain one through
  /// [useFakePathProvider] rather than constructing it directly.
  FakePathProvider(this._root);

  final String _root;

  String _sub(String name) {
    final dir = Directory(p.join(_root, name));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => _sub('tmp');

  @override
  Future<String?> getApplicationSupportPath() async => _sub('support');

  @override
  Future<String?> getApplicationDocumentsPath() async => _sub('documents');

  @override
  Future<String?> getApplicationCachePath() async => _sub('cache');

  @override
  Future<String?> getLibraryPath() async => _sub('library');

  @override
  Future<String?> getDownloadsPath() async => _sub('downloads');
}

/// Installs a [FakePathProvider] for the enclosing test `main()`, backed by
/// a fresh temp directory per test, and restores the previous platform
/// instance afterwards.
///
/// Call once at the top of `main()` (after
/// `TestWidgetsFlutterBinding.ensureInitialized()`). It registers its own
/// `setUp`/`tearDown` hooks; those compose with any the test already
/// declares.
void useFakePathProvider() {
  late Directory tmp;
  late PathProviderPlatform previous;
  setUp(() {
    previous = PathProviderPlatform.instance;
    tmp = Directory.systemTemp.createTempSync('lintcrux_fake_pp_');
    PathProviderPlatform.instance = FakePathProvider(tmp.path);
  });
  tearDown(() {
    PathProviderPlatform.instance = previous;
    if (tmp.existsSync()) {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; a leftover temp dir must never fail a test.
      }
    }
  });
}
