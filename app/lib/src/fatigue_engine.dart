import 'dart:math' as math;

import 'models.dart';

abstract final class FatigueEngine {
  static ScoreSnapshot score({
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final recent = signals
        .where((item) => clock.difference(item.timestamp).inHours.abs() <= 36)
        .toList();
    double? value(SignalType type) {
      final matches = recent.where((item) => item.type == type).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return matches.isEmpty ? null : matches.first.value;
    }

    final sleep = value(SignalType.sleep);
    final hydration = value(SignalType.hydration);
    final exercise = value(SignalType.exercise);
    final study = value(SignalType.study);
    final screen = value(SignalType.screenTime);
    final reaction = value(SignalType.reactionTime);
    final hrv = value(SignalType.hrv);
    final restingHr = value(SignalType.restingHeartRate);
    final latestCheckIn = checkIns.isEmpty
        ? null
        : (checkIns.toList()
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp)))
              .first;

    var energy = 58.0;
    final drivers = <ScoreDriver>[];
    if (sleep != null) {
      final impact = ((sleep - 7.5) * 8).clamp(-22, 14).toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Sleep',
          impact,
          '${sleep.toStringAsFixed(1)} hr last night',
        ),
      );
    }
    if (hydration != null) {
      final impact = ((hydration - 1.4) * 7).clamp(-8, 7).toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Hydration',
          impact,
          '${hydration.toStringAsFixed(1)} L logged',
        ),
      );
    }
    if (exercise != null) {
      final impact = exercise > 1.5
          ? -8.0
          : exercise > 0.3
          ? 4.0
          : -1.0;
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Training',
          impact,
          '${exercise.toStringAsFixed(1)} hr load',
        ),
      );
    }
    if (screen != null) {
      final impact = (-(screen - 3).clamp(0, 5) * 2.4).toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Screen time',
          impact,
          '${screen.toStringAsFixed(1)} hr today',
        ),
      );
    }
    if (latestCheckIn != null) {
      final impact =
          ((latestCheckIn.energy - 5.5) * 2.5 -
                  (latestCheckIn.stress - 5.5) * 1.5)
              .clamp(-16, 16)
              .toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver(
          'Check-in',
          impact,
          'Energy ${latestCheckIn.energy.round()}/10 · stress ${latestCheckIn.stress.round()}/10',
        ),
      );
    }
    if (hrv != null) {
      final impact = ((hrv - 48) / 6).clamp(-7, 7).toDouble();
      energy += impact;
      drivers.add(ScoreDriver('HRV', impact, '${hrv.round()} ms'));
    }
    if (restingHr != null) {
      final impact = (-(restingHr - 62) / 3).clamp(-7, 7).toDouble();
      energy += impact;
      drivers.add(
        ScoreDriver('Resting HR', impact, '${restingHr.round()} bpm'),
      );
    }

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
    const expected = <SignalType>{
      SignalType.sleep,
      SignalType.hydration,
      SignalType.exercise,
      SignalType.study,
      SignalType.screenTime,
      SignalType.reactionTime,
    };
    final present = expected
        .where((type) => recent.any((item) => item.type == type))
        .length;
    final wearableBonus = recent.any((item) => item.type == SignalType.hrv)
        ? .08
        : 0;
    final confidence = (.28 + present / expected.length * .57 + wearableBonus)
        .clamp(.25, .95);
    return ScoreSnapshot(
      energy: energy.round().clamp(0, 100),
      cognitive: cognitive.round().clamp(0, 100),
      confidence: confidence,
      drivers: drivers.take(6).toList(),
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
