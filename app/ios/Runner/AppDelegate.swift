import Flutter
import CryptoKit
import Darwin
import FamilyControls
import DeviceActivity
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
  private var ai1CaptureChannel: FlutterMethodChannel?
  private var ouraChannel: FlutterMethodChannel?
  private let ouraAuthorization = OuraAuthorizationBridge()
  private let backupExporter = DeviceBackupExporter()
  private let ai1CaptureStore = Ai1CaptureFileStore()
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

    let ai1CaptureChannel = FlutterMethodChannel(
      name: "tonyo/ai1_capture",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    ai1CaptureChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "capture_unavailable", message: "Capture storage is unavailable.", details: nil))
        return
      }
      self.ai1CaptureStore.handle(call, result: result)
    }
    self.ai1CaptureChannel = ai1CaptureChannel

    let ouraChannel = FlutterMethodChannel(
      name: "tonyo/oura",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    ouraChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "oura_unavailable", message: "The app is unavailable.", details: nil))
        return
      }
      self.ouraAuthorization.handle(call, result: result)
    }
    self.ouraChannel = ouraChannel
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
    case "syncAvailability":
      result(screenTimeSyncAvailability())
    case "requestSyncAuthorization":
      requestScreenTimeSyncAuthorization(result: result)
    case "readDailyTotals":
      readScreenTimeDailyTotals(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func screenTimeSyncAvailability() -> String {
    guard #available(iOS 26.4, *) else { return "unsupportedOS" }
    // This opt-in build flag must accompany the separately approved signed
    // app-and-website-usage entitlement. The Apple API enforces entitlement,
    // region and account eligibility; never infer eligibility from locale.
    guard hasFamilyControlsEntitlement,
      Bundle.main.object(forInfoDictionaryKey: "TonyoScreenTimeDataAccessApproved")
        as? Bool == true
    else { return "entitlementRequired" }
    switch AuthorizationCenter.shared.authorizationStatus {
    case .approvedWithDataAccess: return "authorized"
    case .denied: return "denied"
    case .notDetermined, .approved: return "notDetermined"
    default: return "error"
    }
  }

  private func requestScreenTimeSyncAuthorization(result: @escaping FlutterResult) {
    let state = screenTimeSyncAvailability()
    guard state == "notDetermined" || state == "denied" else {
      result(state)
      return
    }
    Task { @MainActor in
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        let updated = screenTimeSyncAvailability()
        // Standard report approval is insufficient for importing totals.
        result(updated == "notDetermined" ? "denied" : updated)
      } catch FamilyControlsError.unavailable {
        result("regionUnavailable")
      } catch FamilyControlsError.authorizationCanceled {
        result("denied")
      } catch {
        result("error")
      }
    }
  }

  private func readScreenTimeDailyTotals(result: @escaping FlutterResult) {
    guard #available(iOS 26.4, *), screenTimeSyncAvailability() == "authorized" else {
      result(FlutterError(code: "unauthorized", message: "Screen Time data access is required.", details: nil))
      return
    }
    Task { @MainActor in
      do {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today)!
        // Omitting users/devices limits the import to the current user/device.
        let filter = DeviceActivityFilter(segment: .daily(during: DateInterval(start: start, end: now)))
        var totals: [Date: (seconds: TimeInterval, updatedAt: Date)] = [:]
        for try await activity in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
          for await segment in activity.activitySegments {
            let day = calendar.startOfDay(for: segment.dateInterval.start)
            guard day >= start, day <= today else { continue }
            let previous = totals[day]
            totals[day] = (
              (previous?.seconds ?? 0) + segment.totalActivityDuration,
              max(previous?.updatedAt ?? .distantPast, min(activity.lastUpdatedDate, now))
            )
          }
        }
        guard screenTimeSyncAvailability() == "authorized" else {
          result(FlutterError(code: "unauthorized", message: "Screen Time access changed.", details: nil))
          return
        }
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        // No app names, domains, category, pickup or notification records leave
        // native code. This does not read from the private report extension.
        result(totals.keys.sorted().map { day -> [String: Any] in
          let total = totals[day]!
          return ["day": dayFormatter.string(from: day), "seconds": total.seconds,
                  "updatedAt": iso.string(from: total.updatedAt)]
        })
      } catch DeviceActivityData.Error.unavailable {
        result(FlutterError(code: "regionUnavailable", message: "Apple Screen Time data access is unavailable for this device or account.", details: nil))
      } catch DeviceActivityData.Error.unauthorized {
        result(FlutterError(code: "unauthorized", message: "Allow Screen Time data access again.", details: nil))
      } catch DeviceActivityData.Error.missingData {
        result(FlutterError(code: "missingData", message: "Apple has no Screen Time data available yet.", details: nil))
      } catch {
        result(FlutterError(code: "syncFailed", message: "Apple Screen Time could not be refreshed.", details: nil))
      }
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
      .heartRate,
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
      let arguments = call.arguments as? [String: Any]
      syncHeartData(recentOnly: arguments?["recentOnly"] as? Bool == true, result: result)
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
      // Ask HealthKit to notify us when samples change. iOS still controls
      // actual delivery timing and may throttle individual sample types.
      healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) {
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

  private func syncHeartData(recentOnly: Bool, result: @escaping FlutterResult) {
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
    // Frequent refreshes need only the recent high-volume heart-rate samples.
    // The initial/manual/daily full sync still backfills all 30 days, including
    // older samples that another device only recently uploaded to Health.
    let recentHeartRatePredicate = HKQuery.predicateForSamples(
      withStart: now.addingTimeInterval(-24 * 60 * 60),
      end: now,
      options: .strictStartDate
    )
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
    let definitions: [(HKQuantityTypeIdentifier, String, HKUnit)] = [
      (.heartRate, "heartRate", HKUnit.count().unitDivided(by: HKUnit.minute())),
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
        predicate: recentOnly && identifier == .heartRate ? recentHeartRatePredicate : predicate,
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
            "sourceName": sample.sourceRevision.source.name,
            "sourceBundleId": sample.sourceRevision.source.bundleIdentifier,
            "sourceRecordId": sample.uuid.uuidString.lowercased(),
            "measurementMethod": signalType == "hrv" ? "sdnn"
              : (signalType == "restingHeartRate" ? "healthkit_resting" : "instantaneous"),
            "quality": 1.0,
            "note": "Apple Health · \(sample.sourceRevision.source.name)",
          ])
        }
      }
      healthStore.execute(query)
    }

    group.notify(queue: .main) {
      if let queryError {
        // Treat this combined import as unsuccessful when any query fails;
        // a partial response must not look like a complete heart-data sync.
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

/// A private, device-local journal. All operations share one serial queue;
/// account/capture generations and two-phase receipts are owned by Dart.
private final class Ai1CaptureFileStore {
  private static let maximumBytes = 4 * 1024 * 1024
  private let queue = DispatchQueue(label: "tonyo.ai1.capture.storage")
  private let files = FileManager.default

  private enum StoreError: Error {
    case invalidArguments, tooLarge, invalidData, persistence

    var flutterError: FlutterError {
      switch self {
      case .invalidArguments:
        return FlutterError(code: "capture_invalid_arguments", message: "Invalid capture storage request.", details: nil)
      case .tooLarge:
        return FlutterError(code: "capture_too_large", message: "Capture history exceeds the storage limit.", details: nil)
      case .invalidData:
        return FlutterError(code: "capture_invalid_data", message: "Capture history is not a valid JSON object.", details: nil)
      case .persistence:
        return FlutterError(code: "capture_storage_failed", message: "Capture history could not be saved or read. Please retry.", details: nil)
      }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard ["available", "read", "write", "clear", "clearAll"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    queue.async {
      let response: Any?
      do {
        response = try self.perform(call)
      } catch let error as StoreError {
        response = error.flutterError
      } catch {
        // Do not expose private paths, owner identifiers or journal contents.
        response = StoreError.persistence.flutterError
      }
      DispatchQueue.main.async { result(response) }
    }
  }

  private func perform(_ call: FlutterMethodCall) throws -> Any? {
    if call.method == "available" { return true }
    if call.method == "clearAll" {
      let directory = try directoryURL(create: false)
      if files.fileExists(atPath: directory.path) {
        try files.removeItem(at: directory)
      }
      // A previous attempt may have removed the directory but failed its
      // flush. A retry must still make that deletion durable before success.
      let parent = directory.deletingLastPathComponent()
      if files.fileExists(atPath: parent.path) {
        try flushDirectory(parent)
      }
      return nil
    }
    guard let arguments = call.arguments as? [String: Any],
          let owner = arguments["owner"] as? String,
          !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          owner.utf16.count <= 200
    else { throw StoreError.invalidArguments }
    let filename = SHA256.hash(data: Data(owner.utf8))
      .map { String(format: "%02x", $0) }.joined() + ".json"
    let directory = try directoryURL(create: call.method == "write")
    let destination = directory.appendingPathComponent(filename, isDirectory: false)

    switch call.method {
    case "read":
      guard files.fileExists(atPath: destination.path) else { return nil }
      let data = try readBounded(destination)
      try validate(data)
      guard let value = String(data: data, encoding: .utf8) else { throw StoreError.invalidData }
      return value
    case "write":
      guard let value = arguments["value"] as? String else { throw StoreError.invalidArguments }
      // Check UTF-8 length before allocating a second copy of the payload.
      guard value.utf8.count <= Self.maximumBytes else { throw StoreError.tooLarge }
      let data = Data(value.utf8)
      try validate(data)
      // A crash may leave an unfinished temporary snapshot. Its owner-specific
      // prefix lets disablement/deletion remove it without reading its payload.
      _ = try removePendingFiles(directory: directory, filename: filename)
      let temporary = directory.appendingPathComponent("\(filename).pending-\(UUID().uuidString).tmp")
      defer { try? files.removeItem(at: temporary) }
      try data.write(to: temporary, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
      let file = try FileHandle(forWritingTo: temporary)
      do {
        try file.synchronize()
        try file.close()
      } catch {
        try? file.close()
        throw error
      }
      // POSIX rename replaces the old journal atomically in this directory.
      guard Darwin.rename(temporary.path, destination.path) == 0 else { throw StoreError.persistence }
      try flushDirectory(directory)
      let completedAt = Date()
      // The channel receipt has millisecond resolution. Round upward so a
      // sub-millisecond save after a cutoff cannot appear to precede it.
      let receiptAt = Date(timeIntervalSince1970: ceil(completedAt.timeIntervalSince1970 * 1000) / 1000)
      let formatter = ISO8601DateFormatter()
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter.string(from: receiptAt)
    case "clear":
      _ = try removePendingFiles(directory: directory, filename: filename)
      if files.fileExists(atPath: destination.path) {
        try files.removeItem(at: destination)
      }
      // Retry the flush even when an earlier removal already succeeded. If
      // clearAll removed this directory, flush its parent for the same reason.
      if files.fileExists(atPath: directory.path) {
        try flushDirectory(directory)
      } else {
        let parent = directory.deletingLastPathComponent()
        if files.fileExists(atPath: parent.path) {
          try flushDirectory(parent)
        }
      }
      return nil
    default:
      throw StoreError.invalidArguments
    }
  }

  private func directoryURL(create: Bool) throws -> URL {
    guard let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw StoreError.persistence
    }
    var directory = support.appendingPathComponent("tonyo-ai1-history", isDirectory: true)
    if create {
      try files.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
      )
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
      try flushDirectory(directory.deletingLastPathComponent())
      // Application Support may also have been created on first use. Flush
      // Library even on retries after a prior ancestor flush failed.
      let supportParent = support.deletingLastPathComponent()
      if files.fileExists(atPath: supportParent.path) {
        try flushDirectory(supportParent)
      }
    }
    return directory
  }

  private func readBounded(_ url: URL) throws -> Data {
    if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
       size > Self.maximumBytes { throw StoreError.tooLarge }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var data = Data()
    while let chunk = try file.read(upToCount: min(64 * 1024, Self.maximumBytes - data.count + 1)),
          !chunk.isEmpty {
      guard data.count + chunk.count <= Self.maximumBytes else { throw StoreError.tooLarge }
      data.append(chunk)
    }
    return data
  }

  private func removePendingFiles(directory: URL, filename: String) throws -> Bool {
    guard files.fileExists(atPath: directory.path) else { return false }
    var changed = false
    for candidate in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      if candidate.lastPathComponent.hasPrefix(filename + ".pending-"),
         candidate.pathExtension == "tmp" {
        try files.removeItem(at: candidate)
        changed = true
      }
    }
    return changed
  }

  private func validate(_ data: Data) throws {
    guard data.count <= Self.maximumBytes else { throw StoreError.tooLarge }
    guard let object = try? JSONSerialization.jsonObject(with: data),
          object is [String: Any] else { throw StoreError.invalidData }
  }

  private func flushDirectory(_ url: URL) throws {
    let descriptor = Darwin.open(url.path, O_RDONLY)
    guard descriptor >= 0 else { throw StoreError.persistence }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else { throw StoreError.persistence }
  }
}
