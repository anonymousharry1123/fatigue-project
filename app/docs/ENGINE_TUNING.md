# FatigueEngine Tuning Loop (Cohort Lab + Versions 0.11–0.12)

Use this checklist whenever you change scoring weights. The synthetic cohort
(~3000 students) is the shared simulator; Versions 0.11–0.12 persist Energy
and Cognitive scores through the live-app path. Keep both aligned.

## Goals

- Change one driver family at a time (sleep, screen, exercise, caffeine, check-in).
- Verify directionality on Cohort Lab plots before shipping.
- Re-check a real signed-in account’s Today energy after Publish is optional;
  local **Load CSV → Recompute** is enough for most loops.

## Preconditions

1. Branch includes Cohort Lab (`Profile → Developer → Cohort Lab`).
2. App can load `assets/data/synthetic_students.csv`.
3. You know which `FatigueEngine` APIs Versions 0.11–0.12 use for live scores
   (usually `score()` / shared snapshot writers in `AppController`).
4. Optional Firebase path: run with
   `--dart-define-from-file=config/firebase_options.json`, signed in, rules
   deployed for `syntheticUsers` / `syntheticCohort`.

## Loop (repeat per tuning change)

### 1. Baseline

- [ ] Open **Cohort Lab → Load CSV** (or **Recompute** if already loaded).
- [ ] Record Overview: `N`, mean/median **Energy**, mean/median **Cognitive**.
- [ ] Glance Relations: sleep→energy/cognitive, screen→energy, caffeine→energy.
- [ ] Spot-check 3 outlier people via **People → Sort**:
  1. Sort **Sleep ↑ low** → open the first 3 → confirm low sleep pulls energy down and Sleep appears in drivers.
  2. Sort **Screen ↓ high** → open the first 3 → confirm high folded screen shows up in Energy drivers.
  3. Sort **Caffeine ↓ high** → open the first 3 → confirm caffeine driver sign matches intake (mild + vs excess −).
  Optional extras: **Energy ↑ low**, **Stress ↓ high** if you are tuning check-in weights.

### 2. Hypothesize

Write one sentence before editing code, e.g.:

> “Increasing sleep weight by ~20% should raise mean energy and steepen the
> sleep→energy scatter without collapsing confidence.”

### 3. Change one place

Edit only the relevant block in [`lib/src/fatigue_engine.dart`](../lib/src/fatigue_engine.dart):

| Driver | What to touch | Cohort signal to watch |
|--------|---------------|------------------------|
| Sleep | sleep → energy (and cognitive sleep term) | Relations → Sleep vs Energy |
| Screen | Energy screen-time penalty | Screen+social vs Energy |
| Exercise | daily load thresholds (CSV uses weekly/7) | Exercise vs Energy |
| Caffeine | mild + for 0–2 drinks, − for excess | Caffeine vs Energy |
| Check-in | Energy and Cognitive mood/stress terms | People with high `stress_level` / burnout |
| Reaction | Cognitive personal-baseline term | Live fixtures/tests only; CSV has no reaction column |
| Confidence | per-model input coverage | Overview confidence via person detail |

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

### 6. Live app sanity (Versions 0.11–0.12)

- [ ] On a normal account with manual sleep/activity/check-in, Today energy
      still looks explainable (drivers match what you logged).
- [ ] Complete a reaction test and confirm Cognitive explains reaction, sleep,
      study, mood, and stress without mixing in Energy-only drivers.
- [ ] Confirm `scoreSnapshots` stores both scores after logging data (or after
      the controller’s score refresh path), with yesterday comparison when a
      prior Cognitive snapshot exists.
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

## Joint workflow after merging Cohort Lab + Versions 0.11–0.12

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
