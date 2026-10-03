import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:app/src/sleep_observation_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 3, 12);
  SignalReading sleep(
    String id,
    double hours,
    DateTime end, {
    SignalType type = SignalType.sleep,
    SignalSource source = SignalSource.manual,
    String? groupId,
  }) => SignalReading(
    id: id,
    type: type,
    value: hours,
    timestamp: end,
    source: source,
    groupId: groupId,
  );
  SleepObservations summary(
    List<SignalReading> rows, {
    PrivacyAgeBand? age = PrivacyAgeBand.age16to17,
  }) => SleepObservations.build(signals: rows, now: now, ageBand: age);

  test('only supported teen bands receive the 8–10 hour comparison', () {
    final rows = [sleep('main', 8, DateTime(2026, 10, 3, 7))];
    for (final age in [PrivacyAgeBand.age13to15, PrivacyAgeBand.age16to17]) {
      expect(
        summary(rows, age: age).compare(allSleepConfirmed: true),
        SleepRangeComparison.within,
      );
    }
    for (final age in [null, PrivacyAgeBand.adult, PrivacyAgeBand.under13]) {
      expect(summary(rows, age: age).supportsTeenGuidance, isFalse);
      expect(
        summary(rows, age: age).compare(allSleepConfirmed: true),
        SleepRangeComparison.unavailable,
      );
    }
  });

  test('a main record is not evidence of complete 24-hour coverage', () {
    final result = summary([sleep('main', 9, DateTime(2026, 10, 3, 7))]);
    expect(
      result.compare(allSleepConfirmed: false),
      SleepRangeComparison.unavailable,
    );
    expect(result.mainObservationCount, 1);
    expect(result.bedtimeObservationCount, 0);
    expect(result.bedtimeVariationMinutes, isNull);
    expect(result.days.where((day) => day.mainHours == null), hasLength(6));
    expect(summary([]).latestMain, isNull);
  });

  test(
    'separate naps count once in elapsed window, without recovery points',
    () {
      final result = summary([
        sleep('main', 7.5, DateTime(2026, 10, 3, 7)),
        sleep(
          'manual-nap',
          .5,
          DateTime(2026, 10, 2, 15),
          type: SignalType.nap,
        ),
        sleep(
          'import-duplicate',
          .5,
          DateTime(2026, 10, 2, 15),
          type: SignalType.nap,
          source: SignalSource.healthKit,
        ),
        sleep(
          'overlap-main',
          .5,
          DateTime(2026, 10, 3, 7),
          type: SignalType.nap,
        ),
      ]);
      expect(result.totalHours, 8);
      expect(result.napHours, .5);
      expect(result.napCount, 1);
      expect(
        result.compare(allSleepConfirmed: true),
        SleepRangeComparison.within,
      );
    },
  );

  test(
    'overlapping main intervals on different wake dates use their union',
    () {
      final result = summary([
        sleep('earlier', 8, DateTime(2026, 10, 2, 23)),
        sleep('later', 10, DateTime(2026, 10, 3, 7)),
      ]);
      expect(result.totalHours, 16); // 15:00 previous day through 07:00 today.
      expect(result.latestMain!.id, 'later');
    },
  );

  test('existing main-source reconciliation remains authoritative', () {
    final manual = sleep('manual', 6, DateTime(2026, 10, 3, 7));
    final imported = sleep(
      'health',
      8,
      DateTime(2026, 10, 3, 7),
      source: SignalSource.healthKit,
      groupId: 'healthkit-sleep-2026-10-03',
    );
    expect(summary([manual, imported]).latestMain!.id, 'manual');
    final stage = sleep(
      'core',
      5,
      imported.timestamp,
      type: SignalType.sleepCore,
      source: SignalSource.healthKit,
      groupId: imported.groupId,
    );
    expect(summary([manual, imported, stage]).latestMain!.id, 'health');
  });

  test('short usual pattern never lowers age recommendation', () {
    final result = summary([
      for (var i = 0; i < 7; i++) sleep('$i', 6, DateTime(2026, 10, 3 - i, 7)),
    ]);
    expect(result.mainObservationCount, 7);
    expect(result.usualMainHours, 6);
    expect(result.compare(allSleepConfirmed: true), SleepRangeComparison.below);
  });

  test(
    'clock variation wraps midnight and abstains on insufficient timing',
    () {
      expect(
        SleepObservations.circularVariationMinutes([
          DateTime(2026, 10, 2, 23, 50),
          DateTime(2026, 10, 3, 0, 10),
        ]),
        closeTo(10, .001),
      );
      expect(SleepObservations.circularVariationMinutes([now]), isNull);
      expect(
        SleepObservations.circularVariationMinutes([
          DateTime(2026, 10, 3, 0),
          DateTime(2026, 10, 3, 12),
        ]),
        isNull,
      );
    },
  );

  test('boundary clipping and midnight preserve the exact elapsed window', () {
    final result = summary([
      sleep('boundary', 3, DateTime(2026, 10, 2, 13)),
      sleep('latest', 8, DateTime(2026, 10, 3, 7)),
      sleep('future', 12, now.add(const Duration(hours: 1))),
      sleep('model', 14, DateTime(2026, 10, 3, 8), source: SignalSource.model),
    ]);
    expect(
      result.windowEnd.difference(result.windowStart),
      const Duration(hours: 24),
    );
    expect(result.totalHours, 9);
    expect(result.latestMain!.id, 'latest');
  });

  test('incomplete interval geometry suppresses comparison at a boundary', () {
    final result = summary([
      sleep('summary', 3, DateTime(2026, 10, 2, 14), groupId: 'night'),
      sleep(
        'bed',
        9,
        DateTime(2026, 10, 2, 9),
        type: SignalType.bedtime,
        groupId: 'night',
      ),
    ]);
    expect(result.boundaryUncertain, isTrue);
    expect(
      result.compare(allSleepConfirmed: true),
      SleepRangeComparison.unavailable,
    );
  });

  test(
    'clipped imported total without interval geometry is not comparable',
    () {
      final result = summary([
        sleep(
          'health-total',
          3,
          DateTime(2026, 10, 2, 13),
          source: SignalSource.healthKit,
        ),
      ]);
      expect(result.boundaryUncertain, isTrue);
      expect(
        result.compare(allSleepConfirmed: true),
        SleepRangeComparison.unavailable,
      );
    },
  );

  // Run under TZ=America/Los_Angeles as well as the host zone. Duration uses
  // instants; pattern buckets use local dates, including 23/25-hour DST days.
  for (final day in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
    test('DST sleep/window boundaries $day', () {
      final bedtime = DateTime(day.year, day.month, day.day - 1, 22);
      final wake = DateTime(day.year, day.month, day.day, 7);
      final hours = wake.difference(bedtime).inMinutes / 60;
      final result = SleepObservations.build(
        signals: [sleep('dst', hours, wake)],
        now: DateTime(day.year, day.month, day.day, 12),
        ageBand: PrivacyAgeBand.age13to15,
      );
      expect(result.totalHours, hours);
      expect(result.windowEnd.difference(result.windowStart).inHours, 24);
      expect(result.days.last.day.day, day.day);
      expect(result.mainObservationCount, 1);
    });
  }
}
