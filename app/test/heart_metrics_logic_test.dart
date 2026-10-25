import 'package:app/src/daily_history_logic.dart';
import 'package:app/src/heart_derivation_logic.dart';
import 'package:app/src/heart_metrics_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 24);
  final now = DateTime(2026, 10, 25, 12);
  SignalReading reading(
    String id,
    double value, {
    SignalType type = SignalType.heartRate,
    DateTime? timestamp,
    SignalSource source = SignalSource.healthKit,
    double quality = 1,
    DateTime? syncedAt,
  }) => SignalReading(
    id: id,
    type: type,
    value: value,
    timestamp: timestamp ?? day.add(const Duration(hours: 9)),
    source: source,
    quality: quality,
    syncedAt: syncedAt,
  );

  test(
    'history replaces pulse rows with one local-day average without changing originals',
    () {
      final signals = [
        reading(
          'first',
          60,
          timestamp: day.add(const Duration(minutes: 10)).toUtc(),
        ),
        reading(
          'second',
          90,
          timestamp: day.add(const Duration(hours: 23)).toUtc(),
        ),
        reading(
          'previous',
          50,
          timestamp: day.subtract(const Duration(minutes: 1)).toUtc(),
        ),
        reading('hrv', 45, type: SignalType.hrv),
        reading('resting', 55, type: SignalType.restingHeartRate),
      ];
      final original = signals.map((r) => r.toJson()).toList();
      final history = DailyHistoryLogic.build(
        signals: signals,
        checkIns: [],
        activityLogs: [],
        sleepLogs: [],
        now: now,
      );
      expect(history.map((d) => d.date), [day, DateTime(2026, 10, 23)]);
      expect(history.first.heartRateAverage!.mean, 75);
      expect(history.first.heartRateAverage!.sampleCount, 2);
      expect(
        history.first.items.map((i) => i.signal!.type),
        unorderedEquals([SignalType.hrv, SignalType.restingHeartRate]),
      );
      expect(history.last.heartRateAverage!.mean, 50);
      expect(history.last.items, isEmpty);
      expect(history.first.completionCount, 0);
      expect(signals.map((r) => r.toJson()).toList(), original);
    },
  );

  test(
    'averages deduplicate observation IDs and exclude unavailable or invalid values',
    () {
      final days = HeartMetricsLogic.build(
        now: now,
        includeDerivations: false,
        readings: [
          reading('one', 60, syncedAt: day.add(const Duration(hours: 10))),
          reading(' ONE ', 80, syncedAt: day.add(const Duration(hours: 11))),
          reading('two', 100),
          reading('nan', double.nan),
          reading('out-of-range', 400),
          reading('zero-quality', 10, quality: 0),
          reading('future', 200, timestamp: now.add(const Duration(hours: 1))),
          reading(
            'future-import',
            200,
            syncedAt: now.add(const Duration(hours: 1)),
          ),
        ],
      );
      expect(days.single.heartRate!.sampleCount, 2);
      expect(days.single.heartRate!.mean, 90);
    },
  );

  test(
    'measured resting rate and native HRV stay separate from derived values',
    () {
      final days = HeartMetricsLogic.build(
        now: now,
        readings: [
          reading(
            'overnight-1',
            60,
            timestamp: day.add(const Duration(hours: 1)),
          ),
          reading(
            'overnight-2',
            58,
            timestamp: day.add(const Duration(hours: 2)),
          ),
          reading(
            'overnight-3',
            62,
            timestamp: day.add(const Duration(hours: 3)),
          ),
          reading('resting', 54, type: SignalType.restingHeartRate),
          reading(
            '${HeartDerivationLogic.restingIdPrefix}old',
            60,
            type: SignalType.restingHeartRate,
            source: SignalSource.model,
          ),
          reading('native-hrv-1', 40, type: SignalType.hrv),
          reading('native-hrv-2', 50, type: SignalType.hrv),
          reading(
            'model-hrv',
            900,
            type: SignalType.hrv,
            source: SignalSource.model,
          ),
        ],
      );
      expect(days.single.restingHeartRate!.mean, 54);
      expect(days.single.estimatedRestingHeartRate, isNull);
      expect(days.single.hrv!.mean, 45);
      expect(days.single.hrv!.sampleCount, 2);
    },
  );

  test(
    'ordinary heart samples may yield an explicit resting estimate, never HRV',
    () {
      final days = HeartMetricsLogic.build(
        now: now,
        readings: [
          for (var hour = 1; hour <= 3; hour++)
            reading(
              'overnight-$hour',
              60,
              timestamp: day.add(Duration(hours: hour)),
            ),
          for (var i = 0; i < 6; i++)
            reading(
              'daytime-$i',
              i.isEven ? 60 : 64,
              timestamp: day.add(Duration(hours: 9, minutes: 30 * i)),
            ),
        ],
      );
      expect(days.single.restingHeartRate, isNull);
      expect(days.single.estimatedRestingHeartRate!.mean, 60);
      expect(days.single.hrv, isNull);
      expect(days.single.variation!.rmsSuccessiveDifferenceBpm, 4);
    },
  );
}
