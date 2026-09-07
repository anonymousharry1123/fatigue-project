import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final observedAt = DateTime.utc(2026, 9, 1, 9);
  final recordedAt = DateTime.utc(2026, 9, 2, 10, 30);

  SignalReading signal({DateTime? recorded}) => SignalReading(
    id: 'real-manual-signal',
    type: SignalType.hydration,
    value: 2,
    timestamp: observedAt,
    quality: 0.8,
    note: 'After breakfast',
    groupId: 'morning-log',
    recordedAt: recorded,
  );

  DailyCheckIn checkIn({DateTime? recorded}) => DailyCheckIn(
    id: 'real-check-in',
    timestamp: observedAt,
    energy: 7,
    mood: 8,
    stress: 3,
    period: CheckInPeriod.morning,
    note: 'A normal morning',
    recordedAt: recorded,
  );

  test(
    'manual signal local round trip keeps availability separate from observation',
    () {
      final original = signal(recorded: recordedAt);
      final encoded = original.toJson();
      expect(encoded['recordedAt'], recordedAt.toIso8601String());
      final decoded = SignalReading.fromJson(encoded);
      expect(decoded.timestamp, observedAt);
      expect(decoded.recordedAt, recordedAt);
      expect(decoded.syncedAt, isNull);
      expect(decoded.toJson(), encoded);
    },
  );

  test('check-in local round trip retains actual save time and ratings', () {
    final original = checkIn(recorded: recordedAt);
    final encoded = original.toJson();
    expect(encoded['recordedAt'], recordedAt.toIso8601String());
    final decoded = DailyCheckIn.fromJson(encoded);
    expect(decoded.timestamp, observedAt);
    expect(decoded.recordedAt, recordedAt);
    expect(decoded.energy, 7);
    expect(decoded.mood, 8);
    expect(decoded.stress, 3);
    expect(decoded.toJson(), encoded);
  });

  test(
    'legacy local records never infer availability from observation time',
    () {
      final rawSignal = signal().toJson();
      final rawCheckIn = checkIn().toJson();
      expect(rawSignal, isNot(contains('recordedAt')));
      expect(rawCheckIn, isNot(contains('recordedAt')));
      expect(SignalReading.fromJson(rawSignal).recordedAt, isNull);
      expect(DailyCheckIn.fromJson(rawCheckIn).recordedAt, isNull);
      expect(
        SignalReading.fromJson({...rawSignal, 'recordedAt': null}).recordedAt,
        isNull,
      );
      expect(
        DailyCheckIn.fromJson({...rawCheckIn, 'recordedAt': null}).recordedAt,
        isNull,
      );
    },
  );

  test(
    'legacy check-in scale migration does not invent a recording timestamp',
    () {
      final legacy = checkIn().toJson()..remove('period');
      legacy['energy'] = 4;
      final migrated = DailyCheckIn.fromJson(legacy);
      expect(migrated.energy, 8);
      expect(migrated.recordedAt, isNull);
      expect(migrated.toJson(), isNot(contains('recordedAt')));
    },
  );

  test(
    'signal copyWith preserves every field and supports explicit edit availability',
    () {
      final original = signal(
        recorded: recordedAt,
      ).copyWith(syncedAt: observedAt);
      expect(original.copyWith().toJson(), original.toJson());
      final editedAt = recordedAt.add(const Duration(days: 1));
      final edited = original.copyWith(value: 3, recordedAt: editedAt);
      expect(edited.toJson(), {
        ...original.toJson(),
        'value': 3.0,
        'recordedAt': editedAt.toIso8601String(),
      });
      expect(original.recordedAt, recordedAt);
      expect(signal().copyWith(value: 3).recordedAt, isNull);
    },
  );

  test('signal Firestore serialization preserves DateTime availability', () {
    final original = signal(recorded: recordedAt);
    final data = signalToCloud(original);
    expect(data['recordedAt'], recordedAt);
    expect(data['timestamp'], observedAt);
    expect(data['schemaVersion'], cloudSchemaVersion);
    final decoded = signalFromCloud(original.id, data);
    expect(decoded.toJson(), original.toJson());
  });

  test('check-in Firestore serialization preserves DateTime availability', () {
    final original = checkIn(recorded: recordedAt);
    final data = checkInToCloud(original);
    expect(data['recordedAt'], recordedAt);
    expect(data['timestamp'], observedAt);
    expect(data['schemaVersion'], cloudSchemaVersion);
    final decoded = checkInFromCloud(original.id, data);
    expect(decoded.toJson(), original.toJson());
  });

  test('cloud readers accept normalized ISO recording timestamps', () {
    final signalData = signalToCloud(signal())
      ..['recordedAt'] = recordedAt.toIso8601String();
    final checkData = checkInToCloud(checkIn())
      ..['recordedAt'] = recordedAt.toIso8601String();
    expect(signalFromCloud('signal', signalData).recordedAt, recordedAt);
    expect(checkInFromCloud('check', checkData).recordedAt, recordedAt);
  });

  test(
    'legacy cloud serialization omits unknown availability without backfill',
    () {
      final signalData = signalToCloud(signal());
      final checkData = checkInToCloud(checkIn());
      expect(signalData, isNot(contains('recordedAt')));
      expect(checkData, isNot(contains('recordedAt')));
      expect(signalFromCloud('signal', signalData).recordedAt, isNull);
      expect(checkInFromCloud('check', checkData).recordedAt, isNull);
      expect(
        signalFromCloud('signal', {
          ...signalData,
          'recordedAt': null,
        }).recordedAt,
        isNull,
      );
      expect(
        checkInFromCloud('check', {
          ...checkData,
          'recordedAt': null,
        }).recordedAt,
        isNull,
      );
    },
  );

  test(
    'invalid availability is rejected instead of silently using observation time',
    () {
      expect(
        () => SignalReading.fromJson({
          ...signal().toJson(),
          'recordedAt': 'bad-date',
        }),
        throwsFormatException,
      );
      expect(
        () => DailyCheckIn.fromJson({
          ...checkIn().toJson(),
          'recordedAt': 'bad-date',
        }),
        throwsFormatException,
      );
      expect(
        () => signalFromCloud('signal', {
          ...signalToCloud(signal()),
          'recordedAt': 123,
        }),
        throwsFormatException,
      );
      expect(
        () => checkInFromCloud('check', {
          ...checkInToCloud(checkIn()),
          'recordedAt': 123,
        }),
        throwsFormatException,
      );
    },
  );
}
