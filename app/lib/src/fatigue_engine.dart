import 'dart:math' as math;

import 'models.dart';

abstract final class FatigueEngine {
  static ScoreSnapshot score({
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
    DateTime? now,
    DateTime? day,
  }) {
    final clock = now ?? DateTime.now();
    final target = day ?? clock;
    final start = DateTime(target.year, target.month, target.day);
    final end = start.add(const Duration(days: 1));
    final cutoff = !clock.isBefore(start) && clock.isBefore(end) ? clock : end;
    final recentStart = start.subtract(const Duration(days: 6));
    final recent =
        signals
            .where(
              (item) =>
                  !item.timestamp.isBefore(recentStart) &&
                  item.timestamp.isBefore(end) &&
                  !item.timestamp.isAfter(cutoff),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final targetDay = recent
        .where((item) => !item.timestamp.isBefore(start))
        .toList();

    double? dailyTotal(SignalType type) {
      final values = targetDay.where((item) => item.type == type).toList();
      if (values.isEmpty) return null;
      return values.fold<double>(0, (sum, item) => sum + item.value);
    }

    final sleepReadings = recent
        .where((item) => item.type == SignalType.sleep)
        .take(3)
        .toList();
    final sleep = sleepReadings.isEmpty
        ? null
        : sleepReadings.fold<double>(0, (sum, item) => sum + item.value) /
              sleepReadings.length;
    final hydration = dailyTotal(SignalType.hydration);
    final exercise = dailyTotal(SignalType.exercise);
    final study = dailyTotal(SignalType.study);
    final screen = dailyTotal(SignalType.screenTime);
    final applicableCheckIns =
        checkIns
            .where(
              (item) =>
                  !item.timestamp.isBefore(
                    start.subtract(const Duration(hours: 36)),
                  ) &&
                  item.timestamp.isBefore(end) &&
                  !item.timestamp.isAfter(cutoff),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final latestCheckIn = applicableCheckIns.firstOrNull;

    // A neutral estimate starts at 60. Every available input contributes an
    // independently bounded adjustment so the result remains explainable.
    var energy = 60.0;
    final drivers = <ScoreDriver>[];
    if (sleep != null) {
      final impact = ((sleep - 7.5) * 8).clamp(-20, 10).toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Sleep',
          impact,
          '${sleep.toStringAsFixed(1)} hr ${sleepReadings.length == 1 ? 'last night' : '${sleepReadings.length}-night average'}',
        ),
      );
    }
    if (hydration != null) {
      final impact = ((hydration - 2) * 5).clamp(-8, 6).toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Hydration',
          impact,
          '${hydration.toStringAsFixed(1)} L logged today',
        ),
      );
    }
    if (exercise != null) {
      final impact = switch (exercise) {
        < .25 => -2.0,
        <= 1.5 => 5.0,
        <= 2.5 => 1.0,
        _ => -7.0,
      };
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Exercise',
          impact,
          '${exercise.toStringAsFixed(1)} hr logged today',
        ),
      );
    }
    if (study != null) {
      final impact = study <= 2
          ? 2.0
          : (-(study - 4).clamp(0, 4) * 2.5).toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Workload',
          impact,
          '${study.toStringAsFixed(1)} hr study load today',
        ),
      );
    }
    if (screen != null) {
      final impact = ((3 - screen) * 2).clamp(-10, 4).toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Screen time',
          impact,
          '${screen.toStringAsFixed(1)} hr logged today',
        ),
      );
    }
    if (latestCheckIn != null) {
      final moodImpact = ((latestCheckIn.mood - 5.5) * 1.8)
          .clamp(-8, 8)
          .toDouble();
      final stressImpact = ((5.5 - latestCheckIn.stress) * 2)
          .clamp(-9, 9)
          .toDouble();
      energy += moodImpact + stressImpact;
      drivers.add(
        ScoreDriver(
          'Mood',
          moodImpact,
          '${latestCheckIn.mood.round()}/10 at latest check-in',
        ),
      );
      drivers.add(
        ScoreDriver(
          'Stress',
          stressImpact,
          '${latestCheckIn.stress.round()}/10 at latest check-in',
        ),
      );
    }

    // Cognitive remains a local preview until Version 0.12 and is not written
    // by the Version 0.11 cloud serializer.
    final reaction = recent
        .where((item) => item.type == SignalType.reactionTime)
        .firstOrNull
        ?.value;
    var cognitive = 64.0;
    if (reaction != null) cognitive += ((330 - reaction) / 5).clamp(-18, 16);
    if (sleep != null) cognitive += ((sleep - 7.5) * 6).clamp(-16, 12);
    if (study != null) cognitive -= ((study - 3).clamp(0, 5) * 3);
    if (latestCheckIn != null) {
      cognitive += (latestCheckIn.mood - 5.5) * 1.5;
      cognitive -= (latestCheckIn.stress - 5.5) * 2;
    }

    drivers.sort(
      (a, b) => b.contribution.abs().compareTo(a.contribution.abs()),
    );
    final inputCount = drivers.length.clamp(0, 7);
    final confidence = (.2 + inputCount / 7 * .75).clamp(.2, .95);
    return ScoreSnapshot(
      energy: energy.round().clamp(0, 100),
      cognitive: cognitive.round().clamp(0, 100),
      confidence: confidence,
      drivers: List.unmodifiable(drivers),
      day: start,
      calculatedAt: clock,
      inputCount: inputCount,
      isEstimate: true,
    );
  }

  static List<ForecastPoint> forecast(ScoreSnapshot score, DateTime day) {
    final start = DateTime(day.year, day.month, day.day, 6);
    return List.generate(17, (index) {
      final hour = 6 + index;
      final circadian = 13 * math.sin(((hour - 7) / 15) * math.pi);
      final afternoonDip = 18 * math.exp(-math.pow((hour - 16.5) / 2.0, 2));
      final rebound = 6 * math.exp(-math.pow((hour - 20.5) / 1.7, 2));
      final energy = (score.energy + circadian - afternoonDip + rebound)
          .clamp(12, 96)
          .toDouble();
      return ForecastPoint(
        start.add(Duration(hours: index)),
        energy,
        (100 - score.confidence * 100) * (.7 + index / 50),
      );
    });
  }

  static List<ForecastWindow> windows(
    List<ForecastPoint> points,
    ScoreSnapshot score,
  ) {
    if (points.isEmpty) return const [];
    final peak = points.reduce((a, b) => a.energy > b.energy ? a : b);
    final crashCandidates = points
        .where((point) => point.time.hour >= 13)
        .toList();
    final crash = crashCandidates.reduce((a, b) => a.energy < b.energy ? a : b);
    final recoveryCandidates = points
        .where((point) => point.time.isAfter(crash.time))
        .toList();
    final recovery = recoveryCandidates.isEmpty
        ? points.last
        : recoveryCandidates.reduce((a, b) => a.energy > b.energy ? a : b);
    return [
      ForecastWindow(
        ForecastWindowType.peak,
        peak.time.subtract(const Duration(minutes: 45)),
        peak.time.add(const Duration(minutes: 75)),
        peak.energy.round(),
        'Best focus window based on today’s recovery signals',
      ),
      ForecastWindow(
        ForecastWindowType.crash,
        crash.time.subtract(const Duration(minutes: 45)),
        crash.time.add(const Duration(minutes: 45)),
        crash.energy.round(),
        score.drivers.isEmpty
            ? 'Expected circadian dip'
            : '${score.drivers.first.label} and circadian load compound',
      ),
      ForecastWindow(
        ForecastWindowType.recovery,
        recovery.time.subtract(const Duration(minutes: 30)),
        recovery.time.add(const Duration(minutes: 60)),
        recovery.energy.round(),
        'A lighter workload supports a gradual rebound',
      ),
    ];
  }

  static List<Recommendation> recommendations(
    List<ForecastWindow> windows,
    ScoreSnapshot score,
  ) {
    String time(ForecastWindowType type) {
      final window = windows.firstWhere((item) => item.type == type);
      return _hour(window.start);
    }

    final items = <Recommendation>[
      Recommendation(
        id: 'focus',
        title: 'Protect a 60-minute focus block',
        detail:
            'Your highest predicted energy and cognitive readiness overlap here.',
        timeLabel: time(ForecastWindowType.peak),
        category: 'Study',
      ),
      Recommendation(
        id: 'dip',
        title: score.energy < 58
            ? 'Take a 20-minute recovery nap'
            : 'Use the dip for lighter work',
        detail:
            'A short reset is better aligned with the predicted afternoon dip.',
        timeLabel: time(ForecastWindowType.crash),
        category: 'Recovery',
      ),
      Recommendation(
        id: 'training',
        title: score.energy > 70
            ? 'Train with normal intensity'
            : 'Taper today’s training load',
        detail: score.energy > 70
            ? 'Recovery signals support your planned session.'
            : 'Lower intensity protects recovery while readiness rebuilds.',
        timeLabel: time(ForecastWindowType.recovery),
        category: 'Training',
      ),
    ];
    return items;
  }

  static List<RiskAlert> alerts(
    List<SignalReading> signals,
    List<DailyCheckIn> checkIns,
    ScoreSnapshot score,
  ) {
    final alerts = <RiskAlert>[];
    final recentSleep = signals
        .where((item) => item.type == SignalType.sleep)
        .take(4)
        .toList();
    if (recentSleep.length >= 2 &&
        recentSleep.take(3).every((item) => item.value < 6.5)) {
      alerts.add(
        const RiskAlert(
          'Sleep debt building',
          'Several short nights are lowering the recovery estimate.',
          AlertSeverity.caution,
        ),
      );
    }
    final exercise = signals
        .where((item) => item.type == SignalType.exercise)
        .take(5)
        .fold<double>(0, (sum, item) => sum + item.value);
    if (exercise > 6 && score.energy < 60) {
      alerts.add(
        const RiskAlert(
          'Recovery may be lagging',
          'Recent training load and lower energy suggest an easier session.',
          AlertSeverity.high,
        ),
      );
    }
    final strained = checkIns
        .take(5)
        .where((item) => item.stress >= 7 && item.energy <= 4)
        .length;
    if (strained >= 3) {
      alerts.add(
        const RiskAlert(
          'Sustained fatigue pattern',
          'Repeated low-energy, high-stress check-ins deserve recovery time and support.',
          AlertSeverity.high,
        ),
      );
    }
    return alerts;
  }

  static String _hour(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
  }
}
