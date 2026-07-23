# Tonyo Development Log

## Project Overview
- **App Name:** Tonyo
- **Purpose:** Private, explainable fatigue and energy coaching for students and athletes — check-ins, reaction benchmarks, scores, forecasts, and recovery guidance (wellness tool, not a diagnostic product).
- **Target Users:** Adolescent students and student athletes who want to balance focus, training, and recovery.

## Features Implemented
1. App shell & navigation (Today, Forecast, Add, Insights, Profile) - Complete (v0.1)
2. Dark visual foundation & shared widgets - Complete (v0.2)
3. Welcome / onboarding screen - Complete (v0.3)
4. User profile (name, role, schedule, goals) - Complete (v0.4)
5. Local storage & persistence - Complete (v0.5)
6. Mood & stress daily check-in (1–10, auto morning/evening from clock, history) - Complete (v0.8)
7. Reaction-time daily benchmark (early taps, invalid attempts, baseline) - Complete (v0.9)
8. Manual activity log - Not started (v0.6)
9. Manual sleep log - Not started (v0.7)
10. Daily history (edit/delete by date) - Not started (v0.10)

## Day-to-Day Entries

### 2026-07-23 — Versions 0.8 & 0.9 (check-in + reaction test)

**Branch:** `feature/v0.8-v0.9-checkin-reaction`

**Goal:** Promote Daily Check-in and Reaction Test from previews into completed roadmap features; use an intuitive 1–10 scale for mood/stress; add automated tests.

**Results:**
- Check-ins store morning/evening energy, mood, and stress on a 1–10 scale with optional notes and on-screen history.
- Reaction test requires three valid rounds; early taps and out-of-range times are discarded; results compare to a personal baseline.
- Added `CheckInLogic` and `ReactionTestLogic` helpers; updated fatigue engine thresholds for 1–10 ratings.
- App version bumped to `0.9.0`; `PLAN.md` marked 0.8/0.9 complete.
- All automated tests passed (`flutter test` — 21 tests).

**Major issues:**
- Widget test failed initially because lazy `ListView` had not built “Stress” / history sections off-screen — fixed by scrolling until visible in the test.
- Rating migration risk: doubling any value ≤5 on reload would corrupt real 1–10 data — fixed by only migrating legacy check-ins that lack a `period` field.

### 2026-07-23 (later) — Auto morning/evening + docs + PR prep

**Goal:** Stop allowing manual morning/evening overrides on Daily Check-in; add development log process; prepare branch for PR to main.

**Results:**
- Period is derived only from check-in timestamp (`periodFor`: morning before 2:00 PM, evening afterward).
- UI shows a read-only period banner instead of a segmented control.
- Added `DEVELOPMENT_LOG.md` and agent update instructions in `PLAN.md`.

**Major issues:** None beyond the product rule that evening check-ins must not be mislabeled as morning.

---

## Prompts Used

### Feature: Versions 0.8 & 0.9 check-in and reaction test
**Prompt:**
"setup a new feature branch, follow plan.md in docs

-complete versions .8 and .9

-for mood and stress i want it to be an intuitive scale 1-10
-add tests for functionality"

**Result:** Feature branch created; Daily Check-in and Reaction Test promoted to completed features; 1–10 scales; persistence + baseline comparison; new unit/widget tests; `PLAN.md` and `pubspec` updated.

**Modifications:** None required beyond the agent’s implementation pass (tests green after scroll fix).

### Docs: Development log process
**Prompt:**
"before we merge to main, ongoing we want to implement a development log md file. i will post a starting template, this template should be updated with major issues, important details of prompts, and results from prompts and work in a day to day. implement a new development log md file and instructions for future agents on how to use the file in plan.md file"

**Result:** Created this `DEVELOPMENT_LOG.md` and added agent instructions in `PLAN.md`.

**Modifications:** _(fill in if you edit the log structure after generation)_

### Feature: Auto morning/evening check-in + PR prep
**Prompt:**
"change daily checkin to automatically determine morning or evening input of energy,mood, stress. right now you can manually change to a morning checkin even if your checking in at evening! after this commit all changes to branch. publish branch and prepare for PR to main. setup pr name and description. i will complete the pr manually on the github web portal"

**Result:** Removed manual period selector; `addCheckIn` always sets period from timestamp; docs/log updated; branch committed and published for a manual PR.

**Modifications:** None expected beyond review on GitHub.

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

## What I Learned
- Fixture-backed UI previews are not “done” until data is validated, persisted, and covered by tests (`PLAN.md` release rules).
- Extracting pure helpers (`CheckInLogic`, `ReactionTestLogic`) makes feature behavior easy to unit test without driving the full UI.
- Widget tests against scrollable forms need explicit scroll-into-view for lazily built children.
- Keep rating-scale migrations keyed to a clear schema signal (e.g. new fields), not raw numeric ranges alone.

## Future Improvements
- [ ] Implement Version 0.6 — Manual Activity Log
- [ ] Implement Version 0.7 — Manual Sleep Log
- [ ] Implement Version 0.10 — fuller Daily History (edit/delete by date)
- [ ] Keep this log updated each working day before merge/PR
- [ ] Backfill earlier versions (0.1–0.5) prompt entries if curriculum requires a complete prompt history
