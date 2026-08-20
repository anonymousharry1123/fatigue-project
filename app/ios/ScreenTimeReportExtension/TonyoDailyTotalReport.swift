import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
  static let tonyoDailyTotal = Self("Tonyo Daily Total")
}

struct TonyoDailyTotalConfiguration {
  let totalDuration: TimeInterval
  let lastUpdatedAt: Date?
}

/// Reduces protected Device Activity results to one total. This scene never
/// traverses applications, categories, web domains, pickups, or notifications.
struct TonyoDailyTotalReport: DeviceActivityReportScene {
  let context: DeviceActivityReport.Context = .tonyoDailyTotal
  let content: (TonyoDailyTotalConfiguration) -> TonyoDailyTotalView

  func makeConfiguration(
    representing data: DeviceActivityResults<DeviceActivityData>
  ) async -> TonyoDailyTotalConfiguration {
    var totalDuration: TimeInterval = 0
    var lastUpdatedAt: Date?

    for await activity in data {
      if lastUpdatedAt == nil || activity.lastUpdatedDate > lastUpdatedAt! {
        lastUpdatedAt = activity.lastUpdatedDate
      }
      for await segment in activity.activitySegments {
        totalDuration += segment.totalActivityDuration
      }
    }

    return TonyoDailyTotalConfiguration(
      totalDuration: totalDuration,
      lastUpdatedAt: lastUpdatedAt
    )
  }
}
