import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct ScreenTimeReportExtension: DeviceActivityReportExtension {
  var body: some DeviceActivityReportScene {
    TonyoDailyTotalReport { configuration in
      TonyoDailyTotalView(configuration: configuration)
    }
  }
}
