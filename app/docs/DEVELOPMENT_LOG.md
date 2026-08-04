# Tonyo Development Log

## Project Overview
- **App Name:** Tonyo
- **Purpose:** Private, explainable fatigue and energy coaching for students and athletes — check-ins, reaction benchmarks, scores, forecasts, and recovery guidance (wellness tool, not a diagnostic product).
- **Target Users:** Adolescent students and student athletes who want to balance focus, training, and recovery.
- **Current release:** Version 0.14 — Score Drivers (as of 2026-08-04)

## Implementation Report

| Version | Feature | Status |
| --- | --- | --- |
| 0.1 | App shell & bottom navigation | Complete |
| 0.2 | Dark visual foundation & shared widgets | Complete |
| 0.3 | Welcome / onboarding screen | Complete |
| 0.4 | User profile | Complete |
| 0.5 | Local storage & persistence | Complete |
| 0.5.1 | Account setup + Forecast/Insights & Coach nav | Complete |
| 0.6 | Manual activity log (hydration, study, exercise, screen) | Complete |
| 0.7 | Manual sleep log (duration + bedtime consistency) | Complete |
| 0.8 | Mood & stress check-in (1–10, auto morning/evening, history) | Complete |
| 0.9 | Reaction-time daily benchmark (invalid attempts + baseline) | Complete |
| 0.10 | Daily history (grouping, completion, edit/delete) | Complete |
| 0.10-a | Firebase Auth + Firestore schema, rules, migration | Complete |
| 0.11 | Firebase-backed Basic Energy Score | Complete |
| 0.12 | Firebase-backed Cognitive Score + daily comparison | Complete |
| 0.13 | Snapshot-backed Today dashboard | Complete |
| 0.14 | Ranked, evidence-aware score drivers | Complete |
| 0.15+ | Forecast engine, HealthKit, AI coach | Not started |

### What ships in 0.8
- Energy, mood, and stress ratings on an intuitive **1–10** scale
- Morning vs evening derived **automatically** from check-in time (morning before 2:00 PM; evening afterward) — no manual override
- Optional notes, validation, local persistence, on-screen check-in history
- Legacy 1–5 check-ins without a `period` field migrate onto 1–10

### What ships in 0.9
- Three valid reaction rounds form one daily benchmark
- Early taps and out-of-range times are discarded (do not affect baseline)
- Average compared to a personal baseline from prior reaction signals
- Results persist as `SignalType.reactionTime` readings

### What ships in 0.10
- Signals and check-ins grouped into local calendar days
- Activity and sleep signal groups displayed once as semantic history entries
- Activity, Sleep, Check-in, and Reaction completion status for each day
- Manual activity, sleep, and check-in records can be edited; all manual records can be deleted
- Imported and fixture-backed signals remain visible but read-only

### Verification
- Command: `flutter test` (from `app/`)
- Last verified: 2026-08-04 — **71 tests passed** with Version 0.14 Score Drivers

## Features Implemented
1. App shell & navigation (Today, Forecast, Add, Insights, Profile / Coach) - Complete (v0.1, v0.5.1)
2. Dark visual foundation & shared widgets - Complete (v0.2)
3. Welcome / onboarding screen - Complete (v0.3)
4. User profile (name, role, schedule, goals) - Complete (v0.4)
5. Local storage & persistence - Complete (v0.5)
6. Local account email + nav restructure - Complete (v0.5.1)
7. Manual activity log - Complete (v0.6)
8. Manual sleep log - Complete (v0.7)
9. Mood & stress daily check-in (1–10, auto morning/evening, history) - Complete (v0.8)
10. Reaction-time daily benchmark (early taps, invalid attempts, baseline) - Complete (v0.9)
11. Daily history (date grouping, completion, edit/delete) - Complete (v0.10)
12. Firebase foundation (Auth, Firestore schema, rules, migration) - Complete (v0.10-a)
13. Basic Energy Score (seven explainable factors + daily cloud snapshot) - Complete (v0.11)
14. Cognitive Score (five explainable factors + previous-day comparison) - Complete (v0.12)
15. Today Dashboard (saved scores + fatigue state + daily signals) - Complete (v0.13)
16. Score Drivers (ranked contributions + evidence-aware confidence) - Complete (v0.14)

## Day-to-Day Entries

### 2026-07-23 — Versions 0.8 & 0.9 (check-in + reaction test)

**Branch:** `feature/v0.8-v0.9-checkin-reaction` (merged to `main` via PR #2)

**Goal:** Promote Daily Check-in and Reaction Test from previews into completed roadmap features; use an intuitive 1–10 scale for mood/stress; add automated tests.

**Results:**
- Check-ins store morning/evening energy, mood, and stress on a 1–10 scale with optional notes and on-screen history.
- Reaction test requires three valid rounds; early taps and out-of-range times are discarded; results compare to a personal baseline.
- Added `CheckInLogic` and `ReactionTestLogic` helpers; updated fatigue engine thresholds for 1–10 ratings.
- App version bumped to `0.9.0`; `PLAN.md` marked 0.8/0.9 complete.

**Major issues:**
- Widget test failed initially because lazy `ListView` had not built “Stress” / history sections off-screen — fixed by scrolling until visible in the test.
- Rating migration risk: doubling any value ≤5 on reload would corrupt real 1–10 data — fixed by only migrating legacy check-ins that lack a `period` field.

### 2026-07-23 (later) — Auto morning/evening + docs + PR prep

**Goal:** Stop allowing manual morning/evening overrides on Daily Check-in; add development log process; prepare branch for PR to main.

**Results:**
- Period is derived only from check-in timestamp (`periodFor`: morning before 2:00 PM, evening afterward).
- UI shows a read-only period banner instead of a segmented control.
- Added `DEVELOPMENT_LOG.md` and agent update instructions in `PLAN.md`.
- Branch published; PR completed on GitHub (`main` includes 0.8/0.9).

**Major issues:** None beyond the product rule that evening check-ins must not be mislabeled as morning.

### 2026-07-23 (UI polish) — Check-in slider alignment + activity category charts

**Goal:** Align daily check-in scale labels under slider ticks; improve activity logging UX.

**Results:**
- Check-in rating cards use a 1–10 tick row under the slider so the “5” label centers on the middle tick.
- Activity log: removed None chips; blank fields save as 0; all four categories persist together.
- Added last-7-days category bar charts highlighting the peak day for hydration, study, exercise, and screen time.
- `flutter test` — 32 tests passed.

**Major issues:** Chart column overflow when value labels sat above tall bars — fixed by reserving label height and capping bar height.

### 2026-07-23 (closeout) — Implementation report + post-merge test repair

**Goal:** Refresh this development log to reflect completion through v0.9 and confirm the full suite is green on `main`.

**Results:**
- Documented an Implementation Report table covering v0.1–v0.9 and next upcoming work.
- Fixed merge damage that broke the build: missing `}` on `CheckInPeriodLabel` in `models.dart`, and a missing `});` closing the v0.9 rejection test in `app_controller_test.dart`.
- Tidied garbled Version 0.7 / 0.9 bullets in `PLAN.md`.
- Re-ran `flutter test` after repairs: **29 tests passed**.

**Major issues:**
- Post-merge syntax errors nested `ActivityLogEntry` / later classes inside the check-in period extension and left a dangling test body — compile failed until braces were restored.

### 2026-07-23 — Version 0.10 Daily History

**Branch:** `main`

**Goal:** Complete Version 0.10 with date-grouped signals and check-ins, a four-part daily completion status, and working edit/delete actions for manual entries.

**Results:**
- Group activity and sleep signal groups into one semantic history item each.
- Assign overnight sleep to its wake date.
- Track Activity, Sleep, Check-in, and Reaction as the four daily completion categories.
- Keep imported/read-only signals visible while restricting edit/delete actions to manual records.
- Added a Daily History launch card under Add, date cards with progress/checklist status, and edit/delete controls.
- Activity, sleep, and check-in forms accept an initial record when opened from history and update in place.
- Added pure grouping tests, controller persistence/edit/delete coverage, and a widget edit/delete flow.
- `flutter analyze` reported no issues; `flutter test` passed all 37 tests.

**Major issues:**
- Raw activity and sleep data uses multiple `SignalReading` rows per logical record. The history builder explicitly suppresses grouped raw rows and emits one semantic item to prevent duplicates.
- Overnight sleep spans two dates; assigning it by wake time keeps the full sleep record on the day it informs.

### 2026-07-28 — Planned Version 0.10-a Firebase Foundation

**Goal:** Insert Firebase setup into the roadmap before scoring/forecast work, and retarget later versions to the cloud schema.

**Results:**
- Added **Version 0.10-a — Firebase Foundation** to `PLAN.md` (Auth, Firestore collections, Security Rules, migration, query helpers, export/delete).
- Updated Versions 0.11–0.35 to reference user-scoped queries, schema collections, and privacy constraints.
- Mapped Stable Data Interfaces to Firestore paths; release rules now prefer Firebase for new persisted features.

**Major issues:** None (planning-only change).

### 2026-07-28 — Version 0.10-a Firebase Foundation implementation

**Branch:** `main`

**Goal:** Complete Version 0.10-a with Firebase Auth, a private Firestore
schema, first-sign-in migration, offline cache behavior, query helpers,
export/deletion, and automated coverage.

**Results:**
- Added environment-injected Firebase initialization. Builds without Firebase
  values remain runnable in explicit offline demo mode.
- Added Firebase Email/Password Auth integration; Tonyo never persists
  passwords in SharedPreferences or Firestore.
- Added user-scoped Firestore repositories for `users/{uid}`, `signals`, and
  `checkIns`, plus reserved schema serializers for scores, forecasts,
  recommendations, and risk alerts.
- Added day-range, `SignalType`, latest-check-in, and reaction-baseline query
  helpers.
- Added first-authenticated-launch migration from the Version 0.5
  SharedPreferences JSON cache. Existing migrated cloud data wins on later
  launches and refreshes the offline cache.
- Added full account export and permanent deletion across the six user
  subcollections, user document, Auth account, and local cache.
- Added deny-by-default Security Rules and the signal type/timestamp compound
  index.
- Updated onboarding, Profile privacy/account state, and Add Data storage copy
  for cloud sync and offline cache behavior.
- Added `FIREBASE_SETUP.md` and a gitignored build-time configuration template.
- `flutter test` passed all **50 tests**.
- `flutter analyze` reported **no issues**.

**Major issues:**
- `flutter analyze` initially traversed Firebase Swift Package sources already
  present under `build/`; excluding generated `build/**` sources restored
  project-only analysis.
- The Firebase account already contains **Fatigue Project**
  (`fatigue-project-e28a3`), but Authentication and Firestore are not activated.
  Console-side activation, app registration, and rules deployment remain
  pending explicit confirmation because they change external account state.

### 2026-07-28 (console closeout) — Version 0.10-a complete

**Branch:** `main`

**Goal:** Finish the authorized Firebase console setup in a US West region and
close Version 0.10-a.

**Results:**
- Confirmed Email/Password Authentication is enabled.
- Created the default Standard Cloud Firestore database in Production mode at
  `us-west2` (Los Angeles).
- Registered the **Tonyo Flutter Runtime** web app and populated the local,
  gitignored build-time configuration.
- Published the repository's deny-by-default, owner-UID-only Security Rules.
- Created the `signals` collection index on `type` ascending and `timestamp`
  descending.
- Re-ran `flutter analyze` with no issues and all **50 tests** passed.
- Built `build/web` successfully with the real, gitignored Firebase runtime
  configuration.

**Major issues:** None. The index may briefly report `Building` after creation;
Firebase enables it automatically when construction finishes.

### 2026-08-01 — Version 0.11 Basic Energy Score

**Branch:** `feature/v0.11-basic-energy-score`

**Goal:** Complete Version 0.11 as a professional, explainable daily Energy
Score backed by the Version 0.10-a Firebase schema.

**Results:**
- Replaced the fixture-only prototype path with a bounded 0–100 estimate using
  sleep, exercise, hydration, workload, screen time, mood, and stress.
- Added day-scoped activity totals, future-reading exclusion, a three-record
  recent sleep window, bounded point contributions, and completeness-based
  confidence. Self-reported energy is intentionally excluded to avoid a
  circular score.
- Added user-scoped Firestore and memory-repository queries for check-in ranges,
  plus deterministic `scoreSnapshots/{yyyy-MM-dd}` reads/upserts.
- Score documents include `energy`, `confidence`, `inputCount`, `isEstimate`,
  explainable `drivers`, `day`, and `calculatedAt`. The cognitive field remains
  reserved for Version 0.12.
- Recalculation runs after relevant data changes. Query/write failures retain a
  local wellness estimate and surface an offline-cache status.
- Refined Today, Insights, Profile, and Forecast copy to distinguish the real
  Energy Score from upcoming preview models. Today shows loading, refresh,
  input coverage, confidence, factor points, and non-medical positioning.
- Bumped the app to `0.11.0+12`.
- `flutter test` passed all **57 tests**; `flutter analyze` reported no issues.

**Major issues:**
- The memory repository initially exported raw score `DateTime` values, unlike
  the production Firestore exporter, breaking account JSON export. The mock now
  normalizes nested score data to ISO-8601 strings.
- The previous score used latest values and HRV/resting heart rate, combined
  check-in energy with stress, and never persisted a snapshot. Version 0.11 now
  follows the seven roadmap inputs and keeps later-version fields out of its
  cloud write.

### 2026-08-01 — Version 0.12 Cognitive Score

**Branch:** `feature/v0.12-cognitive-score`

**Goal:** Complete Version 0.12 professionally on top of the merged Version
0.11 and synthetic Cohort Lab work, without breaking either path.

**Results:**
- Added a bounded 0–100 Cognitive Score with separate explainable contributions
  for reaction time, recent sleep, same-day study load, mood, and stress.
- Personalized reaction contribution against up to 14 prior valid reaction
  tests when available; generic expectations are used only while a personal
  baseline is still building.
- Added Cognitive-specific confidence, five-input completeness, drivers, and
  previous-day comparison without changing Version 0.11 Energy fields.
- Extended the user-scoped controller workflow to query reaction history and
  the prior `scoreSnapshots/{yyyy-MM-dd}` document, then merge both scores into
  today's existing snapshot.
- Preserved backwards compatibility with Version 0.11 Energy-only documents:
  a missing Cognitive field is treated as no comparison, never as a score of 0.
- Promoted Cognitive from preview copy to a polished Today/Insights experience
  with status, confidence, yesterday change, leading factor points, and clear
  wellness-only positioning.
- Kept the merged synthetic Cohort Lab compatible with the new model and added
  distinct Energy and Cognitive driver views for synthetic-person inspection.
- Updated `ENGINE_TUNING.md` so cohort tuning no longer implies that screen time
  is a Version 0.12 Cognitive input.
- Bumped the app to `0.12.0+13`.
- `flutter test` passed all **64 tests**; `flutter analyze` reported no issues.

**Major issues:**
- The current `main` included a newly merged synthetic cohort harness after
  Version 0.11. Version 0.12 was implemented against that current state and
  retains all cohort parsing, scoring, persistence, charts, sorting, and tests.
- Version 0.11 documents intentionally lack a Cognitive field. Schema parsing
  now records field presence so yesterday comparisons do not show a misleading
  jump from zero after upgrade.

### 2026-08-04 — Version 0.13 Today Dashboard

**Branch:** `main`

**Goal:** Complete Version 0.13, verify the app for errors, and make the Today
experience visually clean.

**Results:**
- Changed startup scoring to prefer the authenticated user's saved
  `scoreSnapshots/{yyyy-MM-dd}` document. A missing or legacy Energy-only
  snapshot falls back to live calculation and a manual refresh forces a fresh
  calculation.
- Added a dedicated day-scoped Firestore query for Today signals and six
  consistent summaries: sleep, hydration, exercise, study, screen time, and
  reaction time.
- Added tested Fresh, Moderate, and Fatigued Energy status thresholds.
- Rebuilt Today around a compact readiness hero, side-by-side Energy/Cognitive
  scores, a clean two-column signal grid, separate factor cards, offline state,
  and wellness-only language. Removed forecast/recommendation fixture clutter
  from the dashboard.
- Made the greeting time-aware and guarded empty profile initials.
- Bumped the app to `0.13.0+14` and added controller, logic, and widget coverage.
- `flutter test` passed all **67 tests**; `flutter analyze` reported no issues.

**Major issues:**
- Loading an existing snapshot on every refresh would hide newly logged inputs.
  Startup now reuses saved scores, while data mutations and the Refresh action
  explicitly recalculate and upsert the daily document.
- Day summaries must not count future or previous-day readings. The pure
  dashboard logic applies both calendar-day and current-time cutoffs.

### 2026-08-04 — Version 0.14 Score Drivers

**Branch:** `main`

**Goal:** Complete Version 0.14 with a professional, evidence-backed driver
experience on top of the uncommitted Version 0.13 work.

**Results:**
- Ranked supporting contributions from strongest to weakest and reducing
  contributions from largest penalty to smallest, separately for Energy and
  Cognitive models.
- Added plain-language explanations plus representative evidence timestamps,
  source labels, and per-driver freshness to the daily snapshot schema.
- Replaced count-only confidence with a bounded calculation combining input
  completeness and average evidence freshness. HealthKit, manual, and model
  sources receive explicit reliability weights alongside stored data quality.
- Removed caffeine from Energy driver scoring so Version 0.14 uses exactly the
  seven Version 0.11 roadmap inputs.
- Rebuilt Insights as a real driver report with model confidence panels,
  coverage/freshness breakdowns, ranked supporting/reducing sections, and
  evidence chips. Removed the fixture pattern cards scheduled for Version 0.21.
- Updated Today to show freshness beside confidence and separate supporting
  from reducing factors.
- Advanced the Firestore schema marker to Version 2. Older score snapshots stay
  readable; snapshots without freshness metadata recalculate and upgrade on
  the next signed-in launch.
- Bumped the app to `0.14.0+15`.
- `flutter test` passed all **71 tests**; `flutter analyze` reported no issues.

**Major issues:**
- Existing 0.13 snapshots contain valid scores but no freshness evidence.
  Treating them as current would leave the 0.14 report incomplete, so startup
  detects missing freshness fields, recalculates, and upserts the same daily ID.
- Completeness alone overstates confidence when records are old. The updated
  formula retains the 20% low-data floor while combining 55% coverage weight
  and 20% freshness weight above that baseline.

---

## Prompts Used

### Feature: Versions 0.8 & 0.9 check-in and reaction test
**Prompt:**
"setup a new feature branch, follow plan.md in docs

-complete versions .8 and .9

-for mood and stress i want it to be an intuitive scale 1-10
-add tests for functionality"

**Result:** Feature branch created; Daily Check-in and Reaction Test promoted to completed features; 1–10 scales; persistence + baseline comparison; new unit/widget tests; `PLAN.md` and `pubspec` updated.

**Modifications:** Scroll-into-view fix in widget tests; legacy rating migration keyed off missing `period`.

### Docs: Development log process
**Prompt:**
"before we merge to main, ongoing we want to implement a development log md file. i will post a starting template, this template should be updated with major issues, important details of prompts, and results from prompts and work in a day to day. implement a new development log md file and instructions for future agents on how to use the file in plan.md file"

**Result:** Created this `DEVELOPMENT_LOG.md` and added agent instructions in `PLAN.md`.

**Modifications:** Expanded with Implementation Report after merge to main.

### Feature: Auto morning/evening check-in + PR prep
**Prompt:**
"change daily checkin to automatically determine morning or evening input of energy,mood, stress. right now you can manually change to a morning checkin even if your checking in at evening! after this commit all changes to branch. publish branch and prepare for PR to main. setup pr name and description. i will complete the pr manually on the github web portal"

**Result:** Removed manual period selector; `addCheckIn` always sets period from timestamp; docs/log updated; branch committed and published for a manual PR.

**Modifications:** None expected beyond review on GitHub.

### Feature: Check-in slider + activity category charts
**Prompt:**
"fix these following issues/small changes. *daily checkin ui should be centered so that the label for 5 is under the ticker on the number line

*activity data should be split up between the different categories. remove the none button and make it so that if user inputs an activity and leaves others blank those will be taken as 0. the recent activity should be broken down into different categories of the last week. show which days had the most of each category in a bar chart"

**Result:** Slider tick labels aligned; None removed; blanks → 0; weekly per-category peak charts added; tests updated (32 passing).

**Modifications:** None expected.

### Feature: Version 0.10 Daily History
**Prompt:**
"complete version .10 -daily history. Make sure it functions correctly."

**Result:** Completed date-grouped Daily History with four-part completion status, semantic activity/sleep grouping, manual edit/delete actions, read-only imported data, and automated coverage.

**Modifications:** Overnight sleep is assigned to the wake date; reaction benchmarks are removable but not editable so measured results are not converted into manual values.

### Docs: Version 0.10-a Firebase roadmap
**Prompt:**
"we want to setup a firebase database before working . add that in as a version .10-a and then edit later versions to reference what you created (using the database schema, querying correctly for new data, privacy)"

**Result:** Added Version 0.10-a Firebase Foundation to `PLAN.md`; retargeted 0.11–0.35 and Stable Data Interfaces to Firestore paths, user-scoped queries, and Security Rules / privacy.

**Modifications:** Planning docs only (no app code yet).

### Feature: Version 0.10-a Firebase implementation
**Prompt:**
"view docs/plan.md and complete version 10-a"

**Result:** Implemented the Firebase-ready app foundation, schema, repositories,
migration/cache policy, Auth flow, privacy UI, export/delete support, rules,
indexes, setup documentation, and automated coverage. Verified 50 tests pass
and static analysis has no issues.

**Modifications:** Reused the existing `fatigue-project-e28a3` Firebase project
instead of creating a duplicate. Console activation remains gated on explicit
confirmation.

### Feature: Version 0.10-a Firebase console closeout
**Prompt:**
"I enable email/password auth go though and complete rest of tasks use us west
region for data base"

**Result:** Completed the remaining Firebase console work in `us-west2`,
published the repository Security Rules, provisioned the required compound
index, and populated the ignored local runtime configuration.

**Modifications:** Used the existing project and selected `us-west2` (Los
Angeles) as the requested US West database location.

### Feature: Version 0.11 Basic Energy Score
**Prompt:**
"complete version 0.11 in a seperate feature branch. Make it professional."

**Result:** Created `feature/v0.11-basic-energy-score`; implemented a
Firebase-backed, explainable 0–100 Energy Score, deterministic daily snapshot
persistence, offline fallback, polished UI states/copy, and regression tests.

**Modifications:** Daily activity rows are summed; sleep uses up to three recent
records; future readings are ignored; mood and stress contribute independently;
self-reported energy is not used as a score input; Version 0.12’s cognitive
field is deliberately not written by the Version 0.11 serializer.

### Feature: Version 0.12 Cognitive Score
**Prompt:**
"complete version 0.12, make it profesional,make sure it works out with what i have"

**Result:** Created `feature/v0.12-cognitive-score` from the current merged
`main`; completed the Firebase-backed, explainable Cognitive Score, shared
snapshot persistence, previous-day comparison, professional UI, Cohort Lab
compatibility, and regression coverage.

**Modifications:** Cognitive uses five roadmap inputs and independent metadata;
reaction time is personalized when history exists; legacy Energy-only snapshots
remain readable; the existing Energy Score and synthetic cohort functionality
remain in place.

### Feature: Version 0.13 Today Dashboard
**Prompt:**
"complete version 0.13, check for error, and make it look clean"

**Result:** Completed the snapshot-backed Today dashboard, day-scoped signal
summaries, fatigue status model, visual cleanup, release metadata, and automated
coverage.

**Modifications:** Saved snapshots are preferred on startup; data changes and
manual refreshes force recalculation so persisted scores never mask new inputs.

### Feature: Version 0.14 Score Drivers
**Prompt:**
"complete 0.14 now, make it professional"

**Result:** Completed ranked positive/negative drivers, stored evidence
metadata, freshness-aware confidence, professional Today/Insights presentation,
backward-compatible snapshot upgrades, and regression coverage.

**Modifications:** Confidence now combines completeness with recency, source,
and quality. Caffeine is excluded to preserve the exact seven Version 0.11
Energy inputs named by the roadmap.

---

## Challenges & Solutions

### Challenge 1: Lazy list broke widget expectations
**Problem:** `find.text('Stress')` failed in widget tests even though the screen contained a Stress slider — off-screen `ListView` children were not built yet.
**Solution:** Use `tester.scrollUntilVisible` before asserting on lower sections.
**Prompt used:** Same as Versions 0.8 & 0.9 feature prompt (surfaced during test run).

### Challenge 2: Legacy 1–5 vs new 1–10 check-in scale
**Problem:** Blindly remapping any stored rating ≤5 to a 1–10 scale would corrupt legitimate mid-scale ratings after v0.8.
**Solution:** Treat missing `period` as the legacy signal and only then double 1–5 values; new saves always include `period`.
**Prompt used:** N/A (implementation detail during v0.8).

### Challenge 3: Merge left `models.dart` / tests uncompilable
**Problem:** After PR merge on `main`, `CheckInPeriodLabel` was missing a closing brace and a v0.9 controller test was missing `});`, so every suite failed to load.
**Solution:** Close the extension before `ActivityLogEntry`; finish the reaction-rejection test block; re-run `flutter test`.
**Prompt used:** Implementation report closeout prompt.

### Challenge 4: Grouped signals duplicated logical history records
**Problem:** Activity is stored as four signals and sleep as duration + bedtime, so naïve date grouping would show repeated rows and split overnight sleep.
**Solution:** Build semantic activity/sleep items first, suppress their grouped raw signals, and assign sleep by wake date.
**Prompt used:** Version 0.10 Daily History prompt.

## What I Learned
- Fixture-backed UI previews are not “done” until data is validated, persisted, and covered by tests (`PLAN.md` release rules).
- Extracting pure helpers (`CheckInLogic`, `ReactionTestLogic`) makes feature behavior easy to unit test without driving the full UI.
- Widget tests against scrollable forms need explicit scroll-into-view for lazily built children.
- Keep rating-scale migrations keyed to a clear schema signal (e.g. new fields), not raw numeric ranges alone.
- After merging parallel feature branches, re-run the full test suite immediately — small brace mismatches can look like “missing types” across the whole app.

## Future Improvements
- [x] Implement Version 0.10 — fuller Daily History (edit/delete by date)
- [x] Implement Version 0.10-a — Firebase Auth + Firestore schema, Security Rules, local migration
- [x] Implement Version 0.11 Energy Score and Version 0.12 Cognitive Score (query Firebase)
- [x] Implement Version 0.13 Today Dashboard from persisted snapshots
- [x] Implement Version 0.14 ranked Score Drivers and freshness confidence
- [ ] Keep this log updated each working day before merge/PR
- [ ] Backfill earlier versions (0.1–0.7) prompt entries if curriculum requires a complete prompt history
