import Flutter
import FamilyControls
import HealthKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let healthStore = HKHealthStore()
  private var healthChannel: FlutterMethodChannel?
  private var screenTimeChannel: FlutterMethodChannel?
  private var timezoneChannel: FlutterMethodChannel?
  private var backupChannel: FlutterMethodChannel?
  private let backupExporter = DeviceBackupExporter()
  private var healthObserverQueries: [HKObserverQuery] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "tonyo/health",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleHealthCall(call, result: result)
    }
    healthChannel = channel

    let screenTimeChannel = FlutterMethodChannel(
      name: "tonyo/screen_time",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    screenTimeChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleScreenTimeCall(call, result: result)
    }
    self.screenTimeChannel = screenTimeChannel

    let timezoneChannel = FlutterMethodChannel(
      name: "tonyo/timezone",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
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
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    backupChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "save" || call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(FlutterError(code: "backup_unavailable", message: "The app is unavailable.", details: nil))
        return
      }
      if call.method == "open" {
        self.backupExporter.open(result: result)
      } else {
        self.backupExporter.save(call.arguments, result: result)
      }
    }
    self.backupChannel = backupChannel
  }

  private func handleScreenTimeCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "authorizationStatus":
      result(screenTimeAuthorizationStatus())
    case "requestAuthorization":
      requestScreenTimeAuthorization(result: result)
    case "showReport":
      showScreenTimeReport(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Family Controls is a restricted entitlement. The optional report stays
  /// disabled until Apple approves it and the release configuration is
  /// deliberately activated alongside the matching code-signing entitlement.
  private var hasFamilyControlsEntitlement: Bool {
    Bundle.main.object(
      forInfoDictionaryKey: "TonyoFamilyControlsEntitlementApproved"
    ) as? Bool == true
  }

  private func screenTimeAuthorizationStatus() -> String {
    guard hasFamilyControlsEntitlement else {
      return "entitlementRequired"
    }
    let status = AuthorizationCenter.shared.authorizationStatus
    if #available(iOS 26.4, *), status == .approvedWithDataAccess {
      return "authorized"
    }
    return switch status {
    case .notDetermined: "notDetermined"
    case .denied: "denied"
    case .approved: "authorized"
    default: "error"
    }
  }

  private func requestScreenTimeAuthorization(result: @escaping FlutterResult) {
    guard hasFamilyControlsEntitlement else {
      result("entitlementRequired")
      return
    }
    Task { @MainActor in
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        result(screenTimeAuthorizationStatus())
      } catch {
        result(
          FlutterError(
            code: "screen_time_authorization_failed",
            message: "The private Screen Time report could not be authorized.",
            details: nil
          )
        )
      }
    }
  }

  private func showScreenTimeReport(result: @escaping FlutterResult) {
    guard hasFamilyControlsEntitlement else {
      result(false)
      return
    }
    guard screenTimeAuthorizationStatus() == "authorized" else {
      result(false)
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let rootViewController = self?.window?.rootViewController else {
        result(false)
        return
      }
      var presenter = rootViewController
      while let presented = presenter.presentedViewController {
        presenter = presented
      }
      let report = UIHostingController(rootView: TonyoScreenTimeReportView())
      report.modalPresentationStyle = .pageSheet
      presenter.present(report, animated: true) {
        result(true)
      }
    }
  }

  private var requestedHealthTypes: Set<HKObjectType> {
    var types: Set<HKObjectType> = [HKObjectType.workoutType()]
    let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
      .heartRateVariabilitySDNN,
      .restingHeartRate,
      .dietaryWater,
      .stepCount,
    ]
    for identifier in quantityIdentifiers {
      if let type = HKObjectType.quantityType(forIdentifier: identifier) {
        types.insert(type)
      }
    }
    if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
      types.insert(sleep)
    }
    return types
  }

  private func handleHealthCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(HKHealthStore.isHealthDataAvailable())
    case "authorizationStatus":
      healthAuthorizationStatus(result: result)
    case "requestAuthorization":
      requestHealthAuthorization(result: result)
    case "openSettings":
      openAppSettings(result: result)
    case "sync":
      syncHeartData(result: result)
    case "syncSleep":
      syncSleepData(result: result)
    case "syncActivity":
      syncActivityData(result: result)
    case "enableBackgroundUpdates":
      enableBackgroundHealthUpdates(result: result)
    case "disableBackgroundUpdates":
      disableBackgroundHealthUpdates(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func enableBackgroundHealthUpdates(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(false)
      return
    }
    disableHealthObservers()
    let group = DispatchGroup()
    let lock = NSLock()
    var enabled = true

    for objectType in requestedHealthTypes {
      guard let sampleType = objectType as? HKSampleType else { continue }
      let observer = HKObserverQuery(sampleType: sampleType, predicate: nil) {
        [weak self] _, completion, error in
        guard error == nil, let channel = self?.healthChannel else {
          completion()
          return
        }
        DispatchQueue.main.async {
          channel.invokeMethod("healthDataChanged", arguments: nil) { _ in
            completion()
          }
        }
      }
      healthObserverQueries.append(observer)
      healthStore.execute(observer)
      group.enter()
      healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly) {
        success, _ in
        if !success {
          lock.lock()
          enabled = false
          lock.unlock()
        }
        group.leave()
      }
    }

    group.notify(queue: .main) { result(enabled) }
  }

  private func disableBackgroundHealthUpdates(result: @escaping FlutterResult) {
    disableHealthObservers()
    healthStore.disableAllBackgroundDelivery { success, _ in
      DispatchQueue.main.async { result(success) }
    }
  }

  private func disableHealthObservers() {
    for query in healthObserverQueries {
      healthStore.stop(query)
    }
    healthObserverQueries.removeAll()
  }

  private func healthAuthorizationStatus(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result("unavailable")
      return
    }
    healthStore.getRequestStatusForAuthorization(
      toShare: Set<HKSampleType>(),
      read: requestedHealthTypes
    ) { status, error in
      let value: String
      if error != nil {
        value = "error"
      } else {
        value = status == .shouldRequest ? "notDetermined" :
          status == .unnecessary ? "authorized" : "error"
      }
      DispatchQueue.main.async { result(value) }
    }
  }

  private func requestHealthAuthorization(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result("unavailable")
      return
    }
    healthStore.requestAuthorization(
      toShare: Set<HKSampleType>(),
      read: requestedHealthTypes
    ) { success, _ in
      // HealthKit deliberately reports only whether the sheet completed. It
      // does not disclose which read categories the person allowed.
      DispatchQueue.main.async { result(success ? "authorized" : "denied") }
    }
  }

  private func openAppSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }

  private func syncHeartData(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(
        FlutterError(
          code: "health_unavailable",
          message: "Apple Health is unavailable on this device.",
          details: nil
        )
      )
      return
    }

    let now = Date()
    guard let start = Calendar.current.date(byAdding: .day, value: -30, to: now) else {
      result(
        FlutterError(
          code: "health_sync_failed",
          message: "Could not create the Apple Health sync window.",
          details: nil
        )
      )
      return
    }

    let predicate = HKQuery.predicateForSamples(
      withStart: start,
      end: now,
      options: .strictStartDate
    )
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
    let definitions: [(HKQuantityTypeIdentifier, String, HKUnit)] = [
      (.heartRateVariabilitySDNN, "hrv", HKUnit.secondUnit(with: .milli)),
      (
        .restingHeartRate,
        "restingHeartRate",
        HKUnit.count().unitDivided(by: HKUnit.minute())
      ),
    ]
    let group = DispatchGroup()
    let lock = NSLock()
    var payload: [[String: Any]] = []
    var queryError: Error?

    for (identifier, signalType, unit) in definitions {
      guard let sampleType = HKObjectType.quantityType(forIdentifier: identifier) else {
        continue
      }
      group.enter()
      let query = HKSampleQuery(
        sampleType: sampleType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [sort]
      ) { _, samples, error in
        lock.lock()
        defer {
          lock.unlock()
          group.leave()
        }
        if let error {
          queryError = queryError ?? error
          return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for sample in samples as? [HKQuantitySample] ?? [] {
          let value = sample.quantity.doubleValue(for: unit)
          guard value.isFinite, value > 0 else { continue }
          payload.append([
            "id": "healthkit-\(sample.uuid.uuidString.lowercased())",
            "type": signalType,
            "value": value,
            "timestamp": formatter.string(from: sample.endDate),
            "source": "healthKit",
            "quality": 1.0,
            "note": "Apple Health · \(sample.sourceRevision.source.name)",
          ])
        }
      }
      healthStore.execute(query)
    }

    group.notify(queue: .main) {
      if let queryError {
        result(
          FlutterError(
            code: "health_sync_failed",
            message: queryError.localizedDescription,
            details: nil
          )
        )
      } else {
        payload.sort {
          ($0["timestamp"] as? String ?? "") > ($1["timestamp"] as? String ?? "")
        }
        result(payload)
      }
    }
  }

  private func syncSleepData(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(
        FlutterError(
          code: "health_unavailable",
          message: "Apple Health is unavailable on this device.",
          details: nil
        )
      )
      return
    }
    guard let sampleType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
      result(
        FlutterError(
          code: "health_sync_failed",
          message: "Apple Health sleep data is unavailable on this device.",
          details: nil
        )
      )
      return
    }

    let now = Date()
    guard let start = Calendar.current.date(byAdding: .day, value: -30, to: now) else {
      result(
        FlutterError(
          code: "health_sync_failed",
          message: "Could not create the Apple Health sleep sync window.",
          details: nil
        )
      )
      return
    }
    let predicate = HKQuery.predicateForSamples(
      withStart: start,
      end: now,
      options: .strictStartDate
    )
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
    let query = HKSampleQuery(
      sampleType: sampleType,
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: [sort]
    ) { _, samples, error in
      if let error {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "health_sync_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
        return
      }

      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var payload: [[String: Any]] = []
      for sample in samples as? [HKCategorySample] ?? [] {
        guard let signalType = self.sleepSignalType(for: sample.value) else { continue }
        let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
        guard hours.isFinite, hours > 0, hours <= 24 else { continue }
        payload.append([
          "id": "healthkit-\(sample.uuid.uuidString.lowercased())",
          "type": signalType,
          "value": hours,
          "timestamp": formatter.string(from: sample.endDate),
          "source": "healthKit",
          "quality": 1.0,
          "note": "Apple Health · \(sample.sourceRevision.source.name)",
          "groupId": sample.sourceRevision.source.bundleIdentifier,
        ])
      }
      DispatchQueue.main.async { result(payload) }
    }
    healthStore.execute(query)
  }

  private func sleepSignalType(for value: Int) -> String? {
    // HealthKit's stable category raw values: 0 is in-bed and intentionally
    // excluded; 1 is asleep/unspecified, followed by awake and staged sleep.
    switch value {
    case 1: return "sleepUnspecified"
    case 2: return "sleepAwake"
    case 3: return "sleepCore"
    case 4: return "sleepDeep"
    case 5: return "sleepRem"
    default: return nil
    }
  }

  private func syncActivityData(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(
        FlutterError(
          code: "health_unavailable",
          message: "Apple Health is unavailable on this device.",
          details: nil
        )
      )
      return
    }

    let now = Date()
    guard let start = Calendar.current.date(byAdding: .day, value: -30, to: now) else {
      result(
        FlutterError(
          code: "health_sync_failed",
          message: "Could not create the Apple Health activity sync window.",
          details: nil
        )
      )
      return
    }
    let predicate = HKQuery.predicateForSamples(
      withStart: start,
      end: now,
      options: .strictStartDate
    )
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
    let group = DispatchGroup()
    let lock = NSLock()
    var payload: [[String: Any]] = []
    var queryError: Error?

    group.enter()
    let workoutQuery = HKSampleQuery(
      sampleType: HKObjectType.workoutType(),
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: [sort]
    ) { _, samples, error in
      lock.lock()
      defer {
        lock.unlock()
        group.leave()
      }
      if let error {
        queryError = queryError ?? error
        return
      }
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      for sample in samples as? [HKWorkout] ?? [] {
        let hours = sample.duration / 3600
        guard hours.isFinite, hours > 0, hours <= 24 else { continue }
        payload.append([
          "id": "healthkit-\(sample.uuid.uuidString.lowercased())",
          "type": "exercise",
          "value": hours,
          "timestamp": formatter.string(from: sample.endDate),
          "source": "healthKit",
          "quality": 1.0,
          "note": "Apple Health workout · \(sample.sourceRevision.source.name)",
        ])
      }
    }
    healthStore.execute(workoutQuery)

    if let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater) {
      group.enter()
      let waterQuery = HKSampleQuery(
        sampleType: waterType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [sort]
      ) { _, samples, error in
        lock.lock()
        defer {
          lock.unlock()
          group.leave()
        }
        if let error {
          queryError = queryError ?? error
          return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for sample in samples as? [HKQuantitySample] ?? [] {
          let liters = sample.quantity.doubleValue(for: HKUnit.liter())
          guard liters.isFinite, liters > 0, liters <= 10 else { continue }
          payload.append([
            "id": "healthkit-\(sample.uuid.uuidString.lowercased())",
            "type": "hydration",
            "value": liters,
            "timestamp": formatter.string(from: sample.endDate),
            "source": "healthKit",
            "quality": 1.0,
            "note": "Apple Health water · \(sample.sourceRevision.source.name)",
          ])
        }
      }
      healthStore.execute(waterQuery)
    }

    if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
      group.enter()
      var interval = DateComponents()
      interval.day = 1
      let calendar = Calendar.current
      let anchor = calendar.startOfDay(for: start)
      let stepsQuery = HKStatisticsCollectionQuery(
        quantityType: stepType,
        quantitySamplePredicate: predicate,
        options: .cumulativeSum,
        anchorDate: anchor,
        intervalComponents: interval
      )
      stepsQuery.initialResultsHandler = { _, collection, error in
        defer { group.leave() }
        if let error {
          lock.lock()
          queryError = queryError ?? error
          lock.unlock()
          return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let idFormatter = DateFormatter()
        idFormatter.calendar = calendar
        idFormatter.locale = Locale(identifier: "en_US_POSIX")
        idFormatter.dateFormat = "yyyy-MM-dd"
        var stepPayload: [[String: Any]] = []
        collection?.enumerateStatistics(from: start, to: now) { statistics, _ in
          guard let sum = statistics.sumQuantity() else { return }
          let steps = sum.doubleValue(for: HKUnit.count())
          guard steps.isFinite, steps > 0, steps <= 200_000 else { return }
          let timestamp = min(now, statistics.endDate.addingTimeInterval(-1))
          stepPayload.append([
            "id": "healthkit-steps-\(idFormatter.string(from: statistics.startDate))",
            "type": "steps",
            "value": steps,
            "timestamp": formatter.string(from: timestamp),
            "source": "healthKit",
            "quality": 1.0,
            "note": "Apple Health daily step total",
          ])
        }
        lock.lock()
        payload.append(contentsOf: stepPayload)
        lock.unlock()
      }
      healthStore.execute(stepsQuery)
    }

    group.notify(queue: .main) {
      if let queryError {
        result(
          FlutterError(
            code: "health_sync_failed",
            message: queryError.localizedDescription,
            details: nil
          )
        )
      } else {
        payload.sort {
          ($0["timestamp"] as? String ?? "") > ($1["timestamp"] as? String ?? "")
        }
        result(payload)
      }
    }
  }
}

/// Retains the picker delegate and temporary source until Files confirms that
/// the export completed. Presenting the sheet alone is not a successful save.
private final class DeviceBackupExporter: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private var pendingResult: FlutterResult?
  private var temporaryDirectory: URL?
  private var activePicker: UIDocumentPickerViewController?
  private var openingBackup = false
  private static let maximumBackupBytes = 20 * 1024 * 1024

  func open(result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "backup_busy", message: "A backup file dialog is already open.", details: nil))
      return
    }
    guard let presenter = backupPresenter() else {
      result(FlutterError(code: "backup_unavailable", message: "The open dialog is unavailable.", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    picker.modalPresentationStyle = .formSheet
    openingBackup = true
    pendingResult = result
    activePicker = picker
    presenter.present(picker, animated: true)
    picker.presentationController?.delegate = self
  }

  func save(_ arguments: Any?, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
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
    guard let presenter = backupPresenter() else {
      result(FlutterError(code: "backup_unavailable", message: "The save dialog is unavailable.", details: nil))
      return
    }

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("tonyo-backup-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let source = directory.appendingPathComponent(filename)
      try Data(json.utf8).write(to: source, options: [.atomic, .completeFileProtection])
      let picker = UIDocumentPickerViewController(forExporting: [source], asCopy: true)
      picker.delegate = self
      picker.modalPresentationStyle = .formSheet
      pendingResult = result
      openingBackup = false
      temporaryDirectory = directory
      activePicker = picker
      presenter.present(picker, animated: true)
      picker.presentationController?.delegate = self
    } catch {
      try? FileManager.default.removeItem(at: directory)
      result(FlutterError(code: "backup_failed", message: "The backup could not be saved. Please try again.", details: nil))
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard controller === activePicker else { return }
    guard let url = urls.first else {
      finish(FlutterError(code: "backup_failed", message: "Files did not provide a backup file.", details: nil))
      return
    }
    if openingBackup {
      // Ignore dismissal after selection while the coordinated read finishes.
      activePicker = nil
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        let value = Self.readBackup(at: url)
        DispatchQueue.main.async { [self] in finish(value) }
      }
    } else {
      finish(true)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard controller === activePicker else { return }
    finish(openingBackup ? nil : false)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard presentationController.presentedViewController === activePicker else { return }
    finish(openingBackup ? nil : false)
  }

  private func backupPresenter() -> UIViewController? {
    // Flutter's scene-based lifecycle does not keep AppDelegate.window set.
    guard var presenter = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .filter({ $0.activationState == .foregroundActive })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })?.rootViewController
    else { return nil }
    while let presented = presenter.presentedViewController {
      presenter = presented
    }
    return !presenter.isBeingDismissed && presenter.view.window != nil ? presenter : nil
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
        // Bound every read even when a file provider omits or misreports size.
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

  private func finish(_ value: Any?) {
    let result = pendingResult
    pendingResult = nil
    if let directory = temporaryDirectory {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectory = nil
    activePicker = nil
    openingBackup = false
    result?(value)
  }
}
