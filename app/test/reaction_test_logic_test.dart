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
    });

    test('averages three valid rounds for a daily benchmark', () {
      expect(ReactionTestLogic.averageMs([250, 260, 270]), 260);
      expect(ReactionTestLogic.isComplete([240, 250]), isFalse);
      expect(ReactionTestLogic.isComplete([240, 250, 260]), isTrue);
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
      expect(
        ReactionTestLogic.baselineMs(signals, minSamples: 4),
        isNull,
      );
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
      expect(
        ReactionTestLogic.comparisonLabel(285, 280),
        'Near your baseline',
      );
    });
  });
}
