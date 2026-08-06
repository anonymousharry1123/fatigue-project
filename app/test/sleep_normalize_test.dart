import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SleepLogEntry.normalizeOvernightPair', () {
    test('keeps early-morning bedtime on the wake calendar day', () {
      final pair = SleepLogEntry.normalizeOvernightPair(
        // Time picker kept "yesterday" when changing 11 PM → 1 AM.
        bedtime: DateTime(2026, 7, 31, 1),
        wakeTime: DateTime(2026, 8, 1, 8),
      );
      expect(pair.$1, DateTime(2026, 8, 1, 1));
      expect(pair.$2, DateTime(2026, 8, 1, 8));
      expect(pair.$2.difference(pair.$1), const Duration(hours: 7));
    });

    test('moves evening bedtime to the night before wake', () {
      final pair = SleepLogEntry.normalizeOvernightPair(
        bedtime: DateTime(2026, 8, 1, 23),
        wakeTime: DateTime(2026, 8, 1, 7),
      );
      expect(pair.$1, DateTime(2026, 7, 31, 23));
      expect(pair.$2, DateTime(2026, 8, 1, 7));
      expect(pair.$2.difference(pair.$1), const Duration(hours: 8));
    });

    test('preserves an already-correct overnight pair', () {
      final pair = SleepLogEntry.normalizeOvernightPair(
        bedtime: DateTime(2026, 7, 31, 23, 30),
        wakeTime: DateTime(2026, 8, 1, 7, 30),
      );
      expect(pair.$1, DateTime(2026, 7, 31, 23, 30));
      expect(pair.$2, DateTime(2026, 8, 1, 7, 30));
    });
  });
}
