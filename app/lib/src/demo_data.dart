import 'models.dart';

List<SignalReading> buildDemoSignals(DateTime now) {
  SignalReading reading(
    SignalType type,
    double value,
    int daysAgo, {
    SignalSource source = SignalSource.manual,
  }) => SignalReading(
    id: 'demo-${type.name}-$daysAgo',
    type: type,
    value: value,
    timestamp: DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: daysAgo)).add(const Duration(hours: 8)),
    source: source,
  );
  return [
    reading(SignalType.sleep, 6.2, 0, source: SignalSource.healthKit),
    reading(SignalType.bedtime, 23.7, 0),
    reading(SignalType.hydration, 1.8, 0),
    reading(SignalType.study, 3.5, 0),
    reading(SignalType.exercise, 1.35, 0, source: SignalSource.healthKit),
    reading(SignalType.screenTime, 4.1, 0),
    reading(SignalType.reactionTime, 286, 0),
    reading(SignalType.hrv, 54, 0, source: SignalSource.healthKit),
    reading(SignalType.restingHeartRate, 60, 0, source: SignalSource.healthKit),
    reading(SignalType.sleepDeep, 1.1, 0, source: SignalSource.healthKit),
    reading(SignalType.sleepRem, 1.4, 0, source: SignalSource.healthKit),
    reading(SignalType.sleep, 7.4, 1, source: SignalSource.healthKit),
    reading(SignalType.exercise, .65, 1, source: SignalSource.healthKit),
    reading(SignalType.study, 2.8, 1),
    reading(SignalType.sleep, 7.8, 2, source: SignalSource.healthKit),
    reading(SignalType.sleep, 6.9, 3, source: SignalSource.healthKit),
    reading(SignalType.sleep, 8.1, 4, source: SignalSource.healthKit),
    reading(SignalType.sleep, 7.1, 5, source: SignalSource.healthKit),
    reading(SignalType.sleep, 7.6, 6, source: SignalSource.healthKit),
  ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
}

List<DailyCheckIn> buildDemoCheckIns(DateTime now) => [
  DailyCheckIn(
    id: 'demo-checkin-0',
    timestamp: now.subtract(const Duration(hours: 2)),
    energy: 4,
    mood: 4,
    stress: 2,
  ),
  DailyCheckIn(
    id: 'demo-checkin-1',
    timestamp: now.subtract(const Duration(days: 1)),
    energy: 3,
    mood: 3,
    stress: 3,
  ),
  DailyCheckIn(
    id: 'demo-checkin-2',
    timestamp: now.subtract(const Duration(days: 2)),
    energy: 4,
    mood: 4,
    stress: 2,
  ),
];
