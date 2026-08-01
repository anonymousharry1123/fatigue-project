# FatigueEngine Tuning Loop (Cohort Lab + Version 0.11)

Use this checklist whenever you change scoring weights. The synthetic cohort
(~3000 students) is the shared simulator; Version 0.11’s persisted energy
snapshots are the live-app path. Keep both aligned.

## Goals

- Change one driver family at a time (sleep, screen, exercise, caffeine, check-in).
- Verify directionality on Cohort Lab plots before shipping.
- Re-check a real signed-in account’s Today energy after Publish is optional;
  local **Load CSV → Recompute** is enough for most loops.

## Preconditions

1. Branch includes Cohort Lab (`Profile → Developer → Cohort Lab`).
2. App can load `assets/data/synthetic_students.csv`.
3. You know which `FatigueEngine` APIs Version 0.11 uses for live energy
   (usually `score()` / energy snapshot writers in `AppController`).
4. Optional Firebase path: run with
   `--dart-define-from-file=config/firebase_options.json`, signed in, rules
   deployed for `syntheticUsers` / `syntheticCohort`.

## Loop (repeat per tuning change)

### 1. Baseline

- [ ] Open **Cohort Lab → Load CSV** (or **Recompute** if already loaded).
- [ ] Record Overview: `N`, mean/median **Energy**, mean/median **Cognitive**.
- [ ] Glance Relations: sleep→energy, screen→cognitive, caffeine→energy.
- [ ] Spot-check 3 People IDs (low sleep, high screen, high caffeine).

### 2. Hypothesize

Write one sentence before editing code, e.g.:

> “Increasing sleep weight by ~20% should raise mean energy and steepen the
> sleep→energy scatter without collapsing confidence.”

### 3. Change one place

Edit only the relevant block in [`lib/src/fatigue_engine.dart`](../lib/src/fatigue_engine.dart):

| Driver | What to touch | Cohort signal to watch |
|--------|---------------|------------------------|
| Sleep | sleep → energy (and cognitive sleep term) | Relations → Sleep vs Energy |
| Screen | screen time penalty | Screen+social vs Cognitive / Energy |
| Exercise | daily load thresholds (CSV uses weekly/7) | Exercise vs Energy |
| Caffeine | mild + for 0–2 drinks, − for excess | Caffeine vs Energy |
| Check-in | energy/stress/mood terms | People with high `stress_level` / burnout |
| Confidence | expected-signal set / present ratio | Overview confidence via person detail |

Do **not** retune hydration/HRV/reaction using this CSV alone — those columns
are not in the synthetic file (unless you add fixtures).

### 4. Recompute

- [ ] Hot restart or relaunch if needed.
- [ ] Cohort Lab → **Recompute**.
- [ ] Compare new mean/median energy & cognitive to the baseline.
- [ ] Confirm the target scatter moved in the hypothesized direction.
- [ ] Confirm other scatters did not wildly invert (no “fix everything”).

### 5. Guardrails (fail the change if any fail)

- [ ] Energy and cognitive stay in **0–100** for sampled people.
- [ ] Mean energy does not jump more than ~8 points from a small weight tweak
      (unless intentional); large jumps usually mean a clamp or baseline bug.
- [ ] Drivers list still names the edited factor on person detail.
- [ ] `flutter test` passes — especially `test/fatigue_engine_test.dart` and
      `test/synthetic_cohort_test.dart`.

### 6. Live app sanity (Version 0.11)

- [ ] On a normal account with manual sleep/activity/check-in, Today energy
      still looks explainable (drivers match what you logged).
- [ ] If 0.11 persists `scoreSnapshots`, confirm a new snapshot after logging
      data (or after the controller’s score refresh path).
- [ ] Fixture / empty-signal users still get a bounded score (no NaN / crash).

### 7. Optional share with teammate

- [ ] **Export** clipboard JSON (sample) or **Publish** cohort summary for
      Console comparison.
- [ ] Note baseline vs new means in the PR / chat:
      `energy 61→64, cognitive 58→57, sleep slope steeper`.

### 8. Stop or iterate

- [ ] If hypothesis confirmed → commit the engine change alone (small diff).
- [ ] If not → revert the weight, adjust hypothesis, repeat from step 2.
- [ ] Never combine unrelated UI refactors with a scoring tweak in one commit.

## Joint workflow after merging Cohort Lab + 0.11

1. Merge this feature into `main` (Cohort Lab side track).
2. Pull `main` so both of you share the same `FatigueEngine` + CSV asset.
3. Pick **one** driver per day to tune together using this checklist.
4. Prefer PRs titled like `tune: strengthen sleep energy weight` with before/after
   Overview numbers in the body.
5. Keep synthetic Publish for demos; do not treat synthetic scores as clinical
   labels for ML (that waits on consented outcomes in later roadmap versions).

## Quick commands

```powershell
cd app
flutter test test/fatigue_engine_test.dart test/synthetic_cohort_test.dart
flutter run -d edge --dart-define-from-file=config/firebase_options.json
```

In app: **Profile → Cohort Lab → Load CSV → Recompute**.
