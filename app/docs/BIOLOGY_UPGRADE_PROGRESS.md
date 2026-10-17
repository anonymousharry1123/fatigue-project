# Biology upgrade — Phase 1

Latest follow-up, October 17: **AI-3 synthetic comparison preparation adds B0/B1/M1 replay without private-data inputs or app model activation.** See [AI3_SYNTHETIC_PREPARATION.md](AI3_SYNTHETIC_PREPARATION.md) for its fixed synthetic manifest, boundaries and verification. Full real-data AI-3 and AI-4 remain pending.

AI-1/AI-2 completion, October 17: **Local study infrastructure and the readiness assessment/report are implemented; empirical modeling readiness is not established.** The user requested completion and reported no/uncertain prospective history. No real participant data were inspected. See [DATA_READINESS_REPORT.md](DATA_READINESS_REPORT.md) for scope, final verification and readiness gaps, and [AI1_DATA_DICTIONARY.md](AI1_DATA_DICTIONARY.md) for schemas and private export.

The [prediction contract `v0.3-draft`](PREDICTION_CONTRACT.md) retains the selected 10:00 timing, 18:00–22:00 English Evening Energy, own-data-first scope, manual default and selectable Apple Health. Future study plans explicitly fix one source/timezone; the device journal captures revisions and readable Health batches, freezes morning snapshots and retains unopened days in closed-opportunity coverage. No app model predictions, real-data training or empirical pilot completion are claimed. The separate AI-3 fixture runner fits synthetic coefficients only. Remaining contract and physical-device/release review stays open. Earlier measurement, bug-audit and automatic-Health-sync work is recorded below as dated history.

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

## Deferred Phase 1 work and acceptance

- Phase 2 constrained conversational Coach, Phase 3 future-outcome model/validation, Phase 4 replacement attention protocol, and Phase 5 participant experiments are not implemented.
- A new school timetable/fixed-commitment model, clinician approval, biological coefficient estimation, forecast calibration, immediate server token revocation and production guardian workflow remain outside this change.
- Physical-device review remains necessary for Health imports, schedule edits across travel/DST, notification delivery/cancellation and voice-over behavior; automated tests do not demonstrate those.
- **Remaining acceptance:** complete the device checks marked Not run or Blocked in [PHASE1_DEVICE_ACCEPTANCE.md](PHASE1_DEVICE_ACCEPTANCE.md), particularly physical notification delivery/cancellation, background/resume, cold restart and isolated signed-in cloud flows. The local Firestore harness has now passed. The separately authorized measurement and local AI-1 work is recorded below; deployment remains outside scope.

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

## Continued Phase 1 verification and language preference — 2026-10-04

**Phase 1 still has outstanding acceptance checks.** This section supersedes the older app/emulator tooling blocker above; it does not retroactively turn any prior Not run result into a pass. The separate language preference is expressly user-requested. No Phases 2–5 work, training, production access, deployment, rules weakening, commit, push or system-wide toolchain installation occurred. Passing software tests does not establish biological, clinical, or fatigue-prediction accuracy.

### Environment and safe scope

Reverified Git root `fatigue-project/`, Flutter root `fatigue-project/app/`, branch `main`, applicable instructions, current progress/biology plan, and existing security scripts/configuration. No applicable `AGENTS.md` was found; the development log requirement in `docs/PLAN.md` was followed. Git was clean at the start. A separate untracked `app/TONYO_BIOLOGY_AND_AI_ROADMAP_v2.md` appeared during this work and was left untouched.

Reused Node **24.19.0**, repository-pinned pnpm **11.19.0**, and the existing portable Temurin **21.0.12.1+1** JRE identified in the previous follow-up. They were installed but not all on PATH; neither a duplicate toolchain nor a persistent shell change was needed. Flutter uses the same installed SDK path as above. Loopback sockets, native simulator services and SDK cache access required approved execution-tool sandbox access, not sudo. `flutter pub get --offline` passed for the SDK localization/integration dependencies; the lockfile adds only their dependency closure and does not upgrade previously locked packages.

### Confirmed regressions and fixes

| Reproduced issue | Fix and regression evidence |
| --- | --- |
| Native Forecast linked demo sleep as `HealthKit`, even though no Health import occurred. | Forecast now resolves the existing shared demo markers from the linked signal/ID before assigning the display source. Actual HealthKit labels remain unchanged. Four added cases in `test/forecast_phase1_widget_test.dart` cover source provenance and Spanish/Simplified/Traditional Chinese availability/caveat presentation. |
| Daily History omitted explicit zero activity values because display required a positive value. The recent Activity card showed missing study/screen fields as zero. Both failed focused widget checks with valid `activity-*` synthetic fixtures. | Both displays now include a category only when its value is non-null. An explicit exercise zero is visible; absent categories remain absent. Two cases in `test/logging_localization_test.dart` reproduced and verify the distinctions. No scoring or storage interpretation changed. |
| The first native emulator scenario passed, but the separate process restart threw `FormatException`: nested score-driver `evidenceAt` values still contained Firestore SDK `Timestamp` objects. | The repository now recursively normalizes map/list timestamps before domain decoding, retaining the existing `Timestamp.toDate()` semantics and leaving zero/null values and original snapshots unchanged. `lib/src/firestore_value_codec.dart` and `test/firestore_value_codec_test.dart` cover both Energy/Cognitive evidence and nested metadata. Both final native scenarios passed after this fix, including retained-cache restart and nested evidence reload. |
| Delaying an older language save let it finish after a newer selection and become the restart value. | The language write queue retains request order and recovers after failure. A gated preference-store test failed with the older Spanish value instead of the newer Traditional Chinese value before the fix. |
| A delayed language snapshot could overwrite a newer raw observation; another gated test reloaded an empty signal list instead of the just-saved observation. | Shared `_writeLocal` operations now serialize their platform writes, check their captured session before writing, and capture current state when each write begins. This protects concurrent ordinary observation/background saves too. |
| A language write already in progress could finish after account deletion and recreate the deleted local state. | Reset invalidates the session and drains active shared-state writes before deleting the cache. The regression checks deletion stays pending until the platform write finishes, queued old choices fail, and a newly loaded controller has neither observations nor a consent receipt. |

The three preference/storage race cases are in `test/language_persistence_test.dart`; source changes are in `lib/src/app_controller.dart`. These are confirmed persistence failures, not speculative concerns. Failure/rollback, queued failure recovery, consent/guardian gates, unchanged score/forecast/preparation state, retained training ledger and unchanged notification scheduling are also checked. An independent read-only review found no queue cycle: local writes await only preference operations, and the language/cloud paths use the independent local queue.

### User-requested language preference

English remains the default. Spanish, Simplified Chinese and Traditional Chinese are available on the welcome/sign-up screen and in Profile Settings. The choice updates the interface immediately and is stored as `profile.preferredLanguage` through ordinary consented profile persistence. Before signup it is a presentation-only preview in memory; it cannot authorize collection. Native names stay visible in the picker. Names, notes, stored enum values, consent policy, model versions and destructive confirmation tokens retain their existing values.

The main interface has authored local catalogs and Flutter SDK localization delegates. Some technical details, generated explanations and native notification text remain English; both pickers disclose that limitation. No private data is sent to a translation service. Spanish activity input accepts decimal commas without converting a blank into zero. Full scope, fallback behavior, sign-out behavior and source links are in [LANGUAGE_PREFERENCES.md](LANGUAGE_PREFERENCES.md).

The additive profile field defaults missing/unsupported values to English and travels through existing local/cloud/backup/export serialization. No schema, score, preparation or consent-version bump, artifact deletion, safeguard reset or retraining is required. Nested timestamp normalization lets existing server documents reload without rewriting their stored schema. Ordinary launch keeps its existing Firebase configuration behavior. Emulator routing is a separate debug-only opt-in, rejected in release/profile and when any real Firebase compile-time option is supplied.

### Executed automated checks

Commands ran from verified `app/` unless stated otherwise. Flutter below is `/Users/harrygao/Downloads/flutter/bin/flutter`; Dart is `/Users/harrygao/Downloads/flutter/bin/cache/dart-sdk/bin/dart`.

| Actual command | Result |
| --- | --- |
| `flutter test` | **950 passed**, 0 failures/skips; exit 0 after all parser, queue, display and localization fixes. This is the final complete unit/widget suite. |
| `TZ=America/Los_Angeles flutter test --no-pub test/sleep_observation_logic_test.dart test/engine_local_day_test.dart test/local_calendar_test.dart test/daily_plan_logic_test.dart` | **32 passed**, 0 failures/skips; exit 0. Already included in the 950 total. |
| `flutter pub get --offline` | Passed; SDK localization/integration dependencies resolved from existing cache, without upgrading existing lock entries. |
| `flutter analyze --no-pub` | **No issues found**, exit 0, after all application and final native integration assertions. |
| `dart analyze` | No issues found after adding a missing `@override` in the Forecast test fixture. This is separate from the required Flutter analysis command recorded below. |
| `flutter test --no-pub test/account_language_widget_test.dart test/onboarding_sign_in_test.dart test/profile_sign_in_test.dart test/profile_sign_out_test.dart test/profile_schedule_test.dart test/privacy_center_screen_test.dart test/appearance_screen_test.dart` | **54 passed**, 0 failures/skips after correcting the sign-in test's scroll-settle helper. |
| `flutter test --no-pub test/account_language_widget_test.dart` | **4 passed** after adding a narrow-phone / 1.4× Spanish layout case. Overlaps the earlier focused run and the full suite. |
| `flutter test --no-pub test/language_preference_test.dart test/language_persistence_test.dart test/forecast_phase1_widget_test.dart` | **26 passed**, 0 failures/skips after all three confirmed persistence races were fixed. Earlier failed reproductions are not additional passing cases. |
| `flutter test --no-pub test/logging_localization_test.dart test/activity_zero_widget_test.dart test/firebase_options_test.dart test/firebase_emulator_options_test.dart` | **11 passed**, 0 failures/skips. Includes two preexisting zero-editor checks, five existing/new Firebase configuration guard checks, and four logging/localization cases. |
| `flutter test --no-pub test/firestore_value_codec_test.dart test/cloud_schema_test.dart` | **18 passed**, 0 failures/skips after the native-discovered nested-timestamp fix. |
| Changed-Dart-only `dart format --output=none --set-exit-if-changed` over Git's changed/new Dart paths | **45 files, 0 changed**, exit 0. All implementation formatting was restricted to changed Dart files. |
| `git diff --check` | Passed. Relative links in the four current verification/language guides also resolve. |
| Existing `pnpm test` from `app/tool/security_rules/` using the exact environment/runtime command in the previous section | **28 passed**, 0 failed, skipped, canceled or TODO; exit 0. Emulator shut down normally. |
| `pnpm test:app` from `app/tool/security_rules/` using the exact portable-runtime command in [the integration guide](PHASE1_EMULATOR_INTEGRATION.md#commands) | **2 native scenarios passed**, 0 failures/skips; overall exit 0 on a new iPhone 17 / iOS 26.5 Simulator. Separate from the Flutter unit/widget and Node rules suites. |

The real Firestore suite again used only `demo-tonyo-privacy` on loopback, an allowlisted credential-free child environment, synthetic rules-test authentication and the actual current `app/firestore.rules`. Its 28 cases include ownership/cross-account isolation, consent/guardian enforcement, dual outcome consent, zero/clear/server-reload persistence, deterministic null-field merge, and retained owner export/deletion. `firestore.rules` is unchanged. These are executable emulator cases, not memory repository mocks.

The first whole-suite execution reached 940 passes and six reported failures, then was interrupted because additional widget cases were waiting indefinitely. The new queues had retained eagerly created/idle futures across the widget framework’s fake-async and real-async zones. Queues now start lazily and clear their tail when idle; genuine in-flight writes remain serialized. Existing sign-in, conflict-resolution, foreground-sync and the new preference-reload workflows pass again. The run also exposed an English singular-nap label regression (fixed by selecting the singular template) and an Appearance navigation helper tapping under the bottom bar (fixed by settling and centering the row). No timeout or assertion was weakened.

`flutter test --no-pub test/language_preference_test.dart test/language_persistence_test.dart test/account_language_widget_test.dart test/profile_sign_in_test.dart test/theme_navigation_test.dart test/sync_conflict_resolution_test.dart test/profile_conflict_navigation_test.dart test/coach_sync_test.dart test/sleep_kind_screen_test.dart` then passed **81 tests**, 0 failures/skips. This is an overlapping focused run, not 81 extra unique tests. Flutter analysis was rerun after these fixes and remained clean.

The previous **28-test timezone subset was included in 903**, not additional to it. The same four files grew to **32 tests included in 916** after provenance cases and remain included in the current **950**; only some cases specifically exercise DST. Focused executions here likewise overlap the whole Flutter suite and must not be added to its total. Native integration scenarios and the Node rules suite are distinct suites.

### Native coverage and remaining acceptance

The isolated manual iOS 26.5 simulator demonstrated naturally stale prior-day records, unavailable current scores/Coach plans, historical deterministic-version disclosure, notification-off restart persistence, actual OS Coach reminder delivery, notification-tap routing to Coach, and signed-out restart persistence. Exact times, qualifications and the preserved synthetic installation are recorded in [PHASE1_DEVICE_ACCEPTANCE.md](PHASE1_DEVICE_ACCEPTANCE.md).

The earlier 13:15 canceled-notification interval remains **Inconclusive** because a separate simulator boot disturbed the background interval. A new clean interval on the current no-Firebase build **passed on the isolated simulator**: a first Coach reminder scheduled for 14:12 was disabled at about 14:07; Home remained visible through the cutoff, and at 14:14 the OS lock-screen notification list had no Tonyo/App reminder. Returning to Coach showed reminders still off and the old block marked “Time passed”; the disabled state also survived a real cold restart. Only the preserved test simulator was shut down, confirmed at 14:16 PDT. This establishes this Daily plan reminders cancellation case, not every cancellation path or physical-device behavior. Master-switch, sign-out and eligibility-loss non-delivery and all physical-device checks remain **Not run**. Native scroll automation is still **Blocked** by Device Hub's `noWindowsAvailable` error. Connected physical devices and the normal installation were never selected for installation or health access; exact restart/cleanup details are in the device record.

The new native Auth/Firestore harness passed **both scenarios** on a fresh iPhone 17 / iOS 26.5 Simulator, using ordinary explicit consent/account APIs, synthetic records, fixed loopback endpoints and current rules. The final pair preserves the app installation with `--no-uninstall`; the second process reads actual retained native preferences **before cloud hydration**, checking explicit zero, the cleared override, Spanish preference and bedtime/wake time. Persistent emulator Auth, current-version nested score evidence, cleared personalization fields and visible Spanish navigation also passed. Cross-account, consent/guardian and outcome restrictions and owner export/deletion were exercised through native Firebase clients. The synthetic owner account/data were deleted normally, both emulators stopped and only the newly created simulator was shut down.

An earlier two-scenario pass confirmed cloud recovery only: Flutter's default integration cleanup had uninstalled the app. It was not accepted as native-cache restart evidence. Commands, startup failures, the corrected harness and final execution details are in [PHASE1_EMULATOR_INTEGRATION.md](PHASE1_EMULATOR_INTEGRATION.md). The final two native scenarios are separate from 950 unit/widget tests and 28 Node security cases. They do not substitute for physical notification/Health/DST checks or validate the biology.

**Next acceptance work:** On an explicitly isolated physical test installation, follow the device checklist for real notification delivery and non-delivery after disable/sign-out/eligibility loss, background/resume and cold restart. Check complete protected-sleep timelines, zero/clear behavior, migration fixtures and travel/DST using synthetic data and supported test pathways. Do not use a normal installation, real Health records, production accounts or manufactured guardian approval. Keep unavailable checks Not run/Blocked; do not start later phases or deploy.

### Changed-file guide

- Language model/controller/root: `lib/src/language_preference.dart`, `models.dart`, `app_controller.dart`, `app.dart`; new `lib/src/l10n/` catalogs and `widgets/language_picker.dart` / `widgets/translated_text.dart`.
- Presentation: onboarding, Profile, appearance, privacy, sign-in, Today, Forecast/Insights, Coach, Add/activity/sleep/check-in/reaction/history screens; shared score/section/sleep/personal-baseline widgets. Only the confirmed provenance/zero fixes alter non-language display behavior.
- Local native integration: `lib/src/firebase_emulator_options.dart`, `firebase_options.dart`, `firebase_services.dart`, `firestore_value_codec.dart`, `firebase.integration.json`, `integration_test/phase1_cloud_test.dart`, the two `tool/security_rules/*app_integration*.mjs` scripts, package script and security README. Existing rules and production launch scripts are unchanged.
- Dependencies/tests: `pubspec.yaml`, `pubspec.lock`; six new language/routing/Firestore-codec test files, expanded Forecast tests and the sign-in/Appearance scroll helpers. Test fixture changes retain normal privacy gates.
- Evidence: this progress record, development log, device checklist, new integration guide and language guide.

## Roadmap v2 — Phase 2A measurement foundation, 2026-10-04

The user subsequently requested implementation of the next step in `TONYO_BIOLOGY_AND_AI_ROADMAP_v2.md`. This authorizes a separate measurement slice: Section 16 steps 1–3, plus independent raw-response display. It does not authorize the roadmap's future AI stages or settle its blank research decisions. Existing uncommitted Phase 1/language changes and the user-authored roadmap were preserved. No production access, deployment, training, commit, push, dependency upgrade, persistent shell change or system installation occurred.

**Implemented:** Six initially unanswered integer ratings, explicit Morning/Evening choice, partial saves and clearing; exact supplied draft wording with a nonclinical disclosure; stored observation/save time, captured local date/zone/offset, version/language and displayed definition; separate Today/history presentation; local/cloud/backup compatibility. New-format responses are excluded from legacy scores, forecasts, Coach evidence, preparation and outcome labels. Legacy original 1–5 values remain intact and read-only; ordinary three-item responses retain their old form. The field dictionary, source links, limits and manual checklist are in [PHASE2A_MEASUREMENT.md](PHASE2A_MEASUREMENT.md).

### Confirmed issues and corrections

| Finding | Correction and evidence |
| --- | --- |
| New metadata with a missing/null version could be decoded as legacy, and noncanonical outcome IDs linked to a draft response could survive restore. | All new-field presence requires versioned validation; outcome reconciliation removes every linked draft-response outcome, including pending/noncanonical IDs. Schema and restore regressions pass. |
| History regrouped a new response by the current host timezone. | New reports use their captured local date; a date-boundary travel regression passes. |
| Valid rich questionnaire writes exceeded Firestore's 1,000-expression budget in initial real-emulator runs. | Equivalent exact-key/type/length checks and duplicate-preserving answer counting reduce evaluation work. Snapshot checks still apply to edits; malformed payloads remain denied. The final 35-case suite includes full guardian-authorized create/update, duplicate ratings and Unicode/multiline wording. |
| The first native measurement run failed on create → edit/clear with a false “another device changed” conflict. | Installed native Firebase encodes bare `DateTime` at millisecond precision while the sync journal retains microseconds. Explicit SDK timestamps now preserve precision for journaled inputs/profile changes and linked legacy outcomes. Exact conflict detection is retained. Three new codec regressions cover precise timestamps, real conflicting values, nested/sentinel preservation and source/outcome agreement. |
| Initial full software run had two fixture failures: schema 15 was expected after the intentional schema-16 change, and the new Today card moved a lazily built control off screen. | The schema expectation was updated and the widget helper scrolls the actual Today list before tapping. Assertions remain intact. Initial focused tests also exposed an equivalent UTC/local fixture comparison and a typed-map fixture issue; both were corrected. |

### Executed checks

Commands below run from verified `fatigue-project/app/` unless otherwise stated. `flutter` and `dart` refer to `/Users/harrygao/Downloads/flutter/bin/flutter` and `/Users/harrygao/Downloads/flutter/bin/cache/dart-sdk/bin/dart`.

| Command | Observed result |
| --- | --- |
| `flutter test` before the native precision correction | **994 passed**, zero failures/skips, exit 0. Earlier initial full run had 991 passes and two failures; it is not the final result. |
| `flutter analyze --no-pub` before the native precision correction | No issues, exit 0, after fixing one brace lint. Final post-correction verification follows below. |
| `TZ=America/Los_Angeles flutter test --no-pub test/sleep_observation_logic_test.dart test/engine_local_day_test.dart test/local_calendar_test.dart test/daily_plan_logic_test.dart test/self_report_persistence_test.dart test/research_check_in_schema_test.dart` | **55 passed**, zero failures/skips, exit 0; all overlap the full suite. |
| `flutter test --no-pub test/self_report_persistence_test.dart test/research_check_in_schema_test.dart test/model_transparency_screen_test.dart test/privacy_data_repository_test.dart test/phase2a_consumer_separation_test.dart` | **71 passed**, zero failures/skips, exit 0 before native verification; overlapping focused run. |
| `flutter test --no-pub test/firestore_value_codec_test.dart test/input_sync_test.dart test/self_report_persistence_test.dart test/research_check_in_schema_test.dart` | **36 passed**, zero failures/skips, exit 0 after the timestamp correction. Two intermediate new test-fixture errors (SDK value comparison and misplaced declaration) were corrected before this pass. |
| Existing `pnpm test`, from `tool/security_rules/` | **35 passed**, zero failures/skips/cancellations/TODOs, exit 0; seven new measurement cases beyond the previous 28. Actual current rules loaded into the fixed demo-project loopback emulator. |
| Existing `pnpm test:app` | Final post-fix run: **2 native scenarios passed**, zero failures/skips, exit 0. The initial false-conflict failure is not counted as passed. |

The exact existing-runtime commands used from `app/tool/security_rules/` were:

```sh
env PATH="/Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH" JAVA_HOME="$PWD/.runtime/java21/jdk-21.0.12.1+1-jre/Contents/Home" /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime.previous/dependencies/node/node_modules/pnpm/artifacts/exe/dist/pnpm.mjs test
env PATH="/Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH" JAVA_HOME="$PWD/.runtime/java21/jdk-21.0.12.1+1-jre/Contents/Home" FLUTTER_BIN=/Users/harrygao/Downloads/flutter/bin/flutter /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node /Users/harrygao/.cache/codex-runtimes/codex-primary-runtime.previous/dependencies/node/node_modules/pnpm/artifacts/exe/dist/pnpm.mjs test:app
```

Logs were redirected to local temporary files without printing credentials or participant data. Reused Node 24.19.0, pinned pnpm 11.19.0, existing portable Java 21 and locked emulator dependencies. No toolchain installation was required. Both scripts strip cloud credentials and require `demo-tonyo-privacy`/loopback; the app harness creates a fresh simulator and retains its app container between two separate processes. Consent comes from ordinary synthetic adult onboarding, with optional outcome learning and Health import off. Actual security tests are separate from memory-repository unit tests and native integration.

The former **28 timezone cases were included in 903**, not added to it. That overlapping four-file subset later grew to 32. The current six-file run has 55 including 23 measurement persistence/schema cases; neither 55 nor any other focused total should be added to the whole-suite count.

**Final native result:** A fresh iPhone 17 / iOS 26.5 Simulator passed the complete/partial/clear save and independent restart scenarios. The second process checked retained native preferences before cloud hydration; native Auth/server reload also retained raw answers and definition metadata. Builds took 28.5s/24.5s. Synthetic owner deletion, the new simulator shutdown and emulator shutdown all completed. Normal installations were untouched. These saves use normal controller APIs; the full six-control native UI walkthrough and physical-device acceptance remain Not run. Details and the current rules hash are in [the integration record](PHASE1_EMULATOR_INTEGRATION.md).

**Final post-correction software result:** From the verified app root, `flutter analyze --no-pub` returned **No issues found** (exit 0), then `flutter test` passed **997 tests**, zero failures/skips (exit 0). This supersedes the earlier 994 total and includes **47 added measurement/codec regressions** beyond the preceding 950-test suite. The 36- and 55-case focused runs overlap this total. Changed/new-Dart-only `dart format --output=none --set-exit-if-changed` checked **63 files, zero changes**; `git diff --check` and relative documentation link checks passed. Final evidence logs are `/private/tmp/tonyo-phase2a-analysis-final.log`, `/private/tmp/tonyo-phase2a-full-post-native.log`, `/private/tmp/tonyo-phase2a-security-pass.log` and `/private/tmp/tonyo-phase2a-native-integration-final.log`. These local temporary logs may be removed by OS cleanup; the commands and results above are the durable record.

### Compatibility, outstanding acceptance and next steps

- Cloud schema is **16**; local migration stays **1**. No bulk migration, raw-data deletion or reinterpretation of old answers occurred. New metadata cannot silently relabel old entries. Old client behavior against schema 16 and the proposed local rules needs release review; no rules were deployed.
- Timestamp encoding prevents future precision loss. Existing millisecond documents remain readable. A pre-fix pending journal expecting a different precise timestamp may still require normal explicit sync review; no proximity-based conflict bypass or silent overwrite was added.
- Phase 2A steps 4–7 remain: personal references with counts, independent trends, research-specific export, approved-instrument framework. Optional unusual-day/illness/travel markers are not in this slice. No research minimum/window, required-item protocol, instrument, matching rule or AI threshold was chosen. Existing raw backup/export includes new fields; this is not the proposed analysis dataset export.
- Physical-device measurement, screen-reader, OS timezone/travel and expanded native screen walkthrough checks are **Not run**. Follow the isolated synthetic workflow in [the measurement guide](PHASE2A_MEASUREMENT.md). Existing notification/background/eligibility-loss and protected-sleep acceptance gaps remain in [the Phase 1 device checklist](PHASE1_DEVICE_ACCEPTANCE.md); earlier passes are not promoted to broader coverage.
- **Phase 1 is still not fully verified**, and this measurement foundation is not all of Phase 2A. Passing software tests does not establish biological, clinical, psychometric or fatigue-prediction accuracy.

### Changed-file guide for this measurement slice

- Definition/data/persistence: new `lib/src/check_in_measurement.dart`; `models.dart`, `cloud_schema.dart`, `app_controller.dart`, `backup_restore.dart`, `sync_conflict_resolution.dart`; native precision changes in `firestore_value_codec.dart` / `firebase_services.dart`.
- Display/localization: check-in, Today, Add/history and nullable admin views; new `widgets/self_report_card.dart`, `l10n/measurement_translations.dart`, existing localization catalog registration, and captured-date `daily_history_logic.dart`.
- Consumer separation: `fatigue_engine.dart`, `ml_prep_builder.dart`; no formula or fitted/preparation version change.
- Policy/tests: `firestore.rules`, existing Node suite and README; four new measurement test files, expanded codec tests, existing UI/schema helpers and `integration_test/phase1_cloud_test.dart`.
- Documentation: this record, development log, plan, measurement guide, integration guide and language guide. Earlier Phase 1/language edits remain present and uncommitted; not every Git change belongs to this slice.

## Phase 2A Step 4: personal self-report references — 2026-10-10

The user requested “complete the next step”. Following the completed measurement steps 1–3, implemented roadmap v2 Section 16 Step 4. In **Today → Today's self-report → Recent personal averages**, each morning/evening report now exposes separate Energy, Fatigue, Sleepiness, Focus, Mood and Stress references. Each average shows its answered-day count; the current raw answer is unchanged. Missing answers have no comparison, and insufficient history has no average.

### Display policy and compatibility

Use at least seven distinct answered days within the preceding 28 captured local dates, independently for each measure and period. The panel discloses this window, dates, minimum and selection policy. These are product display defaults only, not reviewed research settings, clinical thresholds or model eligibility gates. Personal averages do not describe a healthy or normal range.

Only valid genuine current draft-format responses with matching version, language and exact stored questionnaire definitions contribute. Map ordering does not affect compatibility. Legacy/synthetic/unknown formats, current-day and later observations, and records not yet available at viewing time are excluded. Duplicate revisions resolve before filtering; each date contributes its latest matching submission before per-item missingness. Clearing an answer does not resurrect an older submission. Calendar arithmetic preserves captured dates through travel/DST.

References are derived in memory from existing owner-scoped check-ins, with no extra query, new saved derived field, schema/rules change, migration or training. Edits, clearing, deletion and reload update the display naturally. These current descriptive averages are not historical prediction snapshots or inputs to existing estimates. No source measurements, consent flags, model artifacts, deployment settings or research-decision blanks were modified. The user-authored roadmap remains unchanged.

All four supported interface languages have reference copy. Expanded cards fit 320-pixel displays at 2× text in widget tests. Review identified a rounding mismatch where a mean of 6.0476 displayed as 6.0 beside a current 6 yet said “Lower”; averages now show up to two decimals, with regression cases in both directions. Today also excludes future recording times and resolves same-time displayed submissions deterministically.

### Verification performed

Commands ran in `app/` using `/Users/harrygao/Downloads/flutter/bin/flutter` and the cached Dart SDK executable. The first full-suite invocation stopped before tests because the installed SDK cache was outside the writable sandbox; the approved SDK-cache escalation allowed the full run. No dependency change or installation was needed.

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub` | No issues found, exit 0 after final code changes. |
| `flutter test --no-pub --reporter expanded` | **1,025 passed**, exit 0. Includes all 28 new tests: 17 logic and 11 widget/persistence cases. |
| Initial focused widget, measurement persistence and consumer-separation run | **40 passed**, before the two additional rounding regressions. Overlaps the full suite; not an additional unique total. |
| Agent's focused `self_report_reference_logic_test.dart` run | **17 passed**, also included in the full suite. |
| Changed-Dart-only `dart format --output=none --set-exit-if-changed` | Seven files checked, zero changed. |
| `git diff --check` | Passed. |

New checks cover per-measure availability, six-to-seven-day gating, repeat submissions, exact window bounds, versions/languages/wording, map order, raw preservation, invalid/synthetic/legacy exclusions, future save times, travel/DST, local persistence and recomputation after clearing/deletion, consumer separation, rounding and all four languages at enlarged text. Existing whole-app accessibility and regression checks also passed.

This is software verification, not psychometric or clinical validation. No new native simulator/physical-device, VoiceOver/TalkBack or cloud-emulator run was performed for this read-only derived display. Existing release/physical-device gaps remain open. Phase 2A **Steps 5–7 remain**: independent trends, research export and the approved-instrument framework. No commit, push or deployment was performed.

## Phase 2A Steps 5–7: trends, research export and questionnaire framework — 2026-10-10

The user requested continued step-by-step work following the plan with high quality. Preserved the prior uncommitted Step 4 changes and implemented the remaining authorized measurement scope. The user-authored roadmap/research blanks, model versions and future AI stages remain unchanged. The detailed behavior, data dictionaries and boundaries are in [PHASE2A_MEASUREMENT.md](PHASE2A_MEASUREMENT.md).

### Implemented outcome

| Step | App location and behavior |
| --- | --- |
| 5 — Independent trends | **Forecast → Insights → Self-report trends** selects six raw measures independently by period and questionnaire language. Shows 28 captured dates, exact-definition filtering, missing gaps, counts and fixed 1–10 axes. Sparse/unvarying data uses exact records. Descriptive sleep pairs preserve sources/availability, exclude naps/demo/invalid/future evidence and withhold ambiguous matches; actual saved bedtimes are required when disambiguating sessions. No correlation coefficient, causal conclusion, prediction or composite score is manufactured. |
| 6 — Research export | **Profile → Research export** prepares an explicit device snapshot after a user-entered study code. Saves a versioned JSON analysis bundle through the existing system picker or copies its response CSV/JSON after confirmation. Raw partial answers, timestamps, definitions, sources, missingness, exclusion counts and separate raw/pair availability are retained. Names, account IDs, emails, notes and original record IDs are excluded. Account/session checks protect pending actions. No export is triggered by opening the screen. |
| 7 — Questionnaire framework | **Profile → Questionnaire library** exposes the actual empty catalog and review requirements. Separate immutable definition/response codecs, a trusted registry, distinct review/permission/population/time gates and optional reviewed external score metadata prepare for a future instrument. No published questions, scoring formula, reviewer identity, approval, collection UI or persistent questionnaire collection were added. |

All new screens support English, Spanish, Simplified Chinese and Traditional Chinese. Current draft wording and saved definitions are unchanged. Step 5's visual-density threshold and retrospective 24-hour pairing are product display choices, not approved research matching or statistical adequacy. The research export explicitly states that it is a retrospective saved-device table, not the future prediction-event dataset. Derived views and exports do not alter raw observations, scores, Coach, outcomes, model fitting, consent or sync acknowledgements.

### Review findings and fixes

- A shared sleep record can participate in matches whose selection depends on different availability evidence. Keying the sleep table only by record ID originally reused the first match's availability for later reports. The sleep table now contains raw-record availability; each response separately records pair availability. A regression covers a known-time morning pair and unknown-dependency later pair pointing to the same raw sleep.
- A duplicate record lacking `recordedAt` could tie a valid record whose save time equaled observation time. Omitting the actual nullable save time from the conflict key made output depend on iteration order. The key now retains it, and contradictory equal-time copies are excluded consistently in both orders.
- Chart QA first rendered Flutter's Ahem test glyphs, which could not establish readable typography. Capture-only QA now loads the bundled font and a local macOS CJK fallback. Readable full-card and 320px/2× chart captures were inspected. Axis tick positions and compact endpoint labels were adjusted for enlarged fonts; full ISO date bounds remain visible above the chart.
- Initial widget development exposed a semantics-handle cleanup failure and test-only fake-async/ambiguous-scroll issues. Those helpers were corrected without weakening assertions. The first complete run passed 1,104 tests and failed one existing Insights test that assumed the weekly overview was above the new raw-trends section. It now scrolls to that section, retains the original assertions, and additionally checks the new trends card exists. Its focused rerun passed before the final full run.

### Final verification

Commands used the existing installed SDK in `app/`; SDK-cache writes required approved execution-tool escalation. No dependency/native bridge/schema/rules or lockfile changes were needed.

| Executed check | Result |
| --- | --- |
| `flutter analyze --no-pub` | No issues found, exit 0. |
| Cached SDK `dart analyze` after the final navigation-test adjustment | No issues found, exit 0. |
| `flutter test --no-pub --dart-define=CAPTURE_TRENDS_QA=true '--dart-define=TRENDS_CJK_FONT=/System/Library/Fonts/STHeiti Light.ttc' --reporter expanded` | **1,105 passed**, zero failures/skips, exit 0. This is 1,025 from the Step 4 handoff plus 80 new checks. |
| Focused suites during implementation | Trend logic 24; trend widget/translation/visual QA 15; export data/UI 16; export availability regressions 3; questionnaire framework/library 20; Profile route checks 2. All pass and overlap the final whole-suite total. |
| Changed/new Dart format verification | **26 files, zero changed**, exit 0. Includes preserved Step 4 files. |
| `git diff --check` and changed-document relative-link checks | Passed. |

The full suite includes existing measurement persistence, consumer/model separation, privacy, source/scoring, backup/recovery, localization and whole-screen accessibility regressions. Synthetic visual QA files were written only to temporary storage: `/private/tmp/self-report-trends-full-390.png`, `/private/tmp/self-report-trends-rating-320-large.png` and `/private/tmp/self-report-trends-sleep-320-large.png`. The CJK font is a local test-render fallback, not a redistributed dependency. Normal tests may omit the capture defines; the screenshot-only case is then explicitly skipped.

Native simulator, physical-device, VoiceOver/TalkBack, cloud-emulator and real file-picker runs were **not** added in this follow-up. Existing physical/release acceptance remains open, and new native flows should be checked in an isolated test installation before release. Software correctness and readable synthetic charts do not establish clinical, psychometric or prospective prediction validity. No live account/data access, new cloud collection, training, deployment, commit or push occurred.

**Next boundary:** measurement/prediction-contract and instrument review, alongside remaining device/release acceptance. The roadmap's AI stages remain planning-only; the empty approved-instrument catalog cannot be activated by serialized response metadata or this implementation record.

## Phase 2A native acceptance (2026-10-10)

Prompt: “continue with next step”. Extended the existing isolated Auth/Firestore simulator harness to cover the completed measurement tools, preserving the uncommitted application changes. This follow-up changes test helpers, driver logging and documentation only.

The final full pair passed **2 native scenarios, zero failures/skips, exit 0** on a newly created **iPhone 17 / iOS 26.5 Simulator**. The first uses the real Spanish form to save/edit/clear a partial response, checks original English wording and canceled edits, and creates eight historical report/sleep pairs through normal APIs. The independent second process compares exact raw records in native preferences before hydration, fresh server reads and the reconstructed controller. It also checks personal references, trend charts/filters/missing records, confirmed/canceled native JSON/CSV clipboard exports and the empty questionnaire library. Read-only views do not alter raw inputs. Existing Phase 1 privacy/ownership/zero/schedule checks remain passing.

Xcode builds were **39.4s/31.1s**; scenarios completed in approximately **36s/21s**. Final `flutter analyze --no-pub` was clean, integration formatting checked **3 files with zero changes**, and the Node driver passed syntax checking. Earlier failures were test timing/localized-navigation/scrolling/visibility assumptions, corrected without changing production behavior. The existing **1,105-test** unit/widget result and **35-case** Node rules result remain the prior verified baseline; they were not rerun or combined with this native count.

Normal owner deletion of the disposable account/data and emulator/simulator shutdown completed. The Firebase rules hash is unchanged. No normal installation, production account, real Health data, model training, approved questionnaire, dependency upgrade, deployment, commit or push was involved.

The [native integration guide](PHASE1_EMULATOR_INTEGRATION.md#phase-2a-measurement-acceptance--2026-10-10) records exact scope, command and limits; the [measurement guide](PHASE2A_MEASUREMENT.md) distinguishes accepted simulator flows from remaining manual checks. Native file-picker saving, physical-device and screen-reader acceptance, OS travel/timezone behavior and the unresolved measurement/prediction contract remain open. Future AI implementation still requires the roadmap's research decisions.

## Pre-ML bug audit (2026-10-11)

Prompt: “Check for bugs and fixes,to be ready to start on the ML model”. Fixed concrete bugs in the existing measurement and optional model infrastructure:

- Preparation rejects conflicting duplicate records and observations/revisions unavailable at the snapshot cutoff. Live learned inputs also abstain on conflicting copies. Collection-scoped provenance distinguishes equal IDs in `signals` and `checkIns`, including exclusion of the label's own source.
- Model reloads recover correctly after cancellation. Corrupt storage and discard paths retain a conservative training cooldown. New weights activate only after persistence succeeds; a failed save preserves the prior accepted model.
- Delayed source saves retain their original optional-consent receipt and cannot overwrite newer linked outcomes or recreate outcomes after source deletion. Reaction validation uses the exact finite value; its baseline uses the latest 14 valid records.
- Retrospective sleep preferences retain the availability of both competing summaries and all considered stage evidence. Late evidence that changes a preference cannot backdate the resulting research-export pair; unknown dependency availability remains unknown.

Regression tests reproduce the source/consent races, persistence failures, identity collisions, future evidence and late-stage preference change. Raw storage, schema, model form, rules and dependencies are unchanged. Cached preparation reports rebuild from raw snapshots, so no cache migration is required.

**Final verification:** `flutter analyze --no-pub` is clean. The complete `flutter test --no-pub --reporter expanded` run passed **1,125 tests**, zero failures, with the one opt-in trends screenshot-capture test skipped. The executable Firestore rules suite separately passed **35 cases**, zero failures/skips. The unchanged isolated native harness passed **2 scenarios**, zero failures/skips, overall exit 0, on a newly created iPhone 17 / iOS 26.5 Simulator. Entry/editing, native preferences before hydration, fresh server reads, an independent process restart, references/trends, research clipboard exports and the empty questionnaire library all passed. Xcode builds took **79.9s/62.8s**; scenarios ran for **38s/21s**. Disposable account deletion and simulator/emulator shutdown completed normally. These are separate suites; focused regression counts are not added to them. Changed-Dart formatting checked **15 files with zero changes** and `git diff --check` passed.

The existing installed runtimes and dependencies were reused. Local logs: `/private/tmp/tonyo-readiness-analyze.log`, `/private/tmp/tonyo-readiness-full.log`, `/private/tmp/tonyo-readiness-rules.log`, and `/private/tmp/tonyo-readiness-native.log`. No production account/data access, deployment, commit or push occurred.

**Next ML step:** complete AI-0 in [roadmap v2](../TONYO_BIOLOGY_AND_AI_ROADMAP_v2.md#20-ai-0-agree-on-the-measurement-and-prediction-contract): target/wording, prediction cutoff, outcome window, late-response handling and repeat-submission selection. Then build the AI-1 prediction-event dataset and prespecify the evaluation split. The current export is retrospective; new draft responses intentionally remain excluded from the legacy residual model. Passing these software checks does not establish real-data readiness or predictive accuracy. Physical-device/research/release checks remain open.

## AI-0 prediction contract draft (2026-10-11)

Prompt: “start the next step,i believe it is AI 0?” Started the roadmap's AI-0 documentation step and created [PREDICTION_CONTRACT.md](PREDICTION_CONTRACT.md). Its concrete proposal uses morning-available main sleep to predict the first qualifying evening raw Energy report, with a fixed 10:00 cutoff, issuance before 10:15 and an 18:00–22:00 outcome window. At draft creation, the times and policies were proposals and the timing/population questions were pending; the subsequent choices are recorded below.

The draft captures the actual Energy label, blank standalone prompt, anchors, recall period, language/version and optional-answer behavior. It defines missingness before value-based selection, late/local-save versus late-upload handling, revision/withdrawal rules, same-date sleep eligibility, frozen timezone/cutoff evidence, per-device availability, and separate opportunity/issuance/response counts. Worked synthetic examples make the proposed boundaries reviewable.

Independent read-only reviews checked current implementation facts and internal consistency. They identified additional AI-1 needs: initial durable-save/revision evidence, full prompt context, stable prediction-event identity, a prespecified opportunity calendar, dataset as-of versions and sleep ingestion/reconciliation lineage. Existing mutable records and retrospective exports cannot supply these guarantees by relabeling old rows. The approved questionnaire catalog remains empty; reviewer decisions and any applicable research/data-use authorization are unrecorded.

Only documentation changed in this step. Prior uncommitted bug fixes are preserved. App tests were not rerun for this documentation-only change; the prior audit's **1,125 Flutter passes, one opt-in screenshot skip, 35 rules passes and two native passes** remain that earlier verification, not new AI-0 results. AI-0 is **draft prepared, acceptance pending**; AI-1 implementation, new training, participant collection and deployment have not started.

**User decisions, October 11:** The user selected “Fixed times: predict at 10 am; evening rating 6–10 pm (Recommended)” and “My own data first (Recommended)”. Contract `v0.2-draft` records these as `AI0-D001` and `AI0-D002`. The 15-minute issuance tolerance, exact endpoint/timezone rules, measurement/language and source/matching policies remain proposals. These two preferences do not authorize collection/training or establish reviewer approval. The next contract review concerns those remaining choices, not re-confirmation of the selected times or population.

## AI-1 local synthetic foundation (2026-10-11)

The user selected English and both sleep-source options, then explicitly changed the default to **manual**, with Apple Health selectable, and requested continuation to the next step. Contract `v0.3-draft` records source choice as `AI0-D003` and language as `AI0-D004`. The proposed source policy fixes one source per versioned experiment before cutoff, without automatic fallback or merging; competing main episodes within that source remain ambiguous. A source change requires a new protocol ID/versioned experiment.

AI-1 has started with offline, synthetic-only Dart [protocol/calendar rules](../lib/src/ai1_protocol.dart), [immutable records](../lib/src/ai1_records.dart) and [dataset validation](../lib/src/ai1_dataset_builder.dart), plus [synthetic acceptance fixtures](../test/ai1_dataset_builder_test.dart). The slice addresses cutoff availability, immutable snapshots, source isolation and explicit outcome missingness. App wiring, durable storage, real-data adapters and training are outside this slice; the prospective real-data dataset remains unbuilt.

Remaining AI-0 operational rules and construct meaning are still draft decisions. That review does not block the authorized reversible synthetic software work. Existing uncommitted work is preserved.

**Validation:** 38 focused AI-1 tests passed; full `dart analyze lib test tool` reported no issues. Both manual/default and Apple Health variants of the [runnable synthetic audit](../tool/ai1_synthetic_audit.dart) passed JSON/coverage checks: four opportunities, two simulated issuances, two valid outcomes, one fixture pair and zero training-eligible rows. Independent review found and fixed a deletion edge case that could otherwise promote another sleep record after a tombstone changed the original record's date or kind. Tests cover late imports/edits, deletion/withdrawal, first-response missingness, full wording snapshots, retries/conflicts, durability, source isolation and DST/invalid calendar boundaries. These are new checks for the first AI-1 slice; the earlier full app/rules/native results remain separate. No app wiring or training was activated.


## AI-1 optional local revision history (2026-10-11)

The user authorized the next implementation step. Added **Privacy center → Keep local study history**, off by default, for future manual sleep and versioned self-report saves. It records immutable revisions with the complete questionnaire snapshot, actual shared heading and native completion receipts. Notes are excluded. An initial edit of an uncaptured record remains incomplete provenance; existing rows, Health imports, cloud hydration and ordinary backups never become original prospective submissions.

The iOS journal uses a protected, backup-excluded application-support directory, owner-specific files, bounded JSON, serialized atomic replacement and flushes. A payload write precedes its native timestamp, rounded conservatively upward to millisecond resolution; a second write saves the receipt. Interrupted writes and clock rollback pause capture. Source deletion purges every payload revision and retains only its opaque identity. History disablement and tracking clear erase the active journal; account/device deletion clears device journals. Sign-out and owner changes invalidate pending work. Non-iOS surfaces report unavailable without blocking ordinary saves or deletion. Current cloud sync, backups and exports exclude the journal.

This is local app infrastructure, not a running prediction experiment. Every journal is marked `trainingEligible: false`; the check-in disclosure remains unchanged. Health ingestion lineage, prediction opportunities/events, real-data adapters, reviewed export and training remain open. No real participant data was read or exported during implementation, and no history setting was enabled on the user's device.

**Validation:** The final full Flutter run passed **1,249 tests**, zero failures, with one optional screenshot test skipped; all 67 new capture tests are included. Full Dart analysis is clean, the final iOS Simulator build passed, and temporary synthetic Swift checks passed storage, deletion retry and timestamp-boundary cases. Formatting, local documentation links and diff whitespace checks passed. See the [development record](DEVELOPMENT_LOG.md#october-11-2026--ai-1-optional-local-revision-capture) for logs, initial-run fixes and physical-device limitations. The earlier rules/cloud-native runs were not repeated or counted as new results.


## AI-1 infrastructure and AI-2 readiness assessment (2026-10-17)

Implemented the user's request to complete AI-1 and AI-2, with a precise report and no private record access. **Study tools** is now available under enabled local study history. Starting a future calendar, assessing aggregate readiness and saving a private export are separate explicit actions. Plans fix source/timezone and a 1–366-day calendar; the default 28 is an editable scheduling convenience, not a study-size threshold.

The adapter uses native durable receipts and immutable event payloads to freeze the 10:00 information set. Foreground minute checks/resume refresh the timezone; late execution is never backdated. All closed planned dates, including unopened dates, enter coverage. Manual revisions and pre-reconciliation readable Health batches feed source-isolated episode checks. Selected responses preserve original submission/definition/timing lineage; missing, revised, ambiguous or deleted evidence remains unavailable.

Deletion removes event payloads and conservatively invalidates relevant whole-plan lineage until clear/restart. Health comparisons use recent sample starts to avoid rolling query-boundary expiry being mistaken for deletion; they do not prove complete Health permission or detect every older external change. Observed timezone departure stops further snapshots. Source/account/generation checks and queued erasure protect against pending work recreating cleared evidence.

The private export uses export-scoped pseudonyms and includes raw measurements, feature-event rows, Health query lineage, calendar/deletion/timezone provenance and readiness JSON. It excludes notes/account IDs and remains outside ordinary backups/cloud sync. The file picker may offer cloud destinations; the user chooses an on-device folder to keep the copy local. There is no clipboard fallback, and saved/shared copies are not recalled by local deletion.

AI-2 reports coverage, timing, missingness, pooled/within-participant Energy variation, definitions and review gaps without a readiness threshold. The user's “No / unsure — report readiness gaps” means this is an evidence-gap assessment, not a census of zero actual observations. Final commands/results are centralized in the [readiness report](DATA_READINESS_REPORT.md); earlier test counts above are not reused as current verification. No history setting on the user's device, model, production service, deployment, commit or push was activated.


## AI-3 synthetic comparison preparation (2026-10-17)

Added an isolated B0 personal-mean, B1 latest prior compatible Evening-outcome and M1 sleep-only linear-regression runner. Its fixed manifest declares source, exact measurement, history start, evaluation boundaries and final analysis freeze. At each evaluation morning it rebuilds eligible closed personal history as of that cutoff; future answers/revisions/availability cannot enter an earlier estimate. History expands chronologically, including an earlier evaluation outcome only after that outcome is eligible and available.

Baselines require timely synthetic morning execution but can operate without current sleep; their historical outcomes likewise do not require prior sleep/events. M1 requires eligible historical sleep/outcome pairs and current frozen sleep. It fits a centered intercept/slope without a sign constraint, tuning, extra covariates, imputation or population fallback. Its two-pair and `Sxx > 1e-12` checks are numerical requirements only. Raw estimates are retained and clipped to 1–10 without rounding for fixture metrics.

Method-specific coverage, MAE/signed error, participant/macro results and pairwise identical-set comparisons retain the distinction between predictions and scored outcomes. Missing targets are never filled, and an observed execution-to-outcome timezone change excludes baseline scores too. [The preparation report](AI3_SYNTHETIC_PREPARATION.md) contains reproduction commands and final verification; synthetic artifacts are not evidence of real model performance.

The CLI generates invented inputs and accepts no participant files. No runtime UI, dependency, private export reader, real-data training or app model activation is added. AI-2's real-data readiness conclusion and all unresolved scientific/review fields remain unchanged. AI-3 empirical comparison and AI-4 evaluation are still pending.
