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
using reaction time, recent sleep, study load, mood, and stress. Signed-in
scores compare with the previous daily Cognitive snapshot when one exists.

Version 0.13 promotes Today into a snapshot-backed dashboard. It loads the
saved daily Energy and Cognitive scores when available, calculates them live
when missing, labels the day Fresh, Moderate, or Fatigued, and summarizes six
day-scoped signals from the private user collection.

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

# DESCRIPTION
Tonyo is an AI-powered fatigue prediction app that continuously fuses health, sleep, behavior, and exercise data to forecast each user's energy and cognitive state, then delivers personalized recovery and performance recommendations. The app ingests heart-rate variability, resting heart rate, sleep architecture, hydration, screen time, study sessions, training load, and reaction-time tests, and runs a multimodal ML model that produces an Energy Score, a Cognitive Score, and an Energy Forecast curve showing peak and trough windows hour by hour. A reaction-time daily benchmark and stress-and-mood check feed into the model, enabling early-warning alerts for overreaching, sleep debt, or burnout risk. An AI Coach generates daily plans — when to nap, when to study deep work, when to train hard, when to taper — and grounds each suggestion in the user's recent data trends. Insights dashboards explain how sleep, training, and study choices each shifted yesterday's energy and cognitive output. By unifying biology, behavior, and AI into a single fatigue lens, Tonyo helps adolescent students and athletes train smarter, sleep better, and avoid burnout.
