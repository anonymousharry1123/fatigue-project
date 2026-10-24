# Executable Firestore privacy rules tests

These tests execute the repository's actual `firestore.rules` in the Firebase
Firestore emulator; they are not string-pattern assertions. Fixtures are generated
test accounts, never downloaded account data.

## Run

Requirements: Node 22 or later, Java 21 or later, and pnpm 11.19.0.

```sh
cd app/tool/security_rules
pnpm install --frozen-lockfile --ignore-scripts
pnpm test
```

The three direct dependencies and transitive dependency graph are pinned in
`package.json` and `pnpm-lock.yaml`. Installation scripts are unnecessary. The
first run downloads the official Firestore emulator. Node modules, temporary
Firebase configuration and emulator downloads remain in this ignored test
directory, not in the Flutter app bundle. Java may be an existing runtime or a
portable runtime on `PATH`; no system-wide Java installation is required.

`run.mjs` uses only `demo-tonyo-privacy`, strips inherited cloud credentials and
debug logging, and invokes Firestore on loopback. It does not login or deploy.
The test suite refuses missing or non-loopback `FIRESTORE_EMULATOR_HOST` values,
so directly running it cannot silently fall back to a production database. Tests
clear the **demo project's emulator data** before each case. Do not use that demo
project for unrelated emulator sessions while this suite is running.

For an already-running local emulator:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 pnpm test:running
```

## What is covered

- Unauthenticated/cross-account reads, writes, lists and deletion are denied.
- No user-directory queries, including a query filtered to the caller's own ID,
  and no cross-user collection-group queries.
- Owners can inspect/export all ten known collections without renewing consent.
  Tracked input deletion requires its atomic journal entry; account deletion
  permits cleanup of every collection, including retained journal tombstones.
  Unknown collections and deeper nesting remain denied.
- Daily heart-rate and forecast documents have bounded formats. Heart-rate
  summaries retain an immutable writer ID; activating summary storage blocks
  new individual HealthKit heart-rate uploads while allowing HRV/resting rates.
- Input sync/storage versions cannot downgrade. Tracked source changes and
  matching full known-field journal payloads require one atomic revision step.
  Sixteen signal changes or complete research check-ins fit the rule budgets.
  Check-in answer/metadata validation runs on the source and its immutable
  questionnaire definition is validated on the matching journal, keeping the
  complete contract within Firestore's per-write expression limit.
- New adult consent must use a server timestamp. Missing, malformed, implicit,
  backdated or future consent cannot permit data collection.
- Acknowledged age/region cannot be silently changed. A client cannot set
  guardian/operator verification or alter future protected server metadata.
- Under the current conservative pre-release policy, every under-18 band needs
  both server-issued guardian claims at the current policy version. Approval
  conveys no right to read another user's records.
- Outcome writes need both optional consent flags; model metadata retains its
  strict field, size and improvement bounds. Explicit optional-consent changes
  need server-timestamped receipts, while routine profile sync preserves them.
- Deletion intent and root deletion require authentication within five minutes.
  Deletion intent blocks all new data writes, allows export/child deletion,
  survives interrupted retries, and prevents stale profile re-creation.
- Atomic batches cannot combine deletion intent or outcome-consent withdrawal
  with a data write: parent checks use `getAfter`, not pre-batch state.
- Synthetic cohort paths require a server-issued operator claim; ordinary or
  guardian-approved accounts cannot use them as a public sharing channel.
- Phase 1 exercise zero values survive transactional save, merged edit, a new
  authenticated client's server read, and export. A missing document and an
  explicitly deleted manual override stay distinct from zero; the imported
  observation remains intact after the override is deleted.
- Phase 1 deterministic score merge writes explicitly clear obsolete
  personalization fields with nulls. Unavailable-score merges clear prior
  Cognitive values, availability, baseline and change fields on a server reload.
- These Phase 1 payloads retain privacy, guardian, cross-account and optional
  outcome-consent restrictions, including owner export/deletion after revocation.
- Phase 2A custom check-ins preserve six independent integer answers, skipped
  values, explicit clearing and honest completeness through transactions and
  fresh server reads. Zero, fractional and empty submissions are denied.
- New-format records require bounded wording/version/language/time metadata.
  Missing versions, malformed or extra definition fields, and attempts to
  downgrade or rewrite original provenance are denied. Legacy edits remain
  available, but cannot silently upgrade an old measurement into a new one.
- Complete and partial writes retain owner/consent/guardian/outcome gates.
  Duplicate answers still count individually; Unicode and multiline wording,
  including a complete guardian-authorized update, fit the rules expression
  budget without dropping validation.

The Phase 1 cases mirror the current `cloud_schema.dart` wire format; the Dart
serialization suite verifies the app-to-wire conversion. Explicit server reads
from new rules-testing clients verify emulator persistence rather than a local
SDK cache. This is not an app process restart, native background test or physical
device acceptance check.

## Release limitations

Passing emulator tests validates these client rules, not legal compliance,
Firebase deployment, production IAM, or a guardian verification service.
`guardianConsentVerified: true` and `guardianConsentPolicyVersion: 1` must only be
issued by a trusted backend after a reviewed verification process. There is no
client-side way to grant them, and a guardian checkbox is not verification.
The guardian workflow and launch-country/age policy still need product/legal
review. Custom-claim withdrawal affects refreshed ID tokens; already-issued
tokens can remain valid until expiry. A production system needing immediate
withdrawal enforcement needs a server-enforced revocation design.

Synthetic-lab operators similarly require a trusted-backend
`syntheticLabAdmin: true` claim. Ordinary accounts intentionally lose cloud lab
access. Admin SDKs bypass client rules, so backend IAM and any historical unknown
subcollections need a separate trusted-server audit. The mobile export/delete
contract covers the root document and ten flat known collections, not an
arbitrary backend-created subtree, provider backups, or original Apple Health
records. These rules are local until an authorized deployment occurs.

Primary references: [Firebase emulator tests](https://firebase.google.com/docs/firestore/security/test-rules-emulator),
[granular/overlapping rules](https://firebase.google.com/docs/firestore/security/rules-structure),
[field access control](https://firebase.google.com/docs/firestore/security/rules-fields),
and [server-issued custom claims](https://firebase.google.com/docs/auth/admin/custom-claims).

Verified locally on 2026-09-07: **24 executable cases passed** using Node
24.19.0, Firestore emulator 1.22.0 and a temporary Temurin Java 21.0.12.1 runtime.
This is separate from Flutter's fast source-shape regression tests.

Verified again on 2026-10-03: **28 executable cases passed; 0 failures, skips,
cancellations or TODO cases**, including the four Phase 1 persistence/privacy
regressions above. Used existing Node 24.19.0, cached pnpm 11.19.0, Firestore
emulator 1.22.0, and a checksum-verified portable Temurin Java 21.0.12.1 runtime
under ignored `.runtime/java21/`. Existing pinned dependencies were reused; no
system-wide installation or persistent shell change was needed. The initial
sandboxed run could not bind loopback sockets (`EPERM`); the approved local
emulator retry passed. See [the progress record](../../docs/BIOLOGY_UPGRADE_PROGRESS.md)
for exact runtime paths and executed command.

Verified on 2026-10-24 after the storage/sync changes: **47 executable cases passed;
0 failures, skips, cancellations or TODO cases**, including the seven measurement
cases. Existing runtimes and the locked dependencies were reused. Initial runs
exposed the rules expression limit; equivalent exact-key/type/length validation
was simplified and the full suite rerun successfully. No rules were deployed.

## Native Flutter app integration

`pnpm test:app` is a separate opt-in harness. It starts local Auth and Firestore
emulators for the fixed demo project, creates a fresh iOS simulator, and runs
the native Flutter app integration scenario followed by a separate process
restart verification. It never selects a preexisting simulator or physical
device. `pnpm test` remains the security-rules suite described above; its case
counts do not include the Flutter integration scenarios.

See [Phase 1 emulator integration](../../docs/PHASE1_EMULATOR_INTEGRATION.md)
for prerequisites, exact commands, isolation guards, current results, and
limitations. Normal builds now import `lib/src/firebase_secrets.dart`, so the
absence of a Firebase command-line flag does **not** imply an offline build.
Use a separate checkout for native emulator integration. Before its first build,
from that checkout's `app/` directory, create the local file from the empty
example only if no local file already exists:

```sh
if [ ! -e lib/src/firebase_secrets.dart ]; then
  cp lib/src/firebase_secrets.example.dart lib/src/firebase_secrets.dart
fi
```

Keep all constants empty in that isolated checkout. The imported file must
exist for compilation, and the native integration path rejects any nonempty
Firebase configuration. Do not copy real values or a native Firebase project
plist into it, and do not overwrite a configured working copy. Run only the
guarded `pnpm test:app` harness, not `run.sh` or a normal app launch. The Node
rules-only `pnpm test` command does not compile the Flutter app and does not
need the Dart configuration file. These checks do not deploy rules or indexes.

The incremental input and heart-summary scenario uses the same guards and a
separate newly created simulator:

```sh
node run_app_integration.mjs sync
```

It exercises native protocol activation, a two-chunk tracked write, a full
bootstrap, older-timestamp edits, explicit nulls, journal deletions, and durable
cursor replay after a real process restart. Heart-rate summary acknowledgement
and server rereading precede raw-record cleanup; the storage marker then blocks
new raw HealthKit heart-rate uploads. The default native SQLite store preserves
exact raw fields, import provenance, and a deliberately empty snapshot across
the process restart. The second process verifies summary idempotence and deletes
its synthetic account and local records. This suite requires the same
empty configuration in an isolated checkout as the Phase 1 scenario.

Verified on 2026-10-24: the `sync` scenario passed in both independent native app
processes on a newly created iPhone 17 / iOS 26.5 simulator, using the real
FlutterFire and sqflite platform plugins. The guarded runner exited 0 with rules
SHA-256 `3b79a44a2f311d1b23f2eb76a28b776f1caf2b9dcd8e27f70a3c4c16cf54b37e`.
The first attempt exposed an inconsistent synthetic partial-answer fixture;
correcting its completeness fields allowed both full runs to pass. This
verification used only the fixed demo project and loopback emulators, with
empty Firebase configuration in a temporary source copy. It did not deploy
rules, contact a production project, or install on a physical device.
