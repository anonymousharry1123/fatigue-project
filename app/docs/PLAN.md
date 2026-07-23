# Tonyo Product Roadmap

Last updated: July 23, 2026  
Current release: **Version 0.9 — Reaction-Time Test**

Tonyo is developed through small, runnable releases. Fixture data is used first so each screen can be demonstrated before manual inputs, device integrations, and personalized predictions are introduced.

## Development Log (required for agents)

Keep a running narrative of day-to-day work in [`DEVELOPMENT_LOG.md`](./DEVELOPMENT_LOG.md). The product roadmap below tracks *what* ships; the development log tracks *how* it was built (prompts, results, issues, learnings).

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
- Update **`DEVELOPMENT_LOG.md`** with the prompt trail, issues, and daily outcomes for that work.
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

### Version 0.9 — Reaction-Time Test ✅ Current

- Reaction Test is a completed daily benchmark with three valid rounds
- Early taps and out-of-range attempts are detected and discarded
- Valid results compare against a personal reaction-time baseline
- Automated tests cover check-in ratings, reaction validation, baselines, and persistence

## Upcoming Versions

### Version 0.10 — Daily History

- Group signals and check-ins by date
- Edit or delete manual entries
- Display completion status for each day

### Version 0.11 — Basic Energy Score

- Calculate an explainable 0–100 Energy Score
- Use sleep, exercise, hydration, workload, screen time, mood, and stress
- Clearly label the score as an estimate

### Version 0.12 — Cognitive Score

- Calculate an explainable 0–100 Cognitive Score
- Use reaction time, sleep, stress, mood, and study load
- Compare the result with the previous day

### Version 0.13 — Today Dashboard

- Replace Today fixtures with calculated Energy and Cognitive scores
- Display Fresh, Moderate, or Fatigued status
- Show recent-signal summary cards

### Version 0.14 — Score Drivers

- Rank positive and negative score contributions
- Explain each contribution
- Calculate confidence from signal completeness and freshness

### Version 0.15 — Forecast Engine

- Generate hourly energy estimates from collected signals
- Incorporate sleep timing, circadian rhythm, workload, and recovery
- Return uncertainty with each forecast point

### Version 0.16 — Forecast Screen

- Replace the Forecast preview with calculated Today and Tomorrow curves
- Add daily summaries to the Week view
- Handle missing and low-confidence data

### Version 0.17 — Key Windows

- Identify peak-focus, predicted-crash, and recovery windows
- Explain the signals supporting each window

### Version 0.18 — Basic Recommendations

- Recommend study, nap, exercise, hydration, and recovery times
- Match recommendations to forecast windows
- Ground every recommendation in recent data

### Version 0.19 — Fatigue Warnings

- Detect sustained sleep debt
- Detect possible training overreaching
- Detect sustained low-energy and high-stress patterns without diagnosis

### Version 0.20 — Notifications

- Add opt-in crash and recovery alerts
- Add notification timing and category controls
- Suppress duplicate and low-confidence alerts

### Version 0.21 — Insights Dashboard

- Promote the Insights preview into calculated daily and weekly trends
- Add sleep, training, and study contribution charts
- Explain model associations without presenting them as proven causes

### Version 0.22 — HealthKit Permissions

- Explain each requested permission
- Support approval, denial, and revocation
- Preserve manual entry when access is unavailable

### Version 0.23 — Heart Data Sync

- Import HRV and resting heart rate
- Normalize units, timestamps, sources, and duplicates

### Version 0.24 — Sleep Architecture Sync

- Import awake, core, deep, REM, and unspecified sleep stages
- Reconcile overlapping samples and multiple sources
- Prefer imported sleep only when it is more complete than manual data

### Version 0.25 — Workout and Hydration Sync

- Import workouts and available hydration samples
- Derive daily training load
- Retain manual correction and fallback controls

### Version 0.26 — Continuous Refresh

- Refresh HealthKit data as iOS permits
- Track source, freshness, and sync status
- Recalculate only when meaningful input changes

### Version 0.27 — Personal Baselines

- Build rolling HRV, resting-heart-rate, sleep, and reaction-time baselines
- Compare users with their own history
- Reduce confidence until enough baseline data exists

### Version 0.28 — Screen-Time Enhancement

- Keep manual screen time as the dependable model input
- Add a privacy-preserving Device Activity report if entitlement access is approved
- Keep protected activity data inside Apple’s report-extension sandbox

### Version 0.29 — AI Coach Daily Plan

- Promote the AI Coach preview into a generated morning-to-evening plan
- Schedule deep work, naps, training, tapering, and recovery
- Resolve conflicting goals using confidence and user priorities

### Version 0.30 — Recommendation Feedback

- Accept, dismiss, and complete recommendations
- Record whether advice was helpful
- Adjust future recommendation ranking

### Version 0.31 — Outcome Collection

- Collect optional observed-energy ratings
- Use reaction-test results as cognitive outcomes
- Require explicit consent for training records

### Version 0.32 — Personalized ML Model

- Train and evaluate a multimodal fatigue model
- Run approved inference on-device
- Retain deterministic scoring as the fallback

### Version 0.33 — Model Transparency

- Display model version, confidence, and last update
- Explain the signals driving each prediction
- Distinguish measured, estimated, and missing data

### Version 0.34 — Privacy and Youth Safety

- Add age-appropriate onboarding and consent
- Add guardian consent where legally required
- Complete export, deletion, and wellness-language reviews

### Version 0.35 — Production Polish

- Complete accessibility and dynamic-type improvements
- Harden offline, error, and interrupted-test handling
- Complete performance, security, real-device, and App Store readiness testing

## Stable Data Interfaces

- `SignalReading`: measurement type, value, unit, timestamp, source, and quality
- `DailyCheckIn`: morning/evening period, energy, mood, stress (1–10), and optional notes
- `ScoreSnapshot`: Energy Score, Cognitive Score, confidence, and drivers
- `ForecastPoint`: predicted energy, timestamp, and uncertainty
- `ForecastWindow`: peak, crash, or recovery period
- `Recommendation`: action, timing, priority, evidence, and feedback
- `RiskAlert`: warning category, severity, evidence, and dismissal state

## Release Rules

- Every version must remain runnable and demoable.
- Fixture-backed previews do not count as completed roadmap features.
- Manual entry remains available when a device integration is denied or unavailable.
- Deterministic scoring remains available when a personalized model is unavailable or underperforms.
- Tonyo is a wellness and performance tool, not a diagnostic medical product.
