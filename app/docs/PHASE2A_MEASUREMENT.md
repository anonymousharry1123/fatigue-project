# Phase 2A measurement foundation

Implemented October 4, 2026 after the user requested the next step in [roadmap v2](../TONYO_BIOLOGY_AND_AI_ROADMAP_v2.md). This completes the first usable slice of Sections 16 steps 1–3: definitions, check-in UI, and raw storage, plus a separate self-report display. It does **not** complete every Phase 2A acceptance criterion or approve a research protocol. The user-authored roadmap and its undecided research fields are unchanged.

## What the app now does

- Daily Check-in starts with all six ratings unanswered. Energy, Fatigue, Sleepiness, Focus, Mood and Stress each offer integer choices 1–10 and a skip/clear action. A respondent explicitly chooses Morning or Evening; a late response is not silently reassigned by the clock. At least one rating is needed to save a check-in; remaining ratings and the note are optional. This is a product entry rule, not a settled required-item study protocol.
- The supplied English draft Fatigue/Sleepiness/Focus questions and anchors are retained. Energy uses the supplied anchors and label; no unprovided Energy question was invented. Existing Mood/Stress anchors remain context measures. English, Spanish, Simplified Chinese and Traditional Chinese are supported.
- The form is labeled **“Tonyo research check-in — not a clinical assessment”** and explains that these are custom draft questions, not a validated instrument. No published questionnaire is included.
- Today shows the latest non-synthetic raw report for each selected period under **Today’s self-report**, separately from experimental score tiles. This is display selection, not the future research outcome-matching rule. History shows each retained submission, skipped values, original date/time, language and version. History grouping preserves the captured local date through travel.
- Editing a current draft response retains its original observation timestamp, local date/zone/offset, questionnaire version, language and exact displayed wording. A later interface-language change does not rewrite the measurement; its stored prompts remain in their original language during editing. `recordedAt` advances to the edit/save time.

Sources: [definitions](../lib/src/check_in_measurement.dart), [form](../lib/src/screens/daily_checkin_screen.dart), [raw report cards](../lib/src/widgets/self_report_card.dart), [Today](../lib/src/screens/today_screen.dart), [history grouping](../lib/src/daily_history_logic.dart), [measurement translations](../lib/src/l10n/measurement_translations.dart).

## Raw data and compatibility

The existing owner-scoped collection remains `users/{uid}/checkIns/{id}`. Cloud schema **16** adds the measurement format; local migration remains **1**. No bulk migration, new collection or real account operation was performed.

| Field | Meaning |
| --- | --- |
| `id` | Stable local ID, represented by the Firestore document ID in cloud storage. |
| `energy`, `fatigue`, `sleepiness`, `focus`, `mood`, `stress` | Independent integer answers 1–10 or null/missing. Explicit zero, fractions, nonfinite and out-of-range answers are rejected. Existing key names for the original three measures are retained. |
| `timestamp` | Actual observation instant, stored as UTC ISO text locally and a Firestore timestamp in cloud storage. |
| `recordedAt` | Actual save/edit availability time, distinct from the observation time. |
| `localDate`, `timezone`, `utcOffsetMinutes` | Captured local calendar date, validated device IANA identifier when available (otherwise null), and offset at the observation instant. Later travel does not replace them. |
| `period` | Explicit Morning/Evening selection, retained even when submitted late. A deliberate correction can change the selected period. |
| `questionnaireVersion` | Technical wording identifier `tonyo-self-report-draft-v1`; it does not mean a mentor-approved protocol. |
| `questionnaireLanguage` | `en`, `es`, `zh-Hans`, or `zh-Hant`. |
| `questionnaireSnapshot` | Exact presented language/version, custom/draft status, “right now” recall period and translated recall text, and ordered item IDs, labels, prompts, endpoint/midpoint anchors and optional-entry flags. |
| `source` | `selfReport` for the new measurement format. Existing demo/synthetic markers remain separately recognized. |
| `completionStatus`, `answeredItemCount` | Derived honestly from the six retained answers: `complete` for six, otherwise `partial` for one to five. An empty form is not a submission. |
| `note` | Optional user text; the form trims leading/trailing whitespace on save and never automatically translates it. |

Old rows receive no invented fatigue/sleepiness/focus, language, zone, measurement version or completeness. Historical fractional values remain intact. For pre-period 1–5 records, the former normalized 1–10 projection remains available only for legacy compatibility; original numeric answers and absent period survive serialization. Raw UI shows their original `/5` values and unknown recorded period. Those original-scale records and malformed legacy rows are read-only, with export/deletion retained. Ordinary valid three-item 1–10 records remain editable in their original form.

An untouched question and an explicitly cleared/skipped question both persist as missing (`null`); the UI shows “Not answered.” This slice does not claim a separate skip-intent audit trail.

New-format metadata without a version is rejected locally, in backup parsing and by rules rather than disguised as a legacy row. Partial answers and explicit clearing survive local cache, cloud merge, export and backup restore. Restoring a backup never grants consent or guardian approval. Outcome reconciliation also removes noncanonical outcome IDs linked to draft responses.

Native Firebase writes use explicit SDK timestamps for journaled inputs, profile changes and linked legacy outcomes, preserving microseconds. The simulator reproduced a false same-record conflict because the SDK's ordinary `DateTime` encoding kept only milliseconds. Exact conflict checks remain intact. Existing millisecond records remain readable; a pre-fix pending journal with a genuine precision mismatch still requires the normal explicit sync-review flow. No automatic rewrite or conflict overwrite is performed.

Sources: [model and validation](../lib/src/models.dart), [controller save/edit/delete](../lib/src/app_controller.dart), [cloud mapping](../lib/src/cloud_schema.dart), [merge protocol](../lib/src/cloud_sync.dart), [backup parser](../lib/src/backup_restore.dart), [outcome reconciliation](../lib/src/sync_conflict_resolution.dart).

## Separation from the existing model

Versioned custom responses are excluded from the legacy deterministic scores, forecasts, Coach/risk evidence, model preparation and fitted-model inputs. They do not generate an old observed-Energy training outcome even when optional learning is enabled. This avoids assuming that new wording, response selection and language have established equivalence to the earlier target. No new composite score, fitted algorithm, label conversion, training action or prediction-event framework was added.

The existing formulas and model/preparation versions remain unchanged. Saving a new raw response invalidates raw preparation caches, without discarding fitted artifacts, changing scheduled reminders or resetting training-attempt safeguards. Any later research/model compatibility policy requires its own decision. Missing Energy does not become a midpoint or a model-generated label.

Sources: [engine eligibility](../lib/src/fatigue_engine.dart), [preparation source checks](../lib/src/ml_prep_builder.dart), [controller](../lib/src/app_controller.dart), [separation regressions](../test/phase2a_consumer_separation_test.dart).

## Security and verification

[Firestore rules](../firestore.rules) retain ownership, consent, verified-guardian, deletion and independent outcome-learning gates. New payloads validate nullable integer answers, honest completeness, bounded metadata and questionnaire definitions. Updates cannot downgrade a new record or rewrite its original definition/time provenance; old rows cannot be retagged as new research responses. Owner reads/export/deletion remain available under the existing policy.

The first emulator runs exposed Firestore's 1,000-expression ceiling for rich valid writes. Equivalent exact-key/type/length checks were simplified, and answer counting preserves duplicate values. All validations remain exercised, including malformed/missing/extra keys, non-string and oversized text, Unicode/multiline text, complete guardian-authorized updates, zero/fraction rejection, cross-account denial and consent loss. No rules were deployed.

Actual commands/results, native integration and remaining device limits are recorded in [the progress record](BIOLOGY_UPGRADE_PROGRESS.md). Key regressions: [schema](../test/research_check_in_schema_test.dart), [persistence/backup](../test/self_report_persistence_test.dart), [widgets](../test/check_in_measurement_widget_test.dart), [model separation](../test/phase2a_consumer_separation_test.dart), [real security emulator](../tool/security_rules/firestore.rules.test.mjs), [native restart](../integration_test/phase1_cloud_test.dart).

## Remaining roadmap and acceptance work

Phase 2A steps 4–7 remain: separately defined personal references with sample counts, independent trends, a research-specific export, and an approved-instrument questionnaire framework. Raw backups/exports already carry these new responses; they are not yet the proposed analysis table. No research baseline minimum, window, participant protocol, prediction target, outcome matching rule, instrument, study threshold or future AI setting has been invented or approved.

Existing Phase 1 physical-device/notification acceptance gaps remain documented in [the device checklist](PHASE1_DEVICE_ACCEPTANCE.md). Native simulator integration is separate from physical-device and screen-reader acceptance. No normal installation, real Health record or production account was used. Before any future release, review backward-client behavior against schema 16 and the proposed rules; do not silently deploy them.

Passing software tests does not establish biological, clinical, psychometric, or fatigue-prediction accuracy.

### Manual measurement acceptance — Not run

Use an expressly isolated test installation, local emulator routing and synthetic records under normal adult consent. Never select a normal installation, production account or real Health import. For native emulator prerequisites and the existing automatic restart command, see [the integration guide](PHASE1_EMULATOR_INTEGRATION.md). A physical target needs a separately reviewed local test setup; the current automatic harness creates only an iOS simulator.

1. In Add → Daily Check-in, verify all six questions begin unanswered and Morning/Evening requires a choice. Save only Focus = 6; Today/history should show five “Not answered” values and partial completion.
2. Edit that response, add Energy = 5, save, then clear Energy and save again. Terminate/relaunch the isolated app; Energy must remain missing and Focus = 6. A current cloud server read should agree.
3. Save six different values with a deliberate Evening period outside the evening clock window. Confirm the chosen period, separate values, captured date/time and definition version survive a restart. Do not infer clinical significance from the values.
4. Change the interface language, then edit the existing response. Verify its original wording/language is retained while a new response uses the new language. Review Spanish and both Chinese scripts at enlarged text sizes with VoiceOver/TalkBack; these assistive-technology checks are Not run.
5. With synthetic historical fixtures via supported import, confirm original 1–5 data is labeled `/5` and read-only, ordinary three-item data keeps its old editor, and export/deletion remain available. No synthetic entry should become a genuine Today report.
6. Change the isolated test timezone across a date boundary and inspect the saved response in history. Its captured local date/offset must remain unchanged. Unit timezone tests cover this logic; an OS timezone/travel walkthrough is Not run.
