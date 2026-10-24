# Firebase usage and offline operation

Checked October 24, 2026 at 2:47 p.m. Pacific. This is a measured snapshot;
run the command below for current counters. No billing setting was changed.

| Measure | Observed usage | Allowance |
|---|---:|---:|
| Daily read operations | 50,447 | 50,000 |
| Daily write operations | 3,273 | 20,000 |
| Stored data and indexes | 27,699,757 bytes (26.4 MiB) | 1 GiB free storage |

Google's enforcement metric explicitly reports
`ReadOperationsPerProjectPerDay` exceeded. This identifies the daily read limit
as the cause of the observed quota failure. Storage is below the free allowance.
Billing is disabled. Daily read/write quotas reset around midnight Pacific.

The figures above use `serviceruntime.googleapis.com/quota/rate/net_usage`,
`quota/limit`, `quota/exceeded`, and Firestore's data-and-index storage gauge.
Document-operation monitoring totals differ from enforced/billed totals; the
lower document-read counter alone must not be interpreted as spare quota.
Metric reporting can lag. Missing counters mean unknown, never zero.

The compact measured evidence is in [firebase_usage_latest.json](firebase_usage_latest.json).

## Check usage again

From `app`, with the existing Firebase CLI login and the repository's
`tool/security_rules` dependencies installed:

```sh
node tool/firebase_usage_audit.mjs --out /private/tmp/tonyo-firebase-usage.json
```

The default interval starts at midnight in `America/Los_Angeles`, accounting for
daylight saving time. `--start` and `--end` accept explicit ISO timestamps for
historical checks. The command prints a compact summary and writes the full
metadata report to the requested local file. The checked-in snapshot is not
automatically updated and is not displayed as live usage in the iPhone app.

The command uses only allowlisted metadata GET endpoints for Cloud Monitoring,
Service Usage, and billing status. It never queries health documents, embeds
administrator credentials in Tonyo, changes billing, enables services, or starts
a scheduled job. Access errors are reported explicitly.

Console links: [Firestore usage](https://console.firebase.google.com/project/fatigue-project-e28a3/firestore/usage),
[Firestore quotas](https://console.cloud.google.com/iam-admin/quotas?project=fatigue-project-e28a3&service=firestore.googleapis.com).
Reference: [Firebase quotas](https://firebase.google.com/docs/firestore/quotas),
[monitoring and billing differences](https://firebase.google.com/docs/firestore/monitor-usage).

## App behavior

- Records from Health are labelled **Apple Health**, and user entries **Manual**.
  These describe origin only. Profile separately reports **Saved on iPhone**,
  **Backup pending**, **Backed up**, or a device-save problem. Unacknowledged
  changes never receive a backed-up label.
- An existing adult account with matching device ownership, current explicit
  consent and a verified account snapshot can continue locally through network
  failures for up to **72 hours from its last successful verification**.
  Failed requests never extend that period. New accounts, minors, missing
  consent, owner mismatches, clock rollback, known account/permission failures
  and deletion do not receive this access. An upgrade preserves the original
  verified timestamp; it does not start a new grace period.
- Local permission never authorizes cloud access. Cloud reads/writes and model
  preparation wait for successful verification. Recovery checks current consent
  before uploading pending edits; known withdrawal invalidates offline access.
  A quota-only failure retains the earlier separate, freshly authenticated
  local fallback. A signed-out user must enter their credentials again; a
  successful same-account sign-in and fresh Auth check can reopen that account’s
  owned adult cache during a Firestore quota failure. This never signs in
  automatically or permits another account to claim the cache. Neither mode silently changes the user's privacy choices.
- Foreground saves first persist the device journal. Repeated edits wait for
  **two quiet seconds**, capped at ten seconds from the first edit, before
  one upload cycle sends the final record values. Distinct records still count
  as distinct writes; this is coalescing edits, not a claim that batching makes
  multiple documents free. Account setup, explicit Retry/Health sync and
  raw-data deletion retain immediate behavior. Backgrounding cancels the timer; durable changes
  resume on the next launch/foreground recovery.
- Daily heart summaries, raw heart data on the iPhone, and the existing
  three-hour incremental input refresh remain in effect. These changes reduce
  redundant requests; they do not guarantee that every usage pattern fits the
  free daily quota.
