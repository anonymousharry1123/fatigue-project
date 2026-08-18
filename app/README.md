# app
#curriculum https://quest.codingmind.com/view/B209904E4B074FB19F3936BB92
A new Flutter project.

## Firebase

Version 0.10-a adds Firebase Authentication, user-scoped Cloud Firestore
persistence, offline migration/cache behavior, export, and permanent deletion.
See [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md) for console setup and the
environment-safe run command.

Version 0.11 adds a Firebase-backed, explainable daily Energy Score. The
0–100 wellness estimate uses sleep, exercise, hydration, workload, screen time,
mood, and stress, and stores one private daily snapshot per authenticated user.

Version 0.12 extends that same snapshot with an explainable Cognitive Score
using reaction time, recent sleep, study load, screen time, mood, and stress.
Signed-in scores compare with the previous daily Cognitive snapshot when one
exists.

Version 0.13 promotes Today into a snapshot-backed dashboard. It loads the
saved daily Energy and Cognitive scores when available, calculates them live
when missing, labels the day Fresh, Moderate, or Fatigued, and summarizes six
day-scoped signals from the private user collection.

### Flutter web persistence (Edge / Chrome)

SharedPreferences on web is stored per origin (`http://localhost:<port>`). A
plain `flutter run -d edge` often picks a **new port** each launch, which looks
like a wiped cache and sends you through onboarding again. Use a fixed port:

```sh
flutter run -d edge --web-port=7357
```

With Firebase:

```sh
flutter run -d edge --dart-define-from-file=config/firebase_options.json
```

VS Code launch configs under `../.vscode/launch.json` already set `--web-port=7357`.
Version 0.14 ranks supporting and reducing score drivers, explains each
contribution in plain language, and calculates confidence from both input
coverage and evidence freshness. Driver timestamps, sources, and freshness are
stored with the private daily snapshot and remain backward-compatible.

Version 0.15 generates hourly Today and Tomorrow energy forecasts from recent
sleep timing, circadian rhythm, workload, hydration, recovery, and check-ins.
Every point carries uncertainty and is stored under the authenticated user's
private `forecastPoints` collection, with a deterministic offline fallback.

Version 0.16 turns Forecast into a persisted seven-day view. Today and
Tomorrow show hourly curves with uncertainty bands, while Week summarizes each
day's average, range, peak time, and confidence. Empty, stale, low-confidence,
loading, and offline states are handled explicitly.

Version 0.17 derives peak-focus, predicted-crash, and recovery windows directly
from the saved hourly forecast. Forecast documents retain the exact private
signal and check-in IDs used by the model, and each window resolves those links
into plain-language evidence without exposing unrelated records.

Version 0.18 turns those windows into a grounded daily plan for study,
hydration, a short nap, recovery, and exercise. Every action has a stable daily
ID, a forecast-window time, and links to the recent private signals or check-ins
that support it; authenticated plans are persisted in `recommendations`.

Version 0.19 adds dismissible wellness flags for multi-day short sleep,
possible training overreaching alongside lower estimated energy, and recurring
low-energy/high-stress check-ins. The detector uses only the authenticated
user's last seven days, stores evidence-linked rows in `riskAlerts`, and avoids
diagnostic claims.

Version 0.20 adds explicit opt-in forecast alerts for upcoming lower-energy and
recovery windows. Tonyo schedules only fresh, higher-confidence future windows,
uses stable daily IDs to replace duplicates, excludes dismissed `riskAlerts`
from notification context, and keeps all notification copy non-diagnostic.
Master and per-alert preferences sync under the private `users/{uid}.prefs`
map; scheduled delivery is available on Android, iOS, macOS, and Windows.

Version 0.21 promotes Insights into a calculated private dashboard. It queries
only the signed-in user's date-range signals and check-ins, compares the latest
seven days with the prior seven, charts daily Energy, sleep, training, and study
patterns, and summarizes model associations only when enough varied matched
days exist. Missing entries remain missing, and all association copy explicitly
avoids causal or medical claims.

Version 0.22 adds the read-only Apple Health permission flow on iOS. Before the
system prompt, Tonyo explains its sleep, heart, workout, and hydration requests;
permission choices can be reviewed in Settings or disconnected inside Tonyo.
Apple does not disclose individual read-category decisions to apps, so the UI
labels the completed request honestly and keeps manual sleep and activity entry
available for approval, denial, revocation, errors, and unsupported platforms.

Version 0.23 imports the latest 30 days of readable HealthKit HRV and resting
heart-rate samples. Native values are normalized to milliseconds and bpm,
timestamps are converted for local-day grouping, and stable HealthKit UUIDs are
stored as private `signals` with `source: healthKit`. Repeated syncs skip the
same UUID or a same-type sample within two minutes and 0.1 unit; an existing
manual row always wins that match. Profile shows import, empty, duplicate, and
error states without deleting saved data.

Version 0.24 imports awake, core, deep, REM, and unspecified HealthKit sleep
samples as typed private signals. It resolves overlapping intervals across
Health sources before saving one nightly architecture, preventing a phone and
watch from double-counting the same time. Manual sleep remains the model input
unless the imported night is at least 80% as long and at least half of it has
detailed core/deep/REM staging; imported stage evidence remains read-only.

Version 0.25 imports the latest 30 days of HealthKit workouts and available
dietary-water samples into the same private `signals` collection. Daily training
load unions overlapping workout intervals before calculating exercise hours;
hydration totals sum distinct water samples. A manual exercise or hydration row
becomes that day’s correction for scores, forecasts, Insights, and Today, while
deleting it restores the untouched HealthKit fallback.

# DESCRIPTION
Tonyo is an AI-powered fatigue prediction app that continuously fuses health, sleep, behavior, and exercise data to forecast each user's energy and cognitive state, then delivers personalized recovery and performance recommendations. The app ingests heart-rate variability, resting heart rate, sleep architecture, hydration, screen time, study sessions, training load, and reaction-time tests, and runs a multimodal ML model that produces an Energy Score, a Cognitive Score, and an Energy Forecast curve showing peak and trough windows hour by hour. A reaction-time daily benchmark and stress-and-mood check feed into the model, enabling early-warning alerts for overreaching, sleep debt, or burnout risk. An AI Coach generates daily plans — when to nap, when to study deep work, when to train hard, when to taper — and grounds each suggestion in the user's recent data trends. Insights dashboards explain how sleep, training, and study choices each shifted yesterday's energy and cognitive output. By unifying biology, behavior, and AI into a single fatigue lens, Tonyo helps adolescent students and athletes train smarter, sleep better, and avoid burnout.
