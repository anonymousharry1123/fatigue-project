import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/firestore_value_codec.dart';
import 'package:app/src/models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native writes preserve journal timestamp precision and explicit clears',
    () {
      final at = DateTime.utc(2026, 10, 4, 17, 30, 1, 123, 456);
      final before = <String, dynamic>{
        'timestamp': at.toIso8601String(),
        'recordedAt': at.toIso8601String(),
        'energy': 5,
        'focus': 6,
      };
      final after = <String, dynamic>{
        ...before,
        'energy': null,
        'recordedAt': at.add(const Duration(seconds: 1)).toIso8601String(),
      };
      final payload = syncMergedData(before, after);
      final encoded = encodeFirestoreDocument(payload);
      expect(encoded['timestamp'], Timestamp.fromDate(at));
      expect((encoded['timestamp'] as Timestamp).nanoseconds, 123456000);
      expect(payload['timestamp'], isA<DateTime>());
      final remote = normalizeFirestoreDocument(encoded);
      expect(sameSyncValue(remote, after), isTrue);
      expect(
        () => checkSyncValue('check-in', remote, before, after),
        returnsNormally,
      );
      expect(remote['energy'], isNull);
      expect(remote['focus'], 6);
      // A genuinely different remote answer must still trigger a conflict.
      expect(
        () =>
            checkSyncValue('check-in', {...remote, 'focus': 9}, before, after),
        throwsA(isA<InputSyncConflict>()),
      );
    },
  );

  test(
    'write encoding preserves nested precision, SDK values and source data',
    () {
      final at = DateTime.utc(2026, 10, 4, 17, 30, 1, 123, 456);
      final timestamp = Timestamp.fromDate(at);
      final sentinel = FieldValue.serverTimestamp();
      final source = <String, dynamic>{
        'healthSync': {'lastAttemptAt': at},
        'nested': [
          {'at': at},
          [timestamp, 0, null, 'unchanged'],
        ],
        'updatedAt': sentinel,
      };
      final encoded = encodeFirestoreDocument(source);
      expect((encoded['healthSync'] as Map)['lastAttemptAt'], timestamp);
      expect((encoded['nested'] as List).first['at'], timestamp);
      expect((encoded['nested'] as List).last, [
        timestamp,
        0,
        null,
        'unchanged',
      ]);
      expect(encoded['updatedAt'], same(sentinel));
      expect((source['healthSync'] as Map)['lastAttemptAt'], same(at));
      expect(
        sameSyncValue(
          normalizeFirestoreDocument(encoded)..remove('updatedAt'),
          normalizeFirestoreDocument(source)..remove('updatedAt'),
        ),
        isTrue,
      );
    },
  );

  test('legacy outcome and source retain the same microsecond instant', () {
    final at = DateTime.utc(2026, 10, 4, 17, 30, 1, 123, 456);
    final signal = SignalReading(
      id: 'reaction-source',
      type: SignalType.reactionTime,
      value: 300,
      timestamp: at,
      recordedAt: at,
    );
    final outcome = OutcomeRecord(
      id: 'reaction-outcome',
      type: OutcomeType.cognitiveReaction,
      value: 300,
      observedAt: at,
      recordedAt: at,
      source: OutcomeSource.reactionSignal,
      sourceId: signal.id,
    );
    final restoredSignal = signalFromCloud(
      signal.id,
      normalizeFirestoreDocument(
        encodeFirestoreDocument(signalToCloud(signal)),
      ),
    );
    final restoredOutcome = outcomeFromCloud(
      outcome.id,
      normalizeFirestoreDocument(
        encodeFirestoreDocument(outcomeToCloud(outcome)),
      ),
    );
    expect(restoredSignal.timestamp.toUtc(), at);
    expect(restoredOutcome.observedAt.toUtc(), at);
  });

  test(
    'native Firestore timestamps decode nested score evidence without mutation',
    () {
      final day = DateTime(2026, 10, 4);
      final evidenceAt = DateTime.utc(2026, 10, 4, 17, 30);
      final driver = ScoreDriver(
        'Synthetic observation',
        0,
        'Explicit zero',
        evidenceAt: evidenceAt,
        source: SignalSource.manual,
        evidenceSources: const [SignalSource.manual],
      );
      final reference = ScoreSnapshot(
        energy: 0,
        cognitive: 0,
        confidence: .4,
        drivers: [driver],
        cognitiveDrivers: [driver],
        inputCount: 1,
        cognitiveInputCount: 1,
        day: day,
        calculatedAt: evidenceAt,
        energyModelVersion: FatigueEngine.energyModelVersion,
        cognitiveModelVersion: FatigueEngine.cognitiveModelVersion,
      );
      final payload =
          _nativeValues(scoreSnapshotToCloud(snapshot: reference, day: day))
              as Map<String, dynamic>;
      final timestamp = Timestamp.fromDate(evidenceAt);
      payload['metadata'] = [
        {
          'zero': 0,
          'obsolete': null,
          'evidence': {'at': timestamp},
        },
        [timestamp, 'unchanged', 0, null],
      ];
      final normalized = normalizeFirestoreDocument(payload);
      final restored = scoreSnapshotFromCloud(normalized);
      expect(restored.energy, 0);
      expect(restored.cognitive, 0);
      expect(restored.day, day);
      expect(restored.calculatedAt, timestamp.toDate());
      expect(restored.drivers.single.evidenceAt, timestamp.toDate());
      expect(restored.cognitiveDrivers.single.evidenceAt, timestamp.toDate());
      expect(restored.drivers.single.evidenceSources, [SignalSource.manual]);
      expect(restored.personalizedModelVersion, isNull);
      expect(restored.deterministicEnergy, isNull);
      final metadata = normalized['metadata'] as List;
      expect(metadata.first, {
        'zero': 0,
        'obsolete': null,
        'evidence': {'at': timestamp.toDate()},
      });

      expect(metadata.last, [timestamp.toDate(), 'unchanged', 0, null]);
      expect(
        (payload['drivers'] as List).first['evidenceAt'],
        isA<Timestamp>(),
      );
      expect((payload['metadata'] as List).last.first, same(timestamp));
    },
  );
}

// The real SDK returns Timestamp objects, including values nested in arrays.
Object? _nativeValues(Object? value) => switch (value) {
  DateTime instant => Timestamp.fromDate(instant),
  Map map => map.map(
    (key, child) => MapEntry(key as String, _nativeValues(child)),
  ),
  Iterable values => values.map(_nativeValues).toList(),
  _ => value,
};
