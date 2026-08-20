# Tonyo

#curriculum https://quest.codingmind.com/view/B209904E4B074FB19F3936BB92

Flutter app for fatigue, energy, and cognitive estimates. Run commands below
from this `app/` folder.

Cloud Auth and Firestore stay off unless you pass
`--dart-define-from-file=config/firebase_options.json`. Copy
`config/firebase_options.example.json` to `config/firebase_options.json` and
fill project values first. See [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md).

`FIREBASE_APP_ID` is the web app. Android uses `FIREBASE_ANDROID_APP_ID`.
iOS uses `FIREBASE_IOS_APP_ID` plus `FIREBASE_IOS_BUNDLE_ID`. All of those keys
live in the same define file.

## Run on Android (Windows)

Start the Pixel / Android emulator, then:

```sh
flutter run -d emulator --dart-define-from-file=config/firebase_options.json
```

Hot reload is not enough after changing `firebase_options.json`. Quit the
session and run the command again.

## Run on iOS

Start the iOS Simulator first. Do not pass `-d` or a device id. Flutter attaches
to the running simulator:

```sh
flutter run --dart-define-from-file=config/firebase_options.json
```

## Run on Flutter web (Edge / Chrome)

Web storage is per origin (`http://localhost:<port>`). A random port looks like
a wiped cache and sends you through onboarding again. Keep port **7357**:

```sh
flutter run -d edge --web-port=7357 --dart-define-from-file=config/firebase_options.json
```

Local-only (no Firebase):

```sh
flutter run -d edge --web-port=7357
```

`app/web_dev_config.yaml` also pins port 7357. VS Code launch configs under
`../.vscode/launch.json` do the same.

## Tests

```sh
flutter test
```

Roadmap and version notes: [docs/PLAN.md](docs/PLAN.md).

# DESCRIPTION
Tonyo is an AI-powered fatigue prediction app that continuously fuses health, sleep, behavior, and exercise data to forecast each user's energy and cognitive state, then delivers personalized recovery and performance recommendations. The app ingests heart-rate variability, resting heart rate, sleep architecture, hydration, screen time, study sessions, training load, and reaction-time tests, and runs a multimodal ML model that produces an Energy Score, a Cognitive Score, and an Energy Forecast curve showing peak and trough windows hour by hour. A reaction-time daily benchmark and stress-and-mood check feed into the model, enabling early-warning alerts for overreaching, sleep debt, or burnout risk. An AI Coach generates daily plans — when to nap, when to study deep work, when to train hard, when to taper — and grounds each suggestion in the user's recent data trends. Insights dashboards explain how sleep, training, and study choices each shifted yesterday's energy and cognitive output. By unifying biology, behavior, and AI into a single fatigue lens, Tonyo helps adolescent students and athletes train smarter, sleep better, and avoid burnout.
