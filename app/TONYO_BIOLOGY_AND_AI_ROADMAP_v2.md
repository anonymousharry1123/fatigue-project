# Tonyo: Biology Measurement and Future AI Redesign

**Version:** 2.0 draft  
**Updated:** October 17, 2026<br>
**Document status:** Editable roadmap; dated implementation updates link verification evidence and do not grant research approval.

**October 17, 2026 scope update:** The user requested completing AI-1 and AI-2. Default-off local study infrastructure now includes a future calendar, immutable morning feature snapshots, manual/Apple Health ingestion lineage, outcome matching, private export and a local readiness evaluator. [The completion/readiness report](docs/DATA_READINESS_REPORT.md) records verification and the evidence gap: the user said “No / unsure” about existing prospective history, and no real records were inspected. AI-2 tooling and this assessment are complete; empirical modeling readiness is **not established**. The [contract `v0.3-draft`](docs/PREDICTION_CONTRACT.md) retains the selected 10:00 / 18:00–22:00 timing, own-data-first scope, English and manual default with selectable Apple Health. Remaining scientific/operational review is still pending.

**AI-3 preparation follow-up, October 17:** A separate [synthetic comparison runner](docs/AI3_SYNTHETIC_PREPARATION.md) prepares B0 personal mean, B1 latest prior Evening outcome and M1 sleep-only linear regression using invented AI-1 records. This is software preparation; real-data AI-3 comparison and AI-4 evaluation remain pending. No private-data input, app model activation or scientific approval is added.

**Pre-data preparation follow-up, October 17:** The user requested finishing what is possible before entering real data. [The central preparation report](docs/PRE_DATA_PREPARATION_REPORT.md) covers frozen chronological synthetic evaluation, the versioned F1 feature contract and deferred feature ladder, simulated shadow execution, strict synthetic artifacts/lifecycle checks and an evidence-gap audit. These are software preparations for AI-4–AI-7, not completed empirical stages. No private data, new optional collectors or app model activation is involved; scientific decision fields remain open.

## Read This First

**Work now:** finish remaining measurement/protocol decisions and, when appropriate, start an explicit future local plan to obtain prospective evidence. Use AI-2 to assess those records privately; software completion alone does not justify modeling.

**Plan for later:** prospective data collection, real-data model comparisons, real-outcome evaluation, and integration. No real-data AI training or deployment is authorized by this document. Synthetic AI-3–AI-7 preparation is recorded separately below; it adds no approval screen or restriction to ordinary personal app entry.

The original measurement plan is retained below, including Sections 1–18. Sections 19–32 are new proposals with decision fields for Harry, Dr. Sun, Dr. Lin, and any additional reviewer. The original custom questions remain drafts; their inclusion is not a claim of clinical validation.

| Read first | What it contains |
|---|---|
| Sections 1–18 | Current biology measurement scope, unchanged |
| Sections 19–20 | Future boundaries and the target-definition decisions |
| Sections 21–27 | Detailed steps from clean data to a tested, deployable model |
| Sections 28–30 | Optional ideas, adjustable settings, mentor review, and change log |
| Sections 31–32 | Future acceptance checklist and source notes |

**For Codex:** Read the current repository instructions and progress records before implementation. Do not interpret the future roadmap as permission to implement all stages. Do not change approved measurement wording or fill undecided research settings without review.

---

## Phase 2A — Subjective Fatigue, Energy, Sleepiness, and Attention Measurement

**Purpose:** Strengthen the biology/research foundation of Tonyo before changing the AI model.

**Current scope:** This phase only improves how Tonyo measures a student's subjective state using surveys, questionnaires, and 1–10 scales.  
**Not in scope yet:** new ML algorithms, new prediction models, medical diagnosis, treatment advice, or claims that Tonyo measures a biological mechanism directly.

---

## 1. Why This Upgrade Is Needed

Tonyo already tracks sleep, activity, Apple Health data, daily check-ins, reaction time, Energy/Cognitive scores, forecasts, and AI Coach recommendations.

The main scientific weakness is that **"energy," "fatigue," "sleepiness," and "attention" are currently too easy to mix together as if they were the same thing.**

For the next research stage, Tonyo should measure these as separate constructs:

- **Energy** — how energetic the user feels.
- **Fatigue** — how mentally or physically drained the user feels.
- **Sleepiness** — how likely the user feels they could fall asleep or struggle to stay alert.
- **Attention/Focus** — how easy it feels to concentrate at that moment.

These measures may be related, but Tonyo should **not assume they are interchangeable**.

---

## 2. Primary Research Outcome

For the first research question, keep one main outcome:

> **How accurately can previous-night sleep duration predict a student's next-day self-reported energy level?**

### Primary outcome

**Self-reported Energy: 1–10**

Suggested anchors:

- **1** = extremely low energy
- **5** = about average
- **10** = extremely high energy

This should be the main outcome used for the first sleep → energy research analysis.

---

## 3. Secondary Subjective Measures

Add separate 1–10 ratings so Tonyo can later study whether different dimensions of fatigue behave differently.

### A. Perceived Fatigue

Prompt:

> **How fatigued or drained do you feel right now?**

Scale:

- **1** = not fatigued at all
- **5** = moderately fatigued
- **10** = extremely fatigued

### B. Sleepiness

Prompt:

> **How sleepy do you feel right now?**

Scale:

- **1** = fully alert
- **5** = moderately sleepy
- **10** = extremely sleepy

### C. Focus / Attention

Prompt:

> **How easy is it for you to focus right now?**

Scale:

- **1** = extremely difficult to focus
- **5** = average
- **10** = extremely easy to focus

### D. Keep Existing Mood and Stress

Tonyo already records mood and stress. Keep those as **context variables**, not as definitions of fatigue.

They may later help explain why two students with the same sleep duration report different energy levels.

---

## 4. Recommended Daily Check-In

Keep the check-in short enough that students will actually complete it.

### Core Daily Check-In

1. **Energy:** 1–10
2. **Fatigue:** 1–10
3. **Sleepiness:** 1–10
4. **Focus:** 1–10
5. **Mood:** 1–10
6. **Stress:** 1–10

Optional:

- Short note
- "Anything unusual today?" toggle
- Illness / travel / major schedule disruption marker

Do **not** force users to explain why they selected a score.

---

## 5. Timing of Measurements

For research-quality data, timing matters.

### Minimum protocol

Use two standardized check-ins:

**Morning check-in**
- After waking and beginning the day
- Record Energy, Fatigue, Sleepiness, Focus, Mood, Stress

**Evening check-in**
- Near the same general time each evening
- Record the same measures

### Optional

A midday check-in may be added later, but it should not be required in the first study.

Every response should save:

- actual timestamp
- local date
- timezone
- check-in period
- questionnaire version
- whether the response was completed or partially completed

Do not silently move responses into a different period because the user answered late.

---

## 6. Important Research Rule: Prevent Data Leakage

If Tonyo is trying to predict **today's Energy**, the model must not use the user's later Energy answer as an input to predict that same answer.

For example:

### Correct

Previous night's sleep  
↓  
Morning information available before prediction  
↓  
**Tonyo predicts evening Energy**  
↓  
Student later reports actual evening Energy  
↓  
Prediction is compared with the real report

### Incorrect

Evening Energy report  
↓  
Used to generate the same evening Energy prediction  
↓  
Prediction compared with itself

Store the **prediction timestamp** and **outcome timestamp** separately.

---

## 7. Keep Subjective Measures Separate

Do not immediately combine:

- Energy
- Fatigue
- Sleepiness
- Focus
- Mood
- Stress

into one "Biology Score."

First collect data and analyze how strongly they are related.

Later research can ask:

- Does sleep duration predict Energy?
- Does sleep duration predict Sleepiness?
- Does sleep duration predict Focus?
- Are Energy and Fatigue strongly negatively correlated?
- Does subjective Focus agree with reaction-time performance?

A combined score should only be considered after enough evidence shows that combining these variables is meaningful.

---

## 8. Questionnaire / Survey Layer

Tonyo can have two levels of self-report measurement.

### Level 1 — Daily 1–10 Check-In

Purpose:
- frequent
- fast
- low burden
- useful for prediction outcomes

Use the custom Energy/Fatigue/Sleepiness/Focus ratings described above.

### Level 2 — Periodic Research Questionnaire

Purpose:
- provide a broader weekly view
- compare Tonyo's daily ratings with a more structured fatigue/sleepiness measure

**Do not copy a published questionnaire into Tonyo until its age range, permissions, scoring rules, and licensing requirements have been reviewed.**

Candidates to discuss with Dr. Lin or another qualified research mentor may include established pediatric/adolescent fatigue or daytime-sleepiness instruments.

For now, Tonyo should support a generic **questionnaire framework** that can later store an approved instrument without hard-coding copyrighted questions.

Suggested stored metadata:

```text
questionnaireId
questionnaireVersion
instrumentName
completedAt
responses
totalScore
subscaleScores
scoringMethod
source
```

Until an instrument has been formally selected, show experimental custom surveys as:

> **Tonyo research check-in — not a clinical assessment**

---

## 9. Biological Interpretation

Tonyo should use careful wording.

### Appropriate

- "You reported lower energy this morning."
- "Your reported sleepiness was higher than your recent average."
- "You slept less than your recent typical duration."
- "We are studying whether sleep duration is associated with next-day energy."

### Avoid

- "Your brain has not recovered."
- "You have burnout."
- "Your nervous system is overtrained."
- "Your low score means you are unhealthy."
- "Tonyo detected a medical problem."

The app is measuring **self-reported states and behavioral/physiological signals**, not diagnosing the biological cause.

---

## 10. Personal Baselines

After enough observations, show comparisons such as:

> **Energy today: 5/10**  
> Your recent morning average: **6.4/10**

or

> **Sleepiness today: 7/10**  
> Higher than your recent average of **4.8/10**

Requirements:

- Keep the raw 1–10 response unchanged.
- Calculate baseline separately.
- Show sample count.
- Do not create a baseline with too few measurements.
- Do not call a personal average "healthy" or "normal."
- Missing responses remain missing rather than being replaced by 5/10.

---

## 11. Trends Screen

Add separate trend views for:

- Energy
- Fatigue
- Sleepiness
- Focus
- Mood
- Stress

Possible visualization:

```text
Sleep Duration
      ↓
Next-Day Energy
Next-Day Fatigue
Next-Day Sleepiness
Next-Day Focus
```

The app can display **associations**, but it should not label them causal.

Example:

> "On days following longer sleep, your reported Energy tended to be higher."

Not:

> "Sleeping longer caused your Energy to increase."

---

## 12. Data Structure Upgrade

Create or extend the check-in/outcome schema so the original answers are preserved.

Suggested fields:

```text
id
timestamp
localDate
timezone
period

energy1to10
fatigue1to10
sleepiness1to10
focus1to10
mood1to10
stress1to10

note
unusualDayFlag

questionnaireVersion
source = selfReport
recordedAt
```

### Validation

For each 1–10 field:

- integer only
- minimum 1
- maximum 10
- missing is allowed when the user intentionally skips an optional item
- zero must never mean "missing"

Do not overwrite old check-ins during schema migration.

---

## 13. Research Export

Add a research-friendly export where one row represents one completed check-in.

Example:

| Date | Sleep Hours | Energy | Fatigue | Sleepiness | Focus | Mood | Stress |
|---|---:|---:|---:|---:|---:|---:|---:|
| Day 1 | 8.0 | 7 | 3 | 3 | 8 | 7 | 4 |
| Day 2 | 5.5 | 4 | 7 | 8 | 4 | 6 | 7 |

Preserve timestamps and source information in the full export even if the simplified research table hides them.

Do not treat synthetic/demo rows as real participant observations.

---

## 14. App UI Changes

### Daily Check-In Screen

Replace one broad check-in area with clearly labeled cards:

**How do you feel right now?**

- Energy
- Fatigue
- Sleepiness
- Focus
- Mood
- Stress

Each scale should show the meaning of its low and high endpoints.

### Today Screen

Do not turn all six answers into another composite score yet.

Instead show:

**Today's self-report**
- Energy: 6/10
- Fatigue: 5/10
- Sleepiness: 4/10
- Focus: 7/10

Then separately show experimental Tonyo predictions.

This makes it clear which values came **from the user** and which came **from the model**.

---

## 15. Research Questions Enabled by This Upgrade

### Main question

**RQ1:** How accurately can previous-night sleep duration predict a student's next-day self-reported Energy?

### Secondary questions

**RQ2:** How strongly is sleep duration associated with next-day perceived Fatigue?

**RQ3:** How strongly is sleep duration associated with next-day Sleepiness?

**RQ4:** How strongly is sleep duration associated with next-day self-reported Focus?

**RQ5:** How strongly do Energy, Fatigue, Sleepiness, and Focus agree with one another?

Later, after the measurement system is stable:

**RQ6:** Does adding exercise or workload improve prediction beyond sleep duration alone?

Do not begin RQ6 until the first sleep-focused analysis is defined and working.

---

## 16. Implementation Order

### Step 1 — Measurement definitions
Define Energy, Fatigue, Sleepiness, and Focus as separate constructs.

### Step 2 — Check-in UI
Add the new 1–10 ratings and clear endpoint labels.

### Step 3 — Storage/schema
Preserve all raw responses, timestamps, periods, versions, and missingness.

### Step 4 — Personal baselines
Calculate recent averages separately for each measure.

### Step 5 — Trends
Show each outcome independently and relate it to sleep duration without causal wording.

### Step 6 — Research export
Create a clean dataset for later statistical analysis.

### Step 7 — Questionnaire framework
Prepare the app to support an approved validated questionnaire later.

### Step 8 — Only then revisit ML
Once real outcome collection is working reliably, use the new Energy outcome for prediction experiments.

---

## 17. Acceptance Criteria

This biology-measurement phase is complete when:

- [ ] Energy, Fatigue, Sleepiness, and Focus are separate 1–10 measures.
- [ ] Mood and Stress remain available as context variables.
- [ ] The app clearly distinguishes self-reported values from model-generated scores.
- [ ] Morning and evening check-ins retain accurate timestamps.
- [ ] Missing values remain missing.
- [ ] Raw answers are never replaced by calculated scores.
- [ ] Personal baselines show sample counts and do not imply medical normality.
- [ ] Trends use association language rather than causal claims.
- [ ] Research export includes the new measures.
- [ ] Demo/synthetic data remain clearly identified.
- [ ] No new medical diagnosis or treatment claims are added.
- [ ] A generic framework exists for an approved validated questionnaire.
- [ ] No AI-model redesign is performed in this phase.

---

## 18. Main Design Principle

> **Measure first. Model second.**

Before Tonyo tries to build a more advanced AI predictor, it needs a clear and repeatable definition of what it is trying to predict.

For the first stage:

> **Previous-night sleep duration → next-day self-reported Energy**

Fatigue, Sleepiness, and Focus should be collected as separate secondary outcomes so Tonyo can later determine whether they provide additional biological and behavioral insight.

---

## 19. Future AI Redesign: Status and Ground Rules

**Status, October 17, 2026: AI-1 local infrastructure and AI-2 assessment implemented; real-data modeling readiness not established.** The user authorized completing these stages and reporting gaps when prospective history was unavailable/uncertain. See [the report](docs/DATA_READINESS_REPORT.md) and [review draft](docs/PREDICTION_CONTRACT.md). No real participant records were inspected or history enabled during development. Remaining contract review, prospective evidence and later modeling remain separate work.

The first AI goal should remain narrow:

> **Predict a later self-reported Energy rating from information genuinely available earlier.**

This predicts a person's report, not an objectively measured quantity of biological energy. Secondary Fatigue, Sleepiness, and self-reported Focus outcomes remain separate. A questionnaire is not automatically the ground truth for a different construct.

### What is established versus proposed

- **From the current measurement plan:** separate 1–10 ratings, morning/evening check-ins, questionnaire support, original-response storage, and no immediate model redesign.
- **From Dr. Sun's discussion:** compare measurement approaches; start prediction with sleep; later investigate exercise/workload and Coach effectiveness; use mock data for pipeline development.
- **From the earlier source audit:** an Energy residual model exists, while synthetic records support software testing. This is historical audit context, not an inspection of the newest implementation. [P1]
- **User decisions, October 11:** 10:00 prediction, 18:00–22:00 evening rating, own data first, manual sleep default with selectable Apple Health, and English. Source isolation/versioning and remaining operational rules are documented proposals for the synthetic slice.
- **New proposals below:** the exact prediction contract, dataset design, comparisons, evaluation procedures, deployment gates, and adjustable settings. Neither mentor has approved these choices through this document.

### Adjustable versus essential

| Adjustable after discussion | Must remain in every version |
|---|---|
| Primary outcome, response window, and questionnaire choice | No replacement of real responses with model-generated labels |
| Candidate algorithms and feature sets | No information from the future entering an earlier prediction |
| Sample-size plan and study duration | Separate synthetic software tests from evidence on real observations |
| Training schedule and improvement threshold | Privacy, consent, applicable research review, and withdrawal/deletion safeguards |
| Deployment architecture and display design | No diagnosis, unsupported health claims, or causal claims from prediction alone |

A scientific proposal becomes approved only after its decision record is completed. The October 17 request authorizes the AI-1/AI-2 implementation and report while contract review continues. It does not establish a completed empirical pilot, reviewer approval, model training or release; local history and future study plans require explicit in-app enablement.

---

## 20. AI-0: Agree on the Measurement and Prediction Contract

**Purpose:** Resolve what the model will predict before designing a more complex algorithm.

### A. Review the current measurement draft

The custom 1–10 questions above are **draft research items**. This document supplies no validation evidence for them. Keep them labeled as custom self-report measures until appropriate evidence is available.

Before an approved research pilot:

1. Review whether students understand the difference between Energy, Fatigue, Sleepiness, and Focus.
2. Decide whether Fatigue means overall, mental, or physical fatigue. Do not silently combine different definitions.
3. Review anchors such as “average.” Decide what the comparison means, rather than letting each study version use a different reference.
4. Keep the response unset until the user selects it. An untouched slider must not submit an apparent 5/10 answer.
5. Agree on required versus optional questions and permitted skips. Do not make completing all six ratings a condition of accessing unrelated app features.
6. Record item wording, endpoints, order, language, recall period, and version. Changes create a new measurement version rather than rewriting old responses.

These are suggested revisions to discuss, not silent changes to Sections 1–18.

### B. Specify a single primary prediction

**Suggested first design, still adjustable:**

> On the morning of day D, use the main sleep ending that morning to predict the student's self-reported Energy during a defined evening window on day D.

This is “next-day Energy” relative to the previous night's sleep. It is **not** a prediction made before that night's sleep occurred.

```text
Night before day D: sleep occurs
Morning D: eligible sleep information is available; prediction is saved
Evening D: student submits the actual Energy rating
After submission: prediction and report are compared
```

A bedtime prediction for the following evening would be a different task: the upcoming night's measured sleep could not be an input yet.

### C. Keep weekly questionnaires distinct

Select an instrument with mentor review of its intended age group, construct, recall period, scoring instructions, permissions, language, and digital-use terms. No published questionnaire has been selected or approved by this roadmap.

For the future analysis, preserve the approved instrument's original response options and scoring. Do not automatically convert it to 1–10, rewrite its questions, or treat a weekly score as multiple independent daily labels. Compare daily summaries with the corresponding questionnaire recall window only under a written analysis plan.

### Decision space

| Decision | Proposed starting point | Final choice / adjustment |
|---|---|---|
| Primary outcome | Evening self-reported Energy, 1–10 | ______________________________ |
| Primary wording and anchors | Review the existing custom draft | ______________________________ |
| Prediction timing | Morning of day D | User-selected 10:00 local time; issuance tolerance proposed |
| Outcome window | Fixed or individually scheduled evening window | User-selected 18:00–22:00; exact endpoint/timezone rules proposed |
| Initial population | Personal feasibility | User's own data first |
| Sleep source | Explicit source per experiment | Manual default; Apple Health selectable. Isolation/versioning rules proposed |
| Language | Freeze one language and definition | English selected; wording/construct review pending |
| Maximum allowed late response | Not yet selected | ______________________________ |
| Multiple-response selection rule | Prespecify one rule, independent of score values | ______________________________ |
| Questionnaire and recall period | Not yet selected | ______________________________ |
| Required / optional items | Minimize burden while retaining the primary outcome | ______________________________ |
| Reviewer and approval date | Not yet assigned | ______________________________ |

**Deliverable:** `PREDICTION_CONTRACT.md`, including a timing diagram, exact target definition, and permitted inputs.

**Exit condition:** The target, wording, timing, and questionnaire status are explicit. Research participant collection waits for the applicable review and permissions arranged with the mentors.

---

## 21. AI-1: Build a Trustworthy Analysis Dataset

**Purpose:** Make every training example traceable to an earlier information set and a later real report.

**Implementation update, October 17:** The original synthetic calendar/record/builder checks now have a protected local journal adapter, fixed future study calendar, morning feature snapshots, manual/Apple Health lineage, closed-opportunity outcome matching and a private export. Manual remains the default; Health is a separately selected fixed source. No fallback, merging, late backdating or synthetic-to-real conversion is permitted. [The data dictionary](docs/AI1_DATA_DICTIONARY.md) describes `tonyo-study-export-v1`; [the report](docs/DATA_READINESS_REPORT.md) records verification and limits. Events are feature snapshots without numeric predictions or model identities. `trainingEligible` remains false.

### A. Create two linked tables

**1. Raw measurement table:** retain one record per check-in or questionnaire submission, including partial submissions and provenance. This extends the existing export rather than replacing it.

**2. Prediction-event table:** create one row per prespecified prediction opportunity. Keep rows with a missing later outcome for reporting completion and coverage; exclude them from supervised training and error calculations rather than inventing a target.

Proposed prediction-event fields:

```text
prediction_event_id
participant_study_id
protocol_version
measurement_version
prediction_created_at_utc
feature_cutoff_at_utc
local_date_at_prediction
iana_timezone_at_prediction
expected_outcome_window_start_utc
expected_outcome_window_end_utc
sleep_start_at_utc
sleep_end_at_utc
sleep_duration_hours
sleep_source
sleep_record_available_at_utc
feature_snapshot_version
feature_values_and_missingness
matched_outcome_id
outcome_observed_at_utc
outcome_recorded_at_utc
energy_1_to_10
outcome_status
exclusion_reason
provenance
```

These are proposed logical fields, not authorization to create a new live Firestore collection. Decide the storage location and access rules during implementation review.

### B. Match time and availability correctly

Use the main sleep ending before the prediction cutoff, not a simple calendar-day shift. Specify how naps, missing imports, travel, and overlapping sleep records are handled. Any alternative total-sleep window must end at or before the cutoff.

Keep **when something occurred** separate from **when the model could access it**. Sleep entered after an evening outcome cannot be retrospectively treated as available for that morning's real-time prediction.

Save the prediction's original feature snapshot. Later record corrections may support a separately labeled reanalysis, but must not improve an old prediction after the result is known. Preserve revision provenance without overriding privacy deletion obligations.

### C. Apply leakage controls

Learn imputation rules, scaling, feature selection, and fitted preprocessing only from the applicable training partition. Use those fitted transformations unchanged for its validation/test observations. A pipeline can help enforce this separation. [R1]

Tonyo-specific checks should reject:

- An outcome used as its own predictor, directly or through a derived Energy score.
- Later edits silently changing the features of an already-issued prediction.
- A personal baseline calculated from the participant's future ratings.
- The full day's workload used in a morning prediction before that workload happened.
- A later weekly questionnaire score added to an earlier prediction.
- Duplicate submissions counted as independent people or prediction opportunities.

### D. Keep research exports private

Use study identifiers rather than names, emails, or account IDs in analysis tables. Keep any linkage separately with restricted access. Pseudonymized sleep and health records remain sensitive. Exclude free-text notes and precise personal schedules unless the approved analysis genuinely needs them.

Do not send real participant data to Codex, external AI services, or a public repository as part of this workflow.

**Deliverable:** A versioned data dictionary, dataset builder, private export procedure, and automated checks for time alignment and leakage.

**Adjustment space:**

- Storage/export location: ______________________________
- Sleep selection and late-import rule: ______________________________
- Outcome matching and edit policy: ______________________________
- Missing-data and exclusion policy: ______________________________
- Reviewer / approval: ______________________________

---

## 22. AI-2: Check Whether the Measurements Are Ready for Modeling

**Purpose:** Avoid treating a large row count as evidence that the data are informative.

**Implementation/assessment update, October 17:** [AI-2 tooling](lib/src/ai2_readiness.dart) and [DATA_READINESS_REPORT.md](docs/DATA_READINESS_REPORT.md) are complete for the available evidence. The user reported no/uncertain prospective history; no actual participant measurements were inspected. Coverage/missingness/lateness/distribution calculations are implemented and tested with synthetic cases, but a real empirical pilot and modeling readiness are not established. The next step is to resolve remaining protocol decisions, obtain ordinary prospective measurements and rerun the private assessment.

Under the agreed participant protocol, first evaluate whether questions are understandable, responses are completed at the intended times, and there is usable variation in the primary outcome. Use ordinary observed routines; do not ask teenagers to reduce sleep, consume stimulants, or increase exercise for data collection.

Report:

- Number of participants, eligible days per participant, scheduled check-ins, and completed outcomes.
- Missingness and response lateness, including differences between participants.
- Distribution of Energy responses, including repeated endpoints or nearly unchanging ratings.
- Main-sleep source and availability at prediction time.
- Questionnaire completion and which measurement versions were used.
- Reasons for exclusion, not just the final retained sample.

Do not remove low-energy days merely because their predictions are poor. A missing Energy answer is not a neutral answer. Do not fill missing targets using the model being evaluated.

Discuss study size with the mentors or a statistical adviser using the number of independent participants, repeat observations, measurement variation, model complexity, and desired precision. Do not promote a model merely because an old software minimum is met.

**Proposed stop rule:** When response timing, comprehension, or completion is inadequate, improve the measurement workflow before adding algorithms. When the primary rating barely varies, report that limitation rather than forcing a complex model.

**Deliverable:** `DATA_READINESS_REPORT.md`, with no real participant identifiers.

**Adjustment space:**

| Planning item | Agreed value and rationale |
|---|---|
| Intended population / inclusion criteria | ______________________________ |
| Pilot size and duration | ______________________________ |
| Main evaluation size and duration | ______________________________ |
| Minimum usable history for a personal estimate | ______________________________ |
| Acceptable completion and lateness | ______________________________ |
| Rules for revising questions after the pilot | ______________________________ |
| Research review and consent status | ______________________________ |

---

## 23. AI-3: Build Simple Comparisons Before Complex Models

**Purpose:** Determine whether a learned model adds value beyond an ordinary personal expectation.

**Preparation update, October 17:** [AI3_SYNTHETIC_PREPARATION.md](docs/AI3_SYNTHETIC_PREPARATION.md) documents an isolated fixture-only B0/B1/M1 runner with a fixed source/definition/time manifest. It replays per-person expanding history, rebuilding eligibility at each morning cutoff, and reports method-specific coverage and pairwise common-set errors. Numeric regression, clipping to 1–10 and numerical minimums are synthetic execution policies, not approved empirical choices. The command accepts no participant files and has no app integration. This completes AI-3 software preparation only; actual comparison on prospective data and all AI-4 acceptance work remain pending.

### Suggested comparison order

| ID | Candidate | Why include it in this project? |
|---|---|---|
| B0 | Historical same-period personal average | Asks whether a new prediction beats the person's usual evening report |
| B1 | Most recent earlier same-period rating | Tests whether simply repeating a recent report is competitive |
| M1 | Sleep-only linear regression | Provides the first interpretable sleep-based comparison |
| M2 | Regularized regression with an approved small feature set | Tests a modest extension without redesigning the entire product |
| M3 | One justified nonlinear candidate | Tests whether a more flexible relationship improves future prediction |

These are candidates, not a commitment to train five models. If no personal history exists, either withhold a personal estimate or use a clearly labeled population reference trained only on permitted training data. Prespecify that fallback.

For a first exploratory model, a possible structure is:

```text
Predicted later Energy = fitted intercept + fitted sleep coefficient × sleep hours
```

This is an equation to estimate from observations, not a medical formula. Do not hand-pick a positive sleep coefficient or force longer sleep to mean a higher score.

A model that additionally uses personal history is not strictly “sleep only.” Label sleep-only and sleep-plus-history experiments separately. Keep the same evaluation opportunities for fair head-to-head comparisons and separately report each model's missing-data coverage.

### Model choices that remain open

A small tree-based regressor could be M3. Random forest or gradient boosting may be considered if the data and validation design justify them. A neural network, LSTM, or LLM is **not** an automatic upgrade and is not required for this roadmap.

Start with a prespecified, limited tuning budget. Choose settings using development data only. Reusing model-selection results as final test performance can bias the estimate; keep tuning inside the development procedure and final assessment separate. [R4]

### Outcome-scale decision

Keep the observed 1–10 responses unchanged. Treating the rating as numeric regression is a proposed operational choice; it does not establish equal biological differences between adjacent values. An ordered-category model may be considered later with a separate evaluation plan.

Decide clipping and display rounding before final testing. Evaluate the actual deployed output rule and retain the underlying prediction for audit. Never convert error into an unsupported “percent medically accurate” claim.

**Deliverable:** A reproducible baseline/model comparison runner with a fixed experiment manifest.

**Adjustment space:**

- Approved model families: ______________________________
- Small parameter search for each model: ______________________________
- Feature set for each comparison: ______________________________
- Cold-start behavior: ______________________________
- Numeric versus ordered-category target handling: ______________________________
- Training environment and dependency versions: ______________________________

---

## 24. AI-4: Evaluate the Right Kind of Prediction

**Purpose:** Match the evaluation to the claim Tonyo intends to make.

**Software preparation, October 17:** A synthetic runner freezes each person's B0/B1/M1 fit once at a common UTC cutoff, separates earlier training, middle development and later final opportunities, and opens final data through a separate explicit API. Candidate/comparator choices precede scoring; no later labels update the models. Coverage, individual/macro errors and identical-set paired errors are reported. Uncertainty and real promotion rules remain unfilled; no automatic winner is chosen. See [the preparation report](docs/PRE_DATA_PREPARATION_REPORT.md). Actual future-data evaluation and its decision remain pending.

### A. Separate two questions

| Intended claim | Proposed evaluation design |
|---|---|
| Predict a later day for a user with existing history | Train on earlier eligible information and evaluate later outcomes |
| Predict for a completely new user | Hold out entire participants; do not use their labels for training or preprocessing |

Grouped validation addresses person overlap, while time-ordered validation addresses forecasting. Neither automatically solves the other. Repeated observations and time dependence need an appropriate split rather than an ordinary shuffled row split. [R2]

For the first Tonyo study, prioritize the existing-user, future-day question. Use common calendar cutoffs for pooled model training so other users' later records do not enter a model issued earlier. Do not assume sorting a multi-user table and calling a generic time-series splitter is sufficient.

A new-user experiment should be separately labeled. If it uses a calibration period from that user, it is no longer a zero-history result. Document the permitted history and cutoff for that experiment.

### B. Suggested development sequence

```text
Earlier development data
    → fit candidate models
Later development windows
    → select settings and compare approaches
Frozen protocol and candidate
    → evaluate on untouched later outcomes
```

Within each development evaluation window, repeat any fitted preprocessing using its training portion only. Save the split manifest. Do not repeatedly inspect the final test set and then continue tuning against it. If it informs a redesign, treat it as development data and reserve fresh future evaluation.

### C. Primary metric and reporting

**Suggested primary metric: mean absolute error (MAE), measured in 1–10 rating points.** It is the average absolute difference between predictions and observed ratings; lower is better for that measure. [R3]

Illustration only: predicting 6.0 when a person later reports 4 gives an absolute error of 2.0 rating points. This is not a Tonyo result or an acceptance threshold.

Report a small, interpretable set:

- Overall MAE and the difference from the prespecified baseline on matched observations.
- Average per-participant MAE, so frequent reporters do not completely determine the headline result.
- Signed error to show systematic over- or underprediction.
- Participants, evaluated outcomes, missing outcomes, and the proportion of opportunities receiving a prediction.
- A suitable uncertainty assessment chosen with statistical review. Do not treat correlated daily rows as independent for an interval calculation.

If the dataset cannot support dependable subgroup or uncertainty estimates, state that limitation. If a later interval is displayed in the app, test its observed coverage on held-out outcomes; do not recycle heuristic confidence as an accuracy probability.

### D. Agree on promotion criteria beforehand

**“Lower error once” is not a sufficient promotion rule.** Choose the minimum useful improvement and acceptable coverage before looking at final performance. The choices below are intentionally blank rather than invented scientific thresholds.

| Criterion | Agreed requirement |
|---|---|
| Main comparator | ______________________________ |
| Minimum improvement in MAE points | ______________________________ |
| Optional relative improvement requirement | ______________________________ |
| Coverage / abstention requirement | ______________________________ |
| Uncertainty and per-user consistency requirement | ______________________________ |
| Minimum prospective evidence | ______________________________ |
| Privacy and device acceptance gates | ______________________________ |

**Deliverable:** `MODEL_EVALUATION_REPORT.md`, the frozen split manifest, and a signed-off accept/revise/reject decision. A simple baseline winning is a valid outcome.

---

## 25. AI-5: Add Biological Inputs Only When They Help

**Purpose:** Extend the sleep model without returning immediately to an unexplained mixture of variables.

**Software preparation, October 17:** [The feature experiment plan](docs/AI5_FEATURE_EXPERIMENT_PLAN.md) defines a versioned F1 source/unit/timing contract and a future comparison-report schema. The executable validator permits only the existing sleep feature; F2/F3 remain undefined/unimplemented and F4–F6 optional/deferred. No new variables or collectors are added without evidence. Every feature's empirical disposition is currently not adequately tested; B0/B1 history baselines do not count as F2 implementation.

### Proposed feature ladder

| Experiment | Permitted extension | Question |
|---|---|---|
| F1 | Previous main-sleep duration only | Does sleep alone improve on the chosen baseline? |
| F2 | Sleep plus prior personal Energy history | Does history add useful information? |
| F3 | Approved recent sleep-pattern features | Do earlier sleep patterns improve prediction beyond the last night? |
| F4 | Earlier workload or activity, tested separately | Does either add predictive value on the same evaluation design? |
| F5 | Earlier Fatigue, Sleepiness, or Focus reports | Does an earlier subjective state add information beyond sleep/history? |
| F6 | HRV or other wearable features | Is the extra device dependence justified by additional predictive value? |

F4–F6 remain optional later work, not the current biology-only task. Mood/stress may be considered in a separately specified extension, not added automatically because they are collected.

Only use variables observed and available before the cutoff. Same-evening Fatigue, Sleepiness, Focus, or questionnaire answers cannot become inputs to the already-issued prediction of that evening's Energy.

Run feature comparisons inside development data. Once the selected feature set is fixed, evaluate it on untouched later outcomes. Retain negative findings; do not keep adding variables until a favorable test result appears.

### Preserve the biology question

For a separate biological association analysis, consider whether a person reports differently after shorter or longer sleep than their own typical pattern. Distinguish this within-person question from comparing naturally different people. Agree on any confounder adjustment with Dr. Lin; “one main factor” does not mean all other influences disappear.

Prediction error, feature importance, and correlations do not establish the physiological cause. Neither a sleep-only model nor a multivariable model, by itself, proves sleep restoration or a causal effect.

**Deliverable:** An input-comparison report explaining what was retained, rejected, or not adequately tested.

**Adjustment space:**

- Next proposed variable and reason: ______________________________
- Exact timing/source definition: ______________________________
- Additional burden or privacy cost: ______________________________
- Separate biology analysis / controls: ______________________________
- Decision and reviewer: ______________________________

---

## 26. AI-6: Test Predictions Prospectively Before Showing Strong Claims

**Purpose:** Confirm performance when predictions are genuinely saved before later answers exist.

**Software preparation, October 17:** An isolated synthetic shadow harness rehearses a frozen artifact/calendar, actual injected-clock execution, immutable events, two-write simulated receipts, missing/unopened cases and erasure/session races. Simulated receipts are not native durability or actual prospective measurements. No normal app/background task, visible prediction or Coach integration is connected. [The central report](docs/PRE_DATA_PREPARATION_REPORT.md) records this boundary; the prospective empirical deliverable remains pending.

Under the approved protocol, run a **shadow evaluation**: generate and save predictions, but initially keep them out of the check-in workflow and do not let them drive Coach changes. This is a proposed precaution against feeding the app's answer back into the response or changing the conditions being evaluated.

For every opportunity, store the model version, feature cutoff, generated time, expected outcome window, original prediction, and eligibility status. Later link the actual self-report. Report missing outcomes, late answers, and prediction failures instead of silently removing them.

Keep the model frozen during the initial evaluation block. If later testing an adaptive model, prespecify exactly when updates occur and ensure that each update uses only outcomes available at that time.

Do not manufacture a historical prediction when the app was not running. A separate offline replay may be useful, but label it retrospective. Decide how on-device scheduling limitations affect the task before making daily-coverage promises.

Prediction records should be revision-controlled rather than silently overwritten. Export and legally/applicably required deletion must still work; “audit trail” is not a reason to retain withdrawn data against the agreed policy.

**Deliverable:** A prospective report comparing frozen predictions with later observed reports and the same baseline.

**Adjustment space:**

- Frozen-model evaluation duration: ______________________________
- Whether/when predictions become visible: ______________________________
- Missed-run and background limitations: ______________________________
- Outcome window and late-response policy: ______________________________
- Permitted model-update policy: ______________________________
- Decision to continue, revise, or stop: ______________________________

---

## 27. AI-7: Integrate the Selected Model Safely

**Purpose:** Deploy only an approach that has earned its place, without breaking the biology data collection.

**Software preparation, October 17:** Strict synthetic artifact parsing/inference and an isolated registry now exercise target/feature/source/measurement compatibility, abstention, generation invalidation and rollback. They cannot load legacy residual artifacts and have no app consumer. Caller-propagated session state is required; immutable old references are not globally revoked. The [preparation model card and migration plan](docs/PRE_DATA_PREPARATION_REPORT.md#ai-7-preparation-model-card-and-migration-plan) retain the unresolved old/new output decision, device evidence and release decision.

### A. Preserve separation in the interface

Display these as different quantities:

- **Your report:** the original Energy response.
- **Tonyo prediction:** a later-state estimate with its target window and model version.
- **Personal reference:** a historical average, not a clinical normal range.
- **General guidance:** evidence-reviewed information, not proof the prediction is correct.

Do not quietly relabel a 1–10 report as measured physiology or replace raw reports with a 0–100 experimental score. Keep learned Energy, custom Focus, and any later objective attention measurement distinct.

### B. Plan the transition from the existing model

The earlier audit identified a fitted residual correction to a rule-based Energy score. [P1] Before replacement, inspect the current code and confirm what is actually deployed. Decide whether the new predictor is a separately named output, a replacement, or a temporary side-by-side research comparison.

Require versioned target definitions, feature order/units, preprocessing, measurement versions, and model artifacts. Test compatibility and rollback. Old residual models must not be applied to an incompatible reference or target.

An offline Python analysis environment is a possible research tool, not a requirement to move the Flutter app to a server. Decide where fitting and inference belong after comparing privacy, maintainability, device performance, and supported models. If a fitted model is transferred to Dart or another runtime, use fixed test fixtures to verify that predictions match within an agreed numerical tolerance.

### C. Release and monitoring checks

Test missing inputs, invalid values, incompatible artifacts, consent withdrawal, account switching, cached predictions, timezone changes, and sign-out. Preserve the Phase 1 no-data behavior and removed score incentives.

Define a transparent fallback or abstention message when evidence is inadequate. Do not silently return the midpoint as a measured or personalized result.

Monitor error and coverage only under approved data use. Agree on review triggers, retraining intervals, rollback, and new evaluation after substantial wording, feature, or population changes. App-store publication and scientific model acceptance remain separate decisions.

**Deliverable:** A model card, migration plan, device acceptance evidence, and release decision.

**Adjustment space:**

- Deployment architecture: ______________________________
- Old/new model transition: ______________________________
- User-facing naming and wording: ______________________________
- Fallback and abstention rules: ______________________________
- Retraining / rollback policy: ______________________________
- Release reviewer and unresolved blockers: ______________________________

---

## 28. Later Ideas: Keep Them Open, Not Committed

| Idea | Prerequisite before development | Space for adjustment |
|---|---|---|
| Predict Fatigue or Sleepiness separately | Stable outcome wording and its own evaluation protocol | ____________________ |
| Predict perceived Focus | Explicitly label it self-report, not an objective attention test | ____________________ |
| Add reaction/attention performance | Separate protocol, device-timing checks, and appropriate measurement evidence | ____________________ |
| Add a reviewed pediatric questionnaire | Instrument selection, permission review, and faithful scoring | ____________________ |
| Student Smart Planner | Accurate schedules, protected sleep, and evidence-limited prediction wording | ____________________ |
| Evaluate Coach effectiveness | A separate approved intervention design with independent outcomes | ____________________ |
| More complex personalized models | Better future performance than simpler alternatives | ____________________ |

Coach effectiveness is a different question from prediction accuracy. Adding more suggested actions does not by itself establish benefit. Any future intervention should be mentor-reviewed, low risk, and compatible with participant welfare; no sleep restriction, stimulant use, or increased exercise intensity is part of this roadmap.

**Additional idea:** ______________________________

**Why it might help:** ______________________________

**Evidence or prerequisite needed:** ______________________________

**Reason to defer or reject:** ______________________________

---

## 29. Adjustable Experiment Settings

This is an **illustrative configuration template**, not functioning app configuration. Do not wire it into the deployed app now. Empty values mean “undecided,” not permission for a coding agent to choose silently.

```yaml
roadmap_version: "2.0-draft"
active_scope: "biology_measurement_only"
ai_redesign_enabled: false

protocol:
  id: null
  approved_by: null
  approved_at: null
  research_review_reference: null
  measurement_version: null
  primary_outcome: null        # Suggested: evening self-reported Energy, 1–10
  primary_item_id: null
  prediction_timing_rule: null
  outcome_window_rule: null
  late_response_rule: null
  multiple_response_rule: null
  questionnaire_id: null
  questionnaire_version: null
  questionnaire_recall_period: null

study:
  intended_population: null
  participant_count_plan: null
  observation_duration_plan: null
  study_size_rationale: null
  missingness_policy: null

modeling:
  feature_set_version: null
  approved_features: []
  approved_candidates: []
  primary_baseline: null
  cold_start_policy: null
  parameter_search_budget: null
  minimum_personal_history: null
  numeric_or_ordered_target: null
  prediction_postprocessing: null

validation:
  primary_use_case: null       # Known-user future days OR new-user transfer
  chronological_split_plan: null
  participant_grouping_plan: null
  untouched_test_definition: null
  primary_metric: null         # Suggested: MAE in 1–10 rating points
  minimum_mae_improvement: null
  minimum_coverage: null
  uncertainty_method: null
  prospective_evaluation_plan: null

release:
  model_version: null
  feature_version: null
  compatible_measurement_versions: []
  fallback_policy: null
  retraining_policy: null
  rollback_policy: null
  reviewer: null
  approval_date: null
```

Any future training command should fail clearly when required approved settings are absent. Essential privacy and anti-leakage safeguards must not be configurable off.

---

## 30. Review Schedule and Change Log

Use readiness milestones instead of promising that the model will be validated by a particular date. The following table is for planning, not a forecast of completion.

| Stage | Deliverable | Suggested discussion | Owner | Target date | Status |
|---|---|---|---|---|---|
| Phase 2A, current | Survey/check-in implementation and tests | Both mentors as available | ______ | ______ | ______ |
| AI-0 | Approved prediction contract | Dr. Lin: constructs; Dr. Sun: implementation | ______ | ______ | Timing/population/source defaults/English selected 2026-10-11; remaining review pending |
| AI-1 | Dataset and timing checks | Technical review plus research review | ______ | ______ | Local infrastructure implemented 2026-10-17; verification/limits in [report](docs/DATA_READINESS_REPORT.md); no real data inspected |
| AI-2 | Measurement/data readiness report | Both mentors; statistical advice as needed | ______ | ______ | Tooling and evidence-gap report complete 2026-10-17; empirical readiness not established |
| AI-3 | Baseline and candidate comparisons | Dr. Sun and statistical adviser | ______ | ______ | Synthetic B0/B1/M1 preparation implemented 2026-10-17; real-data comparison deferred; [report](docs/AI3_SYNTHETIC_PREPARATION.md) |
| AI-4 | Frozen evaluation report | Both mentors | ______ | ______ | Synthetic frozen evaluation prepared; actual future-data evaluation and decision pending |
| AI-5 | Input-comparison report | Dr. Lin: interpretation; Dr. Sun: modeling | ______ | ______ | F1 contract/feature plan prepared; extra inputs untested and deferred |
| AI-6 | Prospective prediction report | Both mentors and applicable research reviewer | ______ | ______ | Synthetic shadow rehearsal prepared; actual prospective model evaluation pending |
| AI-7 | Integration and release decision | Technical/privacy reviewers | ______ | ______ | Synthetic artifact/lifecycle preparation; app integration/device/release pending |

Suggested roles are invitations for discussion, not commitments already made by either mentor.

### Reusable decision record

**Decision ID:** ______________________________

**Date / reviewer:** ______________________________

**Current proposal:** ______________________________

**Requested adjustment:** ______________________________

**Reason / supporting evidence:** ______________________________

**Affected question, feature, dataset, or UI:** ______________________________

**Does this require a new measurement or model version?** ______________________________

**Has the final test data already been examined?** ______________________________

**Does this require fresh prospective evaluation or updated participant review?** ______________________________

**Decision: approved / revise / defer / reject:** ______________________________

### Change log

| Version | Change | Approval status |
|---|---|---|
| Original measurement plan | Sections 1–18: biology-only survey and scale upgrade | Approval not established in the supplied material |
| 2.0 draft, 2026-10-04 | Preserved Sections 1–18; added future AI stages, evidence notes, and adjustment spaces | Proposed for review |
| Implementation update, 2026-10-17 | AI-1 local infrastructure and AI-2 evidence-gap assessment implemented; links to dictionary/report | User-authorized implementation; scientific decisions and real-data readiness not promoted to approved |
| Synthetic preparation, 2026-10-17 | AI-3 fixed-manifest B0/B1/M1 fixture replay and comparison artifacts | Software preparation only; real-data AI-3/AI-4 decisions remain open |
| Pre-data preparation, 2026-10-17 | AI-4 frozen fixture evaluation, AI-5 manifest/plan, AI-6 simulated shadow lifecycle, AI-7 strict artifacts and evidence audit; [central report](docs/PRE_DATA_PREPARATION_REPORT.md) | User-authorized software preparation; empirical stages and scientific decisions remain open |
| __________ | ______________________________ | ____________________ |
| __________ | ______________________________ | ____________________ |

---

## 31. Future AI Acceptance Checklist

No checklist box is pre-checked: this document does not verify implementation or grant research approval.

- [ ] Measurement wording, anchors, recall periods, and versions are reviewed.
- [ ] One primary outcome and a precise prediction horizon are defined.
- [ ] Relevant participant review, permissions, and privacy procedures are in place before research collection.
- [ ] Data distinguish event time, availability time, edits, and synthetic provenance.
- [ ] Predictions cannot use later answers or retrospectively available inputs.
- [ ] Simple baselines are included on comparable evaluation observations.
- [ ] Development tuning is separate from final evaluation.
- [ ] Evaluation respects time and participant structure for the intended claim.
- [ ] Missing outcomes, failed predictions, coverage, and uncertainty are reported.
- [ ] The model meets prespecified improvement criteria or the simpler baseline is retained.
- [ ] Prospective predictions were saved before outcomes were known.
- [ ] Questionnaire scores, custom self-reports, and model predictions remain distinct.
- [ ] Existing raw data, consent controls, migrations, and rollback behavior are preserved.
- [ ] Physical-device and signed-in integration gaps are closed for the intended release.
- [ ] Claims are limited to the population, outcome, and horizon actually evaluated.
- [ ] Dr. Sun / Dr. Lin feedback and remaining disagreements are recorded.
- [ ] No later phase has started without an explicit scope decision.

> **Working sequence: measure clearly → collect appropriately → compare simply → evaluate honestly → deploy only what is supported.**

---

## 32. Sources and Evidence Boundaries

### Project materials

**[P1]** `PROJECT_SUMMARY.md`, supplied static source audit dated 2026-10-03. Relevant sections: 8 (existing fitted Energy model), 9 (synthetic-data provenance), and 15 (scientific limitations). This roadmap does not re-inspect the source or claim those details describe every later revision.

**[P2]** `TONYO_BIOLOGY_MEASUREMENT_UPGRADE.md`, supplied current biology measurement draft. Its Sections 1–18 are preserved in this version. Its custom scale wording is a proposal, not an established validated instrument.

**[P3]** Dr. Sun's two discussion screenshots supplied on 2026-10-04. They motivate the measurement/prediction/Coach directions; they do not specify the detailed protocol, sample size, metrics, or promotion thresholds added here.

### External methodology references

These references support the narrow methodological points cited in the new roadmap. They do not validate Tonyo, its custom questionnaire, its biological interpretations, or its effectiveness. The detailed stage structure and adjustable defaults are project-specific proposals.

**[R1]** scikit-learn documentation, *Common pitfalls and recommended practices*, especially data leakage and preprocessing. Reviewed 2026-10-04. Supports fitting transformations only on training data and separating information available at prediction time.

<https://scikit-learn.org/stable/common_pitfalls.html>

**[R2]** scikit-learn documentation, *Cross-validation: evaluating estimator performance*, especially grouped and time-series validation. Reviewed 2026-10-04. Supports distinguishing participant grouping from chronological evaluation; the combined Tonyo split procedure still requires project-specific review.

<https://scikit-learn.org/stable/modules/cross_validation.html>

**[R3]** scikit-learn documentation, *mean_absolute_error*. Reviewed 2026-10-04. Supports the MAE definition, not a clinically meaningful threshold for Tonyo's custom rating scale.

<https://scikit-learn.org/stable/modules/generated/sklearn.metrics.mean_absolute_error.html>

**[R4]** scikit-learn documentation, *Nested versus non-nested cross-validation*. Reviewed 2026-10-04. Supports separating tuning from generalization assessment. Its demonstration is not a ready-made longitudinal adolescent study protocol.

<https://scikit-learn.org/stable/auto_examples/model_selection/plot_nested_cross_validation_iris.html>
