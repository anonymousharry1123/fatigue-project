import 'package:app/src/heart_sync_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
