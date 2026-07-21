import 'package:app/src/demo_data.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 21, 9);

  test('fixture data produces bounded scores and useful drivers', () {
    final score = FatigueEngine.score(
      signals: buildDemoSignals(now),
      checkIns: buildDemoCheckIns(now),
      now: now,
    );

    expect(score.energy, inInclusiveRange(0, 100));
    expect(score.cognitive, inInclusiveRange(0, 100));
    expect(score.confidence, inInclusiveRange(0, 1));
    expect(score.drivers, isNotEmpty);
  });

  test('forecast returns an hourly curve and all three window types', () {
    const score = ScoreSnapshot(
      energy: 74,
      cognitive: 78,
      confidence: .82,
      drivers: [],
    );
    final points = FatigueEngine.forecast(score, now);
    final windows = FatigueEngine.windows(points, score);

    expect(points, hasLength(17));
    expect(
      points.every((point) => point.energy >= 0 && point.energy <= 100),
      isTrue,
    );
    expect(
      windows.map((item) => item.type).toSet(),
      ForecastWindowType.values.toSet(),
    );
  });

  test('missing signals lower confidence without breaking scores', () {
    final score = FatigueEngine.score(
      signals: const [],
      checkIns: const [],
      now: now,
    );

    expect(score.confidence, lessThan(.5));
    expect(score.energy, inInclusiveRange(0, 100));
    expect(score.cognitive, inInclusiveRange(0, 100));
  });
}
