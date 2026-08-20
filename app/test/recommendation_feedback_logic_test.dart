import 'package:app/src/models.dart';
import 'package:app/src/recommendation_feedback_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 8, 22);

  Recommendation recommendation({
    required String id,
    required CoachPlanPhase phase,
    required DateTime day,
    RecommendationStatus status = RecommendationStatus.suggested,
    RecommendationPriority priority = RecommendationPriority.routine,
    bool? helpful,
  }) => Recommendation(
    id: id,
    title: phase.name,
    detail: 'Grounded plan block',
    timeLabel: '${8 + phase.index}:00 AM',
    category: phase.name,
    status: status,
    priority: priority,
    scheduledAt: day.add(Duration(hours: 8 + phase.index)),
    day: day,
    generatedAt: day,
    planPhase: phase,
    helpful: helpful,
  );

  test('Version 0.30 ranks future blocks from explicit helpfulness', () {
    final plan = [
      recommendation(
        id: 'today-training',
        phase: CoachPlanPhase.training,
        day: today,
        priority: RecommendationPriority.important,
      ),
      recommendation(
        id: 'today-focus',
        phase: CoachPlanPhase.deepWork,
        day: today,
      ),
    ];
    final history = [
      for (var index = 1; index <= 3; index++) ...[
        recommendation(
          id: 'focus-$index',
          phase: CoachPlanPhase.deepWork,
          day: today.subtract(Duration(days: index)),
          status: RecommendationStatus.completed,
          helpful: true,
        ),
        recommendation(
          id: 'training-$index',
          phase: CoachPlanPhase.training,
          day: today.subtract(Duration(days: index)),
          status: RecommendationStatus.dismissed,
          helpful: false,
        ),
      ],
    ];

    final ranked = RecommendationFeedbackLogic.rank(
      plan: plan,
      history: history,
    );
    final focus = ranked.singleWhere(
      (item) => item.planPhase == CoachPlanPhase.deepWork,
    );
    final training = ranked.singleWhere(
      (item) => item.planPhase == CoachPlanPhase.training,
    );

    expect(ranked.map((item) => item.id), ['today-training', 'today-focus']);
    expect(focus.feedbackScore, .8);
    expect(focus.feedbackSampleCount, 3);
    expect(focus.feedbackRank, 1);
    expect(focus.priority, RecommendationPriority.important);
    expect(training.feedbackScore, .2);
    expect(training.feedbackRank, 2);
    expect(training.priority, RecommendationPriority.routine);
  });

  test('Version 0.30 uses statuses as weaker feedback when no vote exists', () {
    final plan = [
      recommendation(id: 'today-nap', phase: CoachPlanPhase.nap, day: today),
    ];
    final history = [
      recommendation(
        id: 'completed-nap',
        phase: CoachPlanPhase.nap,
        day: today.subtract(const Duration(days: 1)),
        status: RecommendationStatus.completed,
      ),
      recommendation(
        id: 'suggested-nap',
        phase: CoachPlanPhase.nap,
        day: today.subtract(const Duration(days: 2)),
      ),
    ];

    final result = RecommendationFeedbackLogic.rank(
      plan: plan,
      history: history,
    ).single;

    expect(result.feedbackSampleCount, 1);
    expect(result.feedbackScore, closeTo(.6, .0001));
    expect(result.priority, RecommendationPriority.routine);
  });
}
