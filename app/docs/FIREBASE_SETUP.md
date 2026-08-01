# Tonyo Firebase Setup (Version 0.10-a)

Tonyo uses the existing Firebase project **Fatigue Project**
(`fatigue-project-e28a3`). Firebase values are injected at build time and are
not committed to source control.

## Provisioned console state

- Email/Password authentication is enabled.
- The default Cloud Firestore database uses the Standard edition, Production
  mode, and the `us-west2` (Los Angeles) region.
- The **Tonyo Flutter Runtime** web app is registered for shared runtime
  options.
- The owner-only rules in `firestore.rules` are published.
- The `signals(type ASC, timestamp DESC)` collection index declared in
  `firestore.indexes.json` is provisioned.
- The ignored `config/firebase_options.json` contains the current runtime
  values for local builds.

The current native bundle/application ID is `com.example.app`. Register
platform-specific Firebase apps after that placeholder is replaced for a
production release.

## Re-deploying rules and indexes

After changing `firestore.rules` or `firestore.indexes.json`, deploy from
`app/`:

```sh
firebase use fatigue-project-e28a3
firebase deploy --only firestore
```

`firestore.rules` is deny-by-default. It permits access only when
`request.auth.uid` exactly matches the `users/{uid}` path and intentionally
does not grant collection-group access.

## Local runtime values

The current machine already has an ignored runtime file. On a new machine, copy
the safe template:

```sh
cp config/firebase_options.example.json config/firebase_options.json
```

Fill the values from **Project Settings → Your apps → SDK setup and
configuration**. The real file is gitignored.

Run the app with:

```sh
flutter run --dart-define-from-file=config/firebase_options.json
```

When the file is omitted, Tonyo deliberately starts in offline demo mode. It
continues to use the existing SharedPreferences cache and does not attempt a
Firebase connection.

## Data layout

All persisted cloud data lives below the authenticated user's document:

```text
users/{uid}
├── signals/{signalId}
├── checkIns/{checkInId}
├── scoreSnapshots/{snapshotId}       (reserved)
├── forecastPoints/{pointId}          (reserved)
├── recommendations/{recId}           (reserved)
└── riskAlerts/{alertId}               (reserved)
```

The user document stores profile fields, account email, preferences, consent
flags, schema/migration versions, and `updatedAt`. Passwords are handled only
by Firebase Authentication.

## Migration and offline behavior

- On the first authenticated launch, an empty cloud account receives the
  existing SharedPreferences profile, signals, and check-ins.
- If the cloud account already has migrated Tonyo data, the cloud snapshot wins
  and refreshes the local cache.
- Every mutation writes the local cache first, then syncs the complete
  user-scoped snapshot. A network failure leaves the app usable offline and the
  next mutation retries sync.
- Profile → **Model & data privacy** exports the authenticated subtree and can
  permanently delete all six subcollections, the user document, the Firebase
  Auth account, and the local cache.

## Query helpers

`CloudRepository` exposes helpers for:

- Signals in a half-open day/range window
- Optional `SignalType` filtering
- Latest check-in
- Reaction-time baseline windows
- Full user export and recursive user-tree deletion

The `signals(type, timestamp)` compound index is declared in
`firestore.indexes.json`.

## Synthetic Cohort Lab

Tonyo can load a bundled synthetic student CSV for score debugging without
creating Firebase Auth accounts.

### Local visualizations

1. Open the app and complete onboarding / sign in as usual (optional for charts).
2. Profile → **Cohort Lab** → **Load CSV**.
3. Overview / Relations / People tabs render in-memory scores from
   `FatigueEngine`. Firebase config is not required for this path.

### Optional Firestore publish

Requires a signed-in Firebase account and
`--dart-define-from-file=config/firebase_options.json`.

Published tree:

```text
syntheticUsers/{studentId}
  meta, displayName, schemaVersion, updatedAt
  ├── signals/{signalId}
  ├── checkIns/{checkInId}
  └── scoreSnapshots/latest
syntheticCohort/summary
```

Security rules allow any authenticated user to read/write the synthetic tree
only. Real `users/{uid}` documents remain owner-only. Redeploy rules after
pulling this change:

```sh
firebase use fatigue-project-e28a3
firebase deploy --only firestore:rules
```

Use **Clear cloud** in Cohort Lab to delete the published synthetic tree without
touching production user accounts.
