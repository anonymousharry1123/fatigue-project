# Tonyo: Biology and Validation Upgrade Plan

Prepared 3 October 2026 from the uploaded `PROJECT_SUMMARY.md` and the evidence registry below.

## Status and scope

This is an implementation specification, not a patch to the application. The Flutter repository itself was not uploaded, inspected, built, or tested here. Repository facts below are reported by the supplied static audit. Confirm them in the actual workspace before changing code. Proposed modules and interfaces do not already exist unless verified in the repository.

Objective: keep Tonyo's existing interface, local-first architecture, provenance controls, consent gates and useful tracking features. Improve the scientific meaning of its outputs. Do not turn a wellness application into an unvalidated diagnostic or treatment system.

Recommended positioning: **a student-focused sleep and alertness companion that explains its evidence, learns from independently observed outcomes, and fits suggestions around real schedules.** This is proposed positioning, not a verified first-in-market claim.

## Instructions for the developer or coding agent

Read the real implementations and their tests first. Implement Phase 1 only in the first change set; leave later research-dependent features documented and disabled. Do not silently deploy, upload data, enable guardian consent, change live accounts, install new cloud services, or collect participant data. Preserve existing user changes. Do not invent scientific coefficients, successful test results, citations, or clinician approval.

The application lives under `fatigue-project/app`; `app/...` below is relative to the repository. It is Flutter/Dart, not a Node web application. Work in small, reviewable changes. When a schema or model changes, explicitly address migration, stale cached results, previously fitted model compatibility and the Firestore serialization path.

## 1. What the existing audit establishes

- Daily Energy/Cognitive scores, forecasts and Coach plans are mainly deterministic rules. An optional, genuinely fitted on-device ridge regression adjusts Energy; Cognitive is not a deployed learned model. See summary lines 229–243.
- Sleep is centered on 7.5 hours in current rules; the profile's age does not modify those equations. Caffeine can receive positive Energy points, and hydration is centered on 2 liters. See lines 157–185 and 462–474.
- The reaction interaction averages three taps and rejects responses outside 100–1500 ms. Its comparison baseline differs from the scoring baseline. See lines 206–218 and 308.
- The bundled 3,000-row CSV is synthetic QA data with unestablished upstream provenance, not 3,000 measured participants or clinical validation. See lines 245–258.
- Current confidence and forecast uncertainty are heuristics, not calibrated probabilities or prediction intervals. See lines 191–200 and 469.
- Guardian verification infrastructure, youth launch policies and device/release checks remain open. Keep those restrictions. See lines 123–144 and 480–497.

## 2. Scientific boundary

Keep these statements distinct in the data model and interface:

1. **Observed:** a user-entered rating, estimated sleep duration, device HRV value or recorded tap latency, with provenance.
2. **Interpreted:** how a measurement relates to an applicable guideline or the user's previous comparable measurements.
3. **Predicted:** a specific future observation, with a defined target time and demonstrated prospective error when available.
4. **Recommended:** a conservative action selected from an evidence-reviewed catalog.

An Energy score is not ATP production, caloric energy, disease status or physiological recovery measured directly. A short reaction task is not a measurement of intelligence or all cognitive abilities. HRV is not a direct measurement of cortisol, a diagnosis of stress, or proof of autonomic recovery. A statistical association is not proof of causation. These distinctions should appear in concise user-facing copy, not only in legal text.

## Phase 1: Correct unsupported assumptions and misleading states

### A. Age-appropriate sleep interpretation

Suggested new pure-Dart module: `app/lib/src/age_sleep_guidance.dart`.

The AASM recommendation is 8–10 hours per 24 hours for ages 13–18 [S1]. Apply the appropriately reviewed teen rule to the existing 13–15 and 16–17 bands. The existing `18plus` band does not distinguish an 18-year-old from older adults; do not silently assume every adult belongs to the teen guidance group. Preserve the under-13 restriction and use separately reviewed guidance for any other supported group.

Expose descriptive fields rather than replacing one arbitrary score formula with another:

- Most recent completed main-sleep estimate, its date, source and coverage.
- Deduplicated estimated total sleep in a clearly defined 24-hour window, including separately identified naps.
- Recent main-sleep duration trend, with observed-night count and missing dates.
- Bedtime/wake-time regularity using circular clock arithmetic and explicit local-date/time-zone handling.
- A guideline comparison when the observation window is sufficiently complete.

Do not treat time in bed as instrument-measured sleep; preserve the distinction for manual estimates. Do not assume missing nights were zero hours. Do not assert that a nap has precisely the same restorative effect as the same duration of nighttime sleep. Do not label a 7.5-hour main sleep as total insufficient sleep without considering whether the applicable 24-hour record is complete and contains additional sleep.

Separate **usual for this person** from **within the age-group recommendation**. A chronically short personal baseline must not redefine adequate sleep downward. Being within a guideline range does not prove complete recovery or explain persistent symptoms. Do not award ever-increasing health points for ever-longer sleep or recommend shortening sleep to optimize a score.

Until validated weights exist, display sleep facts and the guideline comparison separately from the explicitly experimental composite score. Version any rule change and invalidate incompatible learned residual models.

### B. Remove score incentives and unsupported diagnostic flags

Edit `fatigue_engine.dart`, explanations and corresponding tests:

- Remove caffeine-positive Energy points. Do not suggest caffeine or stimulants to improve alertness or scores. Historical exposure, when already collected with appropriate consent, may be treated as contextual data rather than a recommendation [S2].
- Remove the universal 2-liter optimum and escalating fluid-volume reward. Retain optional logs without claiming liters consumed determine hydration status or readiness. Do not introduce fixed fluid prescriptions.
- Remove automatic exercise-duration bonuses as evidence of recovery and remove the fixed-hours “overreaching” inference. A logged activity total is not a diagnosis. Keep descriptive training history; do not authorize hard training based on Energy or HRV [S8].
- Retire diagnosis-like burnout/overreaching labels. A neutral description of the actual observations is preferable to changing only the wording while retaining the same implied diagnosis.
- Do not prescribe medication, supplements, restrictive eating, intense exercise or sleep restriction. A wellness disclaimer does not validate a recommendation.

### C. Missing data, freshness and uncertainty

Edit `fatigue_engine.dart`, `models.dart`, relevant input logic, Today, Forecast and transparency views:

- With no adequate evidence, show “Not enough information to estimate” rather than presenting the neutral 60/65 defaults as a person's health or readiness.
- Keep **missing**, **explicitly reported zero**, **not available from this device** and **invalid** distinct. Explicit zero activity must survive round trips. Clearing a manual override must remain an explicit action, not the meaning of zero. Do not reinterpret existing missing records as zero.
- Allow old data to contribute to an appropriately documented historical baseline, but do not silently reuse it as a fresh measurement of today's state. Apply the same availability rules during training and serving.
- Rename heuristic confidence to “data coverage/quality” or an equally precise label. Do not render it as percent probability of being correct.
- Label current forecast bands as uncalibrated estimates. Do not call them 95% intervals. Suppress precise peak/crash notifications where support is insufficient.
- Keep the existing evidence IDs, source separation, interruption handling and deterministic fallback rather than replacing those safeguards.

### D. Fix score consistency before adding stronger health interpretations

The summary identifies two source-level issues, not independently reproduced runtime failures: historical Insights uses a different scoring path from Today, and merged Firestore snapshots may retain stale personalized fields (summary lines 370–372).

Inspect, reproduce with focused tests where possible, then fix:

- `insights_logic.dart`: clearly choose saved, versioned historical results or an explicitly labeled recomputation. Do not display silently incomparable series.
- `cloud_schema.dart`, `firebase_services.dart`, `models.dart`: explicitly clear obsolete personalization fields when writing deterministic-only results. Verify reload does not resurrect an old deterministic fallback or personalized model version.

Also make wake/bed schedules editable after onboarding and prevent plan blocks from overlapping fixed commitments or extending into protected sleep time. The existing schedule editor and overlap gaps are described at summary lines 141 and 376.

## Phase 2: Evidence-backed guidance, not an unrestricted medical chatbot

Suggested module: `app/lib/src/health_guidance_catalog.dart`. Integrate through `daily_plan_logic.dart` and `screens/coach_screen.dart`.

Each advice entry should contain:

`id`, `contentVersion`, `supportedAgeBands`, `trigger`, `requiredEvidence`, `exclusions`, `actionText`, `biologyExplanation`, `sourceIds`, `sourcePopulation`, `evidenceLimitations`, `reviewStatus`, `reviewedAt`, and `reviewerRole` when genuinely reviewed.

Use separate review statuses for biological rationale, youth clinical appropriateness and software implementation. Do not fabricate a reviewer. Dr. Lin can review the biological rationale; a pediatrician or sleep clinician should review advice that makes individualized health claims.

Initial conservative content proposals:

| Situation | Proposed response | Evidence and limits |
|---|---|---|
| Complete sleep records fall below the applicable teen recommendation | Explain the recorded duration and the general age-group range; help protect sufficient sleep opportunity around commitments. | AASM [S1]. A range is not an exact estimate of this person's sleep need. |
| Sleep timing varies | Offer a manageable, consistent bedtime/wake routine and a quieter wind-down period. | NHLBI [S3]. Do not rigidly force an earlier wake time that reduces needed sleep. |
| User asks how to replace lost sleep with stimulants | Explain that caffeine is not a substitute for sleep; do not recommend stimulant use. | AAP [S2]. |
| User reports ongoing unexplained tiredness or interference with daily life | Suggest discussing it with a parent/guardian and a healthcare professional; offer an optional factual history export. | NHS care-seeking guidance [S9]. Do not infer a disease or choose tests/treatments. |
| Evidence is weak or conflicting | State what is missing, avoid precision and offer an optional check-in rather than a medical conclusion. | Proposed safety/uncertainty policy, not a validated clinical rule. |

Do not copy adult-specific nap or sleep targets into teen guidance. Avoid automatically scheduling a nap or workout for everyone. Recommendation timing is a scheduling choice, not a clinically proven optimal time.

## Phase 3: Learn a real future outcome

Keep the ridge-regression approach initially. The problem is not a lack of a neural network; it is an insufficiently defined prediction target and evidence of future performance.

### Prediction contract

Start with one explicit product target, such as **a morning prediction of the next scheduled evening self-reported Energy check-in, on its original 1–10 scale**. This is a report of perceived energy, not ground truth for a medical fatigue condition. It uses the existing check-in concept without claiming an hourly validated forecast.

Store a versioned prediction record with `generatedAt`, intended target time/window, endpoint/unit, feature cutoff, input provenance, model version, prediction and later matched observed outcome. Matching rules and acceptable timing differences must be specified in advance. Do not choose the target time retrospectively to improve results. Keep any new cloud collection behind a reviewed schema/rules/export/deletion migration; default to local research scaffolding until approved.

Candidate model structure, **not established physiological coefficients**:

`usual Energy at the target period + learned adjustment for the last sleep + learned adjustment for recent sleep pattern + learned adjustment for time since waking`

Fit coefficients from genuine consented observations; do not choose point weights because they sound biological. Compare each additional feature with a simpler model. Avoid feeding the same sleep signal into several additive terms without checking duplication and collinearity. Use age-guideline comparisons for safe guidance independently of what a fitted association happens to suggest.

Sleep-wake homeostasis and circadian regulation provide a biological rationale for these candidates [S4]. They do not establish that the app measures sleep pressure or internal circadian phase. Clock time and sleep timing are proxies; a sinusoidal curve does not measure melatonin.

### HRV as a later optional addition

The audit reports HealthKit SDNN in milliseconds, not RMSSD. Preserve metric identity. Compare compatible device/source, recording duration, time of day and collection context where available. Unknown context stays unknown. Do not silently pool measurements from breathing sessions, exercise and passive resting collection as equivalent. Retain adequate sample counts, dates and variability with a baseline; readiness cutoffs are engineering choices, not clinical thresholds [S7].

Test whether adding HRV improves prospective prediction over the sleep-only model. Retain it in prediction only when it adds reliable value; retain descriptive tracking otherwise. Never turn one low HRV observation into a diagnosis or exercise clearance.

### Evaluation and acceptance

The current 14-day minimum, small chronological holdout and 5% improvement gate are engineering gates, not evidence of clinical or population validity (summary lines 235–243 and 474).

Proposed evaluation:

- Compare against the person's prior same-period average, the prior comparable observation, and a sleep-only model, using the same cases and time horizon.
- Generate predictions before outcomes arrive. Fit preprocessing and baselines using only historically available data.
- Evaluate multiple forward-in-time test periods and reserve a final untouched prospective period after model selection. Repeated use of the same small holdout is not independent validation.
- Report MAE on the actual target scale, number of distinct people/days, missingness and timing adherence. Do not invent percent “accuracy” for continuous ratings.
- Treat several weeks of data as pilot evidence, not an automatically sufficient sample size. Dr. Lin or a statistical mentor should help plan sample size and the effect worth detecting.
- For claims about new students, hold out whole participants as well as time. A personalized model working for an existing user does not establish new-user performance.
- Keep the simpler model or abstain when improvement is inconsistent. Estimate uncertainty from future prediction errors only when enough appropriate data exist; do not relabel current heuristic bands.
- Keep synthetic data for tests, simulations and performance benchmarks only. Never count synthetic rows as participants or use formula-generated scores as independent biological outcomes.

## Phase 4: A better attention measurement

Keep the existing three-tap interaction labeled **Reaction-time check**, not a validated cognitive-performance assessment. Its observed latency may still be useful as a clearly limited interaction.

A later opt-in research feature could adapt a published brief sustained-attention protocol. The 3-minute PVT-B has adult laboratory validation; that does not validate a custom teen smartphone implementation [S5, S6]. Do not reproduce sleep-deprivation procedures in a youth study.

Proposed changes to `reaction_test_logic.dart`, `screens/reaction_test_screen.dart` and outcome schemas:

- Version the test protocol and keep legacy three-tap data separate.
- Include practice and record test/device conditions, timestamps and interruptions without claiming hardware calibration.
- Retain trial-level data and distinguish valid response, false start, timeout and interruption.
- Do not discard a response solely because it is slower than the existing 1500-ms bound; censoring genuinely slow responses can hide the outcome under investigation. Define a finite timeout and lapse criterion through the reviewed protocol.
- Consider mean reciprocal reaction time as a prespecified endpoint; retain slower-response/lapse information and secondary summaries. A plain median alone is not necessarily the most sleep-sensitive PVT endpoint [S6].
- Choose and validate protocol-specific thresholds. Do not transplant a laboratory cutoff into a phone app as a diagnostic boundary.
- Use this outcome independently of Energy. Never validate a sleep effect by correlating sleep with a score whose formula already rewards sleep.

Research question to discuss with Dr. Lin: **Within a student, is naturally varying sleep duration associated with next-day sustained-attention performance, measured at a consistent time?** Multivariable adjustment may address confounding, but it does not by itself establish a biological mechanism or causation.

## Phase 5: Differentiation worth testing

These are proposed combinations and user needs, not claims that competitors lack every component. Oura and WHOOP already market personalized coaching; RISE already markets sleep/circadian energy scheduling and wearable-optional tracking [S10–S12].

### School-constrained planning

Let a student enter fixed school, commute, practice and homework constraints. Use measured or estimated alertness only to suggest flexible task ordering. Protect adequate sleep opportunity, provide quiet hours, avoid impossible naps/workouts during school, and permit one-tap dismissal. Never predict grades, promise learning gains, or trade needed sleep for productivity.

### Personal habit learning from independent outcomes

Offer one optional, low-risk habit at a time, such as a consistent wind-down routine. Record whether it happened and compare later observed ratings/attention with appropriate baseline periods. Default to association wording; account for weekday, practice and test-time differences. Do not call an uncontrolled before/after change causal. Do not manipulate sleep restriction, stimulant intake, food restriction or exercise intensity. Any participant research needs mentor-arranged ethics/consent review before recruitment or data collection; preserve existing guardian gates.

### A prediction report the user can inspect

Expand the existing transparency screen with prospective baseline-versus-model error, actual eligible-day counts and “not enough evidence” states. This is an extension of existing transparency, not a claim that transparency is newly invented. Do not equate Helpful votes with physiological benefit. An evidence card should distinguish the recommendation's general research support from whether Tonyo has demonstrated benefit for this user.

## Required regression tests

1. Empty input does not display a normal/fresh health assessment.
2. Missing, invalid and explicit-zero records remain distinct across edit/sync/export/restore.
3. Teen guideline comparison uses a complete, defined observation window; naps/overlaps do not double-count.
4. A short personal sleep baseline does not lower the teen guideline.
5. More caffeine or logged water cannot earn wellness bonus points.
6. A fixed weekly exercise total cannot produce an overtraining diagnosis or clearance.
7. Stale measurements cannot masquerade as today's observations.
8. HRV metric/context incompatibility prevents an unsupported comparison.
9. Slow attention responses and timeouts are retained appropriately, not silently removed.
10. No feature or baseline includes observations unavailable at prediction time.
11. Synthetic and genuine-outcome reports remain separated and honestly labeled.
12. Deterministic-only snapshot reload cannot resurrect stale personalization fields.
13. Today and historical views either agree for the same saved version or explicitly label their differing calculation basis.
14. Advice cannot override guardian/consent restrictions, fixed school commitments or protected sleep time.
15. Disabled/unsupported features fail safely; historical exports and deletion still cover all added stored data.

Run appropriate existing Flutter analysis/tests and report precisely what was executed, passed, failed or remained untested. Use synthetic fixtures for software tests; they cannot establish clinical accuracy. Stop before launch or participant research until the documented consent, security, clinician-review and device QA gates are resolved.

## Evidence registry

[S1] American Academy of Sleep Medicine. Teen Sleep Duration Health Advisory. Supports the 8–10 hours per 24-hour recommendation for ages 13–18, not a score coefficient or exact individual sleep need.

[S2] American Academy of Pediatrics / HealthyChildren.org. The Effects of Caffeine on Kids: A Parent's Guide. Supports avoiding caffeine as a youth energy strategy and that caffeine does not replace sleep.

[S3] NHLBI. Sleep Deprivation and Deficiency: Healthy Sleep Habits. Supports consistent schedules, adequate sleep opportunity and quiet bedtime routines. Some specific advice on this page is adult-specific and should not be generalized to adolescents.

[S4] Borbély A. The two-process model of sleep regulation: Beginnings and outlook. Journal of Sleep Research, 2022. DOI: 10.1111/jsr.13598. Biological framework, not Tonyo calibration.

[S5] Basner M, Mollicone D, Dinges DF. Validity and Sensitivity of a Brief Psychomotor Vigilance Test (PVT-B) to Total and Partial Sleep Deprivation. Acta Astronautica, 2011. DOI: 10.1016/j.actaastro.2011.07.015. Adult validation; do not transfer it to teens/custom devices without evaluation.

[S6] Basner M, Dinges DF. Maximizing Sensitivity of the Psychomotor Vigilance Test (PVT) to Sleep Loss. Sleep, 2011. DOI: 10.1093/sleep/34.5.581. Endpoint-selection evidence, not a prescription for sleep manipulation.

[S7] Laborde S, Mosley E, Thayer JF. Heart Rate Variability and Cardiac Vagal Tone in Psychophysiological Research: Recommendations for Experiment Planning, Data Analysis, and Data Reporting. Frontiers in Psychology, 2017. DOI: 10.3389/fpsyg.2017.00213. Measurement/context cautions; not a validated Tonyo recovery threshold.

[S8] Meeusen R et al. Prevention, diagnosis, and treatment of the overtraining syndrome: joint consensus statement of the European College of Sport Science and the American College of Sports Medicine. Medicine & Science in Sports & Exercise, 2013. DOI: 10.1249/MSS.0b013e318279a10a. Clinical distinction and assessment context, not a fixed-hours app rule.

[S9] NHS. Tiredness and fatigue. Supports seeking assessment for unexplained persistent or daily-life-interfering tiredness. Its general sleep-hour advice is not the adolescent standard used here.

[S10] Oura. Oura Advisor. Product feature documentation only, not independent efficacy evidence.
[S11] WHOOP. How to Use the AI-Powered WHOOP Coach. Product feature documentation only.
[S12] RISE Science. Sleep Debt & Energy Tracker website. Product positioning only, not independent efficacy evidence.

Source locations, checked 3 October 2026:

```text
S1 https://aasm.org/advocacy/position-statements/teen-sleep-duration-health-advisory/
S2 https://www.healthychildren.org/English/healthy-living/nutrition/Pages/the-effects-of-caffeine-on-kids-a-parents-guide.aspx
S3 https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits
S4 https://pmc.ncbi.nlm.nih.gov/articles/PMC9540767/
S5 https://pubmed.ncbi.nlm.nih.gov/22025811/
S6 https://pubmed.ncbi.nlm.nih.gov/21532951/
S7 https://pmc.ncbi.nlm.nih.gov/articles/PMC5316555/
S8 https://pubmed.ncbi.nlm.nih.gov/23247672/
S9 https://www.nhs.uk/symptoms/tiredness-and-fatigue/
S10 https://support.ouraring.com/hc/en-us/articles/39512345699219-Oura-Advisor
S11 https://support.whoop.com/s/article/How-to-Use-the-AI-Powered-WHOOP-Coach?language=en_US
S12 https://www.risescience.com/
```

The supplied audit remains the sole basis for repository-specific statements. External sources motivate proposed changes; none independently validates Tonyo, its scores, its predictions, or its outcomes.
