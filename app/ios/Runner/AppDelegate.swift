import Flutter
import HealthKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let healthStore = HKHealthStore()
  private var healthChannel: FlutterMethodChannel?

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
  }

  private var requestedHealthTypes: Set<HKObjectType> {
    var types: Set<HKObjectType> = [HKObjectType.workoutType()]
    let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
      .heartRateVariabilitySDNN,
      .restingHeartRate,
      .dietaryWater,
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
    default:
      result(FlutterMethodNotImplemented)
    }
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
