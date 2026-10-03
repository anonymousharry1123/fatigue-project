# Biology upgrade — Phase 1

Implemented locally on 2026-10-03 against the repository's [biology plan](../../TONYO_BIOLOGY_UPGRADE_PLAN.md). This is a software safety and interpretation change, not clinical validation. Phases 2–5 remain deferred.

## Implemented behavior

| Area | Change and implementation |
| --- | --- |
| Sleep observations | Today displays the latest completed main-sleep estimate with local date and source, a named 24-elapsed-hour window, deduplicated recorded duration and separate naps, seven local-date observation/missing counts, usual main duration, and circular bedtime/wake variation. Existing manual/Health source reconciliation runs first. Manual bed/wake entries are estimates, not measured time asleep. [Logic](../lib/src/sleep_observation_logic.dart), [card](../lib/src/widgets/sleep_observation_card.dart). |
| Age guidance | Only the existing privacy bands `13to15` and `16to17` receive the AASM 8–10 hours per 24 hours comparison [S1]. `18plus`, unknown and under-13 do not receive this teen interpretation. It uses the privacy receipt, not the ambiguous legacy profile age string. Guardian/authentication gates are unchanged. [Logic](../lib/src/sleep_observation_logic.dart), [Today](../lib/src/screens/today_screen.dart), [privacy gates](../lib/src/privacy_consent.dart). |
| Coverage | A sleep record or Health permission never establishes full-day observation. A session-only checkbox confirms all sleep was recorded for the exact displayed window/evidence/age; it resets when any of those change. Without confirmation, or with ambiguous imported interval geometry at a window boundary, comparison is unavailable. A usual short baseline cannot lower the recommendation. Naps are not assigned an equivalent restorative effect. [Logic](../lib/src/sleep_observation_logic.dart), [card](../lib/src/widgets/sleep_observation_card.dart). |
| Scores | Caffeine, fluid volume, exercise duration, steps, main-sleep duration and naps no longer earn Energy or Cognitive points; removed exposure effects are absent from forecast adjustments. Optional logging remains. No replacement biological coefficients were introduced. Existing remaining workload, mood/stress, reaction and mature heart-baseline coefficients are still experimental. [Engine](../lib/src/fatigue_engine.dart). |
| Availability | No current usable scored observation means “Not enough information to estimate,” not a reassuring neutral value. Prior-day, future, invalid and model-only observations cannot qualify as fresh evidence. HRV/resting-HR records without a mature comparison baseline remain context only. Current coverage totals are six Energy categories and five Cognitive categories, distinct from predictive accuracy. [Engine](../lib/src/fatigue_engine.dart), [models](../lib/src/models.dart), [Today](../lib/src/screens/today_screen.dart). |
| Alerts and Coach | Removed sleep-debt and fixed-hours overtraining/overreaching inference. The remaining flag states factual low-energy/high-stress check-in observations. Plans offer optional check-in, focus, pause and quiet wind-down blocks within the saved waking window; blocks cannot overlap or enter protected sleep. No automatic workout/nap, stimulant, fluid quantity or intensity authorization. [Engine](../lib/src/fatigue_engine.dart), [planner](../lib/src/daily_plan_logic.dart), [schedule logic](../lib/src/schedule_logic.dart). |
| Schedule | Wake and bed times can be edited after onboarding in Profile. Finite distinct local clock times are validated; cross-midnight schedules use calendar construction across DST. No fixed-commitment schema exists in this app, so no school-timetable system was added. [Profile](../lib/src/screens/profile_screen.dart), [schedule](../lib/src/schedule_logic.dart), [controller](../lib/src/app_controller.dart). |
| Historical Insights | Deliberately uses current-version deterministic per-day recomputations, not a mixture of original saved and personalized scores. The series discloses this basis and may differ from what was displayed historically. The query includes the full 42-day preceding baseline for each of the 14 displayed days (56 local dates), with past-day cutoff at local day end and current-day cutoff at now. Missing history remains missing. [Insights logic](../lib/src/insights_logic.dart), [screen](../lib/src/screens/insights_screen.dart). |
| Firestore merge bug | A regression reproduced an old deterministic fallback of 50 replacing a newly written deterministic 72 after merge/reload. Deterministic saves now explicitly set `deterministicEnergy` and `personalizedModelVersion` to null; availability and missing Cognitive fields are explicit. Legacy personalized pairs require their existing adjustment-driver provenance. [Serializer](../lib/src/cloud_schema.dart), [regression](../test/cloud_schema_test.dart). |
| Zero versus missing | Explicit zero is persisted, edited, synced, exported and restored as an observation. Blank stays null/absent. A manual zero activity correction overrides an imported value; clearing the field or deleting the log restores imported fallback. Charts retain observation flags so missing bars do not claim recorded zero. Existing omitted records are not backfilled. [Activity logic](../lib/src/activity_log_logic.dart), [editor](../lib/src/screens/activity_log_screen.dart), [controller](../lib/src/app_controller.dart), [round-trip tests](../test/activity_log_signals_test.dart). |
| Uncertainty | Heuristic confidence is shown as data quality/coverage, not probability of correctness. Forecast bands are explicitly uncalibrated estimates, not statistical confidence intervals. Curve high/low positions are not established periods of alertness, fatigue or safe exercise. [Forecast](../lib/src/screens/forecast_screen.dart), [transparency](../lib/src/screens/model_transparency_screen.dart). |
| Notifications | Precise forecast peak/crash/recovery alerts are suppressed regardless of quality percentage. Existing opted-in Coach reminders require current versioned plans and linked current evidence; freshness also must hold at the intended delivery time. Input/schedule changes cancel old native schedules before asynchronous persistence; launch cancels obsolete schedules even if sign-out/privacy gates prevent regeneration. No consent is enabled by migration. [Notification logic](../lib/src/notification_logic.dart), [controller](../lib/src/app_controller.dart), [regressions](../test/coach_notification_controller_test.dart). |

## Versioning and migration

- Deterministic references are `energy-rules-v3-phase1` and `cognitive-rules-v3-phase1`. Forecast points carry `rulesVersion`; absent/older versions cannot drive current views. Score cache reuse checks current day, age, rule versions and actual deterministic evidence, not just the presence of inputs. Removing linked forecast evidence invalidates the curve. [Engine](../lib/src/fatigue_engine.dart), [controller](../lib/src/app_controller.dart).
- Cloud schema is 15. The nullable personalization fields use existing Firestore merge conventions; no security-rule change or deployment is included. Historical documents retain their original provenance; a regenerated daily derived document replaces that day's derived result. Raw signals, check-ins, independent outcomes and consent records are not erased or relabeled. [Schema](../lib/src/cloud_schema.dart), [repository](../lib/src/firebase_services.dart).
- Preparation cache version is 2. Incompatible derived preparation caches must be fetched/prepared again explicitly; raw observation journals are unchanged. [Preparation models](../lib/src/ml_prep_models.dart), [preparation service](../lib/src/ml_prep_service.dart).
- Existing fitted weights tied to old rules are rejected. Local cleanup removes the artifact but preserves a valid `lastAttemptAt` and `eligibleOutcomeKeys` ledger exactly. No launch/migration/view silently trains, uploads model metadata, resets the 24-hour attempt safeguard or manufactures labels. [Model service](../lib/src/energy_model_service.dart), [migration regression](../test/energy_model_service_test.dart).
- The existing ridge estimator remains optional and unchanged in form. Its eight metadata slots are retained, but sleep deviation, movement, hydration and caffeine slots are retired to null. The kernel rejects non-null retired values/ages, and current-reference artifacts reject nonzero retired weights/coverage. They cannot reintroduce removed effects through correction or feature freshness. Remaining feature normalization, bounded corrections and the four-present-features training gate remain. Consequently many previously eligible datasets will now abstain, particularly without mature paired heart baselines. This is an eligibility limitation, not a reason to invent observations or weaken gates. [Builder](../lib/src/ml_prep_builder.dart), [kernel](../lib/src/energy_residual_model.dart).

## Evidence used and limits

- **S1 — AASM teen sleep advisory:** [Teen Sleep Duration Health Advisory](https://aasm.org/advocacy/position-statements/teen-sleep-duration-health-advisory/). Supplies the general 8–10-hour/24-hour teen range. The app supports the two unambiguous adolescent privacy bands only; the range is not an individual's exact sleep need or a validated scoring equation.
- **S2 — AAP:** [The Effects of Caffeine on Kids: A Parent's Guide](https://www.healthychildren.org/English/healthy-living/nutrition/Pages/the-effects-of-caffeine-on-kids-a-parents-guide.aspx). Used for the decision to remove caffeine rewards and stimulant suggestions, not to invent a dose-response coefficient.
- **S3 — NHLBI:** [Healthy Sleep Habits](https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits). Supports protecting sleep opportunity and a quiet routine. The plan's optional block durations are scheduling choices, not clinically optimal treatment timing.
- **S8 — ECSS/ACSM consensus:** [Prevention, diagnosis, and treatment of the overtraining syndrome](https://pubmed.ncbi.nlm.nih.gov/23247672/). The implementation removes diagnosis-like inference from fixed exercise hours; it does not implement a diagnostic assessment.

The existing remaining score weights, neutral internal constants, simple clock-shaped forecasts and bands have not gained clinical calibration. A score is not exercise clearance. Imported sleep stage summaries retain totals rather than complete interval geometry, so clipped-window totals can be approximate and comparison may be unavailable. Circular timing variation describes observed clocks; bedtime variation uses only paired timestamps and has its own observation count. Missing nights are not zeros. The checkbox is self-reported completeness, is not synced or exported as a medical fact, and does not establish measurement accuracy. No clinician approval, medical accuracy, real-user validation or physical-device delivery is claimed.

## Validation record

Commands were run from the verified Flutter app directory with the installed SDK `/Users/harrygao/Downloads/flutter/bin/flutter` (the plain command was not on this shell's PATH). SDK cache writes required the execution tool's approved sandbox escalation. No dependency versions were intentionally changed.

Initial implementation verification (2026-10-03; superseded by the follow-up below):

| Command actually executed from `app/` | Result |
| --- | --- |
| `/Users/harrygao/Downloads/flutter/bin/flutter analyze --no-pub` | No issues found. |
| `/Users/harrygao/Downloads/flutter/bin/flutter test` | 903 tests passed. No unresolved Flutter test failures. |
| `TZ=America/Los_Angeles /Users/harrygao/Downloads/flutter/bin/flutter test --no-pub test/sleep_observation_logic_test.dart test/engine_local_day_test.dart test/local_calendar_test.dart test/daily_plan_logic_test.dart` | 28 passed in a separate execution of a subset already included in the 903-test full suite; not 28 additional unique tests. Includes spring/fall DST and schedule/calendar cases. |
| Changed-files-only `/Users/harrygao/Downloads/flutter/bin/cache/dart-sdk/bin/dart format …` | Changed Dart files formatted; unrelated Dart files untouched. |
| `git diff --check` from the repository | Passed. |

The first full `flutter test` run had 871 passes and 20 failures, including old reward/notification/schema assumptions and the sleep panel's scroll-storage collision. They were resolved and the complete suite rerun successfully. Focused tests also reproduced the merge bug before its serializer fix. These are software regression results, not estimates of medical accuracy. Dependency manifests, lockfile, Firebase configuration and Firestore rules are unchanged by Phase 1.

Focused suites cover empty/stale evidence, retired reward invariance, immature heart-baseline abstention, source reconciliation, teen/unsupported ages, incomplete sleep coverage, naps/overlaps/midnight/DST, circular clock variation, explicit-zero edit/sync/export/restore, deterministic merge reload, incompatible residual artifacts and preserved attempt ledger, historical basis disclosure, schedule edits, evidence-loss cancellation, privacy/guardian/owner gates and narrow-screen enlarged-text behavior. Synthetic fixtures serve software regressions only.

The initial implementation run did not execute the Firestore suite: Node and pnpm were absent from that shell's PATH, and the system Java launcher found no runtime. That lookup did not establish that Node/pnpm were uninstalled. The follow-up below resolves these environment blockers and records actual emulator enforcement tests separately from Dart serialization/source-shape tests.

## Deferred work and next task

- Phase 2 constrained conversational Coach, Phase 3 future-outcome model/validation, Phase 4 replacement attention protocol, and Phase 5 participant experiments are not implemented.
- A new school timetable/fixed-commitment model, clinician approval, biological coefficient estimation, forecast calibration, immediate server token revocation and production guardian workflow remain outside this change.
- Physical-device review remains necessary for Health imports, schedule edits across travel/DST, notification delivery/cancellation and voice-over behavior; automated tests do not demonstrate those.
- **Remaining acceptance:** complete the device checks marked Not run or Blocked in [PHASE1_DEVICE_ACCEPTANCE.md](PHASE1_DEVICE_ACCEPTANCE.md), particularly physical notification delivery/cancellation, background/resume, cold restart and isolated signed-in cloud flows. The local Firestore harness has now passed. Do not start a later phase or deploy as part of this task.

## Phase 1 verification follow-up — 2026-10-03

**Status: Phase 1 still has outstanding device acceptance checks.** Passing software tests does not establish biological, clinical, or fatigue-prediction accuracy. No Phases 2–5 work, model training, production access, deployment, account changes, commit, push, dependency upgrade, or security-rule relaxation was performed.

### Repository and environment

The Git root was verified as `fatigue-project/` and Flutter root as `fatigue-project/app/` using `git rev-parse --show-toplevel` and `pubspec.yaml`. Git status was clean before this follow-up's edits. No applicable `AGENTS.md` was found in the workspace or ancestor chain. The current biology plan, this progress record, `docs/PLAN.md`, security README, package scripts, lockfile, rules, and implementation/tests were reviewed. The same-session development-log requirement in `docs/PLAN.md` is satisfied below in [DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md).

The initial tooling diagnosis was incomplete:

- **Node:** installed and executable, but absent from the shell PATH. Reused `/Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node`, version **24.19.0**, satisfying Node ≥22.
- **pnpm:** the current cached launcher reports **11.25.0**, so it was not used for tests. The existing previous-runtime bundle `/Users/harrygao/.cache/codex-runtimes/codex-primary-runtime.previous/dependencies/node/node_modules/pnpm/artifacts/exe/dist/pnpm.mjs` reports the repository-pinned **11.19.0** and was reused with the Node executable above.
- **Java:** `/usr/bin/java` is only a launcher; both `java -version` and `/usr/libexec/java_home -V` reported no runtime. Searches of standard Java, Homebrew, application, download, runtime-cache and temporary locations found no usable Java binary. Downloaded an official portable **Temurin 21.0.12.1+1 JRE**, checked its SHA-256 against the [Adoptium API](https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=aarch64&image_type=jre&os=mac&vendor=eclipse), and extracted it under ignored `tool/security_rules/.runtime/java21/`. No system-wide installation, privilege elevation such as sudo, or persistent shell changes occurred. The official download was [this Temurin release](https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.12.1%2B1).
- **Dependencies:** existing modules match the three direct pins (`@firebase/rules-unit-testing` 5.0.2, `firebase` 12.18.0, `firebase-tools` 15.29.0); the existing lockfile/module installation was reused. No dependency installation or lockfile change was necessary.
- **Execution restrictions:** the first metadata download failed DNS resolution inside the sandbox; its approved retry succeeded. The first emulator run failed to bind loopback sockets with `EPERM` (the CLI misleadingly summarized this as “port taken”); the approved retry using the same configuration succeeded. No existing listener on port 8080 was found. Flutter SDK-cache writes and simulator service access likewise needed approved execution-tool sandbox retries. These were not missing-tool failures.

### Actual local Firestore enforcement

Before execution, reviewed `run.mjs`, `firebase.json`, and the test initializer: the project is fixed to **`demo-tonyo-privacy`**, Firestore binds **127.0.0.1:8080**, emulator UI is disabled, and the configuration points to the actual `app/firestore.rules`. `initializeTestEnvironment` also reads that same current rules file directly. The test refuses absent or non-loopback emulator hosts. The runner constructs an allowlisted environment without cloud credentials/project overrides and uses an isolated CLI configuration directory. That isolated CLI configuration has no stored authentication state. All authentication/guardian/operator contexts and documents are synthetic rules-testing fixtures; no live Firebase login or production project was used. The emulator shut down successfully after tests.

Exact successful command, executed from `app/tool/security_rules/`:

```sh
env PATH="/Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH" JAVA_HOME="$PWD/.runtime/java21/jdk-21.0.12.1+1-jre/Contents/Home" /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime.previous/dependencies/node/node_modules/pnpm/artifacts/exe/dist/pnpm.mjs test
```

This invokes the existing `test` script (`node run.mjs`), which invokes the existing local `emulators:exec` harness and serial Node test command. It downloaded Firestore emulator **1.22.0** to the ignored runtime cache. **28 passed, 0 failed, 0 skipped, 0 canceled, 0 TODO; exit 0.** These are separate executable Firestore tests, not Flutter repository mocks. The 24 existing enforcement cases passed unchanged, covering ownership, cross-account/query isolation, privacy and guardian checks, optional outcome-learning consent, metadata restrictions, export and deletion, batch revocation/deletion races, and synthetic operator boundaries.

Added four focused [emulator cases](../tool/security_rules/firestore.rules.test.mjs):

1. Exercise zero through transactional save, merged edit, a fresh authenticated client's server read and export; absent document remains absent; explicit manual-override deletion preserves the imported document.
2. Merge from an old personalized score to a current deterministic score writes explicit nulls for obsolete personalization fields, confirmed by a server reload.
3. Unavailable-score merge clears old Cognitive availability/value, baseline, previous value and delta fields.
4. Those Phase 1 zero/null payloads still obey privacy, guardian, ownership and dual outcome-consent gates, while revocation leaves owner export/deletion available.

Dart serializer tests establish app-to-wire conversion; emulator tests establish enforcement and server persistence of that wire format. A fresh SDK client/server read is not an app-process or physical-device restart.

### Confirmed regressions and fixes

| Reproduced problem | Fix and regression evidence |
| --- | --- |
| With only old observations, Today correctly withheld a score but did not display the latest retained observation's age. The new widget test failed because the dated notice was absent. | [Today](../lib/src/screens/today_screen.dart) now shows its local date/time and elapsed age with “not a current measurement,” while excluding future/model-only observations. [Two widget cases](../test/today_stale_observation_test.dart) cover stale and empty states. |
| Another device can commit an edit to a raw observation before replacing derived documents. If the ID/timestamp are unchanged, the old cloud curve passed the prior ID/version/freshness checks although Today recomputed the new score. The regression produced a first curve point of 57.4 instead of 70.1. | [Controller](../lib/src/app_controller.dart) now checks that the curve reproduces from retained inputs, the current schedule and compatible model at its original generation time. Changed values, evidence, bands or model correction invalidate it. [Cache regression](../test/phase1_cache_test.dart) fails before the fix; existing unchanged-cloud-reload coverage still passes. |
| On the isolated simulator, ordinary demo onboarding populated sleep fixtures tagged with a Health source enum. The new sleep card incorrectly described the fixture as an “Apple Health estimate” despite no Health authorization/import. Two new widget cases reproduced the defect. | [Shared provenance](../lib/src/evidence_provenance.dart) reuses the existing score marker rules unchanged. [Sleep logic](../lib/src/sleep_observation_logic.dart) tracks contributing synthetic evidence; the [card](../lib/src/widgets/sleep_observation_card.dart) labels demo/mixed summaries and disables personal coverage confirmation/range comparison for synthetic-containing displays. Six tests cover actual onboarding fixtures, mixed data, ID/group/note markers and ignored demo duplicates. No fixture, consent or score coefficients changed. |

No raw observations, consent receipts or training-attempt ledgers are deleted by these fixes. There is **no additional schema or model-version migration**: existing Phase 1 schema 15 / deterministic v3 / preparation v2 compatibility remains. Previously accepted stale derived curves can now regenerate from retained data. Replay uses existing deterministic/compatible inference only; it neither trains a model nor changes coefficients.

### Flutter verification and count accounting

All commands below ran from the verified `app/` directory with the existing installed SDK.

| Actual command | Result |
| --- | --- |
| `/Users/harrygao/Downloads/flutter/bin/flutter analyze --no-pub` | **No issues found**, exit 0. |
| `/Users/harrygao/Downloads/flutter/bin/flutter test` | **916 passed**, 0 failures or skips reported, exit 0, after all three fixes. Thirteen new Flutter tests beyond the earlier 903. The intermediate follow-up run passed 910 before the native-discovered provenance correction. |
| `/Users/harrygao/Downloads/flutter/bin/flutter test --no-pub test/phase1_cache_test.dart test/app_controller_test.dart test/phase1_restart_acceptance_test.dart test/today_stale_observation_test.dart` | **43 passed**, 0 failures; this focused execution overlaps the 916-test suite. |
| `TZ=America/Los_Angeles /Users/harrygao/Downloads/flutter/bin/flutter test --no-pub test/sleep_observation_logic_test.dart test/engine_local_day_test.dart test/local_calendar_test.dart test/daily_plan_logic_test.dart` | **32 passed** after the final fix, 0 failures or skips, exit 0. The earlier follow-up execution passed 28 before four provenance cases were added to `sleep_observation_logic_test.dart`. |
| `/Users/harrygao/Downloads/flutter/bin/flutter test --no-pub test/sleep_observation_card_test.dart test/sleep_observation_logic_test.dart test/score_explanation_test.dart test/fatigue_engine_test.dart` | **65 passed**, 0 failures; final copy-only widget rerun `flutter test --no-pub test/sleep_observation_card_test.dart` passed **3**. Both overlap the final suite. |
| Changed-files-only Dart formatting (exact arguments below) | **11 files, 0 changed** in the final formatting pass. |
| `git diff --check` from the repository | Passed. |

The previous 903-test completion and 28-test timezone run were also checked against their retained local logs. The “28 daylight-saving-time tests” wording means **28 tests across four sleep/calendar/scheduling files, including DST cases**, run explicitly under `TZ=America/Los_Angeles`; not 28 distinct additional tests or 28 tests all exclusively about DST. They were already included in 903, and remain included in 916. The same four-file timezone command now runs 32 tests because four sleep-provenance cases were added. Do not add the 43/65/3-test focused runs or timezone subset to the full-suite total. Firestore's 28 executable cases are a different suite.

Final formatting command (file list derived only from changed/tracked and new Dart files):

```sh
/Users/harrygao/Downloads/flutter/bin/cache/dart-sdk/bin/dart format \
  lib/src/app_controller.dart lib/src/evidence_provenance.dart \
  lib/src/fatigue_engine.dart lib/src/screens/today_screen.dart \
  lib/src/sleep_observation_logic.dart lib/src/widgets/sleep_observation_card.dart \
  test/phase1_cache_test.dart test/phase1_restart_acceptance_test.dart \
  test/sleep_observation_card_test.dart test/sleep_observation_logic_test.dart \
  test/today_stale_observation_test.dart
```

The first post-provenance `flutter analyze --no-pub` reported one `use_null_aware_elements` style issue and therefore the chained full test had not started. Applied the suggested null-aware list syntax, formatted that changed file, then reran analysis and all 916 tests successfully. No diagnostic was suppressed. Initial failing regression counts and intermediate focused executions are diagnostic evidence, not additional unique passing tests.

### Acceptance evidence and limits

| Acceptance condition | Available evidence |
| --- | --- |
| Empty/stale observations | Existing engine/forecast/availability tests; new Today date/age widget checks and stale-data controller recreation case. Old raw records remain retained; forecasts/reminders abstain. |
| Explicit zero and clearing an override | Existing activity edit/sync/export/restore tests, [new controller recreation tests](../test/phase1_restart_acceptance_test.dart), and actual emulator zero/clear/server-reload case. Zero retains manual priority; deletion permits imported fallback in controller tests. |
| Schedule edit persistence/protected sleep | New controller recreation case checks persisted overnight clocks, nonoverlapping blocks and reminder times within waking bounds; existing calendar/DST and Profile tests. |
| Incompatible model/cache | Existing model-service, residual-kernel, preparation and Phase 1 cache tests pass in the full suite. Incompatible fitted weights are rejected while valid attempt time/outcome-key ledger and raw records survive. No training was requested. |
| Deterministic save removes old personalization | Existing cloud serializer regressions plus actual emulator merged-document server reload. |
| Historical calculation basis/version | Existing Insights/score-explanation/transparency widget and logic tests pass; current deterministic recomputation remains explicitly disclosed. |
| Removed exposure rewards | Existing engine/forecast/kernel/preparation invariance and incompatibility tests pass. Stronger cache validation also rejects curves inconsistent with current inputs/model. |
| Disable/sign-out/loss of eligibility cancels reminders | Existing controller/privacy/notification suites plus new disable→controller recreation→resume and stale→recreation cases pass. Mock scheduler cancellation is not native delivery/cancellation proof. |

Native build, simulator/manual results, prerequisites, exact remaining steps and expected results are recorded separately in [PHASE1_DEVICE_ACCEPTANCE.md](PHASE1_DEVICE_ACCEPTANCE.md). No substantive existing Flutter app-integration harness was found (`integration_test` is absent; `font_integration_test.dart` is a widget test and native RunnerTests are empty templates), so **app integration tests are Not run**. Physical-device acceptance is **Not run**, despite connected devices: their normal installation and real Health data were not touched. Safe signed-in device/cloud flows are **Blocked** because the app has no emulator-routing configuration; do not substitute production.

### Native coverage

A new local-only iPhone 17 / iOS 26.5 simulator installation passed build, boot, install and launch with no Firebase defines. Normal adult data-use onboarding was completed through the UI; Health/Screen Time and Outcome learning stayed off. Actual terminate/relaunch checks retained explicit exercise `0` with other categories absent, and retained an edited 09:00/22:00 schedule. Only this disposable simulator's synthetic native preferences were read to confirm persistence. Coach showed four blocks summarized within that waking window; full native non-overlap remains Not run because scroll/drag automation failed. The initial build preceded the cloud-cache/provenance follow-up fixes. A final no-config rebuild then passed (Xcode 21.4 seconds), was installed into the same disposable container, and visibly showed “Demo sleep,” the synthetic-evidence warning, “Demo / synthetic example” and “Displayed sleep total.” Profile still showed 09:00/22:00 and Add still showed one saved log. Final native preferences again confirmed exercise zero, absent blank categories, saved 09:00/22:00 clocks, retained adult receipt and Health disabled. Only the new test simulator was shut down successfully at 14:58:06 PDT; its synthetic container was preserved. Exact commands and test-container checks are in the device checklist.

The normal onboarding action seeds demo records, so an empty native install was not manufactured by bypassing consent or editing storage. Empty/stale unit/widget checks are not promoted to native acceptance. No physical-device installation, normal-device Health import, actual notification delivery, cloud sign-in or app/emulator integration was performed.

### Changed files in this follow-up

- Application: `lib/src/app_controller.dart`, `lib/src/screens/today_screen.dart`, `lib/src/evidence_provenance.dart` (new), `lib/src/fatigue_engine.dart`, `lib/src/sleep_observation_logic.dart`, `lib/src/widgets/sleep_observation_card.dart`.
- Flutter regressions: `test/phase1_cache_test.dart`, `test/phase1_restart_acceptance_test.dart` (new), `test/today_stale_observation_test.dart` (new), `test/sleep_observation_card_test.dart`, `test/sleep_observation_logic_test.dart`.
- Real emulator suite: `tool/security_rules/firestore.rules.test.mjs`, `tool/security_rules/README.md`.
- Evidence and next steps: `docs/BIOLOGY_UPGRADE_PROGRESS.md`, `docs/DEVELOPMENT_LOG.md`, `docs/PHASE1_DEVICE_ACCEPTANCE.md` (new).

Dependency manifests/lockfiles, Firebase configuration, `firestore.rules`, real user data, and the normal installed app were not changed. The new test simulator and ignored portable/runtime caches remain isolated test artifacts; the simulator's data is retained for the documented remaining checks.
