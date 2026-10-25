import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
  static let tonyoDailyTotal = Self("Tonyo Daily Total")
}

/// Hosts a system-rendered Device Activity report. The report extension—not
/// the Flutter process—receives the protected activity results.
struct TonyoScreenTimeReportView: View {
  private var filter: DeviceActivityFilter {
    let interval = DateInterval(
      start: Calendar.current.startOfDay(for: .now),
      end: .now
    )
    return DeviceActivityFilter(
      segment: .daily(during: interval),
      devices: .all
    )
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 14) {
        Text("Today’s total")
          .font(.title2.bold())
        Text(
          "Apple renders this aggregate privately. Tonyo cannot see app, category, website, pickup, or notification details."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        DeviceActivityReport(.tonyoDailyTotal, filter: filter)
          .frame(maxWidth: .infinity, minHeight: 180)
        Text("This view-only report does not sync to Tonyo. Manage manual entry or automatic daily-total imports in Profile → Screen Time.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(20)
      .navigationTitle("Screen Time")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
