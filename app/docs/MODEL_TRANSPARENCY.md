# Version 0.33 — How your scores work

Open **Today → Why these scores?** or **Profile → How your scores work**.
The screen explains the displayed estimate without changing it. Energy and
Cognitive have separate drivers, confidence, completeness, and model versions.

## Reading an explanation

- The score is an estimate on a 0–100 scale, not a sensor reading or diagnosis.
- Confidence is the existing evidence-quality heuristic, not the probability
  that a prediction is correct. Coverage, observation freshness, source/quality
  weighting and available personal-baseline maturity affect it. Training the
  Energy model does not raise confidence or change Cognitive scoring.
- Driver contributions are the saved `scoreSnapshots.drivers` or
  `cognitiveDrivers`, ranked by absolute point impact. Expand them to read the
  saved explanation, source types, and age **at calculation**. No fresh raw-data
  join is used to invent an explanation for an older saved score.
- A zero-point driver can still represent observed data. An absent driver is
  not proof of a zero measurement. Legacy coverage without driver details is
  explicitly unknown. All stored drivers remain visible, including labels from
  versions outside the current inventory.
- The Energy coverage field is historically capped at seven inputs. The full
  inventory has ten current factor categories. These are shown separately;
  adding repeated records or extra capped drivers need not raise confidence.
  Cognitive uses six categories. This release does not change either formula.

Measured/imported means an input came through Apple Health, not that Tonyo
verified its original measuring device or ruled out manual entry in Health.
Self-reported/app-entry, model-estimated, demo/synthetic, missing, and
unverified/mixed evidence are labeled separately. Every contribution to a
score remains a model estimate regardless of input kind. Driver points describe
the scoring rules; they do not establish that an input caused how someone feels.

## Versions and timestamps

New schema-13 snapshots record `energy-rules-v1` and `cognitive-rules-v1`
separately from the optional `energy-ridge-v1` correction. Older snapshots do
not acquire made-up version identifiers or calculation times. New driver
summaries retain the current/recent observation source types and whether
recognized seed/demo markers occurred. Historical personal-baseline provenance
is not stored in those fields: a measured current observation does not verify
the history used for comparison. Null legacy
provenance means unverified, not genuine. This marker check cannot authenticate
the truth of a logged value, and does not relax training eligibility checks.

The model screen distinguishes:

| Detail | Meaning |
| --- | --- |
| Score calculation | When the displayed snapshot was calculated |
| Local model trained | When the accepted, owner-local weights were fitted |
| Firebase model trained | Training time reported by the last loaded account summary |
| Account data updated | Existing `users/{uid}.updatedAt`, not proof of a model write |
| Metadata loaded | When this device last read the account projection |

A Firebase summary contains validation metadata, not executable weights.
Its presence never claims that a model is installed or applied on this phone.
A valid local model can make no adjustment because a small correction rounds
to zero or its input/safety gate falls back. Only an actual saved/applied
correction is labeled personalized. Held-out mean absolute error is shown in
score points; percentage error reduction is not health improvement or confidence.

## Database and privacy boundary

The summary is parsed from the app's existing `readUser` document response.
The new screen and its selectors/expansion controls add **zero collection reads,
metadata reads, writes, listeners, model loads or training attempts**. The
owner-keyed summary cache is updated during existing account persistence; it
never queries a different account. Offline use retains the original fetched-at
time and labels the data as cached. There is no automatic refresh claiming
remote changes have been observed.

Malformed/unsupported model summaries are unavailable, not active models.
Sign-out hides the score details and metadata, reset removes the local cache,
and delayed old-account hydration or score queries cannot repopulate them after
sign-out or an account switch. Superseded same-account score refreshes cannot
overwrite a more recent request either.
Weights, examples, consent and Firestore rules are unchanged by this release.
Only the existing daily score save gains small version/provenance fields;
no old rows are backfilled and no per-view documents are created.

## Verification and remaining release checks

Automated checks cover metadata parsing and actual repository read budgets,
legacy serialization, exact driver projections, zero/absent data, mixed/demo
sources, stale/future timestamps, unchanged scoring, owner-safe offline caching,
navigation and large-text/narrow-screen layout. UI captures use isolated test
fixtures, not the user's private account or fabricated training labels.

Version 0.32's outstanding real-iPhone performance/actual-heap and Firestore
emulator/deployment checks remain open. This release does not claim to complete
those checks, train the saved July account, or implement Version 0.34 privacy
and youth-consent work.
