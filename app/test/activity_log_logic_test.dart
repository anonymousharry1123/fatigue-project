import 'package:app/src/activity_log_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActivityLogLogic', () {
    test('treats blank values as zero', () {
      expect(ActivityLogLogic.valueOrZero(null), 0);
      expect(ActivityLogLogic.valueOrZero(2.5), 2.5);
      expect(
        ActivityLogLogic.hasAnyLoggedValue(
          hydrationLiters: 0,
          studyHours: 0,
          exerciseHours: 0,
          screenTimeHours: 0,
        ),
        isFalse,
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

      final study = week.firstWhere((series) => series.type == SignalType.study);
      expect(study.peakValue, 4);
      expect(study.peakDay, DateTime(2026, 7, 21));
    });
  });
}
