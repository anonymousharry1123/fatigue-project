import 'package:app/src/check_in_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CheckInLogic', () {
    test('accepts intuitive 1–10 ratings only', () {
      expect(CheckInLogic.isValidRating(1), isTrue);
      expect(CheckInLogic.isValidRating(10), isTrue);
      expect(CheckInLogic.isValidRating(0), isFalse);
      expect(CheckInLogic.isValidRating(11), isFalse);
    });

    test('assigns morning before 14:00 and evening afterward from the clock', () {
      expect(
        CheckInLogic.periodFor(DateTime(2026, 7, 23, 8)),
        CheckInPeriod.morning,
      );
      expect(
        CheckInLogic.periodFor(DateTime(2026, 7, 23, 13, 59)),
        CheckInPeriod.morning,
      );
      expect(
        CheckInLogic.periodFor(DateTime(2026, 7, 23, 14)),
        CheckInPeriod.evening,
      );
      expect(
        CheckInLogic.periodFor(DateTime(2026, 7, 23, 18)),
        CheckInPeriod.evening,
      );
    });

    test('filters check-in history for a calendar day', () {
      final day = DateTime(2026, 7, 23);
      final checkIns = [
        DailyCheckIn(
          id: 'a',
          timestamp: DateTime(2026, 7, 23, 8),
          energy: 7,
          mood: 6,
          stress: 4,
          period: CheckInPeriod.morning,
        ),
        DailyCheckIn(
          id: 'b',
          timestamp: DateTime(2026, 7, 22, 20),
          energy: 5,
          mood: 5,
          stress: 5,
          period: CheckInPeriod.evening,
        ),
        DailyCheckIn(
          id: 'c',
          timestamp: DateTime(2026, 7, 23, 21),
          energy: 6,
          mood: 7,
          stress: 3,
          period: CheckInPeriod.evening,
        ),
      ];

      final today = CheckInLogic.historyForDay(checkIns, day);
      expect(today.map((item) => item.id), ['c', 'a']);
    });
  });

  group('DailyCheckIn serialization', () {
    test('persists period and 1–10 ratings', () {
      final original = DailyCheckIn(
        id: 'check-1',
        timestamp: DateTime(2026, 7, 23, 9),
        energy: 8,
        mood: 7,
        stress: 3,
        period: CheckInPeriod.morning,
        note: 'Felt sharp',
      );

      final restored = DailyCheckIn.fromJson(original.toJson());
      expect(restored.energy, 8);
      expect(restored.mood, 7);
      expect(restored.stress, 3);
      expect(restored.period, CheckInPeriod.morning);
      expect(restored.note, 'Felt sharp');
    });

    test('migrates legacy 1–5 check-ins without a period field', () {
      final restored = DailyCheckIn.fromJson({
        'id': 'legacy',
        'timestamp': '2026-07-20T08:00:00.000',
        'energy': 4,
        'mood': 3,
        'stress': 2,
      });

      expect(restored.energy, 8);
      expect(restored.mood, 6);
      expect(restored.stress, 4);
      expect(restored.period, CheckInPeriod.morning);
    });
  });
}
