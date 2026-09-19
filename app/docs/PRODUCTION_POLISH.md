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
compared at their top-level field boundaries, so concurrent edits to different
parts of one profile/preferences object can conservatively conflict.

Consent receipts, deletion state and model metadata retain their separate APIs.
Routine saves and legacy migration never replace whole input collections or
create missing accounts. A missing account requires explicit setup; old cache
data is not permission to recreate it.

**Profile → Cloud sync** retries pending uploads. A same-record conflict keeps
the local edit and the remote version separately. Choosing **Use cloud version**
requires confirmation and replaces the pending local input edits with the
current cloud inputs. Recovery waits for an active upload and rejects a new
input edit arriving during recovery. There is no automatic last-write-wins
resolution or background retry loop: launch, the next save, and explicit retry
attempt pending input sync while the session and privacy gate permit it.
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
