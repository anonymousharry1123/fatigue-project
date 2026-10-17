# Frozen model evaluation — synthetic preparation only

Date: October 17, 2026<br>
Status: software rehearsal implemented; empirical AI-4 evaluation not performed.<br>
Decision: **No model promotion or real-data readiness conclusion.**

This report describes the executable [AI-4 evaluator](../lib/src/ai4_frozen_evaluation.dart). All observations are invented, and the fixed choices below are fixture settings. They do not fill the scientific review fields in the [prediction contract](PREDICTION_CONTRACT.md).

## Fixed experiment and access boundary

The fixture uses one protocol and one sleep-source variant per run. Training opportunities have morning cutoffs in October 1–5, 2026 UTC; models are fitted once at October 6, 10:00 UTC. Development opportunities cover October 6–8 and final opportunities October 9–12. Development outcomes are assessed at October 9, 10:00 UTC; final outcomes at October 13, 23:00 UTC. Exact UTC boundaries, source and full measurement definition are embedded in `ai4-synthetic-frozen-manifest-v1`.

`prepareSynthetic` accepts training and development partitions. `openSyntheticFinal` is a separate one-use call receiving final observations only after the model objects exist. This prevents accidental final-data reuse inside one in-memory experiment. It is not an attestation that a person has never examined a file, and it does not prevent someone from constructing a different experiment. Any real-data redesign after final inspection still requires fresh evaluation data.

Candidate M1 and comparator B0 are fixed before either evaluation partition. No selection from development performance, tuning, refitting, scaling or final-label update occurs. A new participant without a fitted personal model receives an explicit abstention; this is not a new-user transfer experiment.

## Methods and temporal rules

| Method | Frozen fit |
| --- | --- |
| B0 | Mean of compatible personal Evening outcomes available by the fit cutoff. |
| B1 | Latest compatible personal Evening outcome available by the fit cutoff. |
| M1 | Personal ordinary least squares with an intercept and main-sleep duration in hours; eligible prior morning snapshots paired with available Evening outcomes. |

These baselines stay frozen at the fit cutoff. They differ intentionally from [AI-3's expanding-history replay](AI3_SYNTHETIC_PREPARATION.md), whose baselines can use earlier evaluation-day answers. Both policies are named explicitly rather than compared as if they were the same experiment.

Each training opportunity must have a closed outcome window at fitting. Original availability, exact wording, selected-response revisions, fixed timezone and source lineage follow AI-1. Later ordinary revisions cannot retroactively rewrite an earlier fit. Withdrawal and source deletion remain erasure exceptions: known training tombstones in later supplied partitions invalidate the frozen fit, and explicit invalidation prevents final scoring. Upstream deletion must invalidate dependent retained artifacts; this synthetic evaluator is not a production deletion service.

Current baseline execution requires a timely simulated creation/durable receipt. M1 also requires a valid current sleep feature available by its cutoff. Unopened opportunities, failed execution, absent sleep and absent targets remain visible. No target is imputed. Two-pair and `Sxx > 1e-12` guards allow calculation; they do not establish statistical sufficiency. Negative fitted slopes are permitted. Raw predictions are retained, and scoring uses unrounded values clipped to 1–10.

## Fixture coverage

The same invented scenario runs separately with manual and Apple Health source labels. These counts are software checks, not participant results or sample-size guidance.

| Quantity | Development | Final |
| --- | ---: | ---: |
| Supplied evaluation opportunities | 6 | 8 |
| Simulated executions | 6 | 7 |
| Matched outcomes | 5 | 8 |
| B0 predictions / scored | 3 / 2 | 3 / 3 |
| B1 predictions / scored | 3 / 2 | 3 / 3 |
| M1 predictions / scored | 2 / 1 | 3 / 3 |
| M1–B0 common scored opportunities | 1 | 3 |

Only the first invented person has training history. The second person's withheld estimates exercise the no-population-fallback rule. Final labels do not update either person's frozen estimates.

Reports retain method-specific prediction/scored coverage, MAE, signed error, participant summaries and equal-participant macro MAE. The selected candidate and comparator are also evaluated on identical scored rows. `maeDifference` is candidate minus comparator; the artifact exports the paired errors and opportunity IDs for later statistical review. A smaller fixture error is not evidence of a real predictive advantage.

Uncertainty is explicitly **not estimated pending statistical review**. Repeated daily errors are not assumed independent. No confidence interval, hypothesis test, adequate sample size, subgroup claim or acceptance threshold is invented from synthetic data. The future empirical analysis must fix an appropriate method and study-size rationale before final inspection.

## Reproduction and evidence

From `app/`:

```sh
dart run tool/ai_predata_rehearsal.dart
dart run tool/ai_predata_rehearsal.dart --apple-health
```

The [manual rehearsal](reports/predata_manual.json) and [Apple Health rehearsal](reports/predata_apple_health.json) contain the frozen manifest, fitted synthetic artifacts, training evidence, partition membership, exact predictions, metrics, shadow simulation and unresolved review requirements. Neither command accepts input files or reads the app's local journal, accounts or Health data.

The [independent evaluation tests](../test/ai4_frozen_evaluation_test.dart) check known calculations, final-label and development-label perturbations, late availability, later edits, missing outcomes/features, cold starts, erasure, one-use final access, partition errors, deterministic duplicates, serialization and incompatible timezones. Consolidated observed test/build/native results are recorded in [PRE_DATA_PREPARATION_REPORT.md](PRE_DATA_PREPARATION_REPORT.md).

## Remaining empirical decision

Real-data AI-4 still requires an accepted protocol, prospective data readiness, a separately fixed empirical manifest and reviewed uncertainty/promotion criteria. No accept/revise/reject decision about a real model, mentor sign-off or deployment approval is represented by this rehearsal.
