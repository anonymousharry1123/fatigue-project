# FatigueEngine Tuning Log

Fill one row per tuning attempt. Pair with `[ENGINE_TUNING.md](./ENGINE_TUNING.md)`.

Timeline left → right: **observe** → **predict** → **edit** → **measure**.


| Date | Driver            | Overview                     | Relation focus                                                                                                                              | Spot checks                                                                   | Hypothesis                                                                                                           | Change made                                                   | Data changes                                                                                          |
| ---- | ----------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| 8/4  | sleep             | energy 47, cognitive 58      | sleep vs energy - flat positive                                                                                                             | -20 energy for all 3 lowest sleep                                             | +10% to sleep weight, energy median up by 2, sleep energy tighter                                                    | +10% weight                                                   | no energy or cognitive change                                                                         |
| 8/4  | sleep             | energy 47, cognitive 58      | sleep vs energy - flat positive                                                                                                             | -20 energy for all 3 lowest sleep                                             | +50% to sleep weight, energy median up by 2, sleep energy tighter                                                    | +50% weight                                                   | energy 46, median still 47                                                                            |
| 8/4  | sleep             | energy 47, cog 58            | sleep vs energy, flat positive                                                                                                              | -20 energy for all 3 lowest sleep                                             | change clamp from -20,10 to -30,20. expect much steeper graph                                                        | -30,20 clamp                                                  | no energy cog changes, graph steepened slightly                                                       |
| 8/4  | sleep             | energy 47, cognitive 58      | sleep vs energy - flat positive                                                                                                             | -24.8 for 4.4 hours -23.2 for 4.6 hours                                       | sleep weight +50%                                                                                                    | 8->12                                                         | no energy or cognitive change, much steeper graph                                                     |
| 8/6  | cognitive         | energy 47, cognitive 58      | cognitive vs screen+social weak negative                                                                                                    | drives down energy score, but not listed under cog score drivers              | adding a cog score driver of screen time should help make graph stronger.                                            | final impact = ((3 - screen) * 2.5).clamp(-14, 4).toDouble(); | 22.6 hour screen time -14.0 to cognitive score. 1.0 hour screen time +4.0 to cognitive. cog 46 med 45 |
| 8/6  | energy · screen   | E 47 (med 47), C 46 (med 45) | Screen+social vs Energy, weak negative relation                                                                                             | -10 en for 22.6 hr of screen time, -14 cog for 22.6 hr, clamp upper edge      | raising the clamp radius will steepen the graph and pull points closer together                                      | clamp (-10,4) -> (-16,4)                                      | steeper graph sceen+social vs energy, energy 44, med 43, cog unchanged.                               |
| 8/6  | cognitive · sleep | E 44 (med 43), C 46 (med 45) | cognitive vs sleep, weak positive correlation                                                                                               | -30 energy from 4.4hr sleep, -30 4.6 hr. -16 on cognitive for 4.4hr or 4.6 hr | increasing weight of sleep on cognitive will raise the cog energy scores                                             | weight 6 -> 8                                                 | scores unchanged, graph of cog vs sleep more positive correlation                                     |
| 8/6  | energy · caffeine | E 44 (med 43), C 46 (med 45) | Caffeine vs Energy is very sporatic, generally there is a rise in energy at 2 coffee drinks, but any more than that will bring it back down | 8 caffeine drinks -10 to energy, no cog change                                | Stronger excess-caffeine penalty by increassing clamp, have cleared delineations between energy levels from caffeine | edit clamp >2 drinks (-10,0) -> (-15,0)                       | 8 drinks -13.2, needs more weight probably,                                                           |
| 8/6  | energy · caffeine | E 44 (med 43), C 46 (med 45) | Caffeine vs Energy is very sporatic, generally there is a rise in energy at 2 coffee drinks, but any more than that will bring it back down | 8 caffeine drinks -13.2                                                       | raising weight will ensure that many drinks have a big penalty on energy, pullin energy down once drinks go past 4-5 | edit weight >2 drinks 2.2 -> 3                                | 8 drinks -15, graph tighter together. en 43(med 43) cog 46 (med 45)                                   |




## 2026-09-19 — Separate naps from main sleep

Hypothesis: keeping naps outside the main-sleep average, then applying a small
temporary recovery contribution, removes the penalty for taking a nap without
allowing naps to compensate for sustained short main sleep. Main-sleep Energy
and Cognitive weights, and every other driver family, are unchanged.

The rules are versioned `energy-rules-v2-sleep` and `cognitive-rules-v2-sleep`.
`SignalType.sleep` continues to represent main sleep; `SignalType.nap` is a
separate duration whose timestamp is its end. Main sleep still uses up to three
preferred wake dates. Naps do not enter the main-sleep baseline, duration average,
sleep-debt alerts, bedtime, or observed waking schedule.

Nap recovery is a deliberately conservative **product heuristic**:

- Energy contribution: 0 to +3; Cognitive contribution: 0 to +2.
- Duration credit rises linearly up to 30 minutes, then saturates.
- No credit for the first 30 minutes after waking; linear ramp from 30 to
  60 minutes; full credit through 120 minutes; linear decay to zero at six hours.
- Only the strongest eligible nap contributes. Repeated/long naps do not stack
  credits. Overlapping entries and main-sleep overlaps are reconciled upstream.
- Credit applies to the local wake day. Future readings cannot contribute.
- A separate Nap recovery explanation exposes this limited contribution.
  It does not add an input or increase confidence/freshness. Nap-only records
  leave both confidence values at the empty-input floor of 0.2.
- Forecasts remove the current nap credit from the day-wide anchor, then apply
  credit only at relevant times. A nap does not boost the preceding morning or
  the next day's forecast.
- Foreground resume and stale daily-snapshot reads recalculate changing nap
  credit. Immediate resumes and expired zero credit reuse the current result;
  this adds no timer, background training or recurring collection query.

The direction is informed by [NHLBI's sleep-duration guidance](https://www.nhlbi.nih.gov/health/sleep-deprivation/how-much-sleep),
which describes temporary alertness benefits and explains that naps do not
replace the benefits of main sleep, and [NIOSH's sleep-inertia guidance](https://www.cdc.gov/niosh/work-hour-training-for-nurses/longhours/mod7/03.html),
which describes variable impairment immediately after waking. **Neither source
validates these point values or timing constants.** These are bounded model
choices to be evaluated later against consented real outcomes, not clinical
predictions or a claimed accuracy improvement.

Local cohort check at a fixed `2026-09-19 12:00` calculation time, using the
existing 3,000-row CSV through `SyntheticCohortMapper` and `CohortStats`:

| Measure | Before | After |
| --- | ---: | ---: |
| Energy mean / median | 43.271667 / 43 | 43.271667 / 43 |
| Cognitive mean / median | 45.929667 / 45 | 45.929667 / 45 |
| Sleep–Energy correlation | 0.867289 | 0.867289 |
| Sleep–Cognitive correlation | 0.844450 | 0.844450 |
| Screen–Energy correlation | -0.708944 | -0.708944 |
| Caffeine–Energy correlation | -0.102103 | -0.102103 |
| Energy and Cognitive within 0–100 | All 3,000 | All 3,000 |

All 3,000 individual score pairs are unchanged. This is the intended regression
result because the CSV has main-sleep averages and no nap events; the cohort
cannot validate nap benefit or real-world predictive accuracy. Dedicated nap
fixtures verify preserved main-sleep averages/baselines/confidence, limited
positive recovery, time decay, invalid/future/overlap exclusion, main-sleep
deficits remaining, and time-local forecast evidence. Local-day tests cover
both US daylight-saving transitions and UTC-serialized dates.

## Column guide


| Column             | When            | What to write                                                                                                     |
| ------------------ | --------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Overview**       | Before          | N, mean/median Energy & Cognitive (baseline only)                                                                 |
| **Relation focus** | Before          | Which scatter you care about + baseline shape only (e.g. “Sleep vs Energy — positive but flat”). Not the outcome. |
| **Spot checks**    | Before          | Sort + first 3 people; do drivers match?                                                                          |
| **Hypothesis**     | Before edit     | Predicted effect of *your* change (e.g. “+20% sleep weight → mean energy up ~3, sleep→energy steeper”)            |
| **Change made**    | Edit            | Exact code tweak                                                                                                  |
| **Data changes**   | After recompute | Measured deltas: overview before→after, whether the target relation moved as hypothesized, other plots that broke |




### Relations vs hypothesis (not the same)

- **Relation focus** = observation of the *current* plot (“what does Sleep vs Energy look like now?”).
- **Hypothesis** = prediction about *your edit* (“if I change X, that plot / mean should do Y”).
- **Data changes** = whether that prediction came true after Recompute.



## Empty detail block (optional)



### Attempt —

- **Driver:**
- **Overview (before):**
- **Relation focus (before):**
- **Spot checks:**
- **Hypothesis:**
- **Change made:**
- **Data changes (after):**
- **Pass guardrails?** (0–100 / mean jump / drivers named / tests)
- **Keep or revert:**
