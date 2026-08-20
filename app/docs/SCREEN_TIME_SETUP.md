# Private Screen Time report setup

Version 0.28 ships a Device Activity report extension that reduces Apple’s
protected activity results to one view-only total for the current day. Tonyo’s
Flutter process receives no application, category, website, pickup,
notification, or duration payload from the extension. Manual screen time stays
the dependable model input stored in private `signals` documents.

## Current capability state

Family Controls is a restricted Apple entitlement. This repository keeps
`TonyoFamilyControlsEntitlementApproved` set to `false`, so the app reports
`entitlementRequired` and never opens the authorization prompt before approval.
The extension still compiles and is embedded in unsigned validation builds.

## Activate after Apple approval

1. Replace the example bundle identifiers with the registered app and extension
   identifiers in Xcode.
2. Add the Family Controls capability to both the `Runner` and
   `ScreenTimeReportExtension` targets. Confirm both signed entitlements contain
   `com.apple.developer.family-controls` set to `true`.
3. Set `TonyoFamilyControlsEntitlementApproved` to `true` in
   `ios/Runner/Info.plist`.
4. Refresh the provisioning profiles, install a signed build on a physical
   iPhone or iPad, and verify the individual authorization prompt.
5. Open Profile → Screen Time and confirm the system-rendered report shows only
   today’s aggregate total. Verify that Firestore receives no Device Activity
   detail fields or automatic screen-time signals.

Do not enable the build flag without the matching approved entitlements. The
manual Activity log remains the supported fallback if approval is unavailable,
denied, or revoked.
