import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var timezoneChannel: FlutterMethodChannel?
  private var backupChannel: FlutterMethodChannel?
  private var savingBackup = false

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

    let backupChannel = FlutterMethodChannel(
      name: "tonyo/device_backup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    backupChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "save" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(FlutterError(code: "backup_unavailable", message: "The save dialog is unavailable.", details: nil))
        return
      }
      self.saveBackup(call.arguments, result: result)
    }
    self.backupChannel = backupChannel

    super.awakeFromNib()
  }

  private func saveBackup(_ arguments: Any?, result: @escaping FlutterResult) {
    guard !savingBackup else {
      result(FlutterError(code: "backup_busy", message: "A backup is already being saved.", details: nil))
      return
    }
    guard let values = arguments as? [String: Any],
      let json = values["json"] as? String,
      let filename = values["filename"] as? String,
      !filename.isEmpty, filename.hasSuffix(".json"),
      filename.rangeOfCharacter(from: .controlCharacters) == nil,
      !filename.contains("/"), !filename.contains("\\")
    else {
      result(FlutterError(code: "backup_invalid", message: "The backup file is invalid.", details: nil))
      return
    }
    let panel = NSSavePanel()
    panel.title = "Save device backup"
    panel.nameFieldStringValue = filename
    panel.allowedFileTypes = ["json"]
    panel.canCreateDirectories = true
    savingBackup = true
    panel.beginSheetModal(for: self) { [weak self] response in
      defer { self?.savingBackup = false }
      guard response == .OK else {
        result(false)
        return
      }
      guard let url = panel.url else {
        result(FlutterError(code: "backup_failed", message: "The save location is unavailable.", details: nil))
        return
      }
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      do {
        try Data(json.utf8).write(to: url, options: .atomic)
        result(true)
      } catch {
        result(FlutterError(code: "backup_failed", message: "The backup could not be saved. Please try again.", details: nil))
      }
    }
  }
}
