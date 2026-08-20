import 'package:app/src/daily_plan_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 8, 21);
  final generatedAt = DateTime(2026, 8, 21, 6, 30);

  List<ForecastWindow> windows() {
    ForecastEvidence evidence(String id, SignalType type) => ForecastEvidence(
      id: id,
      kind: ForecastEvidenceKind.signal,
      label: type.label,
      detail: 'Private ${type.label} evidence',
      timestamp: generatedAt,
      signalType: type,
      source: SignalSource.manual,
    );
    return [
      ForecastWindow(
        ForecastWindowType.peak,
        day.add(const Duration(hours: 9)),
        day.add(const Duration(hours: 11)),
        84,
        'Peak',
        evidence: [evidence('sleep-1', SignalType.sleep)],
      ),
      ForecastWindow(
        ForecastWindowType.crash,
        day.add(const Duration(hours: 14)),
        day.add(const Duration(hours: 15)),
        48,
        'Dip',
        evidence: [evidence('study-1', SignalType.study)],
      ),
      ForecastWindow(
        ForecastWindowType.recovery,
        day.add(const Duration(hours: 17)),
        day.add(const Duration(hours: 18, minutes: 30)),
        72,
        'Rebound',
        evidence: [evidence('hydration-1', SignalType.hydration)],
      ),
    ];
  }

  test('Version 0.29 builds a chronological morning-to-evening plan', () {
    final plan = DailyPlanLogic.build(
      windows: windows(),
      score: const ScoreSnapshot(
        energy: 78,
        cognitive: 80,
        confidence: .82,
        cognitiveConfidence: .78,
        drivers: [],
      ),
      profile: const UserProfile(
        coachPriority: CoachPriority.training,
        wakeHour: 7,
        bedHour: 23,
      ),
      day: day,
      generatedAt: generatedAt,
    );

    expect(plan, hasLength(8));
    expect(plan.first.planPhase, CoachPlanPhase.morning);
    expect(plan.last.planPhase, CoachPlanPhase.evening);
    expect(plan.every((item) => item.isGrounded), isTrue);
    expect(plan.every((item) => item.planConfidence == .8), isTrue);
    expect(
      plan.map((item) => item.scheduledAt).toList(),
      orderedEquals(
        [...plan.map((item) => item.scheduledAt)]
          ..sort((left, right) => left!.compareTo(right!)),
      ),
    );
    final training = plan.singleWhere(
      (item) => item.planPhase == CoachPlanPhase.training,
    );
    final recovery = plan.singleWhere(
      (item) => item.planPhase == CoachPlanPhase.recovery,
    );
    expect(training.durationMinutes, 60);
    expect(training.priority, RecommendationPriority.important);
    expect(training.scheduledAt!.isBefore(recovery.scheduledAt!), isTrue);
    expect(training.decisionReason, contains('priority'));
    expect(
      plan
          .singleWhere((item) => item.planPhase == CoachPlanPhase.taper)
          .scheduledAt,
      DateTime(2026, 8, 21, 21, 30),
    );
  });

  test('Version 0.29 makes low-confidence recovery conflicts conservative', () {
    final plan = DailyPlanLogic.build(
      windows: windows(),
      score: const ScoreSnapshot(
        energy: 55,
        cognitive: 58,
        confidence: .35,
        cognitiveConfidence: .45,
        drivers: [],
      ),
      profile: const UserProfile(
        coachPriority: CoachPriority.recovery,
        wakeHour: 7,
        bedHour: 23,
      ),
      day: day,
      generatedAt: generatedAt,
    );

    final recovery = plan.singleWhere(
      (item) => item.planPhase == CoachPlanPhase.recovery,
    );
    final training = plan.singleWhere(
      (item) => item.planPhase == CoachPlanPhase.training,
    );
    final nap = plan.singleWhere(
      (item) => item.planPhase == CoachPlanPhase.nap,
    );

    expect(recovery.scheduledAt!.isBefore(training.scheduledAt!), isTrue);
    expect(training.durationMinutes, 20);
    expect(training.title, contains('light and flexible'));
    expect(training.decisionReason, contains('confidence is limited'));
    expect(nap.durationMinutes, 25);
    expect(nap.priority, RecommendationPriority.important);
  });

  test('Version 0.29 migrates legacy goals into coach priorities', () {
    expect(
      UserProfile.fromJson(const {'goal': 'Improve focus'}).coachPriority,
      CoachPriority.focus,
    );
    expect(
      UserProfile.fromJson(const {'goal': 'Improve recovery'}).coachPriority,
      CoachPriority.recovery,
    );
  });
}
