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
