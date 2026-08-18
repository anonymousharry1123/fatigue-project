# Tonyo Product Roadmap

Last updated: August 17, 2026
Current release: **Version 0.25 — Workout and Hydration Sync**

Tonyo is developed through small, runnable releases. Fixture data is used first so each screen can be demonstrated before manual inputs, device integrations, and personalized predictions are introduced.

## Development Log (required for agents)

Keep a running narrative of day-to-day work in `[DEVELOPMENT_LOG.md](./DEVELOPMENT_LOG.md)`. The product roadmap below tracks *what* ships; the development log tracks *how* it was built (prompts, results, issues, learnings).

### When to update

Future agents **must** update `DEVELOPMENT_LOG.md` during the same session when they:

- Start or finish a roadmap version / major feature
- Hit a non-trivial bug, design decision, or schema migration
- Run an important user prompt that drives implementation
- Close out a work day or prepare a merge/PR

Do **not** wait until merge to invent history. Append as work happens.

### What to record

1. **Day-to-Day Entries** — dated section with branch, goal, results, and major issues.
2. **Prompts Used** — important prompts verbatim (or closely paraphrased if huge), plus **Result** and **Modifications**.
3. **Challenges & Solutions** — problem → fix → related prompt if any.
4. **Features Implemented** — keep status in sync with this roadmap.
5. **What I Learned / Future Improvements** — short bullets only; no essay.

### How to edit

- Prefer **appending** new day entries and prompt blocks; do not rewrite older days unless correcting a factual error.
- Quote prompts under `### Feature:` or `### Screen:` headings matching the template in `DEVELOPMENT_LOG.md`.
- Note test commands and outcomes when they matter (e.g. `flutter test` pass/fail and what broke).
- Keep the tone factual and concise; skip filler and unrelated chat.

### Relationship to this file

- Update **this** `PLAN.md` checklist when a version’s acceptance criteria are met.
- Update `DEVELOPMENT_LOG.md` with the prompt trail, issues, and daily outcomes for that work.
- Both files live under `app/docs/` and should stay consistent on status (Complete vs upcoming).

## Current Progress

### Version 0.1 — Basic Structure ✅

- Flutter application skeleton
- Bottom navigation for Today, Forecast, Add, Insights, and Profile
- Runnable screen structure for every primary destination

### Version 0.2 — Visual Foundation ✅

- Dark visual direction based on the supplied designs
- Shared colors, typography, cards, metric icons, score rings, and forecast charts
- Loading, empty, error, and preview messaging patterns

### Version 0.3 — Welcome Screen ✅

- Tonyo introduction and value proposition
- Fixture-backed Energy Forecast preview
- “Build my fatigue model” onboarding action
- Preview of the signals Tonyo will eventually use

### Version 0.4 — User Profile ✅

- Name, age range, student/athlete role, and primary goal
- Typical wake and bedtime schedule
- Editable Profile screen
- Wellness-only positioning and privacy messaging

### Version 0.5 — Local Storage ✅

- Profile and onboarding state persist across app restarts
- Shared local repository for fixture signals and check-ins
- Saved state can be exported or permanently deleted
- Today and Forecast screens render from the shared persisted state
- Daily Check-in, Reaction Test, Insights, AI Coach, and Profile designs are connected as fixture-backed previews
- Automated tests cover persistence, scoring fixtures, onboarding, navigation, and screen routing

### Version 0.5.1 — Account and Navigation Update ✅

- Welcome continues into local account creation before personal-model setup
- Account setup validates email and password confirmation without persisting the password
- Forecast and Insights share one bottom-navigation destination with an in-screen switcher
- AI Coach has a dedicated bottom-navigation destination
- Profile displays the locally saved account email
- Automated tests cover the new account flow and navigation structure

### Version 0.6 — Manual Activity Log ✅

- Record hydration, study time, exercise load, and screen time
- Validate values and reject impossible entries
- Edit and add data through the center navigation action
- Persist grouped activity records locally
- Automated tests cover validation, editing, persistence, and the activity form

### Version 0.7 — Manual Sleep Log ✅

- Record bedtime, wake time, and sleep quality
- Calculate sleep duration and bedtime consistency
- Display recent sleep entries
- Edit or remove manual sleep entries
- Automated tests cover overnight duration, consistency, validation, persistence, and the sleep form

### Version 0.8 — Mood and Stress Check-In ✅

- Daily Check-in stores morning and evening energy, mood, and stress
- Mood and stress use an intuitive 1–10 scale (energy matches the same scale)
- Morning vs evening is set automatically from the check-in time (before/after 2:00 PM)
- Saved check-ins appear in on-screen daily history
- Ratings validate and persist through the shared local repository

### Version 0.9 — Reaction-Time Test ✅

- Reaction Test is a completed daily benchmark with three valid rounds
- Early taps and out-of-range attempts are detected and discarded
- Valid results compare against a personal reaction-time baseline
- Automated tests cover check-in ratings, reaction validation, baselines, and persistence

### Version 0.10 — Daily History ✅

- Group signals and check-ins by date
- Edit or delete manual entries
- Display completion status for each day
- Show grouped activity and sleep records once while retaining other signals
- Track Activity, Sleep, Check-in, and Reaction completion for each day
- Keep imported and fixture signals read-only
- Automated tests cover grouping, overnight sleep dates, completion, persistence, editing, deletion, and routing

### Version 0.10-a — Firebase Foundation ✅

Set up cloud persistence **before** scoring and forecast work so later versions read and write against a real schema.

- Create a Firebase project (Auth + Cloud Firestore) and wire the Flutter app with environment-safe config
- Map Stable Data Interfaces to Firestore collections under each authenticated user:
  - `users/{uid}` — profile, account email, prefs, consent flags, `updatedAt`
  - `users/{uid}/signals/{signalId}` — `SignalReading` fields (`type`, `value`, `unit`, `timestamp`, `source`, `quality`, `note`, `groupId`)
  - `users/{uid}/checkIns/{checkInId}` — `DailyCheckIn` fields (`period`, `energy`, `mood`, `stress`, `note`, `timestamp`)
  - `users/{uid}/scoreSnapshots/{snapshotId}` — Version 0.11+ daily scores (`energy`, `cognitive`, per-model confidence/input counts/drivers, previous Cognitive comparison, `day`, `calculatedAt`)
  - `users/{uid}/forecastPoints/{pointId}` — hourly forecasts (`time`, `energy`, `uncertainty`, `updatedAt`)
  - `users/{uid}/recommendations/{recId}` — Version 0.18+ grounded guidance (`title`, `detail`, `timeLabel`, `category`, `status`, priority/window timing, evidence IDs, `feedback`)
  - `users/{uid}/riskAlerts/{alertId}` — Version 0.19+ wellness flags (`title`, `detail`, `severity`, category/day/evidence IDs, `dismissed`)
- Enforce privacy with Security Rules: users may only `read`/`write` documents under their own `uid`; deny list/collection-group access across users
- Use Firebase Auth for accounts (no passwords stored in Firestore); keep wellness-only copy and no medical claims in stored metadata
- Migrate existing SharedPreferences state into Firestore on first signed-in launch; keep a local cache for offline demoability
- Provide repository helpers for common queries (by day range, by `SignalType`, latest check-in, reaction baseline window)
- Support export and permanent deletion of the user’s Firebase subtree (aligned with later Version 0.34)
- Automated tests cover rule-safe repository mocks, schema serialization, and migration from local JSON

### Side track — Synthetic Cohort Lab

Debug harness for energy/cognitive scoring against a 3000-row synthetic student CSV. Does **not** replace Versions 0.11–0.13.

- Bundle `assets/data/synthetic_students.csv` and map rows into signals (sleep, folded screen+social, study, daily exercise, caffeine) plus derived check-ins
- Score locally with `FatigueEngine`; visualize distributions and relationships in Profile → **Cohort Lab**
- Optional Firestore publish under `syntheticUsers/{id}` + `syntheticCohort/summary` (authenticated read/write; real `users/{uid}` stays owner-only)
- No Firebase Auth accounts are created for synthetic students
- Shared tuning checklist: [`ENGINE_TUNING.md`](./ENGINE_TUNING.md)

### Version 0.11 — Basic Energy Score ✅

- Calculate an explainable 0–100 Energy Score
- Query Version 0.10-a `signals` and `checkIns` for the target day (and recent window) instead of in-memory fixtures only
- Use sleep, exercise, hydration, workload, screen time, mood, and stress from the Firebase schema
- Persist each result as a `scoreSnapshots` document; clearly label the score as an estimate
- Aggregate same-day activity values, exclude future readings, and use up to three recent sleep records
- Derive confidence from the number of available score inputs and retain a local-cache fallback when cloud queries are unavailable
- Refresh the daily snapshot after relevant input changes and expose manual refresh, loading, and offline states
- Automated tests cover scoring factors, aggregation, circular-input prevention, cloud queries, schema round-trips, daily upserts, controller integration, and UI labeling

### Version 0.12 — Cognitive Score ✅

- Calculate an explainable 0–100 Cognitive Score
- Query reaction-time `signals`, sleep, study load, screen time, and latest mood/stress `checkIns` from Firestore
- Compare the result with the previous day’s `scoreSnapshots` document
- Write cognitive fields onto the same daily snapshot schema from Version 0.10-a
- Personalize the reaction-time contribution against prior valid reaction tests when a baseline exists
- Keep Cognitive drivers, confidence, and six-input completeness separate from Energy model metadata
- Treat Version 0.11 Energy-only documents as valid legacy snapshots without creating a false zero-score comparison
- Show the estimate, previous-day change, leading contributions, loading/offline state, and wellness-only language in Today and Insights
- Keep the synthetic Cohort Lab compatible with the shared engine and show separate Energy/Cognitive driver cards
- Automated tests cover bounds, factors, baselines, legacy snapshots, schema round-trips, shared daily upserts, Firebase-controller integration, previous-day comparison, synthetic scoring, and UI presentation

### Version 0.13 — Today Dashboard ✅

- Replace Today fixtures with Energy and Cognitive scores loaded from `scoreSnapshots` (falling back to live calculation when missing)
- Display Fresh, Moderate, or Fatigued status
- Show recent-signal summary cards from day-scoped Firestore queries

### Version 0.14 — Score Drivers ✅

- Rank positive and negative score contributions using the same inputs Version 0.11 queried from Firebase
- Explain each contribution
- Calculate confidence from signal completeness and freshness (document `timestamp` / `source` fields from the Version 0.10-a schema)

### Version 0.15 — Forecast Engine ✅

- Generate hourly energy estimates from Firebase-backed signals and check-ins
- Incorporate sleep timing, circadian rhythm, workload, and recovery
- Return uncertainty with each forecast point and persist points under `forecastPoints`

### Version 0.16 — Forecast Screen ✅

- Replace the Forecast preview with calculated Today and Tomorrow curves read from `forecastPoints` queries
- Add daily summaries to the Week view
- Handle missing and low-confidence data (empty query windows, stale `updatedAt`)

### Version 0.17 — Key Windows ✅

- Identify peak-focus, predicted-crash, and recovery windows from forecast documents
- Explain the signals supporting each window using linked `signals` / `checkIns` evidence IDs where available

### Version 0.18 — Basic Recommendations ✅

- Recommend study, nap, exercise, hydration, and recovery times
- Match recommendations to forecast windows
- Ground every recommendation in recent Firestore data and store rows in `recommendations`

### Version 0.19 — Fatigue Warnings ✅

- Detect sustained sleep debt, possible training overreaching, and sustained low-energy / high-stress patterns without diagnosis
- Query multi-day `signals` and `checkIns` ranges via Version 0.10-a helpers
- Persist dismissible alerts in `riskAlerts` under the user document

### Version 0.20 — Notifications ✅

- Add opt-in crash and recovery alerts driven by `riskAlerts` / forecast windows
- Store notification prefs on `users/{uid}`; never send content that implies diagnosis
- Suppress duplicate and low-confidence alerts using Firestore fields (`dismissed`, freshness)

### Version 0.21 — Insights Dashboard ✅

- Promote the Insights preview into calculated daily and weekly trends
- Aggregate sleep, training, and study from date-range `signals` queries
- Explain model associations without presenting them as proven causes; do not expose other users’ data

### Version 0.22 — HealthKit Permissions ✅

- Explain each requested permission
- Support approval, denial, and revocation
- Preserve manual Firestore entry when access is unavailable

### Version 0.23 — Heart Data Sync ✅

- Import HRV and resting heart rate into `signals` with `source: healthKit`
- Normalize units, timestamps, sources, and duplicates against the Version 0.10-a schema
- Deduplicate with existing manual rows using timestamp/value rules

### Version 0.24 — Sleep Architecture Sync ✅

- Import awake, core, deep, REM, and unspecified sleep stages as typed `signals`
- Reconcile overlapping samples and multiple sources in Firestore
- Prefer imported sleep only when it is more complete than manual data

### Version 0.25 — Activity and Hydration Sync ✅ Current

- Import workouts, daily step totals, and available hydration samples into `signals`
- Derive daily training load from queried exercise signals
- Use steps as the Energy model’s movement input only when no workout exists
- Retain manual correction and fallback controls on the same documents

## Upcoming Versions

### Version 0.26 — Continuous Refresh

- Refresh HealthKit data as iOS permits and upsert into Firestore
- Track source, freshness, and sync status on `users/{uid}` and signal docs
- Recalculate scores/forecasts only when meaningful Firebase inputs change

### Version 0.27 — Personal Baselines

- Build rolling HRV, resting-heart-rate, sleep, and reaction-time baselines from historical `signals` queries
- Compare users with their own history only (Security Rules keep data user-scoped)
- Reduce confidence until enough baseline data exists in Firestore

### Version 0.28 — Screen-Time Enhancement

- Keep manual screen time as the dependable model input in `signals`
- Add a privacy-preserving Device Activity report if entitlement access is approved
- Keep protected activity data inside Apple’s report-extension sandbox; only derived aggregates may enter Firebase

### Version 0.29 — AI Coach Daily Plan

- Promote the AI Coach preview into a generated morning-to-evening plan
- Schedule deep work, naps, training, tapering, and recovery using Firebase-backed scores and windows
- Resolve conflicting goals using confidence and user priorities stored on `users/{uid}`

### Version 0.30 — Recommendation Feedback

- Accept, dismiss, and complete recommendations by updating `recommendations` documents
- Record whether advice was helpful (`feedback` field from Version 0.10-a schema)
- Adjust future recommendation ranking from that queried history

### Version 0.31 — Outcome Collection

- Collect optional observed-energy ratings into `checkIns` or a dedicated outcomes subcollection under the same user tree
- Use reaction-test `signals` as cognitive outcomes
- Require explicit consent flags on `users/{uid}` before any training-record use; respect Security Rules

### Version 0.32 — Personalized ML Model

- Train and evaluate a multimodal fatigue model on consented, user-exported or on-device datasets — not by reading other users’ Firestore data
- Run approved inference on-device where possible
- Retain deterministic scoring as the fallback; store model metadata on `users/{uid}` without raw third-party PII

### Version 0.33 — Model Transparency

- Display model version, confidence, and last update from Firebase user/model metadata
- Explain the signals driving each prediction via `scoreSnapshots.drivers`
- Distinguish measured, estimated, and missing data using `source` / completeness from the Version 0.10-a schema

### Version 0.34 — Privacy and Youth Safety

- Add age-appropriate onboarding and consent; store consent timestamps on `users/{uid}`
- Add guardian consent where legally required
- Complete export and deletion against the full Version 0.10-a user subtree; review wellness language
- Audit Security Rules so minors’ data cannot be listed or shared across accounts

### Version 0.35 — Production Polish

- Complete accessibility and dynamic-type improvements
- Harden offline, error, interrupted-test, and Firestore sync conflict handling
- Complete performance, security, real-device, and App Store readiness testing

## Stable Data Interfaces

- `SignalReading`: measurement type, value, unit, timestamp, source, and quality → Firestore `users/{uid}/signals/{id}`
- `DailyCheckIn`: morning/evening period, energy, mood, stress (1–10), and optional notes → `users/{uid}/checkIns/{id}`
- `ScoreSnapshot`: Energy Score, Cognitive Score, confidence, and drivers → `users/{uid}/scoreSnapshots/{id}`
- `ForecastPoint`: predicted energy, timestamp, uncertainty, forecast `updatedAt`, and linked signal/check-in evidence IDs → `users/{uid}/forecastPoints/{id}`
- `ForecastWindow`: peak, crash, or recovery period (derived; may be stored or computed from `forecastPoints`)
- `Recommendation`: action, timing, priority, evidence, and feedback → `users/{uid}/recommendations/{id}`
- `RiskAlert`: warning category, severity, evidence, and dismissal state → `users/{uid}/riskAlerts/{id}`

Firebase Auth identifies `uid`. Passwords never appear in Firestore. Local SharedPreferences is the offline cache and migrates on the first authenticated launch.

## Release Rules

- Every version must remain runnable and demoable.
- Fixture-backed previews do not count as completed roadmap features.
- Manual entry remains available when a device integration is denied or unavailable.
- Deterministic scoring remains available when a personalized model is unavailable or underperforms.
- From Version 0.10-a onward, new persisted features should use the Firebase schema and user-scoped queries; local cache is allowed for offline use.
- Tonyo is a wellness and performance tool, not a diagnostic medical product.
