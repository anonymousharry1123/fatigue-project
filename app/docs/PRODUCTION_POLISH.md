# Production polish — 0.35.0+37

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

Transactions use chunks of at most 200 child documents. A large import can be
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
and an actionable connection, authentication, permission, conflict or device
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
Explicit retry can reverify privacy after an offline launch before uploading;
it does not require an already-verified connection. Newer privacy responses,
consent changes and account changes invalidate stale recovery requests.
While input sync is pending, scores, forecasts, guidance and insights use the
saved local edits; they do not replace them with old cloud-derived results or
upload derived data from a mixture of old and pending inputs.

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
