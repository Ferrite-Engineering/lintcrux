import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowAttentionPlugin: WindowAttentionPlugin?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 800, height: 500)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // Registers the channels a Finder double-click is delivered on. The
    // singleton buffers anything that arrived before now, which on a cold
    // launch is the document that caused the launch.
    IncomingFilePlugin.shared.register(with: flutterViewController.engine.binaryMessenger)

    // Handle `crux_window_chrome/attention`
    // requestUserAttention calls with a non-focus-stealing dock bounce.
    windowAttentionPlugin = WindowAttentionPlugin(
      messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
