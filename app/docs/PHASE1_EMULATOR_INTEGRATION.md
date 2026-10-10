# Phase 1 local app integration

This opt-in harness exercises the Flutter app's native Firebase plugins against local Auth and Firestore emulators. It is separate from the Node security-rules suite and from physical-device acceptance. It does not establish biological, clinical, or fatigue-prediction accuracy.

## Isolation

- `TONYO_LOCAL_EMULATORS=true` is accepted only in debug builds and rejects any known `FIREBASE_*` configuration value. Ordinary launch behavior is unchanged.
- The project is fixed to `demo-tonyo-privacy`; Auth is fixed to `127.0.0.1:9099`, Firestore to `127.0.0.1:8080`. Neither host nor project accepts an override. There is no production fallback. The named Firebase app separates the local native Auth session from the usual default Firebase app, and local Firestore persistence is disabled so server checks cannot pass from a cached document. The installed Firestore platform factory also requires a default Core app; the harness initializes that scaffold with the same synthetic demo options. All actual Auth/Firestore clients use the named app.
- `firebase.integration.json` loads the actual current `firestore.rules` and indexes. The runner prints the rules SHA-256 and invokes only `emulators:exec`, never deployment.
- The runner allowlists its child environment, isolates Firebase CLI configuration under ignored `.runtime/app-config`, and excludes credential variables, production project selection and debug environment logging. It refuses the usual native iOS `GoogleService-Info.plist` path.
- The driver requires both expected emulator endpoints and the demo project before creating a **new** simulator. It has no option to select a preexisting simulator or physical device. It shuts down only the simulator it creates, preserving its synthetic container.
- Tests generate synthetic `example.invalid` accounts and ephemeral credentials in memory. They use ordinary explicit privacy consent and account APIs. They never import Health records, enable optional outcome learning, train a model or grant a guardian claim.

The new SDK `integration_test` dependency brings its SDK driver dependencies and existing-cache hosted dependencies; existing package versions are not upgraded.

## Commands

From `app/`, resolve the existing cache and run the guard checks:

```sh
flutter pub get --offline
flutter test --no-pub test/firebase_options_test.dart test/firebase_emulator_options_test.dart
```

From `app/tool/security_rules/`, with the already-required Node >=22, pnpm 11.19.0, Java >=21 and Flutter available:

```sh
pnpm test:app
```

`FLUTTER_BIN` may name the Flutter executable. On this workspace the portable Java and existing Node/pnpm runtimes are reused without system installation:

```sh
env PATH="/Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH" JAVA_HOME="$PWD/.runtime/java21/jdk-21.0.12.1+1-jre/Contents/Home" FLUTTER_BIN=/Users/harrygao/Downloads/flutter/bin/flutter /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime.previous/dependencies/node/node_modules/pnpm/artifacts/exe/dist/pnpm.mjs test:app
```

The historical pnpm path above is no longer present on this workspace as of October 10, 2026. Invoke the same existing runner directly from `app/tool/security_rules/` with the current Node runtime:

```sh
env JAVA_HOME="$PWD/.runtime/java21/jdk-21.0.12.1+1-jre/Contents/Home" FLUTTER_BIN=/Users/harrygao/Downloads/flutter/bin/flutter /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node run_app_integration.mjs
```

The runner executes `flutter test --no-pub --no-uninstall integration_test/phase1_cloud_test.dart -d <new-simulator-id> --dart-define=TONYO_LOCAL_EMULATORS=true --reporter=expanded`. It then stops that app process (or verifies Flutter already stopped it) and runs the same command with `--dart-define=TONYO_VERIFY_PROCESS_RESTART=true` added, retaining the app installation, simulator container and live emulator records. The `--no-uninstall` flag is required because Flutter integration tests otherwise remove the app after each pass. Do not substitute a normal device ID or add the real Firebase configuration file. Do not use `run.sh` for this harness. A compatible installed iOS Simulator runtime/Xcode and free loopback ports 8080/9099 are prerequisites; no toolchain is installed by the script.

## Coverage and limits

The native scenario checks explicit-consent gating before account creation; normal adult consent and registration; exercise zero and absent blank fields on the Firestore server; schedule and language preference reload; controller reconstruction using actual native storage; clearing zero as a cloud deletion; explicit null clearing of obsolete personalization fields; denied outcome writes without opt-in; denied cross-account reads; denied minor consent without a trusted guardian claim; and retained owner export/deletion access.

The first pass includes controller reconstruction, which alone is **not** an OS process restart. Before cloud hydration, the independent second native launch reads actual native preferences and checks retained zero/cleared values, schedule and language. It also checks persistent emulator Auth, server records, absence of obsolete personalization fields, and the visible Spanish navigation/locale before deleting only its synthetic account through the normal owner lifecycle API. Native notification delivery, background behavior, physical-device behavior and guardian-approved account flows remain separate acceptance checks. Normal onboarding still seeds clearly labeled demo records; this suite does not manufacture an empty profile by bypassing consent.

## Execution record — 2026-10-04

- SDK dependency resolution: `flutter pub get --offline` passed.
- Firebase routing unit tests: 5 passed, 0 failed, 0 skipped, counting the three existing options cases and two new emulator guard cases together.
- After the native identifier-shape fix, `flutter test --no-pub test/logging_localization_test.dart test/activity_zero_widget_test.dart test/firebase_options_test.dart test/firebase_emulator_options_test.dart` passed **11 tests**. This includes the same five routing tests; do not add the overlapping totals. The four logging cases also cover the two reproduced/fixed zero-versus-missing display regressions, Spanish decimal-comma input and preserving user notes in Chinese UI.
- Targeted analysis of routing and the native integration scenario: clean after correcting an initially missing test import.
- Initial emulator launch failed before installation because Firebase CLI disallows a rules file above its configuration's project directory. The dedicated config was moved to `app/firebase.integration.json`, referencing the same current rules and indexes. No security rules changed.
- The first native build passed (47.5 seconds), but initialization aborted before any scenario completed. Its isolated crash stack identified native `FIRInstallations.validateAPIKey`: the deliberately fake identifier had an invalid shape. The emulator options now use an unregistered synthetic identifier with the required native shape; guard assertions prevent that startup regression. The locally installed Firebase iOS SDK confirms Installations token prefetch is disabled during initialization. The failed test simulator was shut down and retained.
- An intermediate retry failed compilation while language screens were still being edited in parallel; it did not run a native scenario, and its simulator was shut down. Subsequent native runs wait for source-analysis checks and the exclusive build/device window.
- The next native build passed (28.8 seconds), then exposed `core/no-app` in the installed `cloud_firestore_platform_interface` factory: even `instanceFor(namedApp)` constructs its platform delegate from a default Core app. Added the synthetic default Core scaffold described above; no production configuration is read. That test simulator was shut down and retained.
- After the scaffold fix, the first native scenario passed (Xcode 35.4 seconds). The independent restart build passed (23.6 seconds), but its scenario reproduced an existing Phase 1 defect: nested score-driver `evidenceAt` values arrived as native Firestore `Timestamp`, while the repository normalized only top-level timestamps. Score reload threw `FormatException`. The new read-only `firestore_value_codec.dart` recursively normalizes maps/lists without mutating input or changing existing `Timestamp.toDate()` semantics. Zero and null values remain intact; no schema migration or raw-data rewrite is needed. `flutter test --no-pub test/firestore_value_codec_test.dart test/cloud_schema_test.dart` passed **18 tests**, including the new native-value score/evidence contract fixture.
- The next two native scenarios both passed (Xcode 32.0 and 24.3 seconds; overall exit 0), confirming the Timestamp fix and cloud-backed recovery in Spanish. The second launch logged an empty local cache: inspection of the installed Flutter tool showed integration tests uninstall the app by default. That pair proves cloud recovery and native Auth retention, **not local-cache persistence**. The harness now passes the SDK's existing `--no-uninstall` flag and asserts native preferences before cloud hydration in the restart scenario.
- Final strengthened `pnpm test:app` execution: **2 native scenarios passed, 0 failures, 0 skipped, overall exit 0** on a newly created **iPhone 17 / iOS 26.5 Simulator**. Both invocations used `--no-uninstall`; Xcode builds took 28.7 and 25.8 seconds, with scenarios completing in 4 and 1 seconds. After the first process stopped, the second verified actual retained native preferences **before cloud hydration**, including explicit zero, the cleared exercise override, Spanish language, bedtime and wake time. Persistent emulator Auth, current-version score reload with nested evidence, cleared personalization fields, and the visible Spanish navigation/locale all passed. The synthetic owner account/data were deleted through normal APIs, the new simulator was shut down, and both emulators stopped successfully. The rules SHA-256 remained `234c822c4bcb19d532840ec92563698644c35aa433ceb701d162518ce54646dc`.
- Final test/driver edits passed targeted Dart analysis and `node --check`; `git diff --check` is clean. These two native scenarios are separate from the 950-test unit/widget suite and 28-test Node rules suite. Focused unit runs listed above overlap the full software suite and must not be added to it. This is simulator evidence; physical-device acceptance and biological accuracy remain unverified.

If interrupted, the runner's new simulator ID is retained in ignored `tool/security_rules/.runtime/app-integration-simulator-id`; shut down only that recorded simulator. No simulator is erased automatically.

## Phase 2A extension — 2026-10-04

The same `pnpm test:app` command and isolation guards now also exercise the [measurement foundation](PHASE2A_MEASUREMENT.md). The first process saves a complete six-value Evening response and a partial Morning response, edits the partial response to explicitly clear Energy while retaining Focus = 6, checks actual Firestore integer/null fields and exact observation-time precision, and confirms no legacy outcome was generated. Both native preference checks and the independent second process verify raw answers, missingness, completeness, selected period, version/language, original definition and time metadata. The first native preference check occurs before stopping the process; the second occurs before cloud hydration. Existing Phase 1 zero, override deletion, language, schedule, score, consent/isolation/export and synthetic account-deletion assertions remain present.

The first Phase 2A run failed after the partial response edit with a false concurrent-edit conflict. Inspection of the installed native Firebase codec showed bare `DateTime` serialization drops microseconds. Added a recursive write encoder using `Timestamp.fromDate` for journaled inputs/profile changes and linked legacy outcomes, retaining exact conflict checks and source/outcome timestamp agreement. No rules weakening or timestamp-tolerance bypass was used. Three new codec regressions and the surrounding focused suites passed **36 tests**.

The final rerun passed **2 native scenarios, zero failures/skips, exit 0**, on a newly created iPhone 17 / iOS 26.5 Simulator. Xcode builds took **28.5s** and **24.5s**, with scenarios completing in **3s** and **1s**. Both commands used `--no-uninstall`; local preferences survived the real process stop/restart and were checked before any cloud reload. Complete and cleared-partial responses also survived native server reload. Synthetic account deletion, shutdown of only the new simulator, and both emulator shutdowns completed successfully. Current rules SHA-256: `0cdebfd8a58d7c1a713c5c75cd3619c61130d829e9464995dd471fdc193370af`. This hash describes the Phase 2A rules; the earlier Phase 1 hash above is historical.

This remains native simulator integration, not a physical-device, screen-reader, OS travel/DST, notification-delivery or measurement-validity result. The new native response saves exercise normal controller APIs rather than taps on all six form controls; widget tests cover the form, while an expanded native UI walkthrough remains **Not run**. Exact remaining steps are in the measurement guide. The separate Node security suite passed 35 cases; focused Flutter counts overlap the full suite recorded in [the progress record](BIOLOGY_UPGRADE_PROGRESS.md).

## Phase 2A measurement acceptance — 2026-10-10

The expanded native walkthrough supersedes the earlier **Not run** status for the specific simulator flows below. It retains the same fixed demo project, loopback-only routing, ordinary consent/account APIs, newly created simulator and `--no-uninstall` two-process execution. No production code, Firebase rules, schema, dependencies, native bridge or research/model settings changed in this follow-up.

| Exercised boundary | Accepted evidence |
| --- | --- |
| Native form | Spanish navigation; all six answers initially unset; period and nonempty-answer validation; Focus-only submission; normal history edit adds Energy then clears it. English original wording remains visible under the Spanish interface; changing Focus then canceling leaves the saved record unchanged. |
| Historical observations | Eight preceding captured dates of English reports and varied manual sleep, plus a current English report, created through the normal controller APIs in the disposable account. Exact intended values, independent missing items, sleep durations, wording, source and time metadata are checked. These artificial observations exercise inclusion paths; they are not participant data. |
| True restart and server reload | Exact raw response/sleep maps are captured in a separate test-only native-preferences manifest. Actual app preferences are compared before hydration on the independent process launch; fresh `Source.server` reads and the rebuilt controller match the same manifest. Existing zero/clearing, schedule, Spanish preference, consent and ownership checks remain. |
| References and trends | The restarted Today panel shows Energy average 5.5 from eight days. Independent reference counts, missing current answers and sparse measures are checked. Insights exercises rating/sleep charts, exact missing-date records and measure/period/language filtering. |
| Research export | Opening produces no prepared export. Explicit preparation shows counts. Canceling copy leaves a test sentinel untouched; confirmed JSON and CSV reach the native iOS clipboard and match the expected raw tables. Export privacy/provenance checks exclude notes, original identifiers, account ID and email. The clipboard is cleared afterward. |
| Questionnaire library | The normal Profile route opens a read-only library with zero installed instruments. No questionnaire collection or approval is enabled. |
| Read-only and cleanup | Review/export navigation leaves raw inputs unchanged; optional outcome learning remains off and no measurement outcomes are generated. Normal owner APIs delete the disposable account/data; only the new simulator is shut down, followed by both emulators. |

Implementation: [main native scenario](../integration_test/phase1_cloud_test.dart), [historical/read-model assertions](../integration_test/phase2a_measurement_fixtures.dart), [native UI walkthrough](../integration_test/phase2a_measurement_ui.dart). The [direct Node command above](#commands) runs the complete pair and prints the selected simulator/runtime and current rules hash.

**Final result:** **2 native scenarios passed, zero failures/skips, overall exit 0**, on a fresh **iPhone 17 / iOS 26.5 Simulator**. Xcode builds took **39.4s and 31.1s**; scenario runs completed in approximately **36s and 21s**. Both invocations retained the installation. Full `flutter analyze --no-pub` was clean; three integration Dart files passed format verification, and the driver passed `node --check`. The rules hash remains `0cdebfd8a58d7c1a713c5c75cd3619c61130d829e9464995dd471fdc193370af`.

Earlier attempts found only acceptance-helper issues: an unrendered initial frame, an English-only SDK Back lookup, ancestor scrolling that moved the horizontal pager, and requiring a blank text-panel center to hit-test. These were corrected without dropping data/UI assertions or changing the app. See the [development log](DEVELOPMENT_LOG.md) for the execution trail. Final native log: `/private/tmp/tonyo-phase2a-native-acceptance-5.log` (temporary local artifact).

The previously passing **1,105** unit/widget tests and **35** Node rules cases were not rerun in this harness-only follow-up and are not added to these two scenarios. System file-picker saving, screen readers, physical devices, all-language native review, OS timezone changes and remaining notification/release acceptance are still separate. The English editor was canceled rather than saved, and all six complete values were created through controller APIs. Native clipboard routing is confirmed by the installed SDK and iOS platform handler; host clipboard sharing was not assessed. This provides no research-protocol, psychometric, clinical or prediction-validity approval.
