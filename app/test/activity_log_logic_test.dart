import 'package:app/src/activity_log_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActivityLogLogic', () {
    test('explicit zero is logged while blank remains missing', () {
      // Chart arithmetic is not a storage or editing default.
      expect(ActivityLogLogic.valueOrZero(null), 0);
      expect(ActivityLogLogic.hasAnyLoggedValue(), isFalse);
      expect(ActivityLogLogic.valueOrZero(2.5), 2.5);
      expect(
        ActivityLogLogic.hasAnyLoggedValue(
          hydrationLiters: 0,
          studyHours: 0,
          exerciseHours: 0,
          screenTimeHours: 0,
        ),
        isTrue,
      );
      expect(
        ActivityLogLogic.hasAnyLoggedValue(
          hydrationLiters: 1,
          studyHours: 0,
          exerciseHours: 0,
          screenTimeHours: 0,
        ),
        isTrue,
      );
    });

    test(
      'zero-only series has an observation and missing days remain distinct',
      () {
        final now = DateTime(2026, 11, 2, 12);
        final log = ActivityLogEntry(
          id: 'activity-zero',
          timestamp: now,
          hydrationLiters: null,
          studyHours: 0,
          exerciseHours: null,
          screenTimeHours: null,
        );
        expect(ActivityLogLogic.observationFor(log, SignalType.study), 0);
        expect(
          ActivityLogLogic.observationFor(log, SignalType.hydration),
          isNull,
        );
        final series = ActivityLogLogic.weekByCategory([log], now: now);
        final study = series.singleWhere((s) => s.type == SignalType.study);
        expect(study.hasData, isTrue);
        expect(study.observed.where((present) => present), hasLength(1));
        expect(study.isObserved(6), isTrue);
        expect(study.isObserved(5), isFalse);
        expect(study.values[6], 0);
        expect(study.peakDay, DateTime(2026, 11, 2));
        expect(
          series.singleWhere((s) => s.type == SignalType.hydration).hasData,
          isFalse,
        );
        expect(study.days.map((day) => '${day.month}/${day.day}'), [
          '10/27',
          '10/28',
          '10/29',
          '10/30',
          '10/31',
          '11/1',
          '11/2',
        ]);
        expect(study.days.every((day) => day.hour == 0), isTrue);
      },
    );

    test('builds last-week category series and finds peak days', () {
      final now = DateTime(2026, 7, 23, 12);
      final logs = [
        ActivityLogEntry(
          id: 'a',
          timestamp: DateTime(2026, 7, 21, 18),
          hydrationLiters: 1,
          studyHours: 4,
          exerciseHours: 0,
          screenTimeHours: 2,
        ),
        ActivityLogEntry(
          id: 'b',
          timestamp: DateTime(2026, 7, 23, 10),
          hydrationLiters: 3,
          studyHours: 1,
          exerciseHours: 2,
          screenTimeHours: 5,
        ),
      ];

      final week = ActivityLogLogic.weekByCategory(logs, now: now);
      expect(week, hasLength(4));

      final hydration = week.firstWhere(
        (series) => series.type == SignalType.hydration,
      );
      expect(hydration.values, hasLength(7));
      expect(hydration.peakValue, 3);
      expect(hydration.peakDay, DateTime(2026, 7, 23));

      final study = week.firstWhere(
        (series) => series.type == SignalType.study,
      );
      expect(study.peakValue, 4);
      expect(study.peakDay, DateTime(2026, 7, 21));
    });
  });
}
