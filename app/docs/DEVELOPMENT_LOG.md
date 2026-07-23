# Tonyo Development Log

## Project Overview
- **App Name:** Tonyo
- **Purpose:** Private, explainable fatigue and energy coaching for students and athletes — check-ins, reaction benchmarks, scores, forecasts, and recovery guidance (wellness tool, not a diagnostic product).
- **Target Users:** Adolescent students and student athletes who want to balance focus, training, and recovery.
- **Current release:** Version 0.9 — Reaction-Time Test (as of 2026-07-23)

## Implementation Report (through v0.9)

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
| 0.10+ | Daily history, scores, forecast engine, HealthKit, AI coach, etc. | Not started |

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

### Verification
- Command: `flutter test` (from `app/`)
- Last verified: 2026-07-23 — **29 tests passed** after post-merge syntax repairs

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
11. Daily history (edit/delete by date) - Not started (v0.10)

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

### 2026-07-23 (closeout) — Implementation report + post-merge test repair

**Goal:** Refresh this development log to reflect completion through v0.9 and confirm the full suite is green on `main`.

**Results:**
- Documented an Implementation Report table covering v0.1–v0.9 and next upcoming work.
- Fixed merge damage that broke the build: missing `}` on `CheckInPeriodLabel` in `models.dart`, and a missing `});` closing the v0.9 rejection test in `app_controller_test.dart`.
- Tidied garbled Version 0.7 / 0.9 bullets in `PLAN.md`.
- Re-ran `flutter test` after repairs: **29 tests passed**.

**Major issues:**
- Post-merge syntax errors nested `ActivityLogEntry` / later classes inside the check-in period extension and left a dangling test body — compile failed until braces were restored.

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

### Docs: Implementation report closeout
**Prompt:**
"update development log with current implementation report, we have completed up to .9. double check all tests pass"

**Result:** Implementation report added; merge syntax fixes applied; test suite re-verified.

**Modifications:** _(none expected beyond this log update)_

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

## What I Learned
- Fixture-backed UI previews are not “done” until data is validated, persisted, and covered by tests (`PLAN.md` release rules).
- Extracting pure helpers (`CheckInLogic`, `ReactionTestLogic`) makes feature behavior easy to unit test without driving the full UI.
- Widget tests against scrollable forms need explicit scroll-into-view for lazily built children.
- Keep rating-scale migrations keyed to a clear schema signal (e.g. new fields), not raw numeric ranges alone.
- After merging parallel feature branches, re-run the full test suite immediately — small brace mismatches can look like “missing types” across the whole app.

## Future Improvements
- [ ] Implement Version 0.10 — fuller Daily History (edit/delete by date)
- [ ] Implement Version 0.11+ Energy / Cognitive scores and Today dashboard
- [ ] Keep this log updated each working day before merge/PR
- [ ] Backfill earlier versions (0.1–0.7) prompt entries if curriculum requires a complete prompt history
