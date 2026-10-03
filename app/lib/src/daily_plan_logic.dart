import 'models.dart';
import 'local_day.dart';
import 'schedule_logic.dart';

/// Optional schedule blocks. Experimental forecasts do not establish optimal
/// timing or authorize exercise intensity. No fixed-commitment model exists.
class DailyPlanLogic {
  const DailyPlanLogic._();

  static const planVersion = 'phase1';

  static bool isCurrentPlan(Recommendation item) =>
      item.day != null &&
      item.id.startsWith('${_dayIdentifier(item.day!)}-$planVersion-') &&
      const {
        CoachPlanPhase.morning,
        CoachPlanPhase.deepWork,
        CoachPlanPhase.midday,
        CoachPlanPhase.evening,
      }.contains(item.planPhase);

  static List<Recommendation> build({
    required List<ForecastWindow> windows,
    required ScoreSnapshot score,
    required UserProfile profile,
    required DateTime day,
    required DateTime generatedAt,
  }) {
    if (!score.canEstimateEnergy && !score.canEstimateCognitive) {
      return const [];
    }
    final targetDay = localDay(day);
    if (!sameLocalDay(targetDay, generatedAt)) return const [];
    final waking = ScheduleLogic.wakingWindow(targetDay, profile);
    if (waking == null) return const [];
    final byId = <String, ForecastEvidence>{};
    for (final window in windows) {
      for (final item in window.evidence) {
        if (item.id.trim().isNotEmpty &&
            sameLocalDay(item.timestamp, generatedAt) &&
            !item.timestamp.isAfter(generatedAt)) {
          byId['${item.kind.name}:${item.id}'] = item;
        }
      }
    }
    final evidence = byId.values.toList(growable: false);
    if (evidence.isEmpty) return const [];
    final coverage = ((score.confidence + score.cognitiveConfidence) / 2)
        .clamp(0, 1)
        .toDouble();
    final plan = <Recommendation>[];
    var availableAt = waking.wake;
    final windDown = waking.bed.subtract(const Duration(minutes: 45));

    void add({
      required String slug,
      required String title,
      required String detail,
      required CoachPlanPhase phase,
      required DateTime preferredAt,
      required int minutes,
      required DateTime limit,
    }) {
      final at = preferredAt.isBefore(availableAt) ? availableAt : preferredAt;
      final end = at.add(Duration(minutes: minutes));
      if (at.isBefore(waking.wake) || end.isAfter(limit)) return;
      plan.add(
        Recommendation(
          id: '${_dayIdentifier(targetDay)}-$planVersion-$slug',
          title: title,
          detail: detail,
          timeLabel: _clock(at),
          category: switch (phase) {
            CoachPlanPhase.morning => 'Morning',
            CoachPlanPhase.deepWork => 'Focus',
            CoachPlanPhase.midday => 'Break',
            _ => 'Evening',
          },
          scheduledAt: at,
          day: targetDay,
          generatedAt: generatedAt,
          signalEvidenceIds: evidence
              .where((item) => item.kind == ForecastEvidenceKind.signal)
              .map((item) => item.id)
              .toList(growable: false),
          checkInEvidenceIds: evidence
              .where((item) => item.kind == ForecastEvidenceKind.checkIn)
              .map((item) => item.id)
              .toList(growable: false),
          evidence: evidence,
          planPhase: phase,
          durationMinutes: minutes,
          planConfidence: coverage,
          decisionReason:
              'Optional timing within your saved wake and bed schedule; not a validated alertness or recovery window.',
        ),
      );
      availableAt = end.add(const Duration(minutes: 10));
    }

    add(
      slug: 'morning-setup',
      title: 'Consider a brief morning check-in',
      detail: 'If useful, record how you feel and choose one task for the day.',
      phase: CoachPlanPhase.morning,
      preferredAt: waking.wake.add(const Duration(minutes: 15)),
      minutes: 10,
      limit: windDown,
    );
    add(
      slug: 'focus',
      title: 'Optional focus block',
      detail:
          'Choose a task that fits how you feel. Shorten or skip this block as needed.',
      phase: CoachPlanPhase.deepWork,
      preferredAt: waking.wake.add(const Duration(minutes: 45)),
      minutes: 30,
      limit: windDown,
    );
    add(
      slug: 'break',
      title: 'Consider a pause',
      detail: 'If it fits your day, take a brief break from your current task.',
      phase: CoachPlanPhase.midday,
      preferredAt: waking.wake.add(
        Duration(minutes: waking.bed.difference(waking.wake).inMinutes ~/ 2),
      ),
      minutes: 10,
      limit: windDown,
    );
    add(
      slug: 'wind-down',
      title: 'Optional quiet wind-down',
      detail: 'Leave room for a low-demand transition to your saved bedtime.',
      phase: CoachPlanPhase.evening,
      preferredAt: windDown,
      minutes: 30,
      limit: waking.bed,
    );
    return List.unmodifiable(plan);
  }

  static String _dayIdentifier(DateTime day) => localDayKey(day);

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }
}
