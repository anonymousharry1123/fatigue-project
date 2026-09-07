# Privacy and youth safety — Version 0.34

Implemented on September 7, 2026. This is an engineering safeguard, **not a
declaration of legal compliance or permission to launch to minors**.

## What users see

Open **Profile → Privacy center**. Review the data-use notice, inspect the dated
receipt, independently enable/disable Outcome learning, generate an export, or
delete the account. Merely opening the screen performs no export or consent write.

New users choose a neutral age band and region before the name/email/password
pages. No date of birth or guardian contact information is collected. The
acknowledgement is unchecked; learning stays off. Existing authenticated users
without a valid receipt must review privacy before new tracking, Health imports,
scoring writes, or model preparation. Their existing records remain readable for
export and deletion. An old `wellnessOnlyAcknowledged` boolean is not upgraded
silently into a new receipt. Profile age labels are not evidence of consent.

Tonyo is a wellness tool: estimates and recommendations are not a diagnosis,
medical treatment, or a guarantee of safe activity. Confidence describes available
evidence, not medical certainty. Health access is read-only and separately
controlled by Apple's permission system. Outcome learning is another optional
choice, not part of account registration or the required acknowledgement.

## Provisional youth policy and release gates

Until launch countries, supported ages, and a verification provider are selected,
**every under-18 band is blocked without trusted guardian verification**. This
is a conservative product policy, not a claim that all jurisdictions require
guardian consent until 18. A new unverified minor cannot advance to account
credentials. The selected minor band is locked for that onboarding flow.

Existing minor accounts need both current Auth custom claims:
`guardianConsentVerified: true` and `guardianConsentPolicyVersion: 1`.
Only a trusted backend may issue these after a reviewed, verified guardian
process. No checkbox, profile field, synthetic fixture, or client API can grant
them. This build does **not** provide that verification service. Guardian status
does not grant access to another account's records. Acknowledged age/region are
immutable in client rules; support corrections need a reviewed trusted workflow.

Claims are force-refreshed on load, sign-in and foreground resume. Startup uses
a server root read; resume uses one narrow server user-document read, not a
history scan. Failed verification pauses collection. There are no added Firestore
listeners or model-training loops. Custom-claim withdrawal is not instantaneous
for already-issued tokens: expiry/refresh limits still apply. Production requiring
immediate withdrawal needs a server-enforced revocation design.

Before a youth launch: choose countries/ages, review the current legal policy,
build verified guardian onboarding and withdrawal/correction/support workflows,
review retention and provider backups, audit backend IAM, deploy and verify the
rules, and run actual iPhone permission/account lifecycle QA. These are open
release gates, not completed features. The [FTC's COPPA guidance](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions)
is background for policy review, not a substitute for a launch-specific review.

## Receipts and optional learning

Schema 14 adds `users/{uid}.privacyConsent` with exactly five fields:
`policyVersion`, `ageBand`, `region`, `acceptedAt`, `wellnessAcknowledged`.
Cloud acknowledgements and `outcomeConsentUpdatedAt` use server timestamps and
targeted merges. Ordinary profile sync does not manufacture or replace receipts.
The receipt records the current decision, not an immutable audit-history service.
Local-only mode stores an explicit dated receipt in this device's preferences.

Turning learning off immediately unloads the local model and stops local outcome
collection. The cloud update must succeed to withdraw the cloud flags; a failure
is shown explicitly with a retry instruction. Withdrawal does not retroactively
delete all previously stored outcomes—use account deletion to erase them.

## Export contract

Generation is explicit and can fail; no partial-success export is returned.
The UI displays counts and scope before a separate **Copy** action with a
sensitive-data clipboard warning. Treat exported files/clipboard data as private.

Export version 2 includes:

- `cloud.userDocument`: the raw root document, including unknown root metadata
  and consent/model fields (or null if absent).
- `cloud.collections`: original document IDs and raw fields from all seven
  supported flat collections: `signals`, `checkIns`, `scoreSnapshots`,
  `forecastPoints`, `recommendations`, `outcomes`, `riskAlerts`.
- `local`: the matching owner's current Tonyo state, device preferences and
  owned persisted model/preparation caches. Other owners' caches are excluded.
- Explicit scope/time metadata. Multi-page reads are **not** an atomic snapshot;
  another device can change records during generation.

Cloud export uses server-only pages of 100, with limits of 100,000 documents,
64 MiB of encoded cloud records, and 5,000 requests. Limits stop with an error;
they never quietly truncate the export. Unsupported Firestore scalar values are
represented by tagged JSON so they are not silently lost. Reads and each await
are bound to the current UID. Export performs no Firestore writes.

The contract excludes arbitrary administrator-created nested/unknown collections,
Auth credentials/provider internals, original Apple Health data, other devices,
previous exports and provider backups. Client rules prohibit creating unknown or
nested collections; backend/Admin SDK history still requires a server audit.

## Deletion and recovery

Cloud deletion requires typing `DELETE` and re-entering the current password.
Firebase reauthentication checks the existing user credential—it does not run
the app sign-in/hydration workflow. An incorrect password removes no data.
The [Firebase Auth documentation](https://firebase.google.com/docs/auth/flutter/manage-users)
explains the recent-login requirement.

After verification, a durable device journal pauses collection and automatic
sync. A recent-auth server `privacyDeletion` marker denies new account writes,
including stale and same-batch writes. The repository deletes the seven known
collections in batches of at most 100, verifies all seven are empty, and deletes
the root last. Firebase Auth deletion follows; only then is this device's state,
model/prep cache and notification schedule cleared. Parent deletion alone does
not remove subcollections, as [Firebase documents](https://firebase.google.com/docs/firestore/manage-data/delete-data).

Interruption keeps the journal and any server marker. Retry repeats bounded,
owner-checked deletion safely; remaining server data can still be exported. A
restart never treats a missing root as permission to recreate a deleted profile.
If Auth completion cannot be confirmed, the UI offers signing in to finish or
an explicitly narrower **clear this device only** recovery. Device-only cleanup
does not assert that the Firebase Auth account was deleted. Apple Health originals,
other device caches and previous exports are not erased by this operation.

## Verification and deployment

The executable [security harness](../tool/security_rules/README.md) tests the
actual rules in a credential-stripped, demo-only emulator: 24 cases passed,
including owner isolation, denied directory/collection-group listing, guardian
authority, optional consent, 100-document batches and deletion races. The Flutter
suite covers receipts, server-confirmed repository operations, controller recovery
and real widget interactions, including narrow/large-text layouts.

Final local verification: **508 Flutter tests pass**, **24 executable emulator
tests pass**, full Flutter analysis is clean, and five rendered UI captures were
visually checked. No new runtime package or background model job was added.

Rules and app changes must be released together. Existing old clients without a
receipt cannot make new writes after these rules are deployed. Cloud Cohort Lab
paths now require a trusted `syntheticLabAdmin` claim; ordinary accounts cannot
use them as a sharing channel. Emulator success does not verify production IAM:
Admin SDKs bypass client rules. No rules deployment, live-account mutation or
real-device installation was performed by this implementation.
