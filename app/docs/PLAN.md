# Tonyo Product Roadmap

Last updated: July 21, 2026  
Current release: **Version 0.5.1 — Account and Navigation Update**

Tonyo is developed through small, runnable releases. Fixture data is used first so each screen can be demonstrated before manual inputs, device integrations, and personalized predictions are introduced.

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

### Version 0.5.1 — Account and Navigation Update ✅ Current

- Welcome continues into local account creation before personal-model setup
- Account setup validates email and password confirmation without persisting the password
- Forecast and Insights share one bottom-navigation destination with an in-screen switcher
- AI Coach has a dedicated bottom-navigation destination
- Profile displays the locally saved account email
- Automated tests cover the new account flow and navigation structure

## Upcoming Versions

### Version 0.6 — Manual Activity Log

- Record hydration, study time, exercise load, and screen time
- Validate values and reject impossible entries
- Edit and add data through the center navigation action

### Version 0.7 — Manual Sleep Log

- Record bedtime, wake time, and sleep quality
- Calculate sleep duration and bedtime consistency
- Display recent sleep entries

### Version 0.8 — Mood and Stress Check-In

- Promote the Daily Check-in preview into a completed feature
- Store morning and evening energy, stress, and mood ratings
- Display saved check-ins in daily history

### Version 0.9 — Reaction-Time Test

- Promote the Reaction Test preview into a completed daily benchmark
- Detect early taps and invalid attempts
- Compare valid results with a personal baseline

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
- `DailyCheckIn`: energy, mood, stress, and optional notes
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
