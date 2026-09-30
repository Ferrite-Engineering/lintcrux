import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Finder double-click, `open -a`, and drag-onto-the-Dock-icon.
  ///
  /// File URLs are ours; everything else (a custom scheme a plugin
  /// registered for) goes to `super`. Splitting rather than always calling
  /// `super` keeps this the single path for a document: the base class may
  /// also hand the URL to the framework, and two routes opening the same
  /// file is how a project ends up in two tabs.
  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingFilePlugin.shared.handle(urls: urls)
    let others = urls.filter { !$0.isFileURL }
    if !others.isEmpty {
      super.application(application, open: others)
    }
  }
}

/// Delivers documents macOS opens on LintCrux's behalf to Dart.
///
/// `Info.plist` declares seven `CFBundleDocumentTypes`, so macOS offers
/// LintCrux for `.lintcrux` projects, workspaces, sessions, SARIF reports,
/// HDL sources, `.f` filelists and `.crux-project` manifests, and launches
/// it for them. The file itself arrives through `application(_:open:)`,
/// never through `argv`, so until this existed every double-click opened
/// the app empty.
///
/// The Dart half is `lib/services/platform/incoming_file_source.dart` in
/// the LintCrux open core; its `app.dart` routes each file into the path
/// that already opens that kind of file.
///
/// macOS hands over a real, readable path: the app is not sandboxed (see
/// `Release.entitlements`), so there is no security scope to hold open and
/// no copy to make.
final class IncomingFilePlugin: NSObject {
  static let shared = IncomingFilePlugin()

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?

  /// Paths that arrived before Dart was listening.
  ///
  /// A cold launch fires `application(_:open:)` long before Dart runs, so
  /// without this buffer the case the feature exists for (double-clicking
  /// a project when the app is not running) would be the one that dropped
  /// it.
  private var pending: [String] = []

  private override init() {}

  /// Call from `MainFlutterWindow.awakeFromNib()`, once the engine exists.
  func register(with messenger: FlutterBinaryMessenger) {
    let mc = FlutterMethodChannel(
      name: "com.lintcrux/incoming_file",
      binaryMessenger: messenger)
    mc.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "getInitialFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      // Hand back only the first: Dart opens it and takes the rest off the
      // event stream, the same shape as several files on the command line.
      result(self.pending.isEmpty ? nil : self.pending.removeFirst())
    }
    methodChannel = mc

    let ec = FlutterEventChannel(
      name: "com.lintcrux/incoming_file_stream",
      binaryMessenger: messenger)
    ec.setStreamHandler(self)
    eventChannel = ec
  }

  /// Forwards each file URL; non-file URLs are not ours to open. Buffered
  /// until Dart subscribes to the event stream.
  func handle(urls: [URL]) {
    for url in urls where url.isFileURL {
      if let sink = eventSink {
        sink(url.path)
      } else {
        pending.append(url.path)
      }
    }
  }
}

// MARK: - FlutterStreamHandler

extension IncomingFilePlugin: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    // Drain anything that landed between `getInitialFile` and this
    // subscription: a second file in the same Finder selection, or a fast
    // second double-click during startup.
    let queued = pending
    pending.removeAll()
    for path in queued {
      events(path)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
