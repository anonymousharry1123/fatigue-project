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
- Owners can get/export/delete their seven known collections without renewing
  consent. Unknown collections and deeper nesting remain denied.
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
contract covers the root document and seven flat known collections, not an
arbitrary backend-created subtree, provider backups, or original Apple Health
records. These rules are local until an authorized deployment occurs.

Primary references: [Firebase emulator tests](https://firebase.google.com/docs/firestore/security/test-rules-emulator),
[granular/overlapping rules](https://firebase.google.com/docs/firestore/security/rules-structure),
[field access control](https://firebase.google.com/docs/firestore/security/rules-fields),
and [server-issued custom claims](https://firebase.google.com/docs/auth/admin/custom-claims).

Verified locally on 2026-09-07: **24 executable cases passed** using Node
24.19.0, Firestore emulator 1.22.0 and a temporary Temurin Java 21.0.12.1 runtime.
This is separate from Flutter's fast source-shape regression tests.
