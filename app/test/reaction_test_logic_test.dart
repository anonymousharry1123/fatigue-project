import 'package:app/src/models.dart';
import 'package:app/src/reaction_test_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReactionTestLogic', () {
    test('rejects early-looking and overly slow reactions', () {
      expect(ReactionTestLogic.isValidReaction(99), isFalse);
      expect(ReactionTestLogic.isValidReaction(100), isTrue);
      expect(ReactionTestLogic.isValidReaction(1500), isTrue);
      expect(ReactionTestLogic.isValidReaction(1501), isFalse);
      expect(ReactionTestLogic.isValidReaction(99.6), isFalse);
      expect(ReactionTestLogic.isValidReaction(1500.4), isFalse);
      expect(ReactionTestLogic.isValidReaction(250.5), isTrue);
      expect(ReactionTestLogic.isValidReaction(double.nan), isFalse);
      expect(ReactionTestLogic.isValidReaction(double.infinity), isFalse);
    });

    test('averages three valid rounds for a daily benchmark', () {
      expect(ReactionTestLogic.averageMs([250, 260, 270]), 260);
      expect(ReactionTestLogic.isComplete([240, 250]), isFalse);
      expect(ReactionTestLogic.isComplete([240, 250, 260]), isTrue);
    });

    test('completion requires exactly three valid uninterrupted rounds', () {
      expect(ReactionTestLogic.isComplete([]), isFalse);
      expect(ReactionTestLogic.isComplete([240, 99, 260]), isFalse);
      expect(ReactionTestLogic.isComplete([240, 250, 1501]), isFalse);
      expect(ReactionTestLogic.isComplete([240, 250, 260, 270]), isFalse);
      expect(ReactionTestLogic.isComplete([100, 250, 1500]), isTrue);
    });

    test('builds a personal baseline from prior reaction signals', () {
      final now = DateTime(2026, 7, 23, 9);
      final signals = [
        SignalReading(
          id: 'r1',
          type: SignalType.reactionTime,
          value: 300,
          timestamp: now,
        ),
        SignalReading(
          id: 'r2',
          type: SignalType.reactionTime,
          value: 280,
          timestamp: now.subtract(const Duration(days: 1)),
        ),
        SignalReading(
          id: 'r3',
          type: SignalType.reactionTime,
          value: 260,
          timestamp: now.subtract(const Duration(days: 2)),
        ),
        SignalReading(
          id: 'sleep',
          type: SignalType.sleep,
          value: 7.5,
          timestamp: now,
        ),
      ];

      expect(ReactionTestLogic.baselineMs(signals), closeTo(280, 0.01));
      expect(ReactionTestLogic.baselineMs(signals, minSamples: 4), isNull);
    });

    test('compares a result against the personal baseline', () {
      expect(
        ReactionTestLogic.comparisonLabel(250, 280),
        '30 ms faster than baseline',
      );
      expect(
        ReactionTestLogic.comparisonLabel(300, 280),
        '20 ms slower than baseline',
      );
      expect(ReactionTestLogic.comparisonLabel(285, 280), 'Near your baseline');
    });

    test(
      'baseline ignores invalid values and uses the latest observations',
      () {
        final now = DateTime(2026, 10, 1);
        final signals = <SignalReading>[
          for (var day = 0; day < 15; day++)
            SignalReading(
              id: 'r-$day',
              type: SignalType.reactionTime,
              value: day == 0 ? 1000 : 250,
              timestamp: now.add(Duration(days: day)),
            ),
          for (final invalid in [double.nan, double.infinity, 99.6, 1500.4])
            SignalReading(
              id: 'invalid-$invalid',
              type: SignalType.reactionTime,
              value: invalid,
              timestamp: now.add(const Duration(days: 16)),
            ),
        ];
        expect(ReactionTestLogic.baselineMs(signals), 250);
        expect(signals.first.id, 'r-0');
      },
    );
  });
}
