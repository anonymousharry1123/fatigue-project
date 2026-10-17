# AI-1 implementation and AI-2 data readiness report

Report date: October 17, 2026 (America/Los_Angeles)<br>
Report version: `ai1-ai2-readiness-2026-10-17-v1`<br>
Protocol: `tonyo-sleep-evening-energy-v0.3-draft`<br>
Evidence scope: repository implementation and synthetic software checks; no real participant records inspected.

## Executive Summary

**Decision: measurement readiness for modeling is not established.** The user answered “No / unsure — report readiness gaps” when asked whether prospective local study history already existed. No participant data were requested, accessed, or analyzed for this report. This is a completed assessment of the evidence currently available, with explicit gaps; it is not a finding that the user's actual history contains zero observations or that a model is ready to train.

**AI-1 infrastructure is implemented; AI-2 assessment tooling and this evidence-gap assessment are complete.** Final software verification is recorded below. This does not complete an empirical pilot: no prospective participant dataset was available for inspection. Software tests cannot establish comprehension, adherence, outcome variation, or an adequate study size.

## 1. What the implementation covers

| Requirement | Implementation and boundary |
| --- | --- |
| Prespecified denominator | A future-dated study plan fixes its calendar interval, IANA timezone, protocol and one sleep source. Assessment includes every closed opportunity in that interval, including dates when the app was unopened. Future and still-open outcome windows are excluded from the closed denominator. |
| Morning information set | An immutable event captures the selected main-sleep revision and the information known by the 10:00 cutoff. A local durable receipt must satisfy the proposed `[10:00, 10:15)` event window. A missed window is retained as missing issuance; no morning event is fabricated later. |
| Sleep provenance | Manual saves preserve consecutive revisions. Apple Health ingestion captures the fetched sleep batch before ordinary app reconciliation, so an app-preferred summary alone does not establish source uniqueness. Manual and Apple Health are separate source variants; neither fills the other's missing days. |
| Later outcome | The builder selects the first qualifying, compatible Evening submission before reading Energy, using both observation and initial durable save times in `[18:00, 22:00)`. Missing Energy, selected-response revisions, lineage failures and observed travel have explicit statuses; incompatible submissions remain in raw history for review. |
| Dataset audit | Versioned rows preserve the opportunity, fixed time boundaries, sleep/issuance/outcome statuses and linked outcome provenance. The raw measurement and opportunity tables remain distinct. |
| Private export and lifecycle | Dedicated export uses export-scoped pseudonyms and excludes notes and account identifiers. Local erasure removes derived event payloads; relevant source tombstones conservatively invalidate the plan's sleep/response lineage until clear/restart. Already shared/exported copies require separate deletion by their holder. |
| Modeling boundary | Events are measurement-feasibility snapshots, not numeric predictions. No candidate model, fitted preprocessing, imputation, training, performance claim or production release is added. `trainingEligible` stays false. |

See the [versioned data dictionary](AI1_DATA_DICTIONARY.md), [prediction contract](PREDICTION_CONTRACT.md), and roadmap [AI-1](../TONYO_BIOLOGY_AND_AI_ROADMAP_v2.md#21-ai-1-build-a-trustworthy-analysis-dataset) / [AI-2](../TONYO_BIOLOGY_AND_AI_ROADMAP_v2.md#22-ai-2-check-whether-the-measurements-are-ready-for-modeling).

## 2. Verification record

| Check | Observed result |
| --- | --- |
| `flutter test --no-pub --concurrency=2 --reporter expanded` | **1,322 passed, zero failures, one optional screenshot test skipped.** This is one completed full-suite run; focused runs are not added to the total. It includes 73 new study, controller, Health-lineage, readiness and UI regression tests. |
| `dart analyze lib test tool` | **No issues found.** |
| `flutter build ios --simulator --no-codesign --no-pub --verbose` | **Passed**, exit 0; produced `build/ios/iphonesimulator/Runner.app`. Final Xcode build took 21.0 seconds. No installation or deployment was performed. |
| `dart run tool/ai1_synthetic_audit.dart`, repeated with `--apple-health` | Both source variants produced four invented opportunities, two simulated issuances, two matched outcomes, one fixture pair and zero training-eligible rows. |
| `dart run tool/ai2_readiness_audit.dart --json` | Empty supplied inputs produce zero supplied opportunities, unavailable rates, `modelingReady: false` and `trainingAllowed: false`. Saved receipt checked below. |
| Formatting and document hygiene | All 18 changed/new Dart files passed `dart format --output=none --set-exit-if-changed` with zero changes. Seven documentation files passed local-link and fenced-code checks; `git diff --check` passed. |

The first simulator attempt ended with Flutter's missing `TARGET_BUILD_DIR` setting error after Xcode finished. A separate `xcodebuild -showBuildSettings` succeeded, and the full Flutter build then passed without application or project changes. The final build retains an existing packaging warning: an extension's build number is 32 while the containing app's is 37. This is not release sign-off; synchronize those versions before a release build.

Physical-device protected storage, power-loss behavior, actual Health permissions, native file-picker interaction and OS background execution were not exercised. Firestore rules and the separate cloud/native integration harness were not rerun; their earlier results remain historical. Unit/widget tests use synthetic data, and simulator compilation does not establish physical-device behavior.

Local verification logs: `/private/tmp/tonyo-ai1-ai2-full-final.log`, `/private/tmp/tonyo-ai1-ai2-analyze-final.log`, `/private/tmp/tonyo-ai1-ai2-ios-final.log`, `/private/tmp/tonyo-ai1-ai2-xcode-settings.log` and `/private/tmp/tonyo-ai1-ai2-ios-retry.log`.

Only synthetic fixtures may appear in repository test artifacts. Their participant counts, completion fractions, distributions and pair counts describe invented cases, never real study feasibility or predictive accuracy.

The reproducible [AI-2 audit script](../tool/ai2_readiness_audit.dart) exercises the empty-input assessment path. The [empty-input JSON receipt](reports/ai2_no_data.json) is a software smoke check using supplied empty inputs; it is not a census of the user's device or proof that no real observations exist.

## 3. Real-data evidence available now

| AI-2 question | Current finding | Evidence needed |
| --- | --- | --- |
| Independent participants and eligible days | Not assessed. Own-data-first is an intended population, not a verified enrolled sample. | An agreed protocol and prospective calendar with local history, then counts by pseudonymous participant and source variant. |
| Scheduled check-ins and completed Energy outcomes | Not assessed; no real denominator or numerator was inspected. | Closed planned opportunities, every outcome status, and separate issuance/completion/paired coverage. |
| Missingness and lateness | Not assessed. Missing history is not evidence of missing behavior. | Original observations, initial durable save receipts, expected windows, and explicit unmatched/late records. |
| Energy distribution and stability | Not assessed. | Counts at each original 1–10 response, missing count, range, distinct values, endpoint frequencies and variation over time. |
| Sleep source and morning availability | Not assessed. | Selected-source episodes, acquisition/revision receipts and competing-episode evidence captured before cutoff. |
| Measurement compatibility and comprehension | Exact English snapshot is implemented; real comprehension is not established. | Recorded wording/version/language and a review of how the user interprets the prompt and “about average.” |
| Questionnaire completion | No weekly questionnaire is selected for this protocol; not applicable, not a zero completion rate. | A separate prespecified instrument, version and recall interval if later included. |
| Exclusions and retained pairs | Not assessed. | Counts for all sleep, issuance and outcome statuses, including days with no usable pair. |
| Adequate size for a personal model | Not established; no numerical sufficiency threshold is adopted here. | Agreed size/precision rationale, repeat observations, observed target variation and proposed model complexity. |

No percentages, mean Energy, prediction errors, confidence intervals or “days remaining” estimates can be calculated from the available real-data evidence. A zero denominator must produce an unavailable rate, not 0% or 100%.

## 4. How to interpret the local readiness metrics

The unit is one planned participant–protocol–local-date opportunity. An original submission or revision is not an extra participant or independent day. Analyze source variants separately. The local history is one device's record; multiple devices must not be pooled as independent people. Readiness rates use non-withdrawn closed opportunities; withdrawn rows are counted separately. Participant counts represent retained opportunities, not an enrollment census.

| Metric | Definition and denominator |
| --- | --- |
| Planned opportunities | Prespecified dates in the study plan. Report future/open dates separately. |
| Closed opportunities | Planned dates whose entire outcome window has ended by the named analysis `asOf` instant. Includes unopened days. Non-withdrawn closed opportunities form `scheduledEveningCheckIns`. |
| Sleep eligibility | Non-withdrawn closed opportunities with `sleepStatus = eligible`, with `scheduledEveningCheckIns` as the rate denominator. This alone does not prove an event was issued. |
| Event issuance | Non-withdrawn closed opportunities with a validated, durable event in the issuance window, divided by `scheduledEveningCheckIns`. The private export names successful issuance `snapshotStatus = saved`; it is a feature snapshot, not a numeric model prediction. |
| Outcome completion | Non-withdrawn closed opportunities with `outcomeStatus = matched`, divided by `scheduledEveningCheckIns`. A matched evening outcome can exist without a morning event. |
| Paired coverage | Non-withdrawn closed opportunities with both a saved snapshot and a matched outcome, divided by `scheduledEveningCheckIns`. Conditional completion among saved snapshots is a different denominator and must be labeled. |
| Missingness | Missing or unusable outcomes over `scheduledEveningCheckIns`; preserve `missing_energy` separately from `no_response_in_window`. |
| Lateness | Original Evening responses observed or initially saved at/after 22:00, divided by timing-assessable original Evening responses attributed by recorded local date. Early and invalid timing are separate. Late analysis availability alone is not a late local response. |
| Energy distribution | All matched original 1–10 outcomes, including those without a saved morning snapshot. Report pooled and within-participant distributions, endpoint counts and repeated observed-rating runs. Missing targets are omitted, never filled. |
| Exclusion reasons | Separate sleep, issuance and outcome status counts. A single opportunity can contribute one status to each domain, so the three tables must not be added into a single mutually exclusive total. |
| Source/version summaries | Report counts by fixed sleep source, exact measurement snapshot/version and language. A measurement version string alone does not prove identical wording. |

Descriptive means and standard deviations, if supplied, summarize numeric codes on the original scale; they do not validate equal spacing or convert Energy into an objective biological measurement. Endpoint or low-variation flags are descriptive review prompts, not diagnoses or validated stop thresholds. Repeated observations from one person do not establish transfer to new people.

## 5. Decisions still needed before modeling

| Planning item | Current state / next decision |
| --- | --- |
| Population and inclusion | Own data first is selected. Age eligibility and any required permission/research review remain unrecorded. |
| Primary construct and wording | Raw evening Energy 1–10 is the draft target. Clarify the reference for “about average” and review the full English presentation. |
| Exact operational rules | 10:00 and 18:00–22:00 are selected. Confirm the proposed 15-minute issuance tolerance, endpoint rules, fixed timezone/travel handling, source isolation, first-response matching and revision exclusion. |
| Pilot and main evaluation | Size, duration, acceptable completion/lateness and reasons for those choices remain open. The plan's software date bounds are not statistical recommendations. |
| Minimum personal history | Undecided. The legacy 14-day/30-day/5% settings do not become thresholds for this experiment. |
| Question revision after pilot | Define how wording changes create a new compatible/incompatible measurement version before evaluating outcomes. |
| Review and data-use scope | No mentor approval, consent, training permission or release approval is inferred from authorization to implement this work. Record the appropriate review and participant-facing scope before model use. |
| Future model comparison | Baselines, chronological partitions, untouched test data, metric, precision and acceptance criteria belong to AI-3/AI-4 and are not completed by this report. |

The practical next step is to resolve the remaining measurement/protocol decisions, enable a future local study plan when appropriate, and collect ordinary prospective observations. Then rerun the private readiness assessment and replace the “not assessed” findings with observed counts and reasons. If timing, comprehension or completion is inadequate, improve collection first. If Energy barely varies, report that limitation rather than adding model complexity.

## 6. Using the local tools

Open **Privacy center → Local study history**, enable **Keep local study history**, then open **Study tools**. Opening the screen does not start collection, generate an assessment or save an export. An explicit **Start tomorrow’s plan** saves a future calendar with one fixed source and timezone. The configurable 1–366-day interval and default 28 days are scheduling controls, not a sample-size recommendation.

After windows close, **Assess local readiness** displays only aggregate counts. **Save private study export** separately confirms creation of a sensitive local file and opens the system file picker. Select an on-device folder to keep it local; the picker may also offer cloud destinations. Tonyo does not upload this export or copy it to the clipboard. The export contains the detailed readiness JSON as well as the pseudonymous audit tables. The app assigns a fresh `local-<UTC microseconds>` dataset version and records its UTC `asOf` automatically.

## 7. Scope and limitations

- No private app history, account, Health record or participant identifier was examined for this report.
- A foreground timer checks each minute and refreshes the device timezone. A local event still depends on the app executing in the issuance window; reliable OS background scheduling and continuous travel detection are not guaranteed. Unopened days remain visible in coverage. An observed timezone mismatch stops further snapshots until the history is cleared and a new plan starts.
- Apple Health lineage preserves successful readable query batches before ordinary app reconciliation. Retained sample end times are bounded from 24 hours before the first study day through the final morning cutoff; later corrections to those in-scope samples can still be captured. Missing-sample comparisons use sample start time within a recent 29-elapsed-day window, avoiding false deletion from the native rolling 30-calendar-day query boundary. This does not prove complete read authorization or detect all older external changes. Clear affected history when older changes are known.
- Source deletion invalidates event payloads and conservatively blocks the relevant sleep/response lineage for the whole plan. This favors explicit unavailability over resurrecting a deleted source or silently substituting another response. Clear/restart is required to resume a usable plan after such invalidation.
- Device durable receipts establish the implemented local availability rule, not independent attestation of every clock or power-loss scenario. Interrupted or corrupt history cannot be treated as valid evidence.
- Pseudonymous exports still contain sensitive measurement and timing data. Keep them private and do not attach them to coding tools or public repositories.
- AI-1 software completion and AI-2 assessment completion do not establish real-data modeling readiness. Real-data AI-3 model development remains gated by the evidence and decisions above. The separate [AI-3 synthetic preparation](AI3_SYNTHETIC_PREPARATION.md) exercises comparison software with invented records only and does not change this readiness finding.
