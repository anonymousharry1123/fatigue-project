import 'models.dart';

/// Builds Version 0.29's grounded, morning-to-evening Coach timeline.
///
/// Forecast windows decide *when* an action fits. Score confidence controls
/// how specific or aggressive it may be. The saved user priority resolves the
/// deliberate recovery-versus-training conflict in the rebound window.
class DailyPlanLogic {
  const DailyPlanLogic._();

  static List<Recommendation> build({
    required List<ForecastWindow> windows,
    required ScoreSnapshot score,
    required UserProfile profile,
    required DateTime day,
    required DateTime generatedAt,
  }) {
    final byType = {for (final window in windows) window.type: window};
    if (!ForecastWindowType.values.every(byType.containsKey)) return const [];

    final targetDay = DateTime(day.year, day.month, day.day);
    final wakeAt = _atDecimalHour(targetDay, profile.wakeHour);
    var bedAt = _atDecimalHour(targetDay, profile.bedHour);
    if (!bedAt.isAfter(wakeAt)) bedAt = bedAt.add(const Duration(days: 1));

    final peak = byType[ForecastWindowType.peak]!;
    final crash = byType[ForecastWindowType.crash]!;
    final rebound = byType[ForecastWindowType.recovery]!;
    final planConfidence = ((score.confidence + score.cognitiveConfidence) / 2)
        .clamp(0, 1)
        .toDouble();
    final highConfidence = planConfidence >= .65;
    final canTrainNormally = highConfidence && score.energy >= 65;

    final focusMinutes = switch ((profile.coachPriority, highConfidence)) {
      (CoachPriority.focus, true) => 75,
      (CoachPriority.focus, false) => 45,
      (CoachPriority.balanced, true) => 60,
      (CoachPriority.balanced, false) => 35,
      (CoachPriority.training, true) => 45,
      (CoachPriority.training, false) => 30,
      (CoachPriority.recovery, true) => 45,
      (CoachPriority.recovery, false) => 30,
    };
    final napMinutes = profile.coachPriority == CoachPriority.recovery
        ? 25
        : 20;
    final recoveryMinutes = profile.coachPriority == CoachPriority.recovery
        ? 45
        : 30;
    final trainingMinutes = !canTrainNormally
        ? 20
        : switch (profile.coachPriority) {
            CoachPriority.training => 60,
            CoachPriority.balanced => 45,
            CoachPriority.focus => 35,
            CoachPriority.recovery => 25,
          };

    final taperAt = bedAt.subtract(const Duration(minutes: 90));
    final eveningAt = bedAt.subtract(const Duration(minutes: 45));
    final morningAt = wakeAt.add(const Duration(minutes: 15));
    final focusAt = _clamp(
      peak.start,
      wakeAt.add(const Duration(minutes: 45)),
      taperAt.subtract(Duration(minutes: focusMinutes + 30)),
    );
    final hydrationAt = _clamp(
      crash.start.subtract(const Duration(minutes: 30)),
      focusAt.add(Duration(minutes: focusMinutes + 15)),
      taperAt.subtract(const Duration(minutes: 90)),
    );
    final napAt = _clamp(
      crash.start,
      hydrationAt.add(const Duration(minutes: 15)),
      taperAt.subtract(const Duration(minutes: 75)),
    );

    // Training and recovery both want the rebound window. Training goes first
    // only when the person explicitly prioritizes it and the evidence supports
    // normal intensity. Every other case protects recovery first.
    final trainingFirst =
        profile.coachPriority == CoachPriority.training && canTrainNormally;
    final reboundStart = _clamp(
      rebound.start,
      napAt.add(Duration(minutes: napMinutes + 15)),
      taperAt.subtract(const Duration(minutes: 75)),
    );
    final trainingAt = trainingFirst
        ? reboundStart
        : reboundStart.add(Duration(minutes: recoveryMinutes + 10));
    final recoveryAt = trainingFirst
        ? reboundStart.add(Duration(minutes: trainingMinutes + 10))
        : reboundStart;

    Recommendation? item({
      required String slug,
      required String title,
      required String detail,
      required String category,
      required CoachPlanPhase phase,
      required ForecastWindow window,
      required DateTime scheduledAt,
      required int durationMinutes,
      required String decisionReason,
      RecommendationPriority priority = RecommendationPriority.routine,
    }) {
      final evidence = window.evidence
          .where((value) => value.id.isNotEmpty)
          .toList(growable: false);
      if (evidence.isEmpty) return null;
      final labels = evidence
          .map((value) => value.label)
          .toSet()
          .take(2)
          .join(' and ');
      return Recommendation(
        id: '${_dayIdentifier(targetDay)}-$slug',
        title: title,
        detail:
            '$detail Timed from the ${_windowLabel(window.type)} window using linked $labels data.',
        timeLabel: _clock(scheduledAt),
        category: category,
        priority: priority,
        windowType: window.type,
        scheduledAt: scheduledAt,
        day: targetDay,
        generatedAt: generatedAt,
        signalEvidenceIds: evidence
            .where((value) => value.kind == ForecastEvidenceKind.signal)
            .map((value) => value.id)
            .toSet()
            .toList(growable: false),
        checkInEvidenceIds: evidence
            .where((value) => value.kind == ForecastEvidenceKind.checkIn)
            .map((value) => value.id)
            .toSet()
            .toList(growable: false),
        evidence: evidence,
        planPhase: phase,
        durationMinutes: durationMinutes,
        planConfidence: planConfidence,
        decisionReason: decisionReason,
      );
    }

    final confidenceReason = highConfidence
        ? 'Higher-confidence windows support a specific time block.'
        : 'Lower confidence keeps this block shorter and flexible.';
    final trainingDecision = trainingFirst
        ? 'Training is first because it is your priority and confidence supports normal intensity.'
        : !canTrainNormally
        ? 'Recovery is first and training stays light because readiness or confidence is limited.'
        : '${profile.coachPriority.label} keeps recovery ahead of training in the shared rebound window.';

    final values = <Recommendation?>[
      item(
        slug: 'morning-setup',
        title: 'Start with a calm morning setup',
        detail:
            'Use a short check-in and choose the day’s one most important task.',
        category: 'Morning',
        phase: CoachPlanPhase.morning,
        window: peak,
        scheduledAt: morningAt,
        durationMinutes: 15,
        decisionReason:
            'Anchored to your usual ${_clock(wakeAt)} wake time and ${profile.coachPriority.label.toLowerCase()} priority.',
      ),
      item(
        slug: 'deep-work',
        title: 'Protect a $focusMinutes-minute focus block',
        detail:
            'Use the strongest predicted cognitive stretch for demanding study or focused work.',
        category: 'Deep work',
        phase: CoachPlanPhase.deepWork,
        window: peak,
        scheduledAt: focusAt,
        durationMinutes: focusMinutes,
        decisionReason: profile.coachPriority == CoachPriority.focus
            ? 'Focus-first priority protects the longest safe peak block. $confidenceReason'
            : confidenceReason,
        priority: profile.coachPriority == CoachPriority.focus || highConfidence
            ? RecommendationPriority.important
            : RecommendationPriority.routine,
      ),
      item(
        slug: 'hydration',
        title: 'Hydrate before the predicted dip',
        detail:
            'Use a normal hydration break before the lower-energy stretch begins.',
        category: 'Hydration',
        phase: CoachPlanPhase.midday,
        window: crash,
        scheduledAt: hydrationAt,
        durationMinutes: 10,
        decisionReason: 'Placed before the dip so it does not interrupt rest.',
      ),
      item(
        slug: 'nap',
        title: 'Try a $napMinutes-minute recovery nap',
        detail:
            'Keep the nap brief and use the lowest predicted-energy period.',
        category: 'Nap',
        phase: CoachPlanPhase.nap,
        window: crash,
        scheduledAt: napAt,
        durationMinutes: napMinutes,
        decisionReason: profile.coachPriority == CoachPriority.recovery
            ? 'Recovery-first priority gives the nap five additional minutes.'
            : 'A short duration supports recovery without crowding the rebound.',
        priority:
            profile.coachPriority == CoachPriority.recovery || score.energy < 62
            ? RecommendationPriority.important
            : RecommendationPriority.routine,
      ),
      item(
        slug: 'rebound-recovery',
        title: 'Protect a rebound recovery block',
        detail:
            'Reduce demands while energy begins moving out of its lowest stretch.',
        category: 'Recovery',
        phase: CoachPlanPhase.recovery,
        window: rebound,
        scheduledAt: recoveryAt,
        durationMinutes: recoveryMinutes,
        decisionReason: trainingDecision,
        priority:
            profile.coachPriority == CoachPriority.recovery || !canTrainNormally
            ? RecommendationPriority.important
            : RecommendationPriority.routine,
      ),
      item(
        slug: 'training',
        title: canTrainNormally
            ? 'Place training in the rebound'
            : 'Keep training light and flexible',
        detail: canTrainNormally
            ? 'Use the post-dip rise for planned movement at your normal intensity.'
            : 'Favor easy movement and stop if it does not feel restorative.',
        category: 'Training',
        phase: CoachPlanPhase.training,
        window: rebound,
        scheduledAt: trainingAt,
        durationMinutes: trainingMinutes,
        decisionReason: trainingDecision,
        priority:
            profile.coachPriority == CoachPriority.training && canTrainNormally
            ? RecommendationPriority.important
            : RecommendationPriority.routine,
      ),
      item(
        slug: 'taper',
        title: 'Taper stimulation before bed',
        detail:
            'Lower task intensity, bright-screen exposure, and hard training as bedtime approaches.',
        category: 'Taper',
        phase: CoachPlanPhase.taper,
        window: rebound,
        scheduledAt: taperAt,
        durationMinutes: 30,
        decisionReason:
            'Anchored 90 minutes before your usual ${_clock(bedAt)} bedtime.',
        priority: profile.coachPriority == CoachPriority.recovery
            ? RecommendationPriority.important
            : RecommendationPriority.routine,
      ),
      item(
        slug: 'evening-recovery',
        title: 'Protect your recovery wind-down',
        detail:
            'Use the final block for a consistent, low-demand transition to sleep.',
        category: 'Evening',
        phase: CoachPlanPhase.evening,
        window: rebound,
        scheduledAt: eveningAt,
        durationMinutes: 30,
        decisionReason:
            'Ends near your saved bedtime and keeps the plan morning-to-evening.',
      ),
    ];

    final plan = values.whereType<Recommendation>().toList()
      ..sort((left, right) => left.scheduledAt!.compareTo(right.scheduledAt!));
    return List.unmodifiable(plan);
  }

  static DateTime _atDecimalHour(DateTime day, double hour) =>
      day.add(Duration(minutes: ((hour % 24) * 60).round()));

  static DateTime _clamp(DateTime value, DateTime minimum, DateTime maximum) {
    if (maximum.isBefore(minimum)) return minimum;
    if (value.isBefore(minimum)) return minimum;
    if (value.isAfter(maximum)) return maximum;
    return value;
  }

  static String _dayIdentifier(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  static String _windowLabel(ForecastWindowType type) => switch (type) {
    ForecastWindowType.peak => 'peak-focus',
    ForecastWindowType.crash => 'lower-energy',
    ForecastWindowType.recovery => 'recovery',
  };
}
