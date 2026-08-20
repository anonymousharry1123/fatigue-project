import 'models.dart';

/// Applies Version 0.30 recommendation feedback to a newly generated plan.
///
/// Only prior-day responses are passed in by the controller. Explicit helpful
/// votes carry the clearest signal; completed, accepted, and dismissed states
/// provide weaker implicit outcomes when no vote was recorded. A two-sample
/// neutral prior prevents one response from over-personalizing the plan.
class RecommendationFeedbackLogic {
  const RecommendationFeedbackLogic._();

  static const historyWindow = Duration(days: 30);

  static List<Recommendation> rank({
    required List<Recommendation> plan,
    required List<Recommendation> history,
  }) {
    final scored = <_ScoredRecommendation>[];
    for (final item in plan) {
      final matching = history.where(
        (past) => _feedbackKey(past) == _feedbackKey(item),
      );
      var outcomeTotal = 0.0;
      var sampleCount = 0;
      for (final past in matching) {
        final outcome = _outcome(past);
        if (outcome == null) continue;
        outcomeTotal += outcome;
        sampleCount += 1;
      }
      final score = (1 + outcomeTotal) / (2 + sampleCount);
      final priority = sampleCount >= 2 && score >= .65
          ? RecommendationPriority.important
          : sampleCount >= 2 && score <= .35
          ? RecommendationPriority.routine
          : item.priority;
      scored.add(
        _ScoredRecommendation(
          item.copyWith(
            priority: priority,
            feedbackScore: score,
            feedbackSampleCount: sampleCount,
          ),
        ),
      );
    }

    final ranked = [...scored]
      ..sort((left, right) {
        final byScore = right.item.feedbackScore.compareTo(
          left.item.feedbackScore,
        );
        if (byScore != 0) return byScore;
        final byPriority = right.item.priority.index.compareTo(
          left.item.priority.index,
        );
        if (byPriority != 0) return byPriority;
        final leftTime = left.item.scheduledAt ?? DateTime(0);
        final rightTime = right.item.scheduledAt ?? DateTime(0);
        return leftTime.compareTo(rightTime);
      });
    final rankById = <String, int>{
      for (var index = 0; index < ranked.length; index++)
        ranked[index].item.id: index + 1,
    };

    // Keep the visible daily plan chronological. feedbackRank records the
    // learned ordering and priority reflects strong, repeated preferences.
    return List.unmodifiable(
      scored
          .map(
            (value) =>
                value.item.copyWith(feedbackRank: rankById[value.item.id]),
          )
          .toList(),
    );
  }

  static String _feedbackKey(Recommendation item) =>
      item.planPhase?.name ?? item.category.trim().toLowerCase();

  static double? _outcome(Recommendation item) {
    if (item.helpful case final helpful?) return helpful ? 1 : 0;
    return switch (item.status) {
      RecommendationStatus.completed => .8,
      RecommendationStatus.accepted => .65,
      RecommendationStatus.dismissed => .2,
      RecommendationStatus.suggested => null,
    };
  }
}

class _ScoredRecommendation {
  const _ScoredRecommendation(this.item);

  final Recommendation item;
}
