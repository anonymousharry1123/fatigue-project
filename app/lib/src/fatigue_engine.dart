import 'dart:math' as math;

import 'models.dart';

abstract final class FatigueEngine {
  static ScoreSnapshot score({
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
    DateTime? now,
    DateTime? day,
    ScoreSnapshot? previousDay,
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

    List<SignalReading> readingsFor(SignalType type) =>
        targetDay.where((item) => item.type == type).toList();

    double? totalOf(List<SignalReading> readings) => readings.isEmpty
        ? null
        : readings.fold<double>(0, (sum, item) => sum + item.value);

    final sleepReadings = recent
        .where((item) => item.type == SignalType.sleep)
        .take(3)
        .toList();
    final sleep = sleepReadings.isEmpty
        ? null
        : sleepReadings.fold<double>(0, (sum, item) => sum + item.value) /
              sleepReadings.length;
    final hydrationReadings = readingsFor(SignalType.hydration);
    final exerciseReadings = readingsFor(SignalType.exercise);
    final studyReadings = readingsFor(SignalType.study);
    final screenReadings = readingsFor(SignalType.screenTime);
    final hydration = totalOf(hydrationReadings);
    final exercise = totalOf(exerciseReadings);
    final study = totalOf(studyReadings);
    final screen = totalOf(screenReadings);
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
        _signalDriver(
          'Sleep',
          impact,
          '${sleep.toStringAsFixed(1)} hr ${sleepReadings.length == 1 ? 'last night' : '${sleepReadings.length}-night average'}',
          readings: sleepReadings,
          cutoff: cutoff,
          maximumAge: const Duration(days: 7),
        ),
      );
    }
    if (hydration != null) {
      final impact = ((hydration - 2) * 5).clamp(-8, 6).toDouble();
      energy += impact;
      drivers.add(
        _signalDriver(
          'Hydration',
          impact,
          '${hydration.toStringAsFixed(1)} L logged today',
          readings: hydrationReadings,
          cutoff: cutoff,
          maximumAge: const Duration(hours: 24),
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
        _signalDriver(
          'Exercise',
          impact,
          '${exercise.toStringAsFixed(1)} hr logged today',
          readings: exerciseReadings,
          cutoff: cutoff,
          maximumAge: const Duration(hours: 24),
        ),
      );
    }
    if (study != null) {
      final impact = study <= 2
          ? 2.0
          : (-(study - 4).clamp(0, 4) * 2.5).toDouble();
      energy += impact;
      drivers.add(
        _signalDriver(
          'Workload',
          impact,
          '${study.toStringAsFixed(1)} hr study load today',
          readings: studyReadings,
          cutoff: cutoff,
          maximumAge: const Duration(hours: 24),
        ),
      );
    }
    if (screen != null) {
      final impact = ((3 - screen) * 2).clamp(-10, 4).toDouble();
      energy += impact;
      drivers.add(
        _signalDriver(
          'Screen time',
          impact,
          '${screen.toStringAsFixed(1)} hr logged today',
          readings: screenReadings,
          cutoff: cutoff,
          maximumAge: const Duration(hours: 24),
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
        _checkInDriver(
          'Mood',
          moodImpact,
          '${latestCheckIn.mood.round()}/10 at latest check-in',
          checkIn: latestCheckIn,
          cutoff: cutoff,
        ),
      );
      drivers.add(
        _checkInDriver(
          'Stress',
          stressImpact,
          '${latestCheckIn.stress.round()}/10 at latest check-in',
          checkIn: latestCheckIn,
          cutoff: cutoff,
        ),
      );
    }

    // Version 0.12 Cognitive Score uses a separate explainable factor list.
    // Reaction time is personalized against prior valid tests when available.
    var cognitive = 65.0;
    final cognitiveDrivers = <ScoreDriver>[];
    final currentReaction = targetDay
        .where((item) => item.type == SignalType.reactionTime)
        .firstOrNull;
    final priorReactions =
        signals
            .where(
              (item) =>
                  item.type == SignalType.reactionTime &&
                  item.timestamp.isBefore(start) &&
                  !item.timestamp.isAfter(cutoff),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (currentReaction != null) {
      final baselineReadings = priorReactions.take(14).toList();
      final baseline = baselineReadings.isEmpty
          ? null
          : baselineReadings.fold<double>(0, (sum, item) => sum + item.value) /
                baselineReadings.length;
      final impact = baseline == null
          ? ((330 - currentReaction.value) / 5).clamp(-18, 16).toDouble()
          : (((baseline - currentReaction.value) / baseline) * 120)
                .clamp(-18, 18)
                .toDouble();
      cognitive += impact;
      cognitiveDrivers.add(
        _signalDriver(
          'Reaction time',
          impact,
          baseline == null
              ? '${currentReaction.value.round()} ms · personal baseline building'
              : '${currentReaction.value.round()} ms vs ${baseline.round()} ms baseline',
          readings: [currentReaction],
          cutoff: cutoff,
          maximumAge: const Duration(hours: 24),
        ),
      );
    }
    if (sleep != null) {
      final impact = ((sleep - 7.5) * 6).clamp(-16, 10).toDouble();
      cognitive += impact;
      cognitiveDrivers.add(
        _signalDriver(
          'Sleep',
          impact,
          '${sleep.toStringAsFixed(1)} hr ${sleepReadings.length == 1 ? 'last night' : '${sleepReadings.length}-night average'}',
          readings: sleepReadings,
          cutoff: cutoff,
          maximumAge: const Duration(days: 7),
        ),
      );
    }
    if (study != null) {
      final impact = study <= 2
          ? 3.0
          : (-(study - 4).clamp(0, 4) * 3).toDouble();
      cognitive += impact;
      cognitiveDrivers.add(
        _signalDriver(
          'Study load',
          impact,
          '${study.toStringAsFixed(1)} hr logged today',
          readings: studyReadings,
          cutoff: cutoff,
          maximumAge: const Duration(hours: 24),
        ),
      );
    }
    if (latestCheckIn != null) {
      final moodImpact = ((latestCheckIn.mood - 5.5) * 1.5)
          .clamp(-7, 7)
          .toDouble();
      final stressImpact = ((5.5 - latestCheckIn.stress) * 2)
          .clamp(-9, 9)
          .toDouble();
      cognitive += moodImpact + stressImpact;
      cognitiveDrivers.add(
        _checkInDriver(
          'Mood',
          moodImpact,
          '${latestCheckIn.mood.round()}/10 at latest check-in',
          checkIn: latestCheckIn,
          cutoff: cutoff,
        ),
      );
      cognitiveDrivers.add(
        _checkInDriver(
          'Stress',
          stressImpact,
          '${latestCheckIn.stress.round()}/10 at latest check-in',
          checkIn: latestCheckIn,
          cutoff: cutoff,
        ),
      );
    }

    _rankDrivers(drivers);
    final inputCount = drivers.length.clamp(0, 7);
    final freshness = _averageFreshness(drivers);
    final confidence = _confidence(
      inputCount: inputCount,
      expectedInputs: 7,
      freshness: freshness,
    );
    _rankDrivers(cognitiveDrivers);
    final cognitiveInputCount = cognitiveDrivers.length.clamp(0, 5);
    final cognitiveFreshness = _averageFreshness(cognitiveDrivers);
    final cognitiveConfidence = _confidence(
      inputCount: cognitiveInputCount,
      expectedInputs: 5,
      freshness: cognitiveFreshness,
    );
    final previousCognitive = previousDay?.hasCognitiveScore == true
        ? previousDay!.cognitive
        : null;
    return ScoreSnapshot(
      energy: energy.round().clamp(0, 100),
      cognitive: cognitive.round().clamp(0, 100),
      confidence: confidence,
      drivers: List.unmodifiable(drivers),
      cognitiveConfidence: cognitiveConfidence,
      cognitiveDrivers: List.unmodifiable(cognitiveDrivers),
      cognitiveInputCount: cognitiveInputCount,
      hasCognitiveScore: true,
      previousCognitive: previousCognitive,
      day: start,
      calculatedAt: clock,
      inputCount: inputCount,
      isEstimate: true,
      freshness: freshness,
      cognitiveFreshness: cognitiveFreshness,
    );
  }

  static ScoreDriver _signalDriver(
    String label,
    double contribution,
    String detail, {
    required List<SignalReading> readings,
    required DateTime cutoff,
    required Duration maximumAge,
  }) {
    final sorted = [...readings]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return ScoreDriver(
      label,
      contribution,
      detail,
      explanation: _explanation(label, contribution),
      freshness: _signalFreshness(
        sorted,
        cutoff: cutoff,
        maximumAge: maximumAge,
      ),
      source: sorted.firstOrNull?.source,
      evidenceAt: sorted.firstOrNull?.timestamp,
    );
  }

  static ScoreDriver _checkInDriver(
    String label,
    double contribution,
    String detail, {
    required DailyCheckIn checkIn,
    required DateTime cutoff,
  }) => ScoreDriver(
    label,
    contribution,
    detail,
    explanation: _explanation(label, contribution),
    freshness: _timeFreshness(
      checkIn.timestamp,
      cutoff: cutoff,
      maximumAge: const Duration(hours: 36),
    ),
    evidenceAt: checkIn.timestamp,
  );

  static double _signalFreshness(
    List<SignalReading> readings, {
    required DateTime cutoff,
    required Duration maximumAge,
  }) {
    if (readings.isEmpty) return 0;
    final total = readings.fold<double>(0, (sum, reading) {
      final recency = _timeFreshness(
        reading.timestamp,
        cutoff: cutoff,
        maximumAge: maximumAge,
      );
      final sourceWeight = switch (reading.source) {
        SignalSource.healthKit => 1.0,
        SignalSource.manual => .95,
        SignalSource.model => .8,
      };
      return sum + recency * sourceWeight * reading.quality.clamp(0, 1);
    });
    return (total / readings.length).clamp(0, 1);
  }

  static double _timeFreshness(
    DateTime timestamp, {
    required DateTime cutoff,
    required Duration maximumAge,
  }) {
    final age = cutoff.difference(timestamp);
    if (age.isNegative) return 0;
    final ageRatio = age.inMinutes / maximumAge.inMinutes;
    return (.15 + .85 * (1 - ageRatio).clamp(0, 1)).clamp(0, 1);
  }

  static double _averageFreshness(List<ScoreDriver> drivers) {
    if (drivers.isEmpty) return 0;
    return drivers.fold<double>(
          0,
          (sum, driver) => sum + (driver.freshness ?? 0),
        ) /
        drivers.length;
  }

  static double _confidence({
    required int inputCount,
    required int expectedInputs,
    required double freshness,
  }) {
    final completeness = (inputCount / expectedInputs).clamp(0, 1);
    return (.2 + completeness * .55 + freshness * .2).clamp(.2, .95);
  }

  static void _rankDrivers(List<ScoreDriver> drivers) {
    drivers.sort((left, right) {
      final leftGroup = left.isPositive
          ? 0
          : left.isNegative
          ? 1
          : 2;
      final rightGroup = right.isPositive
          ? 0
          : right.isNegative
          ? 1
          : 2;
      if (leftGroup != rightGroup) return leftGroup.compareTo(rightGroup);
      if (left.isPositive) {
        return right.contribution.compareTo(left.contribution);
      }
      if (left.isNegative) {
        return left.contribution.compareTo(right.contribution);
      }
      return left.label.compareTo(right.label);
    });
  }

  static String _explanation(String label, double contribution) {
    final positive = contribution > .01;
    final negative = contribution < -.01;
    return switch (label) {
      'Sleep' =>
        positive
            ? 'Recent sleep duration supported recovery and readiness.'
            : negative
            ? 'Recent sleep duration was below the model’s recovery range.'
            : 'Recent sleep duration was close to the neutral range.',
      'Hydration' =>
        positive
            ? 'Logged hydration was above the model’s daily reference level.'
            : negative
            ? 'Logged hydration was below the model’s daily reference level.'
            : 'Logged hydration was close to the daily reference level.',
      'Exercise' =>
        positive
            ? 'Today’s movement was within the model’s supportive range.'
            : negative
            ? 'Today’s training load was outside the model’s recovery range.'
            : 'Today’s movement had a neutral estimated effect.',
      'Workload' || 'Study load' =>
        positive
            ? 'Study load stayed within a manageable range for today.'
            : negative
            ? 'A heavier study load reduced the current readiness estimate.'
            : 'Study load was close to the model’s neutral range.',
      'Screen time' =>
        positive
            ? 'Lower screen exposure supported today’s recovery estimate.'
            : negative
            ? 'Higher screen exposure reduced today’s recovery estimate.'
            : 'Screen exposure was close to the model’s neutral range.',
      'Reaction time' =>
        positive
            ? 'Reaction performance was faster than the current reference.'
            : negative
            ? 'Reaction performance was slower than the current reference.'
            : 'Reaction performance was close to the current reference.',
      'Mood' =>
        positive
            ? 'The latest mood check-in supported the readiness estimate.'
            : negative
            ? 'The latest mood check-in reduced the readiness estimate.'
            : 'The latest mood check-in had a neutral estimated effect.',
      'Stress' =>
        positive
            ? 'Lower reported stress supported the readiness estimate.'
            : negative
            ? 'Higher reported stress reduced the readiness estimate.'
            : 'Reported stress was close to the neutral range.',
      _ =>
        positive
            ? '$label supported today’s estimate.'
            : negative
            ? '$label reduced today’s estimate.'
            : '$label had a neutral estimated effect.',
    };
  }

  /// Generates one point per waking hour from the user's known evidence.
  ///
  /// The model deliberately remains deterministic and explainable: the daily
  /// score provides the anchor, while recent sleep timing shifts the circadian
  /// curve, accumulated study/exercise adds workload, and hydration/check-ins
  /// influence recovery. Uncertainty rises when evidence is incomplete, stale,
  /// or farther into the future.
  static List<ForecastPoint> forecast(
    ScoreSnapshot score,
    DateTime day, {
    List<SignalReading> signals = const [],
    List<DailyCheckIn> checkIns = const [],
    UserProfile profile = const UserProfile(),
    DateTime? generatedAt,
  }) {
    final targetDay = DateTime(day.year, day.month, day.day);
    final clock = generatedAt ?? DateTime.now();
    final usualWakeHour = profile.wakeHour.isFinite
        ? profile.wakeHour.clamp(4.0, 11.0)
        : 7.0;
    final usualBedHour = profile.bedHour.isFinite
        ? profile.bedHour.clamp(20.0, 25.0)
        : 23.0;
    final evidenceCutoff =
        clock.isBefore(targetDay.add(const Duration(days: 1)))
        ? clock
        : targetDay.add(const Duration(days: 1));
    final recentStart = targetDay.subtract(const Duration(days: 7));
    final recentSignals =
        signals
            .where(
              (item) =>
                  !item.timestamp.isBefore(recentStart) &&
                  !item.timestamp.isAfter(evidenceCutoff) &&
                  item.value.isFinite,
            )
            .toList()
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    final recentCheckIns =
        checkIns
            .where(
              (item) =>
                  !item.timestamp.isBefore(recentStart) &&
                  !item.timestamp.isAfter(evidenceCutoff) &&
                  item.energy.isFinite &&
                  item.mood.isFinite &&
                  item.stress.isFinite,
            )
            .toList()
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));

    List<SignalReading> readings(SignalType type) => recentSignals
        .where((item) => item.type == type)
        .toList(growable: false);

    double? average(Iterable<double> values) {
      final items = values.toList(growable: false);
      return items.isEmpty
          ? null
          : items.reduce((left, right) => left + right) / items.length;
    }

    double circularHourAverage(Iterable<double> values) {
      final normalized = values
          .map((value) => value < 12 ? value + 24 : value)
          .toList(growable: false);
      return average(normalized) ?? usualBedHour;
    }

    final sleepReadings = readings(SignalType.sleep).take(3).toList();
    final bedtimeReadings = readings(SignalType.bedtime).take(5).toList();
    final sleepHours = average(sleepReadings.map((item) => item.value));
    final observedBedtime = bedtimeReadings.isEmpty
        ? null
        : circularHourAverage(bedtimeReadings.map((item) => item.value));
    final observedWake = sleepReadings.isEmpty
        ? null
        : average(
            sleepReadings.map(
              (item) => item.timestamp.hour + item.timestamp.minute / 60,
            ),
          );

    // Blend recent observations with the saved schedule so a single unusual
    // night can adjust, but not completely overturn, the user's rhythm.
    final wakeHour = observedWake == null
        ? usualWakeHour
        : usualWakeHour * .4 + observedWake * .6;
    final bedtime = observedBedtime == null
        ? usualBedHour
        : usualBedHour * .4 + observedBedtime * .6;
    final scheduleShift = ((bedtime - usualBedHour) * .2).clamp(-1.0, 1.0);
    final circadianWake = wakeHour + scheduleShift;

    final forecastStartHour = usualWakeHour.round();
    // A daily Firestore query owns one calendar day. Bedtimes after midnight
    // are represented by the final 11 PM point instead of leaking documents
    // into the following day's range.
    final forecastEndHour = usualBedHour.round().clamp(
      forecastStartHour + 10,
      23,
    );

    final sameDaySignals = recentSignals
        .where(
          (item) =>
              !item.timestamp.isBefore(targetDay) &&
              item.timestamp.isBefore(targetDay.add(const Duration(days: 1))),
        )
        .toList();
    double modeledDailyTotal(SignalType type) {
      final sameDay = sameDaySignals
          .where((item) => item.type == type)
          .toList();
      if (sameDay.isNotEmpty) {
        return sameDay.fold(0, (sum, item) => sum + item.value);
      }
      final byDay = <String, double>{};
      for (final item in readings(type)) {
        final key =
            '${item.timestamp.year}-${item.timestamp.month}-${item.timestamp.day}';
        byDay.update(
          key,
          (value) => value + item.value,
          ifAbsent: () => item.value,
        );
      }
      return average(byDay.values.take(3)) ?? 0;
    }

    final studyHours = modeledDailyTotal(SignalType.study);
    final exerciseHours = modeledDailyTotal(SignalType.exercise);
    final hydrationLiters = modeledDailyTotal(SignalType.hydration);
    final latestCheckIn = recentCheckIns.firstOrNull;
    final sleepAdjustment = sleepHours == null
        ? 0.0
        : ((sleepHours - 7.5) * 3.2).clamp(-8.0, 5.0);
    final checkInAdjustment = latestCheckIn == null
        ? 0.0
        : ((latestCheckIn.energy - 5.5) * 1.1 +
                  (latestCheckIn.mood - 5.5) * .45 -
                  (latestCheckIn.stress - 5.5) * .65)
              .clamp(-8.0, 8.0);
    final hydrationAdjustment = hydrationLiters == 0
        ? 0.0
        : ((hydrationLiters - 2) * 1.8).clamp(-3.0, 3.0);
    final workload = studyHours + exerciseHours * 1.4;

    final evidenceGroups = <bool>[
      sleepReadings.isNotEmpty,
      bedtimeReadings.isNotEmpty,
      readings(SignalType.study).isNotEmpty ||
          readings(SignalType.exercise).isNotEmpty,
      readings(SignalType.hydration).isNotEmpty || latestCheckIn != null,
    ];
    final coverage = evidenceGroups.where((present) => present).length / 4;
    const forecastSignalTypes = {
      SignalType.sleep,
      SignalType.bedtime,
      SignalType.study,
      SignalType.exercise,
      SignalType.hydration,
    };
    final newestEvidence =
        <DateTime>[
          ...recentSignals
              .where((item) => forecastSignalTypes.contains(item.type))
              .map((item) => item.timestamp),
          ...recentCheckIns.map((item) => item.timestamp),
        ].fold<DateTime?>(
          null,
          (latest, value) =>
              latest == null || value.isAfter(latest) ? value : latest,
        );
    final evidenceAgeHours = newestEvidence == null
        ? 168.0
        : math.max(0, clock.difference(newestEvidence).inMinutes / 60);
    final freshness = (1 - evidenceAgeHours / 168).clamp(0.0, 1.0);
    final modelConfidence =
        (score.confidence * .55 + coverage * .25 + freshness * .2).clamp(
          .2,
          .95,
        );

    return List.generate(forecastEndHour - forecastStartHour + 1, (index) {
      final hour = forecastStartHour + index;
      final time = targetDay.add(Duration(hours: hour));
      final hoursAwake = hour - circadianWake;
      final circadian =
          10 * math.sin(2 * math.pi * (hour - (circadianWake - 2)) / 24);
      final sleepInertia = 7 * math.exp(-math.pow(hoursAwake / 1.15, 2));
      final afternoonDip =
          12 * math.exp(-math.pow((hoursAwake - 8.5) / 1.8, 2));
      final rebound = 5 * math.exp(-math.pow((hoursAwake - 12.5) / 2.0, 2));
      final lateDayDecline = math.max(0, hoursAwake - 14) * 1.5;
      final workloadProgress = ((hoursAwake - 4) / 9).clamp(0.0, 1.0);
      final workloadPenalty =
          math.max(0, workload - 3) * 1.35 * workloadProgress;
      final moderateMovementRecovery = exerciseHours > 0 && exerciseHours <= 1.5
          ? 2.0 * math.exp(-math.pow((hoursAwake - 11) / 3.0, 2))
          : 0.0;
      final energy =
          (score.energy +
                  sleepAdjustment +
                  checkInAdjustment +
                  hydrationAdjustment +
                  circadian -
                  sleepInertia -
                  afternoonDip +
                  rebound -
                  lateDayDecline -
                  workloadPenalty +
                  moderateMovementRecovery)
              .clamp(5.0, 98.0);
      final horizonHours = math.max(0, time.difference(clock).inMinutes / 60);
      final uncertainty =
          (5 + (1 - modelConfidence) * 24 + horizonHours / 24 * 2.5).clamp(
            5.0,
            35.0,
          );
      return ForecastPoint(time, energy, uncertainty, updatedAt: clock);
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
