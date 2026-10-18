# Tonyo Firebase Setup (Version 0.10-a)

Tonyo uses the existing Firebase project **Fatigue Project**
(`fatigue-project-e28a3`). Firebase values are injected at build time and are
not committed to source control. Normal Flutter and Xcode builds now compile
the string constants from the ignored `lib/src/firebase_secrets.dart` file.

## Provisioned console state

- Email/Password authentication is enabled.
- The default Cloud Firestore database uses the Standard edition, Production
  mode, and the `us-west2` (Los Angeles) region.
- The **Tonyo Flutter Runtime** web app is registered for shared runtime
  options.
- The owner-only rules in `firestore.rules` are published.
- The `signals(type ASC, timestamp DESC)` collection index declared in
  `firestore.indexes.json` is provisioned.
- The ignored `config/firebase_options.json` is the legacy migration input;
  runtime builds use `lib/src/firebase_secrets.dart`.

The iOS Firebase registration must match the native target's bundle ID. Its
app ID is separate from the web registration.

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

Before the first build in a new checkout, copy the empty Dart example once.
Preserve any existing configured file:

```sh
if [ ! -e lib/src/firebase_secrets.dart ]; then
  cp lib/src/firebase_secrets.example.dart lib/src/firebase_secrets.dart
fi
```

Leave the constants empty for offline mode, or fill them from **Project
Settings → Your apps → SDK setup and configuration**. `webAppId` is the web
registration; `iosAppId` is the separate iOS registration (its value contains
`:ios:`). The other constants are `apiKey`, `messagingSenderId`, `projectId`,
`authDomain`, `storageBucket` and `iosBundleId`. The real file is gitignored;
commit only the empty `firebase_secrets.example.dart` template.

The existing ignored `config/firebase_options.json` can supply values during
migration. It is no longer read by normal runtime builds, and changing it does
not update the compiled app. The old `--dart-define-from-file` launch flag no
longer configures Firebase. Keep real configuration out of tracked documents,
logs and commits.

Run the app with:

```sh
flutter run
```

VS Code and Xcode **Run** use the same compiled constants without Firebase
launch flags or an Xcode setup script. Rebuild after changing the file.

The one-time copy is a compilation prerequisite because `firebase_options.dart`
imports `firebase_secrets.dart` directly. A missing file cannot compile. An
existing file with empty constants starts offline, continues to use the
existing SharedPreferences cache and does not attempt a Firebase connection.
iOS also starts offline when `iosAppId` is empty or is not an iOS app ID; this
preserves the protection against passing the web app ID to the native iOS SDK.

For offline/emulator testing, use a separate checkout with the empty example
copied to its local secrets file. The guarded native emulator harness rejects
any nonempty Firebase configuration. Do not replace this working copy's
configured file to run an emulator; follow the
[isolated integration instructions](../tool/security_rules/README.md#native-flutter-app-integration).

## Data layout

All persisted cloud data lives below the authenticated user's document:

```text
users/{uid}
├── signals/{signalId}
├── checkIns/{checkInId}
├── scoreSnapshots/{snapshotId}       (daily scores)
├── forecastPoints/{pointId}          (hourly forecasts + updatedAt + evidence IDs)
├── recommendations/{recId}           (daily grounded guidance + evidence IDs)
└── riskAlerts/{alertId}               (dismissible wellness flags + evidence IDs)
```

The user document stores profile fields, account email, preferences, consent
flags, schema/migration versions, and `updatedAt`. Version 0.20 stores explicit
notification consent plus separate lower-energy/recovery choices in `prefs`:
`notificationsEnabled`, `crashNotificationsEnabled`,
`recoveryNotificationsEnabled`, and `notificationPreferencesVersion`.
Passwords are handled only by Firebase Authentication.

Older documents without notification preference Version 1 are treated as not
opted in, even if a legacy preview build stored `notificationsEnabled: true`.
This prevents a placeholder default from becoming notification consent.

## Version 0.20 local notification delivery

Notification timing and pending deliveries remain on the user's device; only
the preferences and the already-private forecast/risk inputs sync through
Firestore. Android uses inexact alarms and restores scheduled items after boot
without requesting exact-alarm access. iOS registers the app notification-center
delegate. macOS and Windows use the plugin's native scheduler. Web and Linux
show the setting as unavailable because reliable scheduled delivery is not
supported there.

Permission is requested only after the user turns on **Profile → Forecast
alerts**. Tonyo cancels its own pending guidance on opt-out, sign-out, and data
reset while preserving unrelated app notifications.

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

## Password reset

### How it works

- **Forgot password?** on either sign-in screen asks Firebase Authentication
  to send its standard password reset email.
- The user copies the link (or just its code) from that email and pastes it
  into Tonyo, then chooses a new password in the app. No deep links, Dynamic
  Links, or hosted action pages are needed; the app reads the `oobCode` from
  the pasted link.
- After requesting a reset, Tonyo always shows the same neutral "if an
  account exists, an email was sent" message, so it never reveals whether an
  email address has an account.
- **Profile → Change password** is for signed-in users. It asks for the
  current password, reauthenticates with Firebase, then updates the password.
  A wrong current password shows "Current password is incorrect." and changes
  nothing.

### Email template

No template changes are required. Firebase's default password reset email
("Follow this link to reset your password…") contains the full `%LINK%`, and
Tonyo extracts the reset code from it. The app itself tells users to press and
hold the link, choose Copy, and paste it into Tonyo. Tapping the link instead
opens Firebase's default action page, which also resets the password; the user
then signs in to Tonyo with the new one.

Firebase currently blocks edits to Auth email templates on many projects
("Email template updates are currently unavailable for this project"). If a
custom message is needed, either ask Firebase Support to apply the change, or
send reset emails yourself from a backend: generate the link with the Admin
SDK's `generatePasswordResetLink` and deliver it through your own email
provider (requires the Blaze plan).

Email enumeration protection (**Authentication → Settings → User actions**)
is compatible with this flow and can stay enabled, because the app already
shows the same message whether or not the account exists.

### Local emulator testing

The Auth emulator does not send real email. After requesting a reset, the
reset link is printed in the terminal running the emulators ("To reset the
password for …, follow this link"). Pending codes are also listed at
`http://127.0.0.1:9099/emulator/v1/projects/<project-id>/oobCodes`. Copy the
link and paste it into Tonyo to continue the flow. Change password works against the emulator unchanged, since
it only needs the current password.

## Query helpers

`CloudRepository` exposes helpers for:

- Signals in a half-open day/range window
- Optional `SignalType` filtering
- Latest check-in
- Reaction-time baseline windows
- Hourly forecast range reads and day-scoped replacement
- Daily recommendation and risk-alert reads/replacement
- Risk-alert dismissal and guidance cleanup
- Version 0.21 owner-scoped date ranges for private daily/weekly Insights
- Full user export and recursive user-tree deletion

The `signals(type, timestamp)` compound index is declared in
`firestore.indexes.json`.

Version 0.21 does not add a collection or broaden Security Rules. Insights
queries up to 20 days of the authenticated user's existing `signals` and
`checkIns`; the app displays the latest seven days, compares the prior seven,
and retains six earlier days only as score-model context. Aggregates and
association summaries are calculated on the client and are not shared across
users or persisted as cohort analytics.

## Synthetic Cohort Lab

Tonyo can load a bundled synthetic student CSV for score debugging without
creating Firebase Auth accounts.

### Local visualizations

1. Open the app and complete onboarding / sign in as usual (optional for charts).
2. Profile → **Cohort Lab** → **Load CSV**.
3. Overview / Relations / People tabs render in-memory scores from
   `FatigueEngine`. Firebase config is not required for this path.

### Optional Firestore publish

Requires a signed-in Firebase account and valid compiled values in
`lib/src/firebase_secrets.dart`.

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
