# Version 0.32 — on-device Energy model

Implemented in `0.32.0+33`. The model is optional: deterministic Energy remains
the default unless one account's genuine, consented data passes all gates.
Cognitive remains deterministic/report-only. This is a wellness estimate, not
a diagnostic model or evidence of a causal effect.

## Use

Open **Profile → Model preparation** in a Firebase-configured signed-in build.
Select the same explicit 30-day account window used for preparation. Inspect it
first, then use the separate **Refresh Energy model** action when Energy is
ready. Nothing trains on screen entry, launch, Health refresh or forecasting.
Outcome learning must already be enabled; model refresh never grants consent.

| Action | Collection reads added | Writes added by this feature |
| --- | --- | --- |
| Prepare / inspect | Cached: zero; uncached: at most three capped queries plus one shared metadata read | Zero |
| Refresh Energy model | Zero; uses the prepared immutable snapshot only | Local attempt/artifact; one small metadata merge only for an accepted change |
| Apply accepted model | Zero; uses existing score inputs | No per-inference writes; existing daily score persistence retains the result and deterministic fallback |

These limits do not describe the app's pre-existing broad account sync or total
Firestore billing. The model path never calls `replaceUser`, attaches listeners,
creates a training collection, or uploads weights/examples. A failed metadata
write leaves the accepted model local and does not schedule automatic retries.

## Fit and safety

- Fixed ridge regularization λ=1, including the intercept; eight fixed-normalized
  features plus one intercept. No fitted scaler/imputer, hyperparameter search,
  neural network, LLM, ML dependency, or cross-user data.
- Target: `(observedEnergy - 1) * 100 / 9`, only from a validated, consented
  outcome linked to its real source. Synthetic/uncertain data is excluded.
- At least 14 distinct labeled days, four present features per Energy example,
  known historical input availability, compatible timezone offsets, and no
  truncated collection are required. Limits remain 1,500/100/100 documents;
  hitting any limit blocks training rather than trusting a truncated window.
- The newest 20% of eligible days (ceil, minimum three) form the holdout; all
  outcomes on one day stay together. Fit uses training rows only, with no refit
  on the holdout. Promotion requires at least 5% improvement in mean absolute
  error using the same rounded/clamped score deployed by the app.
- A correction is limited to ±10 points; final Energy stays within 0–100.
  Missing inputs contribute no feature effect, and coverage also shrinks the
  intercept. Same-day feature freshness fades to zero over 36 hours; baseline
  features fade over 30 days, including the age of baseline evidence. Neither
  Cognitive nor confidence is changed by the learned correction.
- The artifact is immutable, versioned, checksummed and smaller than 4 KB.
  Owner, schema, finite values, coefficient/error bounds and feature order are
  validated on restore. Invalid artifacts use deterministic scoring.
- The owner-local ledger requires a new eligible Energy outcome and at least
  24 hours between attempts, including rejection. It survives normal restart
  and sign-out. Account changes, revoked consent, and edits/deletions interrupt
  pending work safely; edits/deletions and revocation erase accepted weights.
- The numeric training kernel rejects a ≥100 ms execution or estimated working
  payload ≥1 MB; inference rejects a ≥1 ms kernel execution. The reference
  score remains available immediately. Shared feature preparation is part of
  score input processing, not included in the microsecond dot-product benchmark.

Daily score snapshots preserve `deterministicEnergy` and the applied model
version, so a different device without weights—or the same device after
revocation—does not silently reuse a personalized score as its baseline.

## Future records and historical availability

Schema 12 adds optional `recordedAt` to manual signals and check-ins. New records
and edits retain the actual entry/update time separately from their observation
time. Historical records lacking this evidence remain unknown: there is no
backfill that pretends they were available earlier. An unchanged repeated sleep
import retains its first saved availability; an actually changed import gets
the new sync time. Both app-generated activity/sleep IDs and existing manual
IDs are recognized, while seed/demo markers still take precedence.

## Verified local benchmark — September 7, 2026

macOS arm64, Dart 3.12.2 AOT, isolated generated test inputs, warmed kernel,
200 fits and 100,000 predictions per case. These are software benchmarks, not
training or validation on a real account, and not iPhone measurements.

| Case | Artifact | Training p50 / p95 / max | Mean inference | Estimated working payload |
| --- | --- | --- | --- | --- |
| 30 Energy labels | 800 bytes | 1.035 / 1.072 / 1.284 ms | 0.790 µs | 35,640 bytes |
| 99 Energy labels, 1,499 signals, 99 check-ins | 829 bytes | 3.273 / 3.394 / 3.513 ms | 0.813 µs | 224,632 bytes |

No inference budget fallbacks occurred in these runs. Near-cap process peak RSS
grew by 524,288 bytes across the whole loop, but **RSS and estimated numeric/map
reference payload do not prove a per-fit temporary-heap bound**. iPhone release
profiling and actual heap measurement remain open release checks.

Reproduce from `app/` (use a task-specific temporary output directory):

```sh
task_bench_dir=$(mktemp -d)
dart compile exe tool/benchmark_energy_model.dart -o "$task_bench_dir/energy-model"
TZ=UTC "$task_bench_dir/energy-model"
TZ=UTC "$task_bench_dir/energy-model" --maximum-window
```

The training snapshot checksum is cached safely because its entire input graph
is immutable. Kernel validation reads a small report identity instead of
re-exporting every example, reducing repeat allocations without weakening the
source fingerprint, provenance or holdout checks.

## Account and release status

The previously fetched July 2–31 account snapshot still contains 222 synthetic
signals, 60 synthetic check-ins and zero outcomes. That inspected month cannot
train either head. No current-account reads, consent changes, outcome backfills,
training promotion or production database writes occurred during this work.

Local rules restrict new/changed `personalizedEnergyModel` summaries to the
owner with both consent flags, exact metadata fields and bounded values. The
field-difference guard follows [Firebase's documented field-access rules](https://firebase.google.com/docs/firestore/security/rules-fields).
Version 0.34 added **24 passing executable Firestore emulator tests**, including
the owner/dual-consent metadata guard, guardian gating and atomic-batch checks.
See the [security harness](../tool/security_rules/README.md). Production rules
deployment and backend IAM remain unverified; deploy and audit through the normal
release process before relying on these guards in a live account. No cross-user
grants were added.

Before final release sign-off: measure on the target iPhone, verify the actual
temporary heap, validate/deploy rules, and test acceptance on genuine consented
data once enough labeled days exist. Version 0.33's separate
[transparency screen](MODEL_TRANSPARENCY.md) explains the active score and saved
model metadata; it does not complete those outstanding release checks.
