# AI-3 synthetic comparison preparation

Date: October 17, 2026<br>
Document version: `ai3-synthetic-preparation-v1`<br>
Protocol: `tonyo-sleep-evening-energy-v0.3-draft`<br>
Evidence scope: invented AI-1 records only; no participant records, app integration or real-data model activation.

## Outcome and boundary

**AI-3 preparation supplies a reproducible synthetic comparison runner for B0, B1 and M1. Real-data AI-3 comparison and AI-4 evaluation remain pending.** The runner exercises how earlier personal history and morning sleep snapshots produce later numerical estimates. Its errors and coverage describe invented fixtures, not Tonyo's accuracy, sleep effects, measurement validity or readiness for deployment.

The [AI-2 readiness decision](DATA_READINESS_REPORT.md) remains **not established**. No prospective participant dataset was inspected. Synthetic fitting does estimate regression coefficients; it does not train on private records, activate an app model or approve the unresolved scientific choices in the [prediction contract](PREDICTION_CONTRACT.md).

Implementation: [comparison runner](../lib/src/ai3_comparison_runner.dart) and [fixture-only command](../tool/ai3_synthetic_comparison.dart). This preparation adds no runtime UI, dependencies, data import command, population fallback or automatic collection.

## Fixed synthetic experiment manifest

Each run fixes its protocol, selected sleep source, exact measurement definition and chronological boundaries before replay. The same source and definition rules used by AI-1 apply. Manual is the command's default; Apple Health runs as a separate source variant.

| Manifest concept | Fixed meaning |
| --- | --- |
| Evidence | Raw AI-1 days explicitly marked synthetic; inputs marked captured are rejected. A caller falsely relabeling private data does not establish synthetic provenance or permission. The CLI has no input-file path. |
| History start (`historyStart`) | Earliest permitted opportunity, defined by its morning cutoff in UTC. |
| Evaluation interval (`evaluationStart`, `evaluationEnd`) | Start is inclusive and end is exclusive, both compared with the opportunity's morning cutoff in UTC. |
| Final analysis as-of (`analysisAsOf`) | Freeze for evaluating eventual target availability/revisions; all supplied outcome windows must have closed. It does not make later labels available to earlier simulated predictions. |
| Input interval | Inputs must belong to the declared history/evaluation interval; unexpected out-of-interval days do not silently expand the experiment. |
| Candidate set | B0 personal mean, B1 latest personal outcome, M1 sleep-only ordinary least squares. No model or hyperparameter search. |
| Replay policy | Per-person expanding history, rebuilt at every evaluation morning cutoff. Other people's records never fill an individual's history. |
| Output policy | Retain raw finite estimates; clip to 1–10, with no rounding before metrics. This is a synthetic execution policy, not an approved deployment rule. |
| Cold start | Abstain when a method lacks its required earlier evidence. No default neutral rating, target imputation or pooled-person substitute. |

The manifest schema is `ai3-synthetic-expanding-personal-v1`; its result schema is `ai3-synthetic-comparison-v1`. The result retains a canonical `inputSnapshot`, manifest and per-method training opportunity IDs so the replay can be audited. One participant must keep one planned timezone, exact duplicate opportunities collapse, and conflicting copies fail.

The manifest is a software experiment specification. It does not fill the roadmap's undecided real-data model-family, sample-size, split, tuning, consent, uncertainty or promotion decisions. Deterministic fixture identities and artifact provenance should be used when reproducing this run; export-local participant aliases from real study files are not valid cross-file identities. The runner validates supplied opportunities against the interval but does not invent omitted days; fixtures must explicitly supply unopened opportunities for them to enter coverage.

## History and method definitions

For each evaluation opportunity, the runner rebuilds eligible, closed earlier AI-1 history **as of that morning's cutoff**. It uses original response availability and revision evidence at that instant. A later answer, correction or delayed analysis receipt cannot improve an earlier estimate. Earlier evaluation-day outcomes may enter a later day's expanding history only after they have become eligible and available; this is sequential replay, not one model frozen for the whole evaluation interval.

| Method | Earlier evidence | Estimate and abstention |
| --- | --- | --- |
| B0 | The same person's prior matched compatible Evening Energy outcomes. These historical outcomes do not require an eligible sleep feature or morning event. | Arithmetic mean of the available earlier ratings; abstain without personal history. |
| B1 | The same eligible personal Evening outcome history as B0. | Latest by observation time, then initial save time, then opportunity ID; abstain without personal history. |
| M1 | The same person's earlier eligible issued sleep/outcome pairs with valid prior execution, preserving each historical morning's frozen sleep feature. | Centered ordinary least-squares regression of raw Energy on main-sleep hours, with fitted intercept. At least two pairs and centered sleep sum of squares greater than `1e-12` are required to calculate a slope. |

M1's minimum pair count and `1e-12` degeneracy guard are numerical requirements, **not sufficient study sizes or meaningful-variation thresholds**. Its coefficient is fitted without a positive-sign constraint; a non-finite fit abstains. No scaling, imputation, extra covariate, tuning, regularization or population model is added. A model using the personal mean as an extra predictor would be a different candidate; M1's sole predictor remains sleep duration. Withdrawal/deletion markers apply to every replay so an earlier as-of reconstruction cannot resurrect erased evidence; ordinary revisions still follow availability-time rules.

Execution and scoring have separate gates:

- B0 and B1 require the current synthetic day's actual morning creation and durable timestamps in `[10:00, 10:15)`. They can issue without eligible current sleep. Their own historical availability rules still apply.
- M1 additionally requires an eligible frozen current sleep feature. Late sleep imports never become pre-cutoff evidence.
- A missing/revised/unusable eventual target is never filled. Predictions may exist on unscored opportunities, so prediction coverage and scored coverage are reported separately.
- An observed timezone change at/before durable morning execution prevents execution. A change at/before the outcome makes that target unavailable for scoring/history, including for the baselines. The eventual target is assessed at the manifest's final analysis freeze.

## Metrics and interpretation

Metrics use the clipped, unrounded estimate on the original 1–10 scale; the raw estimate remains available for audit. Signed error is **estimate minus observed Energy**, so a positive mean signed error denotes overprediction in the fixture. A missing denominator produces an unavailable metric rather than an invented zero error.

| Output | Interpretation |
| --- | --- |
| Per-method coverage | Predictions and scored outcomes divided by supplied non-withdrawn evaluation opportunities, including missed executions and missing outcomes. Withdrawal is counted separately. Method status counts describe abstentions; row/outcome status counts retain target missingness. A method's larger coverage does not imply lower error. |
| Per-method MAE and signed error | Describe only that method's scored rows. Unequal scored sets can have different difficulty. |
| Per-participant results and macro MAE | Separate personal results and an equal-participant average over participants with scored outcomes; these are not independent-person evidence when the people themselves are invented. |
| Pairwise common-set comparison | Recompute each pair of methods on identical scored opportunities and retain those opportunity IDs. `maeDifference` is left MAE minus right MAE; a negative value favors the left method on that common fixture set. A difference computed from separate overall MAEs is not a common-set comparison. |
| All-method common set | Retain the opportunity IDs and method metrics for rows scored by B0, B1 and M1 together. This set can be smaller than a pairwise set. |
| Raw/clipped predictions and provenance | Allow inspection of history cutoffs, training evidence and output policy without mistaking a fixture result for a real prediction record. |

No numerical fixture performance is promoted to a model-selection, biological or clinical finding. `finalHoldout` is explicitly false: earlier evaluation outcomes may enter later replay history. No uncertainty interval, significance claim, acceptance threshold or final held-out evaluation is inferred from these outputs. AI-4 still needs an agreed real-data evaluation and uncertainty plan.

## Reproduction and verification

Run from `app/` with the repository's available Dart SDK:

```sh
dart run tool/ai3_synthetic_comparison.dart
dart run tool/ai3_synthetic_comparison.dart --apple-health
```

The command generates its own invented records and accepts no participant input files. The saved [manual fixture artifact](reports/ai3_synthetic_manual.json) and [Apple Health fixture artifact](reports/ai3_synthetic_apple_health.json) retain the manifest, predictions, coverage and comparisons for review. Their subjects, dates and numerical outcomes are software fixtures.

The project declares Dart `^3.12.2` in [pubspec.yaml](../pubspec.yaml). [pubspec.lock](../pubspec.lock) records the resolved dependency graph and SDK constraints (`>=3.12.2 <4.0.0` Dart; `>=3.44.0` Flutter). This preparation introduces no dependency changes. The actual artifact-generation runtime was **Dart 3.12.2 stable, macos_arm64**. The lockfile SHA-256 was `ac28314661036de32319b41367ffd992b5e4f1978b7d58c29b0673c2813d11ae`.

Each saved artifact was regenerated by a second run of its corresponding command and matched byte for byte. This checks reproducibility of the invented inputs and current implementation; it does not establish empirical model validity.

Both source-variant CLI runs produced the following verified fixture counts. They demonstrate distinct denominators and cold-start/missing-data behavior; they are not participant results or sample-size advice.

| Fixture quantity | Count in each source variant |
| --- | ---: |
| Supplied unique opportunities | 19 |
| History-only opportunities | 5 |
| Evaluation opportunities | 14 |
| Executed evaluation opportunities | 13 |
| B0 predictions / scored outcomes | 12 / 11 |
| B1 predictions / scored outcomes | 12 / 11 |
| M1 predictions / scored outcomes | 10 / 9 |
| Outcomes scored by all three methods | 9 |

| Check | Observed result |
| --- | --- |
| `flutter test --no-pub --concurrency=2 --reporter expanded` | **1,350 passed**, zero failures, one optional screenshot test skipped. This completed full run includes all 28 new AI-3 regression tests; focused runs are not added to this total. |
| `dart analyze lib test tool` | **No issues found.** |
| Both CLI source variants, each run twice | Saved artifacts reproduce byte for byte. Schema/source, non-activation flags, coverage and prior personal-history linkage checks passed. Unsupported input-file arguments are rejected with usage and exit 64. |
| `dart format --output=none --set-exit-if-changed` on the three new Dart files | Zero changes. |
| Documentation and whitespace | Eight documents passed 172 local-file link checks and fenced-block balance; `git diff --check` passed. |

The new regression suite covers independently calculated baseline/regression values, future-label perturbations, delayed availability, later revisions, global erasure/withdrawal, participant isolation, baseline coverage without sleep, cold starts, degenerate/negative-slope regression, output clipping, missing targets, timezone changes, unequal-participant macro MAE and identical-set comparisons. Passing them establishes software behavior only.

Local final logs: `/private/tmp/tonyo-ai3-full-final.log` and `/private/tmp/tonyo-ai3-analyze-final.log`. Initial targeted analysis found two missing-brace style notices, corrected before the clean final run. No new iOS build, physical-device, Health permission, cloud or native integration check was performed for this standalone Dart runner; earlier AI-1/AI-2 platform results remain attributed to that work. There is no app consumer or dependency change in this preparation.

## Before real-data AI-3 or AI-4

The next empirical step remains resolving the measurement/protocol and study-size decisions, obtaining ordinary prospective observations under the appropriate scope, and rerunning AI-2 privately. A real-data comparison additionally needs approved data use, a separately fixed manifest, explicit history/update and output policies, chronological development/test design, suitable uncertainty assessment and prespecified promotion criteria. The synthetic runner does not accept private exports or bypass those decisions.
