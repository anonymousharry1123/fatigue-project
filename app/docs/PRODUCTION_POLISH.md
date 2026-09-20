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

**Profile → Cloud sync** retries pending uploads. A same-record conflict keeps
the local edit and the remote version separately. Choosing **Use cloud version**
requires confirmation and replaces the pending local input edits with the
current cloud inputs. Recovery waits for an active upload and rejects a new
input edit arriving during recovery. There is no automatic last-write-wins
resolution or background retry loop: launch, foreground reconnect, the next save,
and explicit retry attempt pending input sync while the session and privacy gate
permit it. Explicit retry can reverify privacy after an offline launch before
attempting uploads; it does not require an already-verified connection. Newer
privacy responses and account changes invalidate stale recovery requests.
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
Recommendation feedback and other derived-data services retain their existing
sync mechanisms; this journal is not a general queue for every cloud operation.

## Offline device backup

**Save device backup** is available in Profile settings, its pending-sync card,
and Privacy center, including the connection recovery screen. It never queries
Firebase, requires a new consent receipt, or clears a pending journal. The JSON
contains the current profile, signals, check-ins, outcomes, local settings and
pending input/outcome journals (including deletions). It is a device snapshot,
not a complete cloud export; the existing full-account export remains separate.

iOS exports through Files, Android uses the system document picker, and macOS
uses a save sheet. Save confirmation follows successful file completion;
cancellation and failure do not claim success. Other platforms offer explicit
copy-to-clipboard with instructions to paste into a file. A backup file can be
inspected independently; automatic JSON import is not provided in this change.

When cloud restoration would replace owned legacy inputs with no usable sync
baseline, or restore a missing cloud account, a durable recovery copy is written
first. Later distinct recovery copies preserve the earlier snapshots. These are
included as `beforeCloudRestore` in device backups and in owner-scoped account
exports. Unknown sync status is not treated as permission to upload or resurrect
ambiguous records. Tracking reset and account/device deletion remove recovery
copies. Backup and recovery reject mismatched accounts, sign-out and deletion.

The September 20 change passes **640 Flutter tests**, static analysis and
whitespace checks, including reconnect, account-race, offline-backup,
independent-field merge and native-save tests. An unsigned iOS simulator build
also passes. Actual iPhone/Android picker behavior and production Firebase
connectivity still require device QA; Android compilation is unavailable on the
development host because its SDK/JDK are not installed.
