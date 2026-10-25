import 'package:app/src/heart_derivation_logic.dart';
import 'package:app/src/heart_sync_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HealthKit normalization preserves measurement and origin metadata', () {
    final time = DateTime.utc(2026, 10, 24, 8);
    final imported = SignalReading(
      id: ' healthkit-source ',
      type: SignalType.hrv,
      value: 45,
      timestamp: time,
      source: SignalSource.healthKit,
      sourceName: 'Apple Watch',
      sourceBundleId: 'com.apple.health',
      sourceRecordId: 'native-sample',
      sourceDay: '2026-10-24',
      measurementMethod: 'sdnn',
    );
    final result = HeartSyncLogic.merge(
      existing: [],
      imported: [imported],
      syncedAt: time,
    );
    final normalized = result.readings.single;
    expect(normalized.id, 'healthkit-source');
    expect(normalized.sourceName, imported.sourceName);
    expect(normalized.sourceBundleId, imported.sourceBundleId);
    expect(normalized.sourceRecordId, imported.sourceRecordId);
    expect(normalized.sourceDay, imported.sourceDay);
    expect(normalized.measurementMethod, 'sdnn');
    expect(normalized.source, SignalSource.healthKit);
  });

  test(
    'direct Oura never absorbs a nearby equal Apple HRV or resting value',
    () {
      final time = DateTime.utc(2026, 10, 24, 8);
      for (final type in [SignalType.hrv, SignalType.restingHeartRate]) {
        final oura = SignalReading(
          id: 'oura-${type.name}-2026-10-24',
          type: type,
          value: 50,
          timestamp: time,
          source: SignalSource.oura,
          sourceName: 'Oura',
          sourceDay: '2026-10-24',
        );
        final apple = SignalReading(
          id: 'healthkit-${type.name}',
          type: type,
          value: 50,
          timestamp: time.add(const Duration(seconds: 10)),
          source: SignalSource.healthKit,
        );
        final result = HeartSyncLogic.merge(
          existing: [oura],
          imported: [apple],
          syncedAt: time,
        );
        expect(result.importedCount, 1);
        expect(result.duplicateCount, 0);
        expect(result.readings, hasLength(2));
        expect(result.readings, contains(oura));
        final repeat = HeartSyncLogic.merge(
          existing: result.readings,
          imported: [apple],
          syncedAt: time,
        );
        expect(repeat.importedCount, 0);
        expect(repeat.duplicateCount, 1);
        expect(repeat.readings, hasLength(2));
      }
    },
  );

  test('known distinct HealthKit producers keep equal nearby measurements', () {
    final time = DateTime.utc(2026, 10, 24, 8);
    for (final type in [SignalType.hrv, SignalType.restingHeartRate]) {
      SignalReading record(String id, String bundle) => SignalReading(
        id: id,
        type: type,
        value: 50,
        timestamp: time,
        source: SignalSource.healthKit,
        sourceBundleId: bundle,
      );
      final first = record('oura-mirror', 'com.ouraring.oura');
      final second = record('apple-watch', 'com.apple.health');
      final third = record('apple-nearby', 'com.apple.health');
      final result = HeartSyncLogic.merge(
        existing: [first],
        imported: [second, third],
        syncedAt: time,
      );
      expect(result.importedCount, 1);
      expect(result.duplicateCount, 1);
      expect(
        result.readings.map((r) => r.id),
        unorderedEquals(['oura-mirror', 'apple-watch']),
      );
    }
  });

  test('native resting HR is never deduplicated against a nearby estimate', () {
    final now = DateTime(2026, 10, 24, 9);
    final existing = HeartDerivationLogic.reconcile(
      readings: [
        for (var hour = 1; hour <= 3; hour++)
          SignalReading(
            id: 'healthkit-heart-$hour',
            type: SignalType.heartRate,
            value: 60,
            timestamp: DateTime(2026, 10, 24, hour),
            source: SignalSource.healthKit,
          ),
      ],
      now: now,
    );
    final estimate = existing.estimatedRestingHeartRates.single;
    final merged = HeartSyncLogic.merge(
      existing: existing.readings,
      imported: [
        SignalReading(
          id: 'healthkit-native-resting',
          type: SignalType.restingHeartRate,
          value: estimate.value,
          timestamp: estimate.timestamp.add(const Duration(seconds: 30)),
          source: SignalSource.healthKit,
        ),
      ],
      syncedAt: now,
    );
    expect(merged.importedCount, 1);
    expect(merged.duplicateCount, 0);
    final reconciled = HeartDerivationLogic.reconcile(
      readings: merged.readings,
      now: now,
    );
    expect(reconciled.estimatedRestingHeartRates, isEmpty);
    expect(
      reconciled.readings
          .where((r) => r.type == SignalType.restingHeartRate)
          .single
          .id,
      'healthkit-native-resting',
    );
  });

  test(
    'imports regular heart rate without collapsing nearby equal samples',
    () {
      final observedAt = DateTime.utc(2026, 10, 18, 12);
      SignalReading heart(String id, int seconds, {double value = 72}) =>
          SignalReading(
            id: id,
            type: SignalType.heartRate,
            value: value,
            timestamp: observedAt.add(Duration(seconds: seconds)),
            source: SignalSource.healthKit,
          );
      final original = heart('healthkit-heartRate-first', 0);
      final second = heart('healthkit-heartRate-second', 10);
      final syncedAt = observedAt.add(const Duration(minutes: 1));
      final result = HeartSyncLogic.merge(
        existing: [original],
        imported: [
          original,
          second,
          heart(' healthkit-heartRate-second ', 10),
          heart('healthkit-heartRate-third', 20),
        ],
        syncedAt: syncedAt,
      );

      expect(result.importedCount, 2);
      expect(result.duplicateCount, 2);
      expect(result.rejectedCount, 0);
      expect(result.readings.map((item) => item.id), [
        'healthkit-heartRate-third',
        'healthkit-heartRate-second',
        'healthkit-heartRate-first',
      ]);
      expect(result.readings.first.syncedAt, syncedAt);
      expect(result.readings.first.type, SignalType.heartRate);
      expect(result.readings.first.source, SignalSource.healthKit);
      expect(
        result.readings.first.timestamp.toUtc(),
        observedAt.add(const Duration(seconds: 20)),
      );
    },
  );

  test(
    'regular heart rate validates bpm and stays separate from resting HR',
    () {
      final observedAt = DateTime.utc(2026, 10, 18, 12);
      SignalReading heart(String id, double value) => SignalReading(
        id: id,
        type: SignalType.heartRate,
        value: value,
        timestamp: observedAt,
      );
      final result = HeartSyncLogic.merge(
        existing: [
          SignalReading(
            id: 'healthkit-resting',
            type: SignalType.restingHeartRate,
            value: 72,
            timestamp: observedAt,
            source: SignalSource.healthKit,
          ),
        ],
        imported: [
          heart('normal', 72),
          heart('low-bound', 20),
          heart('high-bound', 300),
          heart('too-low', 19.9),
          heart('too-high', 300.1),
          heart('invalid', double.nan),
        ],
        syncedAt: observedAt,
      );
      expect(result.importedCount, 3);
      expect(result.duplicateCount, 0);
      expect(result.rejectedCount, 3);
      expect(
        result.readings.where((item) => item.type == SignalType.heartRate),
        hasLength(3),
      );
      expect(
        result.readings.where(
          (item) => item.type == SignalType.restingHeartRate,
        ),
        hasLength(1),
      );
    },
  );

  test('dense regular heart history reimport is idempotent by sample ID', () {
    final observedAt = DateTime.utc(2026, 10, 18, 12);
    final samples = List.generate(
      10000,
      (index) => SignalReading(
        id: 'healthkit-heartRate-$index',
        type: SignalType.heartRate,
        value: 72,
        timestamp: observedAt.add(Duration(seconds: index)),
        source: SignalSource.healthKit,
      ),
    );
    final first = HeartSyncLogic.merge(existing: const [], imported: samples);
    final second = HeartSyncLogic.merge(
      existing: first.readings,
      imported: samples,
    );
    expect(first.importedCount, samples.length);
    expect(first.duplicateCount, 0);
    expect(second.importedCount, 0);
    expect(second.duplicateCount, samples.length);
    expect(second.readings, hasLength(samples.length));
  });

  test(
    'Version 0.23 normalizes heart samples and preserves manual duplicates',
    () {
      final hrvTimestamp = DateTime.utc(2026, 8, 17, 10);
      final manual = SignalReading(
        id: 'manual-hrv',
        type: SignalType.hrv,
        value: 50,
        timestamp: hrvTimestamp.toLocal(),
      );
      final priorHealth = SignalReading(
        id: 'healthkit-existing',
        type: SignalType.restingHeartRate,
        value: 60,
        timestamp: DateTime(2026, 8, 17, 9),
        source: SignalSource.healthKit,
      );

      final result = HeartSyncLogic.merge(
        existing: [manual, priorHealth],
        imported: [
          SignalReading(
            id: 'healthkit-near-manual',
            type: SignalType.hrv,
            value: 50.05,
            timestamp: hrvTimestamp.add(const Duration(minutes: 1)),
          ),
          SignalReading(
            id: 'healthkit-existing',
            type: SignalType.restingHeartRate,
            value: 60,
            timestamp: DateTime.utc(2026, 8, 17, 9),
          ),
          SignalReading(
            id: 'healthkit-new-rhr',
            type: SignalType.restingHeartRate,
            value: 62.4,
            timestamp: DateTime.utc(2026, 8, 17, 11),
            source: SignalSource.manual,
            quality: 1.4,
          ),
          SignalReading(
            id: 'healthkit-invalid',
            type: SignalType.hrv,
            value: -1,
            timestamp: DateTime.utc(2026, 8, 17, 12),
          ),
          SignalReading(
            id: 'healthkit-wrong-type',
            type: SignalType.sleep,
            value: 8,
            timestamp: DateTime.utc(2026, 8, 17, 8),
          ),
        ],
      );

      expect(result.importedCount, 1);
      expect(result.duplicateCount, 2);
      expect(result.rejectedCount, 2);
      expect(result.readings, hasLength(3));
      expect(result.readings, contains(manual));
      final imported = result.readings.singleWhere(
        (item) => item.id == 'healthkit-new-rhr',
      );
      expect(imported.id, 'healthkit-new-rhr');
      expect(imported.source, SignalSource.healthKit);
      expect(imported.quality, 1);
      expect(imported.timestamp.isUtc, isFalse);
    },
  );

  test(
    'Version 0.23 keeps distinct heart measurements and newest-first order',
    () {
      final first = SignalReading(
        id: 'healthkit-first',
        type: SignalType.hrv,
        value: 45,
        timestamp: DateTime(2026, 8, 17, 8),
        source: SignalSource.healthKit,
      );
      final second = SignalReading(
        id: 'healthkit-second',
        type: SignalType.hrv,
        value: 47,
        timestamp: DateTime(2026, 8, 17, 8, 1),
        source: SignalSource.healthKit,
      );

      final result = HeartSyncLogic.merge(
        existing: const [],
        imported: [first, second],
      );

      expect(result.importedCount, 2);
      expect(result.duplicateCount, 0);
      expect(result.readings.map((item) => item.id), [
        'healthkit-second',
        'healthkit-first',
      ]);
    },
  );
}
