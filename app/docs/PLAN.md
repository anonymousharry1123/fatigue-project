# Tonyo Product Roadmap

Last updated: September 7, 2026
Current implementation: **Version 0.34 — Privacy and Youth Safety safeguards**
Remaining Version 0.32 release QA: iPhone performance/heap profiling and production rules deployment/IAM verification. Executable rules emulator validation passed during 0.34.

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
  - `users/{uid}/recommendations/{recId}` — Version 0.18+ grounded guidance (`title`, `detail`, `timeLabel`, `category`, `status`, priority/window timing, plan phase/duration/confidence/decision, evidence IDs, `feedback`)
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

### Version 0.25 — Activity and Hydration Sync ✅

- Import workouts, daily step totals, and available hydration samples into `signals`
- Derive daily training load from queried exercise signals
- Use steps as the Energy model’s movement input only when no workout exists
- Retain manual correction and fallback controls on the same documents

### Version 0.26 — Continuous Refresh ✅

- Refresh HealthKit data as iOS permits and upsert into Firestore
- Track source, freshness, and sync status on `users/{uid}` and signal docs
- Recalculate scores/forecasts only when meaningful Firebase inputs change

### Version 0.27 — Personal Baselines ✅

- Build rolling HRV, resting-heart-rate, sleep, and reaction-time baselines from historical `signals` queries
- Compare users with their own history only (Security Rules keep data user-scoped)
- Reduce confidence until enough baseline data exists in Firestore

### Version 0.28 — Screen-Time Enhancement ✅

- Keep manual screen time as the dependable model input in `signals`
- Add a privacy-preserving Device Activity report if entitlement access is approved
- Keep protected activity data inside Apple’s report-extension sandbox; only derived aggregates may enter Firebase

### Version 0.29 — AI Coach Daily Plan ✅

- Promote the AI Coach preview into a generated morning-to-evening plan
- Schedule deep work, naps, training, tapering, and recovery using Firebase-backed scores and windows
- Resolve conflicting goals using confidence and user priorities stored on `users/{uid}`

### Version 0.30 — Recommendation Feedback ✅

- Accept, dismiss, and complete recommendations by updating `recommendations` documents
- Record whether advice was helpful (`feedback` field from Version 0.10-a schema)
- Adjust future recommendation ranking from that queried history

### Version 0.31 — Outcome Collection ✅

- Collect optional observed-energy ratings in `users/{uid}/outcomes`, linked to future check-ins or completed Coach blocks
- Keep reaction tests in `signals` and link future consented results as cognitive outcomes
- Require both explicit outcome-collection and training-record-use flags on `users/{uid}` before writes; enforce the gate in Security Rules

### Prep for Version 0.32 — Bounded 30-Day Account Snapshot ✅ Complete

Engineering prep is complete; this does **not** mark the personalized model or
this account's training readiness complete. Open **Profile → Model preparation**
in a Firebase-configured, signed-in build. Select the window end and IANA timezone,
then use **Prepare / inspect 30-day snapshot**. The selected month survives reopening
and restart; valid cached prep makes no new reads. **Refresh from Firebase** is
the explicit opt-in to another bounded fetch. Coverage inspection never turns on consent.

Do this work before personalized training. The first feasibility run must use one explicit 30-day window from the currently authenticated account only. Use the account’s already-populated 30-day window; do not scan all history to discover a better window, silently widen the range, pool other users, or substitute Cohort Lab rows when labels are sparse.

#### Read the account once, then work locally

- Require `outcomeCollection` and `trainingRecordUse` consent before building training examples. An authorized read-only coverage inspection may report missing consent or labels without changing consent flags or backfilling outcomes.
- Define one half-open local-time window, `[startOfDay(windowEnd - 29 days), startOfDay(windowEnd + 1 day))`, covering exactly 30 calendar dates. Save the chosen bounds in the prep report so the run is reproducible.
- Prefer the authenticated account state already loaded in memory when it fully covers the window. Otherwise issue at most one bounded query each for `signals`, `checkIns`, and `outcomes`, in parallel.
- Never issue one query per day, per signal type, or per outcome. Do not attach Firestore listeners and do not run prep from background HealthKit refresh.
- Do not query `scoreSnapshots` for labels. Recompute the deterministic Energy reference and any Cognitive context locally from the downloaded signals and check-ins.
- Apply server-side query limits of 1,500 signal documents, 100 check-ins, and 100 outcomes before fetching; checking counts after an unlimited read does not enforce the budget. If a limit is reached, stop and report that aggregation/pagination design is needed; do not train on a potentially truncated window.
- Cache the normalized snapshot by `uid + window bounds + timezone + schema/prep version + consent version`, with a stable content fingerprint covering document IDs and all used values/timestamps. Invalidate on known edits, deletions, newly eligible data, or consent changes; counts and the latest timestamp alone cannot detect an edited or deleted row. Reopening must reuse the cache without reads. Remote changes unknown to the app require explicit refresh; show the snapshot's fetched-at time rather than claiming it is always current.
- The prep path must never call the broad `replaceUser` workflow.

Expected Firestore request budget for one uncached prep run: up to three bounded collection queries, plus one shared user-document read only if consent state is not already loaded, zero writes, and no recurring database traffic. Three requests do not mean three billed reads: these caps allow up to 1,700 returned collection documents; report returned-document counts separately from requests, with any rule/index/minimum-query billing accounted for separately. Reuse the consent result across the three queries.

#### Minimal local `TrainingExample`

Build one local/exported row per eligible outcome. Join data in memory rather than creating a Firestore training collection.

Each example should include:

- **Consent and provenance:** `uid` only in local memory, consent version, feature sources, freshness, and an explicit missingness bit for every feature. Classify known seed IDs/notes as synthetic; `source: manual` alone does not prove a real observation. Synthetic account rows may exercise joins, normalization, and coverage reporting as pipeline QA, but never count toward training readiness, model validation, or labels. Report uncertain provenance separately.
- **Time key:** local calendar day and optional morning/evening period; prior-night sleep joins to the wake day, while activity and check-in context join to the observation day. Use only evidence available at or before `observedAt`, and exclude the outcome's own `sourceId` from both features and the deterministic reference. End-of-day aggregates cannot supply earlier same-day features. Preserve observation and ingestion/update times separately where available; flag legacy records whose historical availability cannot be established instead of claiming an exact historical replay.
- **Label and units:** a real, consented `OutcomeRecord` from the selected window. Map `observedEnergy` from its stored 1–10 rating onto the score scale with the fixed formula `energyTarget = (rating - 1) * 100 / 9`, validating the original range first. Keep raw `cognitiveReaction` values in milliseconds for coverage/reporting; a milliseconds label cannot be subtracted from a 0–100 Cognitive Score. Deterministic scores and synthetic data are never labels.
- **Deterministic reference:** recompute the Energy score locally at each outcome's cutoff, on the same 0–100 scale as `energyTarget`. Rebuild personal baselines from only earlier evidence within the selected 30-day snapshot for each row; do not reuse today's baseline or fetch the usual 42-day history. Report early-window cold-start/missing baseline features. Cognitive Score may be reported as context, but is not a valid millisecond prediction reference.
- **At most eight normalized features per model head:**
  - Energy: sleep deviation, one movement value (workout or steps), hydration, combined study/screen load, caffeine, mood, stress, and combined HRV/resting-heart-rate recovery deviation
  - Cognitive: sleep deviation, prior reaction baseline/trend, study, screen time, caffeine, mood, stress, and the same recovery deviation. The reaction measurement being predicted is the label, never an input feature.
- **Missingness:** preserve absent values and shrink their learned effect toward zero; never turn “not logged” into a real zero measurement

The prep output is a local coverage report plus optional JSON/CSV export containing window bounds, source counts, eligible label counts, missingness by feature, and rejected-row reasons. It must not automatically upload the joined rows.

#### Data-readiness gate for this account

- Keep the two outcome heads independent. Energy requires at least 14 distinct genuine, consented labeled days inside the 30-day window. Cognitive remains report-only or unpromoted shadow work until its target, units, and deterministic comparison are explicitly defined; at least 10 valid genuine reaction outcomes is a future minimum, not permission to fit incompatible units. Report reaction outcomes' distinct-day count as well as their total.
- Reserve the newest 20% of eligible labeled local days (round up, minimum three days) as a chronological holdout, keeping every outcome from one day on the same side. Fit any learned normalization/imputation on training rows only, freeze it for holdout, and keep fixed normalization constants independent of this account's holdout. Never randomly mix future observations into training.
- If a head lacks labels, feature coverage, or holdout rows, emit the coverage report and continue using `FatigueEngine`; do not expand beyond the requested 30 days or manufacture labels.
- The implemented conservative coverage gate requires at least four present features
  per eligible Energy row, with inspectable ingestion/update evidence for every
  input used by either learned features or the deterministic reference. Legacy
  unknown availability blocks readiness. Learned mood/stress features use the
  observation day; the reference retains FatigueEngine's existing 36-hour context.
- Until the existing deterministic helpers support arbitrary calendars natively,
  selected account/device historical timezone offsets must agree throughout the
  window for readiness; mismatches remain clearly labeled inspection-only.
  Coach source provenance cannot be verified from these three collections, so
  those labels are rejected as `coach_source_unverified` without adding another query.
- Public datasets may inform terminology and bounded normalization choices later, but the first personalized fit must use only this account’s consented 30-day data.

Acceptance for prep:

- A consented account can generate the same deterministic 30-day snapshot twice without extra Firestore reads on the second run.
- Tests verify the three-query maximum with a shared consent read, server-side document limits, no-write behavior, exact date bounds, consent rejection, cache invalidation for edits/deletes, missing features, prior-only baselines, whole-day temporal holdout, training-only normalization, label-unit compatibility, and exclusion of synthetic rows from readiness/training.
- The coverage report makes it obvious whether Energy, Cognitive, both, or neither model head is ready.
- No Security Rules change permits cross-user reads or introduces a shared training-data tree.

#### Verified account prep inspection — 2026-09-05

- Cloud user metadata was schema version 7, last updated 2026-08-18: `outcomeCollection` was false and `trainingRecordUse` was absent. No `outcomes` collection was visible during the inspection.
- The locally cached 30-day window, 2026-07-02 through 2026-07-31 inclusive, contained 222 signals and 60 check-ins. All were identified as synthetic from IDs/notes; the cache contained zero outcomes.
- This window supports pipeline QA only. Neither head is ready for personalized training, and enabling consent later must not silently turn these seeded records into real labels. The inspection made no cloud writes.

#### Completed implementation and live verification — 2026-09-05

- Implemented `ml_prep_models.dart`, `ml_prep_repository.dart`,
  `ml_prep_service.dart`, `ml_prep_builder.dart` and the Profile prep screen.
  Dedicated prep interfaces expose no writes, listeners or broad account replacement.
- The signed-in simulator fetched `[2026-07-02T07:00:00Z,
  2026-08-01T07:00:00Z)` in America/Los_Angeles at
  `2026-09-05T21:37:48.302808Z`. The current account metadata is schema 11;
  both consent flags evaluated false. This supersedes the earlier schema-7
  metadata inspection, not its historical findings.
- The live bounded snapshot returned **222 signals, 60 check-ins and 0 outcomes**.
  All 282 input documents were identified as synthetic. Energy and Cognitive
  each have **0 eligible labels and 0 labeled days**: neither is training-ready.
- The first prep run showed **3 collection queries + 1 shared user-document read,
  282 returned collection documents, 0 writes**. Reopened July prep showed
  **0 queries, 0 metadata reads and 0 writes**, reusing the same fetched-at time
  and fingerprint `4e07fa57d07bc0a3-77234`. These counts cover prep only, not the
  app's pre-existing startup/sync workflows or Firestore billing overhead.
- Private local report: `build/ml-prep/REPORT.md` and `coverage.json` (ignored by
  Git). `tool/export_ml_prep.dart` rebuilds the report from the saved prep cache
  without network access. No historical outcomes were backfilled, consent was
  not changed, and no model was trained or promoted.

### Version 0.32 — Personalized ML Model — Implemented; release QA pending

- Implement a tiny per-user Energy residual model: `personalized prediction = FatigueEngine prediction + bounded learned correction`, trained against the fixed 0–100 observed-energy target above. Cognitive remains report-only/unpromoted until a separate compatible target/reference specification is defined in this plan; raw reaction milliseconds are never score-point residuals.
- Use fixed-regularization ridge regression with no neural network, no LLM call, no ML framework, no hyperparameter sweep, and no cross-user training. Keep each head to at most eight feature weights plus an intercept.
- Train and infer on-device from the cached 30-day `TrainingExample` set. Target an artifact under 4 KB, training under 100 ms, inference under 1 ms, and less than 1 MB temporary working memory in a release build.
- Clamp the learned correction to ±10 score points and shrink it toward zero as inputs become missing or stale.
- Promote a head out of shadow mode only when chronological holdout error improves on the deterministic reference by at least 5% and no safety/bounds test regresses. Otherwise discard the candidate and keep `FatigueEngine` unchanged.
- Retrain only after a new eligible outcome exists, never more than once per 24 hours, and only from an explicit foreground model refresh. Health sync, app launch, forecasts, and screen navigation must not trigger training.
- Keep weights and the training snapshot on-device. After an accepted model changes, use one targeted merge write (never `replaceUser`) for small metadata only: model/schema version, window bounds, trained-at time, label count, holdout error, deterministic comparison, and feature-coverage summary.
- Do not write per-inference predictions or duplicated training examples to Firestore; continue using the existing daily `scoreSnapshots` persistence path.
- Always retain deterministic scoring as the instant fallback for insufficient data, revoked consent, corrupt artifacts, slower-than-budget inference, or validation underperformance.

#### Implemented on September 7, 2026

- Added the fixed nine-parameter ridge kernel, strict checksummed local artifact,
  owner-keyed local training ledger, and a separate **Refresh Energy model**
  action in **Profile → Model preparation**. Prepare/inspect remains read-only.
- Training consumes the already-prepared, still-valid 30-day snapshot; it cannot
  fetch data. It independently validates whole-day splits, provenance, units,
  cutoff availability and missingness. The newest 20% of days are held out;
  accepted weights use training rows only and are never refitted on the holdout.
- The local ledger requires a new eligible Energy outcome and 24 hours between
  attempts, including rejected fits; it survives ordinary restart/sign-out.
  Async account, consent and data changes cancel pending promotion safely.
- Missing/stale features attenuate weights and intercept. Inference changes only
  Energy by at most ten points; Cognitive and confidence are unchanged. Daily
  snapshots retain deterministic Energy for immediate fallback on another
  device or after consent/model loss. No per-inference writes are introduced.
- Accepted changes write only the small `users/{uid}.personalizedEnergyModel`
  summary using one targeted merge. Weights/examples remain local. Failure of
  that metadata write does not trigger background retry or discard a valid
  local model. New/changed summaries are owner/dual-consent gated in local rules.
- New manual records now preserve `recordedAt` separately from observation time
  (schema 12), including edits. Legacy timestamps are not manufactured. Exact
  duplicate sleep imports preserve the original availability timestamp.
- The existing July account inspection still has **zero eligible labels**;
  nothing was trained/promoted for that account, consent was not changed, and
  this implementation performed no live Firebase reads/writes.
- Remaining verification: release-mode iPhone latency and **actual per-fit heap**
  (<1 MB target, not inferred from numeric-buffer estimates or process RSS),
  and production Firestore deployment/IAM validation (emulator coverage passed
  during 0.34). See `ENERGY_MODEL.md` for the
  reproducible Mac AOT benchmark and limitations. Version 0.33 is tracked below.

### Version 0.33 — Model Transparency ✅

- Display model version, confidence, and last update from Firebase user/model metadata
- Explain the signals driving each prediction via `scoreSnapshots.drivers`
- Distinguish measured, estimated, and missing data using `source` / completeness from the Version 0.10-a schema

#### Implemented on September 7, 2026

- Added **Today → Why these scores?** and **Profile → How your scores work**,
  with a read-only Energy/Cognitive selector, evidence-quality confidence,
  expandable ranked saved drivers and explicit missing-input inventory.
- Separated rules-model version, the correction actually applied to this score,
  a valid local model, and Firebase's historical metadata-only summary. A summary
  never claims to install weights or activate personalization on another phone.
- Displayed score calculation, model training, account-document update and
  metadata-load times distinctly. Older snapshots retain unknown model versions,
  source provenance and calculation times rather than acquiring invented values.
- Schema 13 adds small rules-version and current/recent observation provenance
  fields to ordinary daily snapshots. All recorded observation sources, recognized
  demo markers and unknown/mixed sources are represented conservatively;
  historical baseline provenance remains explicitly unverified.
- Confidence remains the existing evidence heuristic, not a probability of being
  correct. Energy's capped seven-input counter is explained separately from its
  ten-factor inventory. Zero-point observed inputs are present, absent inputs are
  not zero, and neither training nor duplicate records automatically raises
  confidence. No scoring formulas or model-training gates changed.
- Existing account reads supply the strictly validated model summary. Opening,
  selecting or expanding the screen adds no reads, writes, listeners or training.
  Cached metadata is owner-scoped and dated, and sign-out hides private details.
  Session/generation guards also prevent delayed old-account or superseded score
  loads from restoring stale drivers to the current screen.
- Automated parser, projection, repository-budget, account/offline, legacy,
  navigation and narrow/large-text UI tests pass; rendered widget captures were
  visually checked. See [transparency notes](MODEL_TRANSPARENCY.md). No live
  account changes, model promotion, rules deployment or iPhone installation were
  performed. Version 0.32 device/heap and deployment release checks remain open.

## Upcoming Versions

### Version 0.34 — Privacy and Youth Safety — implemented; youth launch gated

- Add age-appropriate onboarding and consent; store consent timestamps on `users/{uid}`
- Add guardian consent where legally required
- Complete export and deletion against the full Version 0.10-a user subtree; review wellness language
- Audit Security Rules so minors’ data cannot be listed or shared across accounts

Implemented September 7, 2026: neutral pre-account age/region review; explicit
server-timestamped privacy and separate optional-learning receipts; required
review for legacy accounts; conservative trusted-claim guardian gate; complete
known-schema raw export and reauthenticated, journaled, retry-safe deletion;
owner-only allowlisted rules and executable emulator coverage. New tracking,
Health imports and learning pause during privacy/deletion recovery. Privacy
screens include deliberate clipboard/deletion confirmation, honest scope and
device-only recovery. See [privacy safety notes](PRIVACY_SAFETY.md).

**Not a completed youth release:** launch countries/ages and a real verified
guardian service have not been selected. Under-18 use remains blocked unless a
trusted backend supplies reviewed verification. Production rule deployment/IAM,
guardian withdrawal/correction, retention/provider-backup policy and real-iPhone
lifecycle QA remain required. No live-account data or consent was modified.

### Version 0.35 — Production Polish

- Complete accessibility and dynamic-type improvements
- Harden offline, error, interrupted-test, and Firestore sync conflict handling
- Complete performance, security, real-device, and App Store readiness testing

## Stable Data Interfaces

- `SignalReading`: measurement type, value, unit, observation timestamp, source, quality, optional sync timestamp and current-version `recordedAt` availability → Firestore `users/{uid}/signals/{id}`
- `DailyCheckIn`: morning/evening period, energy, mood, stress (1–10), optional notes and current-version `recordedAt` availability → `users/{uid}/checkIns/{id}`
- `OutcomeRecord`: consented observed energy or cognitive reaction value, timestamps, source link, consent version, and optional recommendation link → `users/{uid}/outcomes/{id}`
- `TrainingExample` (prep for 0.32): on-device / export-only join from one bounded 30-day account snapshot, linking a day-scoped feature vector + missingness mask to one consented `OutcomeRecord`; not a cross-user Firestore collection
- `ScoreSnapshot`: Energy Score, Cognitive Score, confidence, calculation time, rules versions and drivers with optional current/recent observation source/demo provenance → `users/{uid}/scoreSnapshots/{id}`; legacy unknown fields remain unknown
- `EnergyResidualModel` (0.32): checksummed owner-scoped local artifact; only compact accepted-fit metadata enters `users/{uid}.personalizedEnergyModel`. Personalized score snapshots preserve deterministic Energy and model version for safe fallback.
- `EnergyModelSummary` / `ModelTransparencyState` (0.33): strict read-only account metadata projection plus the already-loaded score; never executable weights, training labels or additional database requests
- `PersonalBaselines`: rolling HRV, resting-heart-rate, sleep, and reaction-time references with sample maturity → embedded in the private daily `scoreSnapshots` document
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
- Personalized prep/training stays foreground-only, bounded to one account window, and may not add recurring database reads or per-inference writes.
- From Version 0.10-a onward, new persisted features should use the Firebase schema and user-scoped queries; local cache is allowed for offline use.
- Tonyo is a wellness and performance tool, not a diagnostic medical product.
