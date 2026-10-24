# Production polish — 0.35.0+37

> **2026-10-03 Phase 1 update:** Current biology, score availability, model compatibility and notification behavior is documented in [BIOLOGY_UPGRADE_PROGRESS.md](BIOLOGY_UPGRADE_PROGRESS.md). Version-specific behavior below is historical where it conflicts with that update.

This pass improves everyday interaction and recovery after interrupted work.
It does not constitute production release approval.

## Interaction

- Today, Forecast, Insights, Profile, Add, Coach, activity, sleep and check-in
  layouts adapt to a 320px display with 2× text. Forecast charts scroll when
  necessary, and chart descriptions include dates, units, missing values and
  uncertainty. Scores expose one named value to assistive technology.
- Activity, sleep, check-in and reaction saves retain their form/results after
  failure, show progress, and reuse the same identity on retry. Save messages
  distinguish a local save from a pending cloud upload.
- Reaction tests discard partial rounds on app inactivity or a covering route.
  The next test starts explicitly. A monotonic stopwatch starts after the green
  frame; color animation no longer shifts the visual timing cue. The test is a
  wellness interaction, not calibrated laboratory reaction-time measurement.

## Daily plan notifications

AI Coach now presents a timed daily plan with reminder status and optional
helpfulness feedback. Accept, complete and dismiss controls and their status
badges are removed from plan blocks. Notification delivery never marks a block
complete or records an observed-energy result. Older status data remains readable
for backup/cloud compatibility and historical feedback.

**Daily plan reminders** is a separate, default-off preference in Coach and
Profile's Notifications sheet. Explicit enablement requests OS permission when
needed and saves the choice before scheduling. The choice syncs in the existing
private input journal. Backups do not import notification preferences or OS
permission. Existing forecast subscribers are not silently enrolled in Coach
reminders, and forecast category switches remain separate.

Each fresh, grounded block in today's plan schedules one notification at its
actual start time, including post-midnight blocks belonging to today's sleep
schedule. Past or imminent starts, stale/missing generation dates, other days
and ungrounded blocks are excluded. At most 12 Coach reminders are pending;
the current plan produces eight blocks. Lower-confidence plans retain gentle
reminders, while forecast dip/recovery alerts keep their confidence gate. Titles
describe the plan action; notification bodies contain duration and a Coach
link, without private evidence notes or raw readings.

Plan refresh, input edits, preference changes, app resume and time-zone changes
replace the schedule. Stable IDs and serialized native operations prevent
duplicates or an older cancellation erasing a newer plan. Partial schedule
failures clear managed reminders and report an error. Unrelated notifications
are preserved. Counts and per-block indicators describe confirmed future
schedules, never delivery or task completion.

Tapping a reminder opens the Coach tab on a cold or warm launch, after existing
authentication, onboarding and privacy gates. Account changes discard pending
navigation. A pushed page returns to Coach when it can safely close; a save
protected by PopScope is not dismissed by a notification.

Scheduled reminders use the OS after the app closes. New AI plans are generated
when Tonyo runs, so users must open the app each day to refresh that day's plan.
Android uses inexact alarms and OS notification settings may delay or suppress
delivery. Physical-device delivery, Focus/Do Not Disturb and travel behavior
remain release QA; desktop/widget tests do not demonstrate actual phone delivery.

The notification update passes **771 Flutter tests** and static analysis.
Coverage includes exact plan-time mapping, fresh/grounded eligibility, legacy
status independence, default-off migration, cloud preference recovery, denied
permission, failed settings saves, concurrent refreshes, partial native failures,
account/privacy cancellation, warm/cold taps and accessible reminder controls.
The final unsigned iOS simulator and release web builds pass. Web retains its
existing nonfatal CupertinoIcons font warning. No app was installed or deployed.

## Input sync contract

`cloud_sync.dart` compares the last acknowledged input snapshot with current
local inputs. A versioned owner-scoped baseline is saved beside the local cache
before uploading. Reloading overlays only pending additions, changes and
deletions on fresh cloud state, retaining records added by another device.

`FirestoreCloudRepository.applyInputPatch` reads and compares each edited
document in a transaction. A write is accepted when the cloud still matches
the baseline or already matches the requested result, so repeating a partially
completed upload is safe. A changed record produces a conflict; it is never
silently overwritten. Known nullable fields cleared by the user are explicitly
cleared in merge payloads, and unknown fields remain intact.

Transactions use chunks of at most 16 child documents so source/change-journal
validation stays within the Firestore Rules access budget. A large import can be
partially committed if a later chunk fails. The durable baseline is acknowledged
only after all chunks succeed, and the next attempt safely repeats completed
chunks. This is not atomic across the whole import. Ordinary profile fields are
compared at individual field boundaries, so concurrent edits to separate profile
or preferences fields merge without blocking unrelated records. Same-field
conflicts still require explicit review. Existing snapshot journals remain
compatible.

Consent receipts, deletion state and model metadata retain their separate APIs.
Routine saves and legacy migration never replace whole input collections or
create missing accounts. A missing account requires explicit setup; old cache
data is not permission to recreate it.

**Profile → Cloud sync** shows the pending record count, last successful upload,
and an actionable connection, quota, authentication, permission, conflict or device
storage error. The timestamp describes the most recent successful upload batch;
other records may still be pending.

A same-record conflict keeps the local edit and remote version separately.
**Review conflicts** offers a phone/cloud choice for each conflicting record or
profile field. Resolving these choices preserves unrelated pending edits and
cloud-only records. Confirmation rereads cloud state and rejects stale previews;
the normal upload transaction still catches changes from a third device.
Learning results linked to a check-in or reaction test follow the selected source
value, including source deletions. Ongoing outcome uploads finish before the
selection is applied, so an older upload cannot undo that correction.
**Use cloud version** remains an explicitly confirmed way to replace all pending
local input edits with the current cloud inputs. Recovery waits for an active
upload and rejects a new input edit arriving during recovery.

Launch, foreground reconnect, new saves and explicit retry attempt pending
uploads while the session and privacy gate permit it. While the app remains
open, connection failures retry after 5 seconds, doubling to a 60-second maximum.
There is no background execution guarantee. Conflicts, authentication,
permissions and device-storage failures require action instead of looping.
Service-quota failures pause automatic attempts for the cooldown described below.
Explicit retry can reverify privacy after an offline launch before uploading;
it does not require an already-verified connection. Newer privacy responses,
consent changes and account changes invalidate stale recovery requests.

### Quota failure and local operation — 2026-10-24

The former privacy gate paused new manual saves and Health imports whenever
Firestore privacy verification failed, even with an existing consented account.
Quota exhaustion now permits local collection for a previously onboarded adult
with current explicit consent, matching privacy/input/metadata ownership and a
saved input baseline, after a fresh successful Firebase Auth verification.
This permission is established only by a Firestore `resource-exhausted` response
(including the persisted quota cooldown). It is ephemeral and separate from
cloud privacy verification. New accounts, minors, ownership mismatches, missing
or expired consent, deletion, Auth failures and other privacy-read failures
remain paused.

Manual entries, Health imports and local derived views can continue in this
mode. Cloud data operations and model preparation remain blocked even after the
quota timer expires, until fresh account privacy verification succeeds. Retry
failure leaves local use available for a quota error; a successful recovery
merges and uploads pending changes only when consent still permits it. Observed
revocation or deletion takes effect before any upload, including when a later
summary read fails. Profile explicitly describes local use with cloud sync
paused. This is not a guarantee of unrestricted offline startup: Firebase Auth
must still verify the current account.

Validation: 179 affected controller/repository regressions pass, including
manual save, Health import, restart, stale hydration, cooldown expiry, failed
retry, recovery, revocation, deletion, ownership and authentication cases.
Static analysis, formatting, signed iOS release build and strict signature
verification also pass. The update is installed on Harry's iPhone without
uninstalling Tonyo. A post-install readback confirms all 4,223 raw readings,
835 other signals and 5 check-ins remain intact, with valid SQLite integrity,
ownership and raw-data separation. Physical saving/Health refresh verification
is still awaiting the user opening the updated app: iOS blocked launch because
the phone had locked. The pre-update Health timestamp has not advanced in the
post-install snapshot, so data preservation alone is not claimed as functional
on-device verification.

Firestore `resource-exhausted` displays **Cloud service quota reached** instead
of claiming the phone has no connection. One owner-scoped circuit breaker covers
ordinary repository reads and writes, including automatic Health refresh and
derived views. The one-hour cooldown is persisted across launches. An explicit
**Retry sync** grants a fresh attempt; another quota response closes the circuit
again. Pending journals stay durable. [Free-tier daily quotas](https://firebase.google.com/docs/firestore/quotas)
reset around midnight Pacific; changing billing is a separate owner decision.

## Efficient health storage and shared inputs — October 24, 2026

On native iOS/Android/macOS builds, ordinary HealthKit `heartRate` readings move
from the preferences JSON into an owner-scoped SQLite database. Migration writes
and commits the raw database before compacting preferences. A persistent database
snapshot marker distinguishes a valid empty history from a missing database;
missing expected history stops migration. Exact raw payloads remain in explicit
device backups. Ownerless legacy data stays quarantined locally, and changing
accounts cannot transfer it to the new account.

The cloud stores `heartRateDays/{UTC-date}` with hourly sample counts, sums,
min/max, quality summaries, exact latest observation, and import-time timezone
provenance. UTC bucket boundaries are stable across phones and travel. Averages
are averages of observed samples, not continuous heart-rate measurements.
Original HealthKit recording timezone is unavailable and is not invented.
Deterministic UUID deduplication and sample/content digests support verification.
HRV, resting heart rate, check-ins, sleep timing/stages, manual corrections and
research evidence remain individual inputs with their original timestamps.

Each UTC day has one immutable writer identity. Identical data from another
phone is acknowledged without adding counts; a differing dataset from another
writer stays on that phone and is reported for review. It does not block ordinary
check-in or study uploads. Summaries are not merged by adding overlapping counts.
A cloud restore recovers summaries and the latest sample; full raw recovery needs
the original device database or an explicit device backup.

Legacy cloud raw samples are retired only after durable local persistence and a
server acknowledgement whose sample IDs, complete statistics, count and latest
reading match. Partial failures retry idempotently; corruption, quota errors,
sign-out and privacy changes stop cleanup. Explicit user deletions have a
separate durable path and do not require retaining a deleted observation in a
summary. Deletion tracking retains small `inputChanges` tombstones; therefore
summary-payload size savings are not total Firestore storage savings. Tombstones
must not be pruned without a future minimum-cursor/full-bootstrap protocol.

`inputSyncVersion:1` activates tracked input writes. Every source change and its
latest `inputChanges` record commit with the same monotonically increasing root
revision. Incremental reads fetch revisions after a persisted server baseline,
including edits to old timestamps and deletion markers, then verify that the
root revision stayed stable. The cursor and its server snapshot are persisted
together, separately from pending local edits. Older clients cannot make
untracked source writes after activation. Full server restores remain available
for conflict recovery. Scores, Forecast, Coach and Insights share the hydrated
repository cache instead of repeating overlapping history queries.

`forecastDays/{local-date}` packs the exact hourly forecast points into one daily
document. Missing legacy days migrate lazily; acknowledged empty days prevent
repeated empty legacy reads. Equivalent forecast content skips rewrites;
generation-time-only changes are ignored, while meaningful time-dependent
uncertainty remains part of the forecast. Legacy hourly documents are retained
for rollback/export. Large summary/forecast payload fields are exempted from
indexes; fields used by range/cursor queries remain indexed. All new collections
participate in account export/deletion and owner/privacy rules.

Cloud and local model preparation exclude ordinary heart rate before the 1,500
input cap, preserving HRV/resting-HR evidence and known-at prediction boundaries.
No daily averages are substituted for intraday research or training evidence.
HealthKit anchored imports remain a separate future battery/CPU improvement;
this change addresses cloud document volume and repeated reads.

Validation on October 24: static analysis and whitespace checks pass. The final
Flutter suite reports **1,651 passed, 1 skipped and 4 pre-existing UI failures**.
The four failures in `ai1_capture_ui_test.dart` and
`input_accessibility_test.dart` were independently reproduced on the unchanged
baseline. All **43 heart-rate tests pass**, including a delayed disk commit
followed by an unsaved correction: only the committed reading is summarized,
the correction remains pending, and legacy cloud raw data is retained.
Focused tests also cover SQLite restart/rollback,
missing databases, safe migration, account isolation, competing writers, corrupt
acknowledgements, historical edits/deletions, cursor races, quota cooldown and
exact model-output parity. The Firestore Rules emulator passes 47 cases,
including 16-signal and 16-research-check-in atomic batches.

The guarded native iOS integration also passes both independent app processes
against loopback Auth/Firestore emulators with the exact final rules. It verifies
two-chunk writes, historical edits, explicit nulls, deletion replay, summary
acknowledgement/readback before cleanup, and raw-upload rejection after migration.
After a real process restart, the default SQLite path retains exact raw payloads,
provenance and intentionally empty snapshots; the cursor resumes correctly and
an unchanged summary is acknowledged without rewriting. Only generated test
accounts and a newly created simulator were used. Physical-device rollout status
is recorded below.

Production rules and indexes were deployed to `fatigue-project-e28a3` on October
24 at 20:37 UTC. A separate metadata-only verification confirmed the deployed
rules exactly match the tested SHA-256
`3b79a44a2f311d1b23f2eb76a28b776f1caf2b9dcd8e27f70a3c4c16cf54b37e`,
the `signals(type ASC, timestamp DESC)` composite index is `READY`, and all four
payload-field exemptions are active. The final signed iOS release build and
strict signature verification pass (`com.ios.tonyo`, `0.35.0+37`, existing team).
Billing was not changed. A read-only owner request still returned HTTP 429
`RESOURCE_EXHAUSTED / Quota exceeded`; live summary acknowledgement and legacy
cleanup cannot be verified until that quota permits requests.

The final release was installed on **Harry's iPhone only** and launched
successfully. A pre-update recovery snapshot was compared with the new SQLite
database and compact preferences, then compared again with fresh device copies
after a separate app process restart. All **4,223 original raw heart-rate
readings** retain their IDs and measurement fields; all **835 other signals**
and **5 check-ins** are preserved without changed measurements. SQLite integrity,
owner markers and account isolation checks pass. Raw heart rate is absent from
primary preferences and sync baselines. The owner-scoped quota cooldown survives
restart with the same expiry, so opening the app does not restart that timer.
The app has zero acknowledged cloud summaries while quota is exhausted; legacy
cloud cleanup is still pending. Temporary health-data verification copies were
removed after the successful local and restart audits; aggregate audit results
remain available without individual measurements or account identifiers.

While input sync is pending, scores, forecasts, guidance and insights use the
saved local edits; they do not replace them with old cloud-derived results or
upload derived data from a mixture of old and pending inputs.

### Device sleep and heart-data follow-up — October 24, 2026

Preferred imported main-sleep and nap groups now appear as actual Sleep Log
and Daily History records. The Evening card displays recorded asleep duration
and source, and opens the same saved night for review. Manual corrections keep
the imported stages and existing preference rules. Deleting an imported group
removes its sibling signals; the UI explains that Apple Health may import the
original again. Insights charts Core, Deep, REM and Awake for each preferred
main night, with missing stages kept unknown and per-stage averages based only
on recorded nights. Sleep stages do not change score weights.

Foreground Health polling now uses 15 minutes. Successful cloud input hydration
has an owner-scoped, persisted 3-hour TTL; explicit retry and initial account
loading bypass it. Privacy checks remain fresh. Health attempt timestamps and
diagnostics stay on the current device rather than creating cloud patches on
unchanged polls. Insights excludes cloud raw-heart-rate lookbacks while keeping
the local raw observations available for its record counts.

Changed heart summaries upload automatically once per local calendar day.
Explicit Health Sync now, cloud Retry sync, and raw-data deletion bypass that
cadence. Pending daily summaries survive restart and use a clear deferred
status instead of repeated short retries. Existing UTC summary buckets remain
unchanged. Schema version 2 adds optional native HRV/resting-HR averages and
descriptive sampled-bpm variation in `cardiacContext`, retaining a separate raw
digest and backward-compatible version 1 decoding. The added payload is not
indexed. Summary construction uses committed SQLite and preferences snapshots,
and upgrade acknowledgement still precedes any legacy raw cleanup.

The user chose a separate heart-rate variation measure in bpm. It requires at
least six distinct daytime readings spanning two hours with gaps no longer
than 45 minutes. It is never converted to HRV milliseconds or used in scores.
Native HRV remains native; absent beat-to-beat evidence stays absent.
Informational resting-HR estimates use the lowest three-sample overnight
median, reduced quality, stable IDs and explicit provenance. Native/manual
same-day resting HR takes precedence. Estimated resting HR is excluded from
measured baselines, fatigue scoring and model preparation. Profile explains
the data source, date and minimum sample requirements.

Follow-up validation: static analysis and whitespace checks pass. The final
serial Flutter suite reports **1,705 passed, 1 skipped and the same 4 known UI
failures** listed above; all added and affected cases pass. An initial parallel
run also tripped the unchanged residual-model 1 ms runtime fallback; its focused
rerun and the serial full suite pass without changing that production guard.
The Rules emulator passes **49/49** cases. Both native iOS emulator processes
pass, including version 1 to version 2 summary compare-and-replace, exact
acknowledgement, legacy cleanup, and SQLite/cursor recovery after restart.

Updated rules and indexes deployed at **21:01 UTC**. Independent metadata-only
verification confirms the tested rules SHA-256
`49bf2407a8aa7b4a1fcdcebb94ca2d6f7426c36be6cbcd20db763a6e94fa5950`,
the existing composite index remains `READY`, and all **five** payload field
exemptions are active. Billing and quota configuration were not changed.
The signed iOS release build and strict signature verification pass for
`com.ios.tonyo`, `0.35.0+37`, using the existing development team. A fresh
pre-update phone snapshot passes SQLite integrity and owner checks and contains
4,223 raw heart-rate readings, 835 other signals and 5 check-ins. Installation on
Harry's iPhone succeeded after one intermittent local-network connection failure.
After the user unlocked the phone, the updated app launched successfully and
passed a separate process-restart audit. All **4,223 original raw readings**,
**835 other signals**, and **5 check-ins** retain their original measurement
fields. Raw import provenance, SQLite integrity, owner markers, compact
preferences and cursor isolation also pass. The same owner quota cooldown
survives without extending its expiry. There are still zero acknowledged cloud
summaries, so live cloud acknowledgement and legacy cleanup remain pending the
existing quota restriction. The verified app was relaunched and left running.
Temporary health-data copies were removed after verification; aggregate audit
results were retained without account identifiers or individual measurements.

### Record source indicators — October 24, 2026

Daily History, Sleep Log, Activity Log, shared check-in cards, Evening sleep
review and Today's latest sleep now show visible source badges with icons and
accessible descriptions. `Manual` identifies records added in Tonyo;
`Auto-synced` identifies imports from Apple Health; model-derived readings show
`Estimated`, and recognized fixtures show `Demo`. Source comes from the saved
record, independently of cloud upload status, so a cloud-restored manual record
or manual correction to imported sleep stays Manual. Add & Explore now calls
its mixed-origin section “Activity and sleep logs.” New copy is translated into
Spanish, Simplified Chinese and Traditional Chinese.

All **67 focused existing tests pass**, including history, sleep, check-in,
localization, accessibility and 320px/doubled-text layouts. Static analysis and
whitespace checks are clean. This update changes presentation only. Its signed
release build, strict signature verification and installation on Harry's iPhone
pass. iOS initially rejected launch with a developer-profile security/trust error.
The signing certificate matches the embedded profile, required entitlements
match, and the valid profile includes this phone. After the user completed the
device-side verification, the user confirmed Tonyo opens and a normal device
launch succeeded. The source-indicator update is installed and running.

Consented outcomes have a separate owner-scoped journal for stable-ID uploads
and deletions. A successful cloud read cannot erase an outcome awaiting upload.
Restart/retry reconciles pending changes before refreshing history. The consent
receipt is retained with the journal; revocation or a new receipt invalidates
old pending uploads, and changing accounts cannot transfer the queue. Explicit
deletions remain eligible for retry after optional outcome learning is disabled.

Firebase transactions retry concurrent modifications and require connectivity;
the app's journal supplies restart recovery outside the transaction. See the
[Firebase transaction contract](https://firebase.google.com/docs/firestore/manage-data/transactions)
and [contention behavior](https://firebase.google.com/docs/firestore/transaction-data-contention).

## Verification and remaining release checks

Verified on September 19, 2026: **606 Flutter tests passed**;
`flutter analyze --no-pub` and `git diff --check` report no issues.
The release web build and unsigned iOS simulator build both passed. An initial
iOS invocation lacked `TARGET_BUILD_DIR`; inspecting Xcode settings and retrying
the simulator build separately succeeded without native project changes. Web
emits a Cupertino font-family warning; the app has no direct `CupertinoIcons`
references, and rendered/widget checks passed. Physical-device font rendering
remains part of release QA.

Local tests cover narrow/large-text layouts, chart semantics, interrupted
reaction tests, failed-save retries, offline restart, concurrent-device record
preservation, conflicts, idempotent replay, nullable clears, migration and cloud
recovery serialization. Memory repositories exercise the controller contract;
they do not establish production Firestore connectivity or deployed rule behavior.

Before release, finish physical iPhone/Android VoiceOver/TalkBack, dynamic text,
keyboard and interruption testing; verify actual device timezone/background
behavior; profile iPhone heap and latency; test airplane-mode/restart and
two-device edits against a dedicated Firebase test project; verify deployed
rules and IAM; and complete store metadata, signing and privacy review. Existing
guardian verification and launch-policy gates in `PRIVACY_SAFETY.md` remain.

Coach completions, ratings and alert dismissals have an owner-scoped durable
journal. They remain visible offline, survive restart and retry alongside input
and outcome changes. Transactions apply only the selected action fields to
existing cloud records, or create their original complete record if missing.
Repeated replay is safe. Queued actions take precedence over refreshed guidance;
derived guidance writes wait so they cannot undo a newer action. Signing out or
changing accounts never transfers these actions to another user. Derived score,
forecast and insight generation still uses its own refresh mechanisms.

## Offline device backup

**Save device backup** is available in Profile settings, its pending-sync card,
and Privacy center, including the connection recovery screen. It never queries
Firebase, requires a new consent receipt, or clears a pending journal. The JSON
contains the current profile, signals, check-ins, outcomes, local settings and
pending input/outcome journals (including deletions) and Coach actions. It is a device snapshot,
not a complete cloud export; the existing full-account export remains separate.

iOS exports through Files, Android uses the system document picker, and macOS
uses a save sheet. Save confirmation follows successful file completion;
cancellation and failure do not claim success. Other platforms offer explicit
copy-to-clipboard with instructions to paste into a file.

**Restore from backup**, in Profile and Privacy center, opens a JSON file on
iOS, Android and macOS; all platforms support explicit pasted JSON. Files are
bounded to 20 MB and validated before a preview appears. The preview shows new,
duplicate and differing records and lets the user select a saved recovery copy.
Restoration merges new records and skips duplicates. Replacing differing values
and importing the profile are separate, explicit choices. Existing activity and
check-in records are never deleted by an import; old deletion requests in a
backup are not replayed. Linked learning results follow the retained source
values, including when phone values are kept over differing backup values.

The original owner must match the current account; local-only backups require
a local-only session. Import never grants privacy consent, Health access or
notification permission, and outcomes require the account's current matching
Outcome learning receipt. Older Coach actions lacking their original plan/alert
records are counted as skipped. Consent and session changes invalidate a pending
preview. Restored data is written to device storage before any upload attempt;
failed writes do not install the staged data or roll back concurrent edits.
Pending journals retain restored changes through restart and later cloud retry.

When cloud restoration would replace owned legacy inputs with no usable sync
baseline, or restore a missing cloud account, a durable recovery copy is written
first. Later distinct recovery copies preserve the earlier snapshots. These are
included as `beforeCloudRestore` in device backups and in owner-scoped account
exports. Unknown sync status is not treated as permission to upload or resurrect
ambiguous records. Tracking reset and account/device deletion remove recovery
copies. Backup and recovery reject mismatched accounts, sign-out and deletion.

The initial September 20 save/reconnect change passed **640 Flutter tests**,
static analysis, whitespace checks and an unsigned iOS simulator build.
The subsequent restore and queued-action changes pass **723 Flutter tests** and
static analysis. Coverage includes restart/replay, malformed backups,
failed/concurrent saves, stale privacy responses, per-record conflicts, linked
learning results, picker cancellation and narrow/large-text layouts.
The final unsigned iOS simulator build and release web build also pass; the
existing nonfatal Cupertino font warning remains on web. Formatting and
`git diff --check` are clean. No app was installed and nothing was deployed.

Actual iPhone/Android picker behavior and production Firebase connectivity still
require device QA; Android compilation is unavailable on this development host
because its SDK/JDK are not installed. For a two-device acceptance check, use a
dedicated Firebase test account: edit one record on each phone while offline,
restart each phone, reconnect and confirm both edits persist. Then edit the same
record on both phones, review each phone/cloud choice, and confirm convergence.
Also save an offline backup, restore it into the same account, retry twice and
confirm no duplicate inputs or Coach actions appear.
