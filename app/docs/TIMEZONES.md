# Device time zones

Tonyo follows the operating system's time-zone setting. It does not request
location permission or infer a region from an IP address, abbreviation, or UTC
offset.

- iOS and macOS return `TimeZone.autoupdatingCurrent.identifier` through the
  `tonyo/timezone` method channel.
- Android returns `TimeZone.getDefault().id` through the same channel.
- Web uses `Intl.DateTimeFormat().resolvedOptions().timeZone`.
- Windows and Linux currently use Dart's system local clock and display its
  offset. Their native shells do not yet expose an IANA region, so historical
  model preparation requires an explicit region. Unknown or unavailable regions
  also use this fallback; they never silently become a US region or UTC.

`DeviceTimezoneService.refresh()` runs on launch and foreground resume. It detects
both region changes (including travel between regions with the same current
offset) and daylight-saving offset changes. Changed local context invalidates
derived scores, forecasts, and guidance before they are rebuilt under the
existing privacy controls. Device region metadata belongs to the device cache,
not the shared user profile.

The shared IANA database includes aliases returned by system APIs, such as
`Asia/Calcutta`. Model preparation starts with the detected region for a new
window. An explicitly saved historical window retains its original region and
dates when reopened, including after travel; preparation remains an explicit
foreground action.

Notification guidance uses one-shot UTC instants. Keeping the instant avoids
ambiguity during repeated daylight-saving hours. Foreground refresh replaces
the guidance plan when the local context changes. A scheduled reminder does
not become a recurring wall-clock alarm.

New timestamp serialization uses UTC instants and local display uses the device
clock. A legacy timestamp without an offset cannot establish the user's
historical region; Tonyo cannot reconstruct that information from the string.

Focused checks cover equal-offset travel, DST transitions, fractional offsets,
IANA aliases, native bridge reads, unknown-host fallback, preservation of saved
model windows, and distinct notification instants in a repeated local hour.
