# Phase 1 device acceptance

Verification inventory: 2026-10-03. These checks concern software behavior, not biological, clinical, or fatigue-prediction accuracy. See [the progress record](BIOLOGY_UPGRADE_PROGRESS.md) for unit/widget and Firestore emulator results.

## Inventory and test boundaries

| Surface | Evidence | Coverage status |
| --- | --- | --- |
| Flutter unit/widget tests | The repository uses `flutter_test`. Even `test/font_integration_test.dart` uses `testWidgets` and mocked SharedPreferences. | Software tests; not app/device integration. |
| Firestore emulator | Separate Node rules-testing harness in `tool/security_rules/`. | Consult the progress record for the current execution result; does not test Flutter plugin/device integration. |
| App integration harness | No `integration_test` dependency or directory, Flutter Driver harness, or existing app-integration command was found. iOS/macOS `RunnerTests.testExample` are empty templates. | **Not run:** no substantive existing app integration suite. No replacement harness or dependencies were added. |
| iOS Simulator | Xcode reported available iOS 26.5 and 27.0 runtimes, with 23 available simulator instances, all shut down during inventory. A new 24th simulator was created only for this verification. | Native local-only launch/save/restart checks passed as qualified below; not an automated integration suite. |
| Physical iOS | Flutter reports two supported connected iOS targets, running 26.6.2 and 26.5.2. Device names and identifiers are deliberately omitted. | **Not run:** no app installed, launched, erased, or changed on either physical target. |
| macOS / Chrome | Flutter reports supported macOS and Chrome targets. | **Not run:** neither normal app nor browser profile was used for acceptance. |
| Android | `adb` and `emulator` are absent from PATH; the default `~/Library/Android/sdk` does not exist; Flutter lists no Android target. | **Blocked:** no available Android target/toolchain was identified. No installation attempted. |

Read-only inventory commands were executed from the verified `app/` directory:

```sh
/Users/harrygao/Downloads/flutter/bin/flutter --no-version-check devices --machine
xcrun simctl list runtimes --json
xcrun simctl list devices available --json
```

The first sandboxed Flutter invocation could not write its SDK cache metadata (`engine.stamp.tmp` and `engine.realm`). The first sandboxed `simctl` invocation could not connect to CoreSimulatorService or open its log. Narrowly approved retries outside that sandbox succeeded. These failures were execution restrictions, not missing Flutter/Xcode runtimes. Inventory output was filtered to omit personal device names/identifiers. No complete environment or Firebase configuration values were printed.

## Executed isolated simulator checks

Manual checks ran approximately 14:45–14:49 PDT on 2026-10-03, using an initial native build from earlier in the same session, before the follow-up cloud-cache and demo-sleep-provenance fixes. It was used to reproduce the source-label problem and check existing local save/restart behavior. The final fixed build was then verified in the same preserved simulator at 14:57–14:58 PDT.

| Executed check | Observed result |
| --- | --- |
| No-config simulator build | `/Users/harrygao/Downloads/flutter/bin/flutter build ios --simulator --debug --no-pub` passed; Xcode build took 66.5 seconds. The generated Dart define names were decoded and checked programmatically; no `FIREBASE_*` definition was present. Values were not printed. |
| New isolated installation | Created `Tonyo Phase 1 Verification`, an iPhone 17 on iOS 26.5, then booted, installed `build/ios/iphonesimulator/Runner.app`, and launched `com.ios.tonyo`. All `simctl` operations exited zero. No preexisting installation was used. |
| Normal consent / local mode | Device Hub displayed “Local mode. No Firebase account is created.” Normal adult age/region choice and data-use acknowledgement were completed through the UI. A synthetic `example.invalid` label was used; the unused local-form validation value was never saved. Health, Screen Time and Outcome learning were not enabled. |
| Fresh empty limitation | The normal final onboarding action is “Start with demo data”; it intentionally seeds fixture observations. Therefore an empty native profile was **Not run**. No consent bypass or direct empty-state injection was performed. Empty/stale software tests remain a separate evidence category. |
| Explicit zero save | In Activity Log, Exercise load was entered as `0`; hydration, study and screen time were left blank. The UI displayed “Activity log saved,” Exercise `Sat: 0 hr`, and other category charts “not recorded.” |
| Actual process restart | `simctl terminate` followed by `simctl launch` passed. Add displayed `1 saved` activity log after relaunch. A read restricted to this new simulator's native preferences confirmed exactly one grouped manual activity observation, exercise `0.0`, with no records for the blank categories. This is native local-storage/process-restart evidence, not a mocked SharedPreferences test. The zero edit field itself could not be reached because of the scrolling limitation below. |
| Editable schedule / second restart | Through Profile → Wake and bed schedule, saved `09:00` wake and `22:00` bed. After a second terminate/relaunch, Profile still displayed those times; the native test preferences also stored `9.0` and `22.0`. |
| Coach after schedule restart | Coach visibly rebuilt four blocks with the summary `9:15 AM–9:15 PM`; the first block was a 10-minute check-in at 9:15 AM. Daily plan reminders remained off and the UI stated uncalibrated forecasts do not trigger alerts. The entire block list, all end times and non-overlap were **Not run in native UI**, because scrolling failed; those properties are exercised by software tests. |
| Confirmed source-label regression | With no Health permission or real import, the new sleep card labeled demo fixture sleep “Apple Health estimate.” This was reproduced in the native UI and reported for a focused Phase 1 provenance fix. See the progress record for the regression test/fix and final-build result below. |
| Final fixed native build | Reran the same no-config `flutter build ios --simulator --debug --no-pub` after the final code changes and successful software tests. Passed; Xcode build took 21.4 seconds. Verified again that no `FIREBASE_*` defines or `GoogleService-Info.plist` were present, then terminated/reinstalled/launched only this test app; all commands exited zero. |
| Final native provenance check | Today visibly displayed “Demo sleep,” the explicit warning that these are demo/synthetic examples rather than imported/measured sleep, “Latest main sleep … Demo / synthetic example,” and “Displayed sleep total.” The misleading “Apple Health estimate” source label was absent from that card. This is an actual final-build native UI check. |
| Final native persistence check | After replacement/relaunch, Profile visibly retained `09:00 wake · 22:00 bed` and Add retained `1 saved`. Assertions against only the new simulator's native preferences passed: exactly one grouped manual exercise `0.0`, no observations for the blank categories, saved wake/bed values `9.0`/`22.0`, adult receipt retained, and Health access still off. |
| Test cleanup | Restored Device Hub keyboard capture to off. `xcrun simctl shutdown "$tonyo_test_simulator_id"` exited zero, and a subsequent device inventory confirmed this test simulator was `Shutdown` at `2026-10-03T14:58:06-07:00`. Its synthetic app/data container remains available; nothing was erased or deleted. Existing simulators and physical devices were unchanged. |

Concrete developer commands used for this installation and restart (the first command's returned test-only identifier was retained in `/private/tmp/tonyo-phase1-simulator-id`; commands below show it as a variable):

```sh
xcrun simctl create 'Tonyo Phase 1 Verification' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
tonyo_test_simulator_id="$(cat /private/tmp/tonyo-phase1-simulator-id)"
xcrun simctl boot "$tonyo_test_simulator_id"
xcrun simctl bootstatus "$tonyo_test_simulator_id" -b
xcrun simctl install "$tonyo_test_simulator_id" build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$tonyo_test_simulator_id" com.ios.tonyo
xcrun simctl terminate "$tonyo_test_simulator_id" com.ios.tonyo
xcrun simctl launch "$tonyo_test_simulator_id" com.ios.tonyo
xcrun simctl get_app_container "$tonyo_test_simulator_id" com.ios.tonyo data
xcrun simctl shutdown "$tonyo_test_simulator_id"
```

The `get_app_container` command only located this disposable app container. A Python `plistlib`/JSON read of its `Library/Preferences/com.ios.tonyo.plist` printed only the synthetic grouped activity type/value, saved wake/bed times, and boolean checks for the adult receipt and disabled Health access. No normal-device preferences were read or modified. Generated Coach blocks are not serialized in that preferences payload; an empty list there is not evidence that native schedule intervals passed.

UI automation used Xcode's **Device Hub** (`com.apple.dt.Devices`), not the unavailable legacy “Simulator” app name. The root handled an initial app-access elicitation and a retry succeeded. Accessibility clicks and screenshots worked; hardware text entry did not, so the simulator's on-screen keys were used. `scroll` and `drag` repeatedly failed with `Computer Use server error -10005: noWindowsAvailable`; no workaround used other UI automation technologies or changed OS privacy permissions. This limits checks requiring off-screen history/timeline controls.

## Safe installation prerequisites

Use a newly created simulator with its own empty data container, or a dedicated test device confirmed not to contain the user's normal Tonyo installation or health records. The iOS app uses `com.ios.tonyo`, so installing onto a normal device can replace the normal app. Do not use an existing populated simulator merely because it is shut down.

For local-only testing, build directly with Flutter and **without** `run.sh`, Firebase launch configurations, or `--dart-define-from-file`. `FirebaseRuntime.initialize()` returns without initializing Firebase when compile-time options are absent. Keep Health and Screen Time disconnected, Outcome learning disabled, and use synthetic adult data entered through normal privacy onboarding. Do not inject a consent receipt or guardian claim to skip onboarding. A synthetic email under `example.invalid` is suitable for local-only form validation; do not reuse any real credential.

The app currently has no Auth/Firestore emulator-routing option. The rules-testing harness simulates authentication for security tests; it does not make the Flutter app emulator-aware. Therefore signed-in app, trusted guardian, cloud save/reload, and eligibility-withdrawal device flows remain **Blocked** for safe demo-only execution until an authorized isolated app/emulator integration path exists. Do not point this acceptance run at production to remove that blocker.

## Manual acceptance checklist

All rows are **Not run** on physical devices. A passed controller or widget test does not change that status. For each executed device row, record the target OS, app revision, synthetic setup, exact wall-clock times, action, visible result, and whether termination/relaunch or actual OS notification delivery occurred. Do not record personal data or account secrets.

| Scenario | Prerequisites and exact steps | Expected result |
| --- | --- | --- |
| Fresh empty install | **Not run natively:** normal onboarding seeds demo observations and has no empty-profile option. Use an authorized empty synthetic installation fixture through a supported setup path when available; do not inject a consent receipt or edit the normal installation. Leave Health/Screen Time and Outcome learning off, then open Today, Forecast and Coach. | Today shows “Not enough information to estimate”; no Fresh/ready label or reassuring default numeric score. No precise peak/crash/recovery alert. Coach has no observation-grounded blocks to schedule. |
| Stale observations / resume | In the same isolated profile, record a synthetic check-in and a manual completed sleep. Note their displayed date/time. Leave the installation until the next local date without adding inputs, then resume and cold-relaunch it. Do not change the host or normal phone's clock. | Old observations retain their actual dates; old measurements do not become current scores, forecasts, or reminders. Latest sleep remains dated rather than implicitly “last night.” |
| Explicit zero / restart | In Add → Activity log, leave hydration, study, and screen time blank; enter `0` in Exercise load and save. Reopen the log, then terminate the isolated app process and launch it again. Reopen the same log and use Profile → Save device backup to export to a test-only path. | Exercise remains explicitly `0`; the other fields stay blank. The synthetic export includes the exercise observation with value zero; it does not invent zero records for blank fields. This must be checked after a real process restart, not only navigation. |
| Clear versus zero | Edit the preceding log. Add a synthetic study value so the record can retain another category; clear Exercise load to blank and save. Terminate/relaunch and reopen the log. Separately repeat by deleting a zero-only log. | Clearing/removing the exercise observation is distinct from saving zero. The exercise field stays blank after restart. Imported fallback cannot be verified without isolated synthetic Health inputs; leave that subcheck Not run rather than importing real health records. |
| Schedule persistence | Profile → Wake and bed schedule: save `09:00` wake and `22:00` bed. Close/reopen the dialog and cold-relaunch. Enter a current synthetic check-in so Coach can generate optional blocks. Repeat with `18:00` wake and `06:00` bed on the test installation. | Times persist. Each Coach block starts at/after wake, ends by bed, and does not overlap the preceding block. The overnight case protects the complementary sleep interval. Invalid/equal times are rejected. |
| Removed rewards | With one current synthetic check-in fixed, record its score/version and forecast. Add/edit only hydration volume or exercise duration, then cold-relaunch and compare. Use the ordinary UI only. | These logged quantities do not add Energy/Cognitive points or restore retired forecast adjustments. Caffeine has no ordinary standalone entry field; its invariance is covered by software fixtures until an authorized synthetic input path is available. |
| Historical basis | Open Forecast → Insights after adding synthetic observations on at least two local dates. Open Today → Why these scores? and compare the disclosed reference version. | Insights labels its current-version deterministic recomputation basis; it does not imply the series is the exact saved/personalized value originally shown. Score provenance/version remains available in the explanation. |
| Notification opt-in and actual delivery | Use an isolated physical device with normal adult consent, a current synthetic scored observation, and a future eligible Coach block. In Profile → Notifications enable notifications and Daily plan reminders; grant the OS prompt. Note the scheduled block's time, background the app, and wait through that time. | Only an optional Coach reminder may be delivered; tapping it opens Coach. Disabled precise forecast categories remain unavailable. A scheduled count alone does not prove delivery. |
| Disable / pending cancellation | Schedule a future Coach reminder as above. Turn off Daily plan reminders before its delivery time; background the app and wait past that time. Repeat using the master Allow notifications switch. Reopen and cold-relaunch afterward. | The applicable count becomes zero, no removed reminder is delivered, and launch/resume does not recreate it while disabled. Test real OS scheduling, not just the UI counter. |
| Sign-out cancellation | Schedule a future reminder in the isolated local profile; sign out before delivery. Background and wait past the old time, then relaunch while still signed out. | Old reminders do not deliver or reappear; no data collection resumes behind the welcome screen. Local profile resumption, if deliberately selected later, retains raw synthetic records. |
| Losing eligibility | **Blocked for signed-in device testing:** requires an authorized isolated Auth+Firestore test setup, synthetic adult/minor accounts, and legitimate server-managed claim/receipt changes. When available, schedule a reminder, withdraw eligibility server-side, then resume/restart. Do not forge the production claim or bypass consent. | New collection stops, relevant pending reminders are canceled, and stale asynchronous work cannot restore them. Owner export/deletion remain accessible according to existing policy. |
| Incompatible artifact / old cache | **Not run on device:** requires a synthetic pre-Phase-1 test installation or fixture using existing supported migration pathways, not the normal installation. Upgrade only that isolated installation, then restart and inspect raw observations, model status, and attempt ledger without requesting refresh/training. | Old derived artifacts are rejected, raw inputs/receipts remain, and the valid training-attempt timestamp/outcome ledger is preserved. No automatic training occurs. |
| Deterministic-only cloud merge | **Blocked for signed-in device testing:** requires an emulator-aware isolated app setup. Use a synthetic account with an old personalized score document, save a new deterministic-only score, reload from the emulator, and restart the app. | Old `deterministicEnergy` and `personalizedModelVersion` are explicitly cleared and cannot change the reloaded score. The real Firestore rules suite separately checks the local emulator's merge behavior. |
| Travel / DST | Use only an isolated simulator or dedicated device. With saved synthetic observations/schedule, change that target's time zone, then resume and cold-relaunch. Exercise spring-forward and fall-back dates using a purpose-built isolated time fixture if available; do not alter the normal host/device clock. | Instants retain provenance, local-day displays/schedules rebuild, protected sleep is respected, and one-shot reminders use distinct instants through a repeated hour. The explicit TZ software suite is not physical DST acceptance. |
| Export / deletion access | In the isolated adult local profile, create a synthetic backup through the UI, inspect only synthetic fields, restore through the normal preview/confirmation flow if desired, and verify zero/missing distinctions. Any deletion check must target this disposable test profile only. Cloud owner/export/deletion and denied cross-account reads are handled separately by the emulator suite. | Backup/restore preserves input distinctions and never grants consent/guardian authority. Deletion is scoped to the disposable test data; no claim is made about production provider backups. |

## Current outcome

Native notification delivery, background/resume behavior, and process-restart persistence remain **Not run on physical devices**. Local zero and schedule persistence received actual simulator process-restart checks, with the specific UI/storage limits above. App integration tests remain **Not run** because no substantive integration suite exists. Connected physical hardware establishes test availability only, not acceptance success. No later phase, model training, production access, deployment, or real Health import is part of this verification.
