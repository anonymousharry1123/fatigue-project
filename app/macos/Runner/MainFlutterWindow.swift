import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var timezoneChannel: FlutterMethodChannel?
  private var backupChannel: FlutterMethodChannel?
  private var handlingBackup = false
  private static let maximumBackupBytes = 20 * 1024 * 1024

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
      guard call.method == "save" || call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(FlutterError(code: "backup_unavailable", message: "The file dialog is unavailable.", details: nil))
        return
      }
      if call.method == "open" {
        self.openBackup(result: result)
      } else {
        self.saveBackup(call.arguments, result: result)
      }
    }
    self.backupChannel = backupChannel

    super.awakeFromNib()
  }

  private func saveBackup(_ arguments: Any?, result: @escaping FlutterResult) {
    guard !handlingBackup else {
      result(FlutterError(code: "backup_busy", message: "A backup file dialog is already open.", details: nil))
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
    handlingBackup = true
    panel.beginSheetModal(for: self) { [weak self] response in
      defer { self?.handlingBackup = false }
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

  private func openBackup(result: @escaping FlutterResult) {
    guard !handlingBackup else {
      result(FlutterError(code: "backup_busy", message: "A backup file dialog is already open.", details: nil))
      return
    }
    let panel = NSOpenPanel()
    panel.title = "Restore device backup"
    panel.allowedFileTypes = ["json"]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    handlingBackup = true
    panel.beginSheetModal(for: self) { [weak self] response in
      guard response == .OK else {
        self?.handlingBackup = false
        result(nil)
        return
      }
      guard let url = panel.url else {
        self?.handlingBackup = false
        result(FlutterError(code: "backup_failed", message: "The selected file is unavailable.", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let value = Self.readBackup(at: url)
        DispatchQueue.main.async {
          self?.handlingBackup = false
          result(value)
        }
      }
    }
  }

  private static func readBackup(at url: URL) -> Any {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    var value: Any = FlutterError(code: "backup_failed", message: "The backup could not be opened. Please try again.", details: nil)
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
      do {
        let size = try readableURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let size, size > maximumBackupBytes {
          value = FlutterError(code: "backup_too_large", message: "Choose a backup of 20 MiB or smaller.", details: nil)
          return
        }
        let file = try FileHandle(forReadingFrom: readableURL)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: min(64 * 1024, maximumBackupBytes - data.count + 1)), !chunk.isEmpty {
          guard data.count + chunk.count <= maximumBackupBytes else {
            value = FlutterError(code: "backup_too_large", message: "Choose a backup of 20 MiB or smaller.", details: nil)
            return
          }
          data.append(chunk)
        }
        guard let json = String(data: data, encoding: .utf8) else {
          value = FlutterError(code: "backup_invalid_encoding", message: "The backup must be a UTF-8 JSON file.", details: nil)
          return
        }
        value = json
      } catch {
        // Keep the readable error and avoid exposing private document paths.
      }
    }
    return value
  }
}
