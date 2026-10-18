# Phase 2A measurement foundation

## Current collection policy — October 18, 2026

The user replaced the fixed clock schedule with flexible personal collection. New **Morning** check-ins collect **Energy only**, with no sleep entry. **Evening** check-ins retain all six optional ratings and link to a separate main-sleep log. Either period can be saved at any time; record the actual sleep and wake times. Earlier saved answers remain intact. New Morning records retain the six-item definition for compatibility, but the five hidden ratings are not collected and stay null; they are not evidence of five deliberate skips. Earlier full Morning records remain editable without discarding their other answers.

The current experimental path is **retrospective**, using `flexible-evening-retrospective-v1` in [the preparation tool](../tool/prepare_experimental_sleep_data.py). It has no 10 a.m. sleep deadline, morning snapshot requirement, or 6–10 p.m. response window. It still requires valid chronology: matched main sleep must end within 24 hours before the selected Evening response, and known save/import times cannot be after the export. Sleep may be logged after Energy; this does not establish a prospective prediction. Morning answers are not Evening targets.

The fixed schedule described below is **historical**. Existing saved plans keep their original meaning and remain reviewable under **Earlier fixed-schedule study**; the ordinary flow no longer starts them. Flexible experiment cohorts are versioned separately. The remainder records the earlier implementation and evidence at its stated date.

Implemented October 4, 2026 after the user requested the next step in [roadmap v2](../TONYO_BIOLOGY_AND_AI_ROADMAP_v2.md). The initial slice completed Section 16 steps 1–3: definitions, check-in UI, and raw storage, plus a separate self-report display. Steps 4–7 were added October 10, 2026: personal references, independent trends, private research export and an empty approved-instrument framework. This does **not** complete physical-device/release acceptance or approve a research protocol. The user-authored roadmap and its undecided research fields are unchanged.

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

## Personal self-report references — Step 4

Open **Today → Today's self-report → Recent personal averages** beneath either recorded period. Energy, Fatigue, Sleepiness, Focus, Mood and Stress each show a separate average and answered-day count, alongside the unchanged current answer. A missing current answer has no comparison. References describe the person's reports; they are not a healthy/normal range, predicted outcome or composite score.

The product display policy requires **at least seven distinct answered days within the preceding 28 captured local dates**, separately for Morning and Evening and each measure. Below that threshold, the card shows “Not enough history” and the available count. These defaults control display only; they do not fill any research-protocol or future AI minimum-history setting. The window dates, minimum and selection rule are disclosed in the expanded card.

- Only valid, non-synthetic `tonyo-self-report-draft-v1` responses with the same period, language and exact stored questionnaire definition can contribute. Structural comparison ignores map key order while preserving question order, wording and anchors. Legacy records and unknown formats are retained but excluded.
- The current captured date and later dates are excluded, as are observations at/after the current report and records whose observation/save time is after the viewing time. The 28-date window uses captured calendar dates, independent of later travel or daylight-saving changes.
- Duplicate IDs resolve to their latest revision before eligibility is checked. Within each compatible historical date/period, only the latest submission is used, before inspecting its answers. A later missing answer never falls back to an older answered submission. Each measure counts only its own answered dates; no value is imputed.
- These are current descriptive references recomputed from saved records. An edit, clearing, deletion or restore can change an average. They are not a reconstruction of what a model knew at an earlier prediction cutoff, and they are never fed into scores, forecasts, Coach, learning outcomes or training.
- Existing local/cloud hydration already supplies the needed records. No new queries, stored derived values, schema/rules changes or cache/model migration are required. All four existing interface languages include the reference copy.

Sources: [reference calculation](../lib/src/self_report_reference_logic.dart), [reference card](../lib/src/widgets/self_report_reference_card.dart), [logic regressions](../test/self_report_reference_logic_test.dart), [display and persistence checks](../test/self_report_reference_widget_test.dart). Verification results appear in [the progress record](BIOLOGY_UPGRADE_PROGRESS.md).

## Remaining roadmap and acceptance work

Software implementation for Phase 2A steps 1–7 is complete locally. The display defaults and retrospective export do not approve a research baseline minimum/window or a study matching rule. The October 11 [prediction contract `v0.3-draft`](PREDICTION_CONTRACT.md) records the user's fixed 10:00 prediction / 18:00–22:00 evening rating times, own-data-first population, English, and manual sleep default with Apple Health selectable. Remaining operational rules and construct meaning are proposals.

The user authorized continuing into the first AI-1 slice: offline, synthetic-only Dart [protocol/calendar rules](../lib/src/ai1_protocol.dart), [immutable records](../lib/src/ai1_records.dart) and [dataset validation](../lib/src/ai1_dataset_builder.dart), with [acceptance fixtures](../test/ai1_dataset_builder_test.dart). The proposed source policy fixes one source per versioned experiment, without fallback or merging. This local work can proceed while review continues. A follow-up adds a default-off **Privacy center → Keep local study history** setting for future manual sleep and check-in revisions. The separate protected iOS journal keeps full item wording and the displayed heading, native post-write receipts and edit history; it excludes notes, cloud sync, backups and exports. Disabling history or deleting the source clears applicable revisions. Existing/imported records are not backfilled, and editing an uncaptured record does not establish its original save time. Health ingestion lineage, prediction events, real-data adapters and training remain future work. Participant review, accepted measurement/prediction settings, instrument selection if needed, and real-outcome readiness remain separate work. Optional unusual-day/illness/travel markers are not implemented.

Existing Phase 1 physical-device/notification acceptance gaps remain documented in [the device checklist](PHASE1_DEVICE_ACCEPTANCE.md). Native simulator integration is separate from physical-device and screen-reader acceptance. No normal installation, real Health record or production account was used. Before any future release, review backward-client behavior against schema 16 and the proposed rules; do not silently deploy them.

Passing software tests does not establish biological, clinical, psychometric, or fatigue-prediction accuracy.

### Measurement acceptance — simulator coverage and remaining manual checks

The expanded local-only native harness passed **two scenarios on October 10, 2026**, including an actual process stop/restart. It now taps the ordinary Spanish check-in form, checks all six initially unanswered displays, exercises period/answer validation, saves Focus = 6, adds then clears Energy through history, and preserves the exact saved data in native preferences and fresh Firestore server reads. It opens an English response under Spanish presentation, verifies original wording, changes a control and cancels without changing the stored response. Complete six-value reports and eight historical report/sleep pairs are created through normal controller APIs, not taps on all six controls.

After restart, native UI checks verify the 5.5 Energy average from eight historical days, raw-rating and sleep charts, sparse/missing records, measure/period/language filters, explicit export preparation, canceled/confirmed native JSON/CSV clipboard copying, and the empty questionnaire library. Read-only navigation/export leaves raw records unchanged. Full raw values, missingness, definitions and timestamp precision are compared against a separate pre-restart test manifest. See [the execution record and command](PHASE1_EMULATOR_INTEGRATION.md#phase-2a-measurement-acceptance--2026-10-10).

The procedure below remains useful for manual/physical acceptance. Automated simulator coverage now supplies evidence for items 1–2 and the persistence portion of item 3; it does not complete all of items 3–6. System file-picker saving, VoiceOver/TalkBack, physical devices, all-language native review, legacy-format UI walkthroughs and OS timezone/travel changes remain **Not run** in this follow-up. The simulator clipboard calls use the real native platform channel; host clipboard sharing was not assessed.

Use an expressly isolated test installation, local emulator routing and synthetic records under normal adult consent. Never select a normal installation, production account or real Health import. For native emulator prerequisites and the existing automatic restart command, see [the integration guide](PHASE1_EMULATOR_INTEGRATION.md). A physical target needs a separately reviewed local test setup; the current automatic harness creates only an iOS simulator.

1. In Add → Daily Check-in, verify all six questions begin unanswered and Morning/Evening requires a choice. Save only Focus = 6; Today/history should show five “Not answered” values and partial completion.
2. Edit that response, add Energy = 5, save, then clear Energy and save again. Terminate/relaunch the isolated app; Energy must remain missing and Focus = 6. A current cloud server read should agree.
3. Save six different values with a deliberate Evening period outside the evening clock window. Confirm the chosen period, separate values, captured date/time and definition version survive a restart. Do not infer clinical significance from the values.
4. Change the interface language, then edit the existing response. Verify its original wording/language is retained while a new response uses the new language. Review Spanish and both Chinese scripts at enlarged text sizes with VoiceOver/TalkBack; these assistive-technology checks are Not run.
5. With synthetic historical fixtures via supported import, confirm original 1–5 data is labeled `/5` and read-only, ordinary three-item data keeps its old editor, and export/deletion remain available. No synthetic entry should become a genuine Today report.
6. Change the isolated test timezone across a date boundary and inspect the saved response in history. Its captured local date/offset must remain unchanged. Unit timezone tests cover this logic; an OS timezone/travel walkthrough is Not run.

## Independent trends — Step 5

Open **Forecast → Insights → Self-report trends**. Select one of the six measures, Morning/Evening and the recorded questionnaire language. The view uses **28 captured dates including today**, separate from the personal-reference panel's preceding-28-date window. It displays the latest compatible submission per date/period before evaluating missing answers. The latest valid current-format report in the chosen window/language defines exact wording compatibility. Older incompatible definitions, invalid/legacy/synthetic records and future observation/save times do not contribute. Gaps stay missing; no zero or midpoint is inserted.

The raw-rating chart fixes its vertical scale at 1–10 and connects only adjacent answered dates. With fewer than eight answered dates, exact dated values replace the chart. The sleep scatter uses raw rating versus preceding recorded main-sleep hours; fewer than eight pairs or an unvarying axis uses exact paired records instead. Eight is a visual-density rule, not statistical power or a validity threshold. Counts disclose answered, missing, paired and unpaired dates. An expandable list retains all 28 dates, values, sleep sources and unpaired reasons. Screen-reader summaries supplement the same accessible records.

### Descriptive sleep matching

The shared matcher uses genuine manual/Health main-sleep summaries ending at/before the report within the previous **24 elapsed hours**. It excludes naps (including imported nap groups), invalid durations/quality, model/demo evidence, future evidence and records unavailable at viewing time. Raw duration is retained; a bedtime is never fabricated by subtracting sleep duration from wake time. Only an actual saved bedtime can establish that another session ended before the latest session began.

Ambiguous competing summaries are withheld. The existing 50%-detailed-stage/80%-manual-duration Health preference is reused only for a provably overlapping manual/Health session, with genuine available stages and bounded totals; it is not a new clinical rule. Grouping uses actual instants rather than the device's present timezone. Captured report dates survive travel/DST.

These are **retrospective descriptions using saved records available now**. A sleep entry or correction made after the report may contribute. Unknown availability stays unknown. Neither the pairing nor a scatter establishes causation, significance or predictive performance. The matcher reports availability of all records needed to choose a pair separately from the selected sleep record's own availability. It does not change input/model/preparation versions, query Firestore, schedule alerts or fit anything.

Sources: [trend and matching logic](../lib/src/self_report_trends_logic.dart), [native chart and exact records](../lib/src/widgets/self_report_trends_card.dart), [logic regressions](../test/self_report_trends_logic_test.dart), [UI/visual QA](../test/self_report_trends_widget_test.dart).

## Private research export — Step 6

Open **Profile → Research export**. Enter a pseudonymous study code (1–32 characters, starting with a letter; letters/numbers/underscore/hyphen only) and choose **Prepare research export**. Opening the screen produces no export. The prepared summary shows row, partial, paired and excluded counts. Later data edits do not silently alter that prepared snapshot; prepare again to include them.

- **Save research JSON** uses the existing JSON system file picker on iOS/Android/macOS. It contains `tonyo-measurement-export-v1`, generation/scope/policy metadata, response and sleep data dictionaries, exact questionnaire definitions, selected raw sleep records and response rows. Native channel changes were unnecessary.
- **Copy research CSV** provides the response table with a header and CRLF line endings; missing values are empty fields. **Copy research JSON** is also available. Clipboard use requires an explicit in-app confirmation. Cancellation and failure never report a saved file, and pending clipboard confirmation cannot cross an account/session change.
- Each valid current-format submission contributes a row, including partial answers and repeated dates. Unlike a trend plot, the export does not collapse independent submissions into one row per day. Duplicate IDs resolve by latest revision; contradictory equal-time copies are excluded. Counts identify duplicate, invalid, synthetic, legacy, future/unavailable and unsupported-version exclusions. Raw backups remain available for retained rows outside this research table.
- Responses retain original raw six-item values, missingness/completeness, selected period, observation/save UTC instants, captured local date/zone/offset, source, version, language and definition reference. JSON keeps exact wording/anchors; CSV references those definitions. Values are not normalized into experimental scores.
- Sleep rows retain raw duration/end/source/quality and actual save/import timestamps. Response rows separately include `sleep_pair_available_at_utc` and `sleep_pair_availability_known`, because deciding a match may require extra records whose availability differs from the selected raw sleep. Unpaired rows retain explicit reasons and null values.
- Export-local response/sleep/definition references replace original record IDs. Names, emails, account IDs, free-text notes and unrelated profile/model/health data are excluded. Dates and wellness observations still make this sensitive **pseudonymized**, not anonymous, data. Keep any identity linkage separately. Study codes are not generated from account identifiers.

The export uses only the current owner's saved device records, including pending edits, under the existing device-export ownership/session gate. It does not perform a fresh cloud fetch, upload anything, change sync acknowledgements/consent, or generate prediction events. Its retrospective sleep pairing policy and unapproved-protocol status are explicit. This is a measurement analysis table, **not** the future prespecified prediction-event dataset or an approved study join.

Sources: [builder and dictionaries](../lib/src/research_export.dart), [export screen](../lib/src/screens/research_export_screen.dart), [data tests](../test/research_export_test.dart), [availability regressions](../test/research_export_pairing_test.dart), [save/copy/session UI checks](../test/research_export_screen_test.dart).

## Generic questionnaire framework — Step 7

**Profile → Questionnaire library** shows the actual empty installed catalog and review requirements. No published questionnaire, copyrighted question set, scoring formula, clinician endorsement or research approval was invented. There is no installation, collection, approval or storage action on this read-only screen.

The separate pure-Dart framework supplies immutable, versioned definitions, original choice IDs/numeric values, required/optional items, age/language/recall/source/permission metadata, distinct biological/youth/software/permissions reviews, and a registry that rejects duplicate identities. Intake validates exact trusted definitions, supported ages, review/permission timing, UTC observation/save times, choices and nonempty partial responses. Under-13 instruments are rejected. JSON responses cannot install or approve their own embedded definition.

Raw responses are never automatically summed, rescaled or filled. Optional total/subscale scores require a separately reviewed external scoring-method identifier/version, finite values, scoring time and all required answers. Scoring is not executed by this framework. Response `recordedAt` describes raw-response availability; any later external score has its own `scoredAt` and must not be used before that instant. Codecs retain the exact definition snapshot and honest completion metadata.

These metadata checks are necessary software safeguards, not authentication of a human reviewer or authority to collect participant data. No questionnaire persistence collection, cloud schema, backup migration or live intake was added while no instrument is approved. Future activation requires reviewed instrument content/permissions/scoring, applicable consent/research approvals and a separate storage/export/deletion migration. The existing custom draft six-item check-in remains unchanged.

Sources: [framework and empty catalog](../lib/src/questionnaire_framework.dart), [library screen](../lib/src/screens/questionnaire_library_screen.dart), [framework regressions](../test/questionnaire_framework_test.dart), [library UI checks](../test/questionnaire_library_screen_test.dart).
