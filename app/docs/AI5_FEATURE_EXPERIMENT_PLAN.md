# AI-5 feature experiment preparation

Date: October 17, 2026<br>
Plan version: `ai5-feature-experiment-plan-v1`<br>
Executable manifest: `ai5-feature-manifest-v1`<br>
Scope: versioned software preparation; no new collector, empirical feature comparison or real-data fitting.

## Decision and current implementation

**Retain the existing sleep-only feature contract for synthetic work. Additional inputs are not adequately tested and remain deferred.** There is no participant evidence here that justifies adding another variable. “Implemented” below describes a software definition, not scientific acceptance or useful predictive performance.

The [feature manifest and evidence audit](../lib/src/ai_predata_gate.dart) allow only F1's ordered `main_sleep_duration_hours` feature. They preserve the exact AI-1 protocol/measurement and selected source, hours as the unit, identity preprocessing and development-only feature comparison. The [tests](../test/ai_predata_gate_test.dart) reject unknown units, alternate/outcome-adjacent feature identities, incompatible timing, duplicate features, final-test feature selection and attempted F2–F6 activation.

The earlier [AI-3](AI3_SYNTHETIC_PREPARATION.md) B0/B1 history baselines do **not** implement F2. F2 would put prespecified historical Energy information alongside sleep in a new candidate, requiring a distinct feature definition and comparison. A baseline using history is not evidence that this extra predictor helps.

## Versioned feature ladder

| Experiment | Software status | Definition required before a comparison | Scientific disposition now |
| --- | --- | --- | --- |
| F1: previous main sleep | Implemented for synthetic execution | One main-sleep duration in hours; `tonyo-study-sleep-v1`; fixed manual or Apple Health source; AI-1 selection/revision rules | Not adequately tested on real observations |
| F2: sleep plus prior personal Energy | Not implemented; requires definition/review | Which prior compatible Evening outcomes, exact lag/window, minimum history, aggregation, missingness and update policy; no same-evening outcome | Not adequately tested; no retention claim |
| F3: earlier sleep patterns | Not implemented; requires definition/review | Fixed prior-date window, source, feature formula, valid-night minimum, handling of missing nights and frozen pre-cutoff revisions | Not adequately tested; no retention claim |
| F4: earlier workload or activity | Optional, deferred; not implemented | Evaluate one specified construct/source at a time; exact observation interval, units, collection burden and zero-versus-missing semantics | Not adequately tested; no collector added |
| F5: earlier Fatigue, Sleepiness or Focus | Optional, deferred; not implemented | Exact item/version/language/recall/period and earlier observation window; each construct remains separate | Not adequately tested; same-evening target-adjacent fields prohibited |
| F6: HRV or other wearable data | Optional, deferred; not implemented | Specific quantity/unit/device/source/context, aggregation and availability semantics; device dependence and missingness accounted for | Not adequately tested; no wearable expansion |

Mood/stress are outside this ladder's executable scope. Their presence in an ordinary form does not authorize their use as model features. Nothing here changes that form, its disclosure, source permissions or optional answers.

## Source and timing contract

For F1, the feature identity is `main_sleep_duration_hours`; the unit is `hours`; the sole selected source must match the experiment's AI-1 protocol. Manual duration is the recorded bedtime-to-wake interval and may include awake time. Apple Health has separate measurement semantics. A missing selected-source record cannot be filled from the other source.

The manifest requires main sleep ending on the opportunity's local date at/before its frozen 10:00 cutoff and availability durably established on the issuing device by that cutoff. The metadata validator rejects an observation, availability timestamp or history-window end after the cutoff; it also rejects internally reversed timing, nonfinite values and values outside the existing 0.5–16-hour software bounds. These bounds are software sanity checks, not a physiological normal range or study inclusion recommendation. The metadata check does not authenticate supplied timestamps or replace the AI-1 builder's local-date, episode, source, revision and lineage checks.

Every future extension must specify the following before it can enter a development comparison:

| Required field | Why it is necessary |
| --- | --- |
| Feature ID, ordered position, version and units | A changed formula, position or unit must not silently reuse an old artifact. |
| Construct, source and exact measurement snapshot | Similar names do not establish interchangeable measures or language versions. |
| Observation interval and aggregation formula | The feature must refer to earlier information, not an interval ending after prediction. |
| Original observation and device-availability times | A historical-looking timestamp cannot make a late entry/import available earlier. |
| Revision/as-of and deletion policy | Later edits cannot rewrite an earlier fit; erased evidence must not be resurrected. |
| Missingness, minimum history and abstention rule | Missing observations are not zeros; no data-dependent fallback is introduced silently. |
| Fitted preprocessing and training-only fit boundary | Any learned transform must use only the training portion of its development comparison. |
| Participant burden, privacy and data-use scope | An optional extra input needs a stated purpose and suitable participant-facing scope. |

For historical self-report features, the earlier outcome window must have closed and its compatible original record must have been available before the new cutoff. Same-evening Energy, Fatigue, Sleepiness, Focus or questionnaire answers cannot become inputs to that morning's estimate. Feature metadata is not itself a predictor unless a new reviewed experiment explicitly says so.

## Planned comparison report schema

The following is a **report plan**, not a claim that F2–F6 have been run. The current executable manifest emits its fixed F1 definition and the ladder's deferred statuses. A later comparison report should use a new versioned schema and contain:

| Group | Required contents |
| --- | --- |
| Identity and scope | Experiment/dataset versions, source, exact target/measurement, participant scope, feature-manifest version and canonical feature order |
| Frozen design | Training/development boundaries, history/update policy, comparator, candidate family, fixed candidate list and search budget |
| Feature availability | Eligible opportunities, feature-missing/late/incompatible counts, abstention reasons and incremental collection burden |
| Own-set results | Predictions, scored outcomes, coverage denominator, MAE and signed error on each method's scored rows |
| Identical-set comparison | Pairwise common opportunity IDs and both errors on that set; candidate-minus-comparator MAE difference; participant results and equal-participant macro summary |
| Uncertainty | Prespecified method and dependence assumptions, or explicit “not estimated”; never an interval that treats repeated daily rows as independent by default |
| Disposition | `retained`, `rejected` or `not_adequately_tested`, evidence/reason, reviewer/date/reference and any new-data requirement |
| Final-test provenance | Feature selection completed before final opening; if final results inform redesign, mark that test as development and reserve fresh future evaluation |

Comparisons belong inside development data. Choosing a feature after inspecting final outcomes spends that final test; repeated searching is not repaired by reporting only the best result. Keep negative and inconclusive findings. A feature's predictive usefulness does not establish a causal sleep effect or an independent biological mechanism. Any separate within-person association/confounder analysis needs its own defined question and review.

## Evidence audit and remaining decisions

`AiPredataGate.assess` reports 15 typed requirements spanning measurement, population/data use, timing/revisions, privacy, study size, actual readiness, chronological splits/baselines, features, metrics/promotion, uncertainty, physical-device acceptance, frozen evaluation, prospective shadow evaluation and artifact/release decisions. The default preparation settings leave the substantive decision versions and evidence unset. This is intentional.

Supplied records are checked for experiment/protocol/version compatibility, a reference, reviewer and decision time. Empirical assessments and physical-device observations have distinct evidence kinds; a review note or synthetic test cannot substitute for them. Duplicate records fail instead of selecting a favorable decision. These are completeness checks on declarations, not authentication of an approval.

The audit always retains `realDataUseAuthorized: false`, `realDataFittingAllowed: false` and `appModelReleaseAllowed: false`; there is no unlock path. Those flags mean this preparation tool grants no permission. They do not assert that a person lacks the right to use the ordinary app, and no restriction or extra approval screen is added to ordinary personal entry. The user's instruction already authorizes this software work. Scientific choices in the roadmap remain unfilled.

Current verification and the remaining empirical/device work are recorded in the [central preparation report](PRE_DATA_PREPARATION_REPORT.md).
