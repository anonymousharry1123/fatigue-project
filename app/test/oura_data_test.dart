import 'package:app/src/cloud_schema.dart';
import 'package:app/src/heart_derivation_logic.dart';
import 'package:app/src/heart_metrics_logic.dart';
import 'package:app/src/models.dart';
import 'package:app/src/oura_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final syncedAt = DateTime.utc(2026, 10, 25, 18);
  Map<String, dynamic> sleep({
    String id = 'sleep-one',
    String day = '2026-10-24',
  }) => {
    'id': id,
    'day': day,
    'type': 'long_sleep',
    'bedtime_start': '2026-10-23T23:00:00-07:00',
    'bedtime_end': '2026-10-24T07:00:00-07:00',
    'average_hrv': 48,
    'lowest_heart_rate': 40,
    'heart_rate': {
      'timestamp': '2026-10-23T23:00:00-07:00',
      'interval': 300,
      'items': [null, 52, 48, 50],
    },
  };
  List<SignalReading> normalize(List<Map<String, dynamic>> records) =>
      OuraData.normalizeSleep(records, syncedAt: syncedAt);
  List<SignalReading> reconcile(
    List<SignalReading> existing,
    List<Map<String, dynamic>> records, {
    DateTime? at,
  }) => OuraData.reconcile(
    existing,
    records,
    syncedAt: at ?? syncedAt,
    startDay: '2026-10-24',
    endDay: '2026-10-24',
  );

  test('nightly RMSSD and app-aligned minimum retain original provenance', () {
    final rows = normalize([sleep()]);
    expect(rows, hasLength(2));
    final hrv = rows.singleWhere((r) => r.type == SignalType.hrv);
    final resting = rows.singleWhere(
      (r) => r.type == SignalType.restingHeartRate,
    );
    expect(hrv.value, 48);
    expect(hrv.measurementMethod, OuraData.hrvMethod);
    expect(resting.value, 48);
    expect(resting.measurementMethod, OuraData.restingMethod);
    expect(rows.map((r) => r.source), everyElement(SignalSource.oura));
    expect(hrv.sourceRecordId, 'sleep-one');
    expect(hrv.sourceDay, '2026-10-24');
    expect(hrv.timestamp.toUtc(), DateTime.utc(2026, 10, 24, 14));
    expect(hrv.syncedAt, syncedAt);
  });

  test(
    'only five-minute samples inside the sleep interval enter app minimum',
    () {
      final record = sleep();
      record['heart_rate'] = {
        'timestamp': '2026-10-23T22:55:00-07:00',
        'interval': 300,
        'items': [20, null, 53, 51],
      };
      expect(normalize([record]).last.value, 51);
      record['heart_rate'] = {
        'timestamp': '2026-10-24T07:00:00-07:00',
        'interval': 300,
        'items': [20],
      };
      final resting = normalize([record]).last;
      expect(resting.value, 40);
      expect(resting.measurementMethod, OuraData.apiRestingMethod);
    },
  );

  test(
    'API fallback remains distinct when five-minute series is unavailable',
    () {
      for (final series in [
        null,
        {
          'interval': 30,
          'items': [30],
        },
        {
          'timestamp': '2026-10-23T23:00:00-07:00',
          'interval': 300,
          'items': [null, null],
        },
      ]) {
        final record = sleep()..['heart_rate'] = series;
        final resting = normalize([record]).last;
        expect(resting.value, 40);
        expect(resting.measurementMethod, OuraData.apiRestingMethod);
      }
    },
  );

  test(
    'longest main sleep selected before metric completeness; naps ignored',
    () {
      final short = sleep(id: 'short')
        ..['bedtime_end'] = '2026-10-24T03:00:00-07:00'
        ..['average_hrv'] = 99;
      final longest = sleep()..['average_hrv'] = null;
      final nap = sleep(id: 'nap')..['type'] = 'sleep';
      for (final records in [
        [short, longest, nap],
        [nap, longest, short],
      ]) {
        final rows = normalize(records);
        expect(rows, hasLength(1));
        expect(rows.single.type, SignalType.restingHeartRate);
        expect(rows.single.sourceRecordId, 'sleep-one');
      }
    },
  );

  test(
    'exact duplicate sessions deduplicate; conflicting duplicates fail closed',
    () {
      expect(normalize([sleep(), sleep()]), hasLength(2));
      expect(
        () => normalize([sleep(), sleep()..['average_hrv'] = 55]),
        throwsFormatException,
      );
    },
  );

  test('invalid main sleep data cannot wipe a previous sync', () {
    final original = normalize([sleep()]);
    for (final edit in <String, Object?>{
      'id': '../bad',
      'day': '2026-02-30',
      'bedtime_start': '2026-10-24T08:00:00-07:00',
      'bedtime_end': '2026-10-26T07:00:00-07:00',
      'average_hrv': -1,
      'lowest_heart_rate': '40',
      'type': 'unknown',
    }.entries) {
      final record = sleep()..[edit.key] = edit.value;
      expect(() => reconcile(original, [record]), throwsFormatException);
      expect(original, hasLength(2));
    }
  });

  test(
    'nighttime deletion and null corrections remove only bounded Oura rows',
    () {
      final otherDate = normalize([sleep(day: '2026-10-23')]);
      final apple = SignalReading(
        id: 'healthkit-one',
        type: SignalType.hrv,
        value: 60,
        timestamp: DateTime.utc(2026, 10, 24, 14),
        source: SignalSource.healthKit,
      );
      final original = [
        ...normalize([sleep()]),
        ...otherDate,
        apple,
      ];
      final missing = reconcile(original, [sleep()..['average_hrv'] = null]);
      expect(missing.where((r) => r.id == 'oura-hrv-2026-10-24'), isEmpty);
      expect(missing, contains(apple));
      expect(missing, containsAll(otherDate));
      final deleted = reconcile(original, [sleep()..['type'] = 'deleted']);
      expect(deleted, unorderedEquals([...otherDate, apple]));
      expect(reconcile(original, []), unorderedEquals([...otherDate, apple]));
    },
  );

  test(
    'repeat sync preserves import time, revised primary replaces stable IDs',
    () {
      final original = normalize([sleep()]);
      final later = syncedAt.add(const Duration(hours: 1));
      final unchanged = reconcile(original, [sleep()], at: later);
      expect(
        unchanged.map((r) => r.toJson()),
        unorderedEquals(original.map((r) => r.toJson())),
      );
      final updated = reconcile(original, [
        sleep(id: 'new-session')..['average_hrv'] = 55,
      ], at: later);
      expect(updated, hasLength(2));
      expect(
        updated.map((r) => r.id),
        unorderedEquals(original.map((r) => r.id)),
      );
      expect(updated.map((r) => r.sourceRecordId), everyElement('new-session'));
      expect(updated.map((r) => r.syncedAt), everyElement(later));
    },
  );

  test(
    'local and cloud round trips retain semantics; legacy metadata stays unknown',
    () {
      for (final row in normalize([sleep()])) {
        expect(SignalReading.fromJson(row.toJson()).toJson(), row.toJson());
        expect(
          signalFromCloud(row.id, signalToCloud(row)).toJson(),
          row.toJson(),
        );
        expect(row.copyWith(value: row.value + 1).sourceDay, row.sourceDay);
      }
      final legacy = SignalReading.fromJson({
        'id': 'old',
        'type': 'hrv',
        'value': 40,
        'timestamp': '2026-10-24T14:00:00Z',
        'source': 'healthKit',
      });
      expect(legacy.sourceName, isNull);
      expect(legacy.measurementMethod, isNull);
      expect(legacy.toJson().containsKey('measurementMethod'), isFalse);
    },
  );

  test(
    'Oura and Apple metrics stay separate, original Oura dates are retained',
    () {
      final oura = normalize([sleep(day: '2026-10-23')]);
      final apple = SignalReading(
        id: 'apple',
        type: SignalType.hrv,
        value: 90,
        timestamp: DateTime(2026, 10, 23, 9),
        source: SignalSource.healthKit,
        measurementMethod: 'sdnn',
      );
      final days = HeartMetricsLogic.build(
        readings: [...oura, apple],
        now: syncedAt,
      );
      expect(days.single.date, DateTime(2026, 10, 23));
      expect(days.single.hrv!.mean, 90);
      expect(days.single.ouraHrv!.mean, 48);
      expect(days.single.restingHeartRate, isNull);
      expect(days.single.ouraRestingHeartRate!.mean, 48);
    },
  );

  test(
    'identified HealthKit mirror suppressed only when same direct metric exists',
    () {
      final direct = normalize([sleep()]);
      final mirror = SignalReading(
        id: 'mirror',
        type: SignalType.hrv,
        value: 48,
        timestamp: DateTime(2026, 10, 24, 9),
        source: SignalSource.healthKit,
        sourceName: 'Oura',
        sourceBundleId: 'com.ouraring.oura',
      );
      final apple = mirror.copyWith(
        id: 'apple',
        value: 80,
        sourceName: 'Apple Watch',
        sourceBundleId: 'com.apple.health',
      );
      final readings = [...direct, mirror, apple];
      final withDirect = HeartMetricsLogic.build(
        readings: readings,
        now: syncedAt,
      );
      expect(withDirect.single.hrv!.mean, 80);
      expect(withDirect.single.hrv!.sampleCount, 1);
      expect(withDirect.single.ouraHrv!.mean, 48);
      expect(readings, hasLength(4));
      final withoutDirect = HeartMetricsLogic.build(
        readings: [mirror],
        now: syncedAt,
      );
      expect(withoutDirect.single.hrv!.mean, 48);
    },
  );

  test('Oura resting minimum does not suppress an Apple resting estimate', () {
    final oura = normalize([sleep()]);
    final pulses = [
      for (var hour = 1; hour <= 3; hour++)
        SignalReading(
          id: 'apple-$hour',
          type: SignalType.heartRate,
          value: 60,
          timestamp: DateTime(2026, 10, 24, hour),
          source: SignalSource.healthKit,
        ),
    ];
    final result = HeartDerivationLogic.reconcile(
      readings: [...pulses, ...oura],
      now: syncedAt,
    );
    expect(result.estimatedRestingHeartRates, hasLength(1));
    expect(result.estimatedRestingHeartRates.single.value, 60);
    expect(result.readings, containsAll(oura));
  });
}
