# AI-1 local study data dictionary

Dictionary version: `ai1-local-study-dictionary-v1`<br>
Date: October 17, 2026<br>
Protocol: `tonyo-sleep-evening-energy-v0.3-draft`<br>
Status: implementation dictionary for the draft measurement protocol; final software verification is recorded in [DATA_READINESS_REPORT.md](DATA_READINESS_REPORT.md).

This dictionary describes device-local measurement history, study plans, frozen daily feature events and the derived audit tables. It does not define a training dataset. Every export retains `trainingEligible: false`; an event records an opportunity and feature snapshot without a fitted model or numeric prediction.

The contract remains a [review draft](PREDICTION_CONTRACT.md). Implementing a rule makes it testable; it does not establish a validated questionnaire, scientific threshold, approved study or model permission.

## 1. Units, identity and timing

| Concept | Definition |
| --- | --- |
| Capture session | A device-local journal started after explicit enablement. Existing app records are not backfilled as prospective observations. |
| Source identity | `(collection, sourceId)` in the private journal. Ordinary edits create consecutive revisions of the same identity. Exact retries are deduplicated. |
| Study plan | A future date interval with one fixed IANA timezone, one sleep source and one protocol version. A source change requires a new plan/session variant rather than fallback. |
| Daily opportunity | One study participant, protocol and local date. Its frozen UTC boundaries are derived using the study timezone. A date remains in the assessment after it closes even if the app never opened. |
| Feature event | An immutable morning snapshot with a durable-save receipt. It records eligible sleep or an explicit abstention; it is not a numeric model prediction. |
| Raw measurement | One original check-in or its later substantive revision. Partial responses are retained. This is separate from the one-row-per-opportunity analysis table. |
| `asOf` | UTC instant at which a versioned assessment is frozen. Only closed outcome windows enter its closed denominator; available revisions are evaluated as of this instant. |
| Missing value | JSON `null` or an explicit status, never zero or an invented value. A missing sleep start stays missing. |

Timestamps use UTC ISO 8601 strings with `Z`. `localDate` uses `YYYY-MM-DD`. Observation time, local durable availability, event attempt time and initial outcome save time are different facts. A late import or edit cannot borrow an earlier sleep-end timestamp as proof of availability.

## 2. Private journal envelope and revision fields

These fields remain in protected local storage; the envelope is not copied verbatim into the dedicated private export.

| Field | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | Local capture-envelope schema version (`1`). |
| `owner` | string | Local owner scope for separation and deletion; not an analysis identifier and not exported. |
| `captureId` | string | Random local capture-session identity. |
| `startedAt` | UTC timestamp | Start of the current capture session. |
| `enabled` | boolean | Persisted capture enabled state. |
| `trainingEligible` | boolean | Always `false`. |
| `entries` | array | Whitelisted immutable source revisions. |
| `tombstones` | array | Opaque collection-scoped identities erased from the journal; suppress resurrection. |
| `collection` | enum | `sleepLogs`, `checkIns` or `study`. |
| `sourceId` | string | Local identity of the observation, study record or event. Export substitutes a pseudonymous identity. |
| `revision` | positive integer | Consecutive revision number beginning at 1; incomplete original provenance cannot be invented by editing an older record. |
| `data` | object | Collection-specific whitelist below; notes and arbitrary payloads are rejected. |
| `originalLocal` | boolean | Whether the first captured revision came from an explicit original local save. |
| `lineageComplete` | boolean | Whether the captured chain establishes the required original and revision provenance. |
| `acknowledgedAt` | timestamp or null | Native durable payload-completion receipt. A null or interrupted receipt is unavailable evidence and pauses capture. |

Storage is bounded; it does not silently discard old revisions to make space. Sign-out unloads the active owner. Turning history off, clearing applicable tracking data, resetting the device or deleting the account clears the relevant history. Source deletion removes retained revisions and invalidates derived event payloads. Relevant source tombstones conservatively block the plan's sleep/response lineage, requiring clear/restart. Queued Health erasure and owner/generation checks prevent pending capture from recreating erased evidence. Deletion rights take precedence over ordinary immutability.

## 3. Raw manual sleep and self-report payloads

| Collection / field | Type | Meaning |
| --- | --- | --- |
| `sleepLogs.startedAt`, `endedAt` | UTC timestamps | Entered bedtime and wake time. |
| `sleepLogs.durationHours` | finite number | Entered bedtime-to-wake interval in hours; may include awake time. |
| `sleepLogs.isNap` | boolean | Naps are excluded from this first main-sleep feature. |
| `sleepLogs.source` | enum | `manual`. |
| `checkIns.observedAt` | UTC timestamp | Time the submitted response describes. |
| `checkIns.localDate`, `timezone`, `utcOffsetMinutes` | string, nullable string, integer | Captured date and timezone context. Unknown/incompatible timezone does not qualify as proven primary provenance. |
| `checkIns.period` | enum | Explicit `morning` or `evening`; not inferred from the clock. |
| `checkIns.questionnaireVersion`, `questionnaireLanguage` | strings | Definition version and language. The primary draft requires the exact English snapshot. |
| `checkIns.source` | enum | `selfReport`. |
| `checkIns.sharedHeading` | string | Actual heading displayed with the response, currently “How do you feel right now?” in English. |
| `checkIns.definition` | object | Full ordered definition, including version, language, kind, status, recall context, labels, item prompts, anchors and optional flags. |
| `checkIns.ratings` | object | Separate `energy`, `fatigue`, `sleepiness`, `focus`, `mood`, `stress` values; each integer 1–10 or null, with at least one answered. |

The first model candidate would receive only main-sleep duration. Other ratings, legacy scores, notes, dates and schedules are not added as predictors. The primary outcome is raw Energy on its original 1–10 scale, not the legacy 0–100 score or a composite.

## 4. Study record payloads

All study records have `kind` and `observedAt`; their native durable receipt remains in the surrounding capture entry.

| Kind / field | Type | Meaning |
| --- | --- | --- |
| `plan.startDate`, `endDate` | date strings | Inclusive prespecified study calendar. Plan creation must precede its first day. Software interval bounds are storage/operational limits, not sample-size advice. |
| `plan.timezone` | IANA timezone | Fixed study calendar timezone. Unknown or ambiguous calendar boundaries fail explicitly. |
| `plan.source` | enum | `manual` or `appleHealth`; no mixing or automatic fallback. |
| `plan.protocolVersion` | string | Contract version used by the plan. |
| `event.localDate`, `timezone`, `source` | strings/enums | Day and fixed source/calendar to which the event belongs. |
| `event.sleepStatus` | status string | Eligibility/abstention decision at the event. |
| `event.feature` | object or null | Frozen selected sleep revision; null if no eligible feature. |
| `event.feature.sourceKey`, `revision` | string, integer | Exact source and revision selected, enabling lineage checks. |
| `event.feature.durationHours` | finite number | Sole candidate feature. The provisional 0.5–16-hour software range is a sanity bound, not a normal physiological range. |
| `event.feature.startedAt` | timestamp or null | Actual retained start, if known; never inferred by subtracting duration. |
| `event.feature.endedAt`, `availableAt` | UTC timestamps | Sleep end and issuing-device availability, both at or before cutoff. |
| `health.samples` | array | Whitelisted sleep sample batch captured before app reconciliation. Each sample has `id`, `type`, `value`, `timestamp`, `sourceGroup`. |
| `health.samples[].type` | enum | `sleepAwake`, `sleepCore`, `sleepDeep`, `sleepRem` or `sleepUnspecified`. |
| `health.samples[].value` | finite number | Imported interval duration in hours. |
| `health.samples[].timestamp` | UTC timestamp | Imported interval endpoint as represented by the app health sample. |
| `health.samples[].sourceGroup` | string | Source grouping used to keep competing provider/episode evidence distinguishable. Not a candidate predictor. |
| `timezone` | marker record | App-detected departure from the planned timezone; not a claim of continuous travel observation. |

Raw Health batches retain sample end times from 24 hours before the first study day through the final morning cutoff. Later corrections to in-scope samples remain eligible for capture; unrelated later sleep is excluded. These batches are evidence of what the app fetched and durably retained. They do not prove that HealthKit exposed every external record, or make Health and manual duration semantics interchangeable. Missing-sample comparisons cover sample start times in the recent 29 elapsed days, inside the native rolling 30-calendar-day query. Older external deletions/changes may remain undetectable and require explicit history clearing. An observed timezone mismatch is recorded and stops subsequent snapshots; the app does not observe travel continuously while suspended.

## 5. Derived opportunity and outcome audit

The builder uses fixed calendar boundaries: cutoff 10:00; event interval `[10:00, 10:15)`; Evening interval `[18:00, 22:00)`. Both response observation and original durable save must be in the Evening interval. The first compatible Evening submission is selected before inspecting Energy; a missing Energy answer is not replaced with a later answer. A substantive later correction excludes the selected target under the draft policy.

| Logical field | Meaning |
| --- | --- |
| Dataset schema/version, protocol and `asOf` | Identifies exactly which build and rules produced the audit. Synthetic and captured inputs are separate paths. |
| Pseudonymous participant and opportunity IDs | Link private analysis tables without exporting an account identity. One participant is not inferred from one submission. |
| Local date, timezone and UTC boundaries | Audit timing and preserve the planned denominator; not model predictors. |
| Sleep, issuance and outcome statuses | Three separate dimensions of missingness. An outcome can be complete when no morning event exists. |
| Event attempt and durable timestamps | Prove actual event availability during the allowed interval; absent timestamps cannot be reconstructed from current records. |
| Frozen feature and source/revision reference | Preserves pre-cutoff information without later edits rewriting the event. |
| Selected response identity and timestamps | Links the original selected submission, its observation, initial durable save and analysis availability. |
| `energy` | Selected raw integer 1–10 or null. |
| Pair indicator | True only when event issuance and outcome matching both qualify. It is not training eligibility or accuracy. |
| `trainingEligible` | Always false, including otherwise valid pairs. |

Examples of explicit statuses include `eligible`, `no_eligible_sleep`, `ambiguous_sleep`, `unknown_sleep_availability`, `sleep_lineage_incomplete`, `conflicting_sleep_revision`, `not_issued`, `missed_cutoff`, `save_not_proven`, `matched`, `missing_energy`, `no_response_in_window`, `selected_response_revised`, `response_lineage_incomplete`, `timezone_changed` and `withdrawn`. Preserve the actual implementation status instead of collapsing everything into “missing.”

## 6. Exact private export schema

The [study adapter](../lib/src/ai1_study.dart) emits `tonyo-study-export-v1`; the [controller](../lib/src/app_controller.dart) adds `readiness` using `ai2-measurement-readiness-v1`. The builder's lower-level audit schemas are `ai1-captured-audit-v1` and `ai1-synthetic-audit-v1`. Synthetic and captured inputs cannot be mixed.

| Export field | Meaning |
| --- | --- |
| `schemaVersion`, `datasetVersion`, `asOf` | Format, named analysis version and UTC freeze. The app automatically assigns `local-<UTC microseconds>` for each assessment/export. |
| `synthetic`, `trainingEligible` | Captured private export is `false` for both. Synthetic audit tools label their evidence separately. |
| `protocolVersion`, `source`, `measurement` | Fixed draft protocol/source and full ordered English measurement context. |
| `calendar` | `startDate`, `endDate`, `timezone`, `plannedOpportunities` and `closedOpportunities`. |
| `coverage` | Counts and separate sleep/issuance/outcome status distributions from the closed-opportunity audit. Internal `issued` means a validated snapshot; it is not evidence of numeric predictions. |
| `predictionEvents[]` | One row per closed opportunity, including unopened days. `eventKind` is `feature_snapshot`; `prediction` and `modelVersion` are null. `snapshotStatus` replaces internal `issuanceStatus` and maps `issued` to `saved`. `analysisPair` replaces fixture terminology. |
| `predictionEvents[].participantKey`, `opportunityId` | Export-local `participant-1` and `day-<localDate>` labels, not account IDs or durable cross-export person identities. |
| `predictionEvents[].feature` | Frozen duration, source, pseudonymous `sourceKey`, revision, actual start/end/availability and selection dependencies. Health features additionally link `parentQueryId` and zero-based `episodeIndex` to their retained query. |
| `predictionEvents[].responseId`, `energy` | Pseudonymous selected response link and original integer 1–10 target or null; missing/revised responses remain explicit statuses. |
| `rawMeasurements[]` | Whitelisted manual sleep/check-in revisions: `recordId`, `collection`, `revision`, `availableAt`, `lineageComplete`, and the collection-specific `data`. No notes or account identities. |
| `healthQueries[]` | Pseudonymous `queryId`, availability/lineage and interval samples. Each sample has aliased `sampleId`/`sourceGroup`, `type`, `valueHours`, and `endedAt`. Original Health sample and producer IDs stay local. |
| `provenance` | `planSavedAt`, `sleepSelectionVersion` (`tonyo-study-sleep-v1`), `timezoneChanges` with observation/availability timestamps, `deletedSourceCategoryCounts` for `sleepLogs`/`checkIns`/`study`, and `deletionPolicy`. These describe conservative exclusions without restoring deleted payloads. |
| `readiness` | Aggregate coverage, report-local participant aliases, Energy summaries, response timing, definitions, review gaps and denominator notes. `modelingReady` and `trainingAllowed` are false. |
| `limitations` | Operational and privacy boundaries accompanying the private artifact. |

Aliases are scoped to the current export; never use equal labels from different files to infer identical people or records. Within an export, `recordId`, `responseId`, `sourceKey` and `parentQueryId` preserve the appropriate table links. Raw tables can contain retained records beyond the closed daily rows; they must not be counted as extra opportunities.

## 7. Private export procedure and retention

1. Open **Privacy center → Local study history** and explicitly enable **Keep local study history**. Open **Study tools**, choose a fixed source and 1–366 calendar days, then use **Start tomorrow’s plan**. The default 28 days is a scheduling convenience, not a sufficiency threshold. Existing records are not backfilled.
2. After the relevant windows close, use **Assess local readiness** for aggregate counts only. This read-only action does not save a file. The complete report includes the automatically named dataset version, UTC `asOf`, fixed source/protocol and measurement context.
3. Use the separate **Save private study export** action, review its confirmation and choose **Choose private location**. This saves whitelisted JSON through the native file picker, with no clipboard fallback and no Tonyo upload.
4. Choose an on-device folder if the copy must stay local; the system picker may offer cloud destinations. Precise timing is audit metadata needed to check this contract, not a model feature. Pseudonymization does not make health/sleep data anonymous.
5. Track copies shared outside the app. Local deletion invalidates local history and derived snapshots; it cannot recall a saved copy from another location or recipient. Delete obsolete copies separately. Ordinary retrospective research exports and device backups do not include the local study journal.

No real participant records should be committed to this repository or sent to coding/AI tools. Use the synthetic audit commands for software review. See [the readiness report](DATA_READINESS_REPORT.md) for metric denominators, verification evidence and remaining review decisions.
