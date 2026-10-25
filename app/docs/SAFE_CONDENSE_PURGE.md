# Safe condense-then-purge (Spark)

Operational runbook for retiring legacy HealthKit raw heart-rate documents from
Firestore without deleting sleep, HRV, check-ins, or other important inputs.
Stays on **Spark** (no Blaze). Free-tier quotas reset around midnight Pacific.

App automation lives in [`efficient_sync.dart`](../lib/src/efficient_sync.dart):
condense into `heartRateDays`, verify digests, then delete matching
`signals` docs in Spark-safe batches (`ContinuousRefreshLogic.maxHeartSummaryDaysPerSync`
and `maxLegacyHeartRateDeletesPerSync`).

## Do not purge

| Keep | Why |
|------|-----|
| Local SQLite raw HR | Full fidelity |
| `heartRateDays` | Condensed cloud form |
| HRV, resting HR, sleep/stages, check-ins, scores, coach, alerts | Model / UX inputs |
| `inputChanges` tombstones | Incremental sync |
| Legacy `forecastPoints` | Migrate-then-keep; app never deletes them |

## Purge target only

`users/{uid}/signals/{id}` where `type == heartRate` and `source == healthKit`,
and only after that sample exists in durable SQLite and its UTC day’s
`heartRateDays` summary is acknowledged.

**Never** bulk-delete from the Firebase console.

## Phase 0 — Protect

On **both** devices (Profile):

1. **Save device backup**.
2. Confirm the build with SQLite efficient sync (0.35+ heart storage).
3. Note Cloud sync: pending count, quota / cooldown, and the heart-rate upgrade line.
4. If over daily limit: wait for Pacific midnight and the in-app cooldown; do not spam Retry.
5. Prefer one primary phone as the heart-summary writer; open the second afterward.

## Phase 1 — Inventory

Purge candidates = HealthKit raw heart-rate signals only. Profile shows:

- day summaries still needing upload
- legacy cloud samples left to remove
- “upgrade complete” when `heartRateStorageVersion == 1` and queues are empty

Optional console **read-only** check when quota allows: count raw HR signals vs
`heartRateDays`. Do not delete.

## Phase 2 — Condense

Open Tonyo → **Retry sync** once (or Health **Sync now**). Each pass uploads at
most a few daily summaries, verifies server digests, then stops for the next
retry / day. Raw samples stay on device.

## Phase 3 — Purge

After a day’s summary is acknowledged, the same sync path deletes a bounded
batch of matching legacy signal docs and writes `inputChanges` tombstones
(leave those). Repeat Retry sync across quota resets until the legacy queue is
empty. Then the app sets `heartRateStorageVersion: 1` (rules block new raw
HealthKit HR uploads).

Stop on digest mismatch, ownership conflict, quota errors, or empty SQLite
while cloud still has raw — fix via backup / Retry, not console deletes.

## Phase 4 — Done (both accounts)

1. Cloud sync shows upgraded / synced (not a large legacy pending count).
2. `heartRateStorageVersion == 1` (Profile complete line, or user root field).
3. Few or no HealthKit raw `heartRate` docs under `signals`.
4. `heartRateDays` present for days that had samples.
5. Local history still shows raw readings.
6. Sleep, HRV, resting HR, check-ins unchanged.

## Stuck

1. Quota UI → wait for reset + cooldown → one Retry sync.
2. Primary device, then second device.
3. Writer conflict → keep the first writer for that UTC day.
4. Restore from Phase 0 backup if needed; still no console mass-delete.
5. May take multiple Spark days; leave devices on the new build overnight.

No Firebase rules redeploy is required for this cleanup.
