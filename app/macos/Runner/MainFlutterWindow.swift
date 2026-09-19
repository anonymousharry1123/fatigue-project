import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var timezoneChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let timezoneChannel = FlutterMethodChannel(
      name: "tonyo/timezone",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    timezoneChannel.setMethodCallHandler { call, result in
      guard call.method == "getTimezone" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(TimeZone.autoupdatingCurrent.identifier)
    }
    self.timezoneChannel = timezoneChannel

    super.awakeFromNib()
  }
}
