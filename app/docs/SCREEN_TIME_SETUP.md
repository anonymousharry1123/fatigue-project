# Screen Time: manual entry, automatic Apple sync, and private reports

## Current behavior

Manual entry is the default. Profile → Screen Time offers **Auto-sync with
Apple**, off until the person explicitly enables it and Apple grants data
access. The separate private report remains view-only.

Automatic sync uses `DeviceActivityData.activityData(filteredBy:using:)` on
iOS 26.4+, with `.live` data and a daily filter for the current user/device's
last seven local calendar days. It runs after opt-in, on launch/resume when due,
and every 15 minutes while Tonyo is open. **Sync now** retries immediately.
There is no promise of background delivery while Tonyo is closed.

Only day, total duration, and Apple's update timestamp cross the native bridge.
The importer never traverses applications, categories, websites, pickups, or
notifications. It does not extract anything from the report extension.

Each imported day updates one `apple-screen-time-YYYY-MM-DD` signal with source
`appleScreenTime`. Unchanged totals produce no signal/cloud write or score
recalculation. Apple corrections can decrease a total. A manual entry, including
explicit zero, takes priority for that day in scoring and Today's summary.
Imported totals otherwise participate in Energy/Cognitive scoring and model
preparation, with an Apple Screen Time source label.

Totals follow existing local persistence, account privacy, and cloud-sync rules.
The opt-in preference is device-local and bound to the current Tonyo account;
it is not an authorization for another account or device. Switching off stops
future imports and retains existing entries. Clearing tracking data disables
this importer, preventing the seven-day backfill from recreating cleared data.
Sign-out, account changes, disabling sync, and privacy restrictions invalidate
in-flight imports. Missing data and errors never become zero-duration records.

## Apple requirements and shipping state

Apple documents customer data access as limited to devices located in the EU
and signed in with an EU-country/region Apple Account. Development testing with
an Apple-provided provisioning profile may work elsewhere. Only one app at a
time may hold `approvedWithDataAccess`; standard report authorization
(`approved`) is insufficient. Tonyo relies on Apple's enforcement rather than
inferring eligibility from the device language or locale.

Both activation flags currently remain **false** in `ios/Runner/Info.plist`:

- `TonyoFamilyControlsEntitlementApproved` — private reports.
- `TonyoScreenTimeDataAccessApproved` — automatic daily-total import.

The existing signed entitlement file does not yet include the restricted
Screen Time capabilities. Consequently, this build displays the option and its
availability explanation but cannot enable real imports. Compilation and mocked
tests do not prove Apple approval or physical-device data access.

## Activate with approved provisioning

1. Confirm the registered identifiers for `Runner` and
   `ScreenTimeReportExtension` in Xcode.
2. Obtain Family Controls distribution approval for the app and report
   extension; add `com.apple.developer.family-controls = true` to both signed
   targets with matching provisioning profiles.
3. For automatic sync, add the **Family Controls App and Website Usage**
   capability to Runner and obtain a matching profile with
   `com.apple.developer.family-controls.app-and-website-usage = true`.
4. Set the corresponding activation flags to `true` only after the signed
   capabilities/profiles are configured. Keep them false in other builds.
   Update clients before enabling imports: older builds that parse signal
   sources strictly cannot decode the new `appleScreenTime` source value.
5. Install a signed build on an eligible physical device. Under Profile →
   Screen Time, turn on Auto-sync with Apple and verify the system authorization
   reaches `approvedWithDataAccess`. Report-only approval must not enable sync.
6. Verify imported totals against Apple's report, resume/poll/manual refresh,
   same-day corrections, midnight/DST behavior, revoked access, empty results,
   sign-out, and switching sync off. Inspect private signal writes: daily totals
   only, no app or domain fields, and no writes for unchanged totals.
7. Confirm unsupported OS/region/account and missing-capability builds remain
   manual with an explanatory status. Confirm the independent private report
   still renders without exporting data.

## Apple references

- [DeviceActivityData.activityData](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitydata(filteredby:using:))
- [approvedWithDataAccess and region restrictions](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess)
- [App and Website Usage entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls.app-and-website-usage)
- [Requesting Family Controls distribution approval](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
