import SwiftUI

struct TonyoDailyTotalView: View {
  let configuration: TonyoDailyTotalConfiguration

  private var formattedDuration: String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: configuration.totalDuration) ?? "0m"
  }

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "hourglass")
        .font(.title2)
        .foregroundStyle(.purple)
      Text(formattedDuration)
        .font(.system(size: 38, weight: .bold, design: .rounded))
      Text("Total across approved devices")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let lastUpdatedAt = configuration.lastUpdatedAt {
        Text("Updated \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Today’s total screen time, \(formattedDuration)")
  }
}
