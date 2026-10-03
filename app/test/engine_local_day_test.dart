import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Also run under TZ=America/Los_Angeles to exercise the 23/25-hour days,
  // and TZ=Asia/Tokyo to exercise UTC instants from the prior calendar date.
  for (final day in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
    test('historical scoring uses complete local calendar day $day', () {
      final nextDay = DateTime(day.year, day.month, day.day + 1);
      final signals = [
        SignalReading(
          id: 'late-today',
          type: SignalType.study,
          value: 1,
          timestamp: DateTime(day.year, day.month, day.day, 23, 30).toUtc(),
        ),
        SignalReading(
          id: 'tomorrow',
          type: SignalType.study,
          value: 10,
          timestamp: DateTime(
            nextDay.year,
            nextDay.month,
            nextDay.day,
            0,
            15,
          ).toUtc(),
        ),
      ];
      final snapshot = FatigueEngine.score(
        signals: signals,
        checkIns: const [],
        day: day.toUtc(),
        now: DateTime(nextDay.year, nextDay.month, nextDay.day, 12).toUtc(),
      );
      expect(snapshot.day, day);
      expect(snapshot.drivers.single.detail, startsWith('1.0 hr'));
    });

    test('forecast uses local wall-clock hours across clock changes $day', () {
      final clock = DateTime(day.year, day.month, day.day, 12).toUtc();
      final inputs = [
        SignalReading(
          id: 'study',
          type: SignalType.study,
          value: 2,
          timestamp: clock,
        ),
      ];
      final snapshot = FatigueEngine.score(
        signals: inputs,
        checkIns: const [],
        now: clock,
      );
      final points = FatigueEngine.forecast(
        snapshot,
        day.toUtc(),
        signals: inputs,
        generatedAt: clock,
      );
      expect(points.first.time.hour, 7);
      expect(points.last.time.hour, 23);
      expect(
        points.map((point) => point.time.hour),
        List.generate(17, (i) => 7 + i),
      );
      expect(points.every((point) => point.time.day == day.day), isTrue);
    });
  }
}
