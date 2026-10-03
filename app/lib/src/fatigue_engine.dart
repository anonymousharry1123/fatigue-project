import 'dart:math' as math;

import 'activity_sync_logic.dart';
import 'models.dart';
import 'personal_baseline_logic.dart';
import 'screen_time_logic.dart';
import 'sleep_sync_logic.dart';

abstract final class FatigueEngine {
  // Versioned separately from the app and the optional learned correction.
  static const energyModelVersion = 'energy-rules-v3-phase1';
  static const cognitiveModelVersion = 'cognitive-rules-v3-phase1';

  static ScoreSnapshot score({
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
    DateTime? now,
    DateTime? day,
    ScoreSnapshot? previousDay,
    PersonalBaselines? personalBaselines,
  }) {
    final clock = now ?? DateTime.now();
    final target = (day ?? clock).toLocal();
    final start = DateTime(target.year, target.month, target.day);
    final end = DateTime(start.year, start.month, start.day + 1);
    final cutoff = clock.isBefore(end) ? clock : end;
    final recentStart = DateTime(start.year, start.month, start.day - 6);
    final recent =
        signals
            .where(
              (item) =>
                  !item.timestamp.isBefore(recentStart) &&
                  item.timestamp.isBefore(end) &&
                  !item.timestamp.isAfter(cutoff) &&
                  _isUsableSignal(item),
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

    final hydrationAggregate = ActivitySyncLogic.aggregateForDay(
      targetDay,
      type: SignalType.hydration,
      day: start,
    );
    final exerciseAggregate = ActivitySyncLogic.aggregateForDay(
      targetDay,
      type: SignalType.exercise,
      day: start,
    );
    final stepsAggregate = ActivitySyncLogic.aggregateForDay(
      targetDay,
      type: SignalType.steps,
      day: start,
    );
    final hydrationReadings = hydrationAggregate?.evidence ?? const [];
    final exerciseReadings = exerciseAggregate?.evidence ?? const [];
    final stepReadings = stepsAggregate?.evidence ?? const [];
    final studyReadings = readingsFor(SignalType.study);
    final screenReadings = ScreenTimeLogic.modelReadings(
      readingsFor(SignalType.screenTime),
    );
    final hydration = hydrationAggregate?.total;
    final exercise = exerciseAggregate?.total;
    final steps = stepsAggregate?.total;
    final study = totalOf(studyReadings);
    final screen = totalOf(screenReadings);
    final applicableCheckIns =
        checkIns
            .where(
              (item) =>
                  !item.timestamp.isBefore(start) &&
                  item.timestamp.isBefore(end) &&
                  !item.timestamp.isAfter(cutoff) &&
                  _isUsableCheckIn(item),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final latestCheckIn = applicableCheckIns.firstOrNull;
    final currentHrv = PersonalBaselineLogic.currentValue(
      PersonalBaselineType.hrv,
      signals: targetDay,
      day: start,
    );
    final currentRestingHeartRate = PersonalBaselineLogic.currentValue(
      PersonalBaselineType.restingHeartRate,
      signals: targetDay,
      day: start,
    );

    // Experimental legacy coefficients, not validated biological weights.
    // The neutral internal value is hidden when no current scored input exists.
    // Sleep guidance is deliberately separate from these composites.
    var energy = 60.0;
    final drivers = <ScoreDriver>[];
    if (personalBaselines != null && currentHrv != null) {
      final readings = readingsFor(SignalType.hrv);
      final baseline = personalBaselines.metric(PersonalBaselineType.hrv);
      final difference = PersonalBaselineLogic.differencePercent(
        current: currentHrv,
        baseline: baseline,
      );
      final impact = difference == null
          ? 0.0
          : (difference * .22).clamp(-8.0, 8.0);
      energy += impact;
      drivers.add(
        _signalDriver(
          'HRV vs baseline',
          impact,
          '${currentHrv.round()} ms${_baselineDetail(baseline, current: currentHrv)}',
          explanation: baseline?.isReady == true
              ? null
              : 'Recorded observation only while your personal baseline is building; no score points or data coverage.',
          readings: readings,
          cutoff: cutoff,
          maximumAge: const Duration(hours: 36),
        ),
      );
    }
    if (personalBaselines != null && currentRestingHeartRate != null) {
      final readings = readingsFor(SignalType.restingHeartRate);
      final baseline = personalBaselines.metric(
        PersonalBaselineType.restingHeartRate,
      );
      final difference = PersonalBaselineLogic.differencePercent(
        current: currentRestingHeartRate,
        baseline: baseline,
      );
      final impact = difference == null
          ? 0.0
          : (-difference * .3).clamp(-8.0, 8.0);
      energy += impact;
      drivers.add(
        _signalDriver(
          'Resting HR vs baseline',
          impact,
          '${currentRestingHeartRate.round()} bpm${_baselineDetail(baseline, current: currentRestingHeartRate)}',
          explanation: baseline?.isReady == true
              ? null
              : 'Recorded observation only while your personal baseline is building; no score points or data coverage.',
          readings: readings,
          cutoff: cutoff,
          maximumAge: const Duration(hours: 36),
        ),
      );
    }
    if (hydration != null) {
      const impact = 0.0;
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
      const impact = 0.0;
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
    } else if (steps != null) {
      // Activity observations remain available without recovery point rewards.
      const impact = 0.0;
      energy += impact;
      drivers.add(
        _signalDriver(
          'Movement',
          impact,
          '${steps.round()} steps from Apple Health today',
          readings: stepReadings,
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
      final impact = ((3 - screen) * 2).clamp(-16, 4).toDouble();
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
    final caffeineReadings = readingsFor(SignalType.caffeine);
    final caffeine = totalOf(caffeineReadings);
    if (caffeine != null) {
      // Optional contextual logging is not a stimulant recommendation.
      const impact = 0.0;
      energy += impact;
      drivers.add(
        _signalDriver(
          'Caffeine',
          impact,
          '${caffeine.toStringAsFixed(0)} drinks today',
          readings: caffeineReadings,
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
                  _isUsableSignal(item) &&
                  item.timestamp.isBefore(start) &&
                  !item.timestamp.isAfter(cutoff),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (currentReaction != null) {
      final baselineReadings = priorReactions.take(14).toList();
      final reactionMetric = personalBaselines?.metric(
        PersonalBaselineType.reactionTime,
      );
      final baseline = personalBaselines == null
          ? baselineReadings.isEmpty
                ? null
                : baselineReadings.fold<double>(
                        0,
                        (sum, item) => sum + item.value,
                      ) /
                      baselineReadings.length
          : reactionMetric?.isReady == true
          ? reactionMetric!.value
          : null;
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
              ? '${currentReaction.value.round()} ms · personal baseline building${reactionMetric == null ? '' : ' (${reactionMetric.sampleCount}/${reactionMetric.minimumSamples})'}'
              : '${currentReaction.value.round()} ms vs ${baseline.round()} ms baseline',
          readings: [currentReaction],
          cutoff: cutoff,
          maximumAge: const Duration(hours: 24),
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
    if (screen != null) {
      // Folded screen+social competes with focus; keep mild use near-neutral.
      final impact = ((3 - screen) * 2.5).clamp(-14, 4).toDouble();
      cognitive += impact;
      cognitiveDrivers.add(
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
    // Context-only logs do not establish score availability or data coverage.
    final energyEvidence = drivers.where((driver) {
      if (_contextOnlyLabels.contains(driver.label)) return false;
      // A current heart observation cannot turn the internal neutral default
      // into an estimate until the existing comparison baseline is ready.
      return switch (driver.label) {
        'HRV vs baseline' =>
          personalBaselines?.metric(PersonalBaselineType.hrv)?.isReady == true,
        'Resting HR vs baseline' =>
          personalBaselines
                  ?.metric(PersonalBaselineType.restingHeartRate)
                  ?.isReady ==
              true,
        _ => true,
      };
    }).toList();
    final inputCount = energyEvidence.length.clamp(0, 6);
    final freshness = _averageFreshness(energyEvidence);
    final energyBaselineTypes = <PersonalBaselineType>[
      if (energyEvidence.any((driver) => driver.label == 'HRV vs baseline'))
        PersonalBaselineType.hrv,
      if (energyEvidence.any(
        (driver) => driver.label == 'Resting HR vs baseline',
      ))
        PersonalBaselineType.restingHeartRate,
    ];
    final energyBaselineReadiness = personalBaselines?.readinessFor(
      energyBaselineTypes,
    );
    final confidence = _applyBaselineReadiness(
      _confidence(
        inputCount: inputCount,
        expectedInputs: 6,
        freshness: freshness,
      ),
      energyBaselineReadiness,
    );
    _rankDrivers(cognitiveDrivers);
    final cognitiveEvidence = cognitiveDrivers
        .where((driver) => !_contextOnlyLabels.contains(driver.label))
        .toList();
    final cognitiveInputCount = cognitiveEvidence.length.clamp(0, 5);
    final cognitiveFreshness = _averageFreshness(cognitiveEvidence);
    final cognitiveBaselineTypes = <PersonalBaselineType>[
      if (currentReaction != null) PersonalBaselineType.reactionTime,
    ];
    final cognitiveConfidence = _applyBaselineReadiness(
      _confidence(
        inputCount: cognitiveInputCount,
        expectedInputs: 5,
        freshness: cognitiveFreshness,
      ),
      personalBaselines?.readinessFor(cognitiveBaselineTypes),
    );
    final previousCognitive =
        previousDay?.canEstimateCognitive == true &&
            previousDay?.cognitiveModelVersion == cognitiveModelVersion
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
      hasEnergyScore: inputCount > 0,
      hasCognitiveScore: cognitiveInputCount > 0,
      previousCognitive: previousCognitive,
      day: start,
      calculatedAt: clock,
      inputCount: inputCount,
      isEstimate: true,
      freshness: freshness,
      cognitiveFreshness: cognitiveFreshness,
      personalBaselines: personalBaselines,
      baselineConfidence: personalBaselines?.overallReadiness ?? 0,
      energyModelVersion: energyModelVersion,
      cognitiveModelVersion: cognitiveModelVersion,
    );
  }

  static const _contextOnlyLabels = {
    'Hydration',
    'Exercise',
    'Movement',
    'Caffeine',
  };

  static bool _isUsableSignal(SignalReading item) =>
      item.value.isFinite &&
      item.value >= 0 &&
      item.quality.isFinite &&
      item.quality > 0 &&
      item.source != SignalSource.model &&
      (!{
            SignalType.reactionTime,
            SignalType.hrv,
            SignalType.restingHeartRate,
          }.contains(item.type) ||
          item.value > 0);

  static bool _isUsableCheckIn(DailyCheckIn item) => [
    item.energy,
    item.mood,
    item.stress,
  ].every((value) => value.isFinite && value >= 1 && value <= 10);

  static String _baselineDetail(
    PersonalBaselineMetric? baseline, {
    required double current,
  }) {
    if (baseline == null || baseline.value == null) {
      return ' · personal baseline building';
    }
    if (!baseline.isReady) {
      return ' · baseline building (${baseline.sampleCount}/${baseline.minimumSamples})';
    }
    final difference = current - baseline.value!;
    final sign = difference >= 0 ? '+' : '−';
    return ' · $sign${difference.abs().toStringAsFixed(1)} ${baseline.type.unit} vs your baseline';
  }

  static double _applyBaselineReadiness(double confidence, double? readiness) {
    if (readiness == null || confidence == 0) return confidence;
    return (confidence * (.72 + readiness.clamp(0, 1) * .28)).clamp(.2, .95);
  }

  static ScoreDriver _signalDriver(
    String label,
    double contribution,
    String detail, {
    required List<SignalReading> readings,
    required DateTime cutoff,
    required Duration maximumAge,
    String? explanation,
  }) {
    final sorted = [...readings]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return ScoreDriver(
      label,
      contribution,
      detail,
      explanation: explanation ?? _explanation(label, contribution),
      freshness: _signalFreshness(
        sorted,
        cutoff: cutoff,
        maximumAge: maximumAge,
      ),
      source: sorted.firstOrNull?.source,
      evidenceAt: sorted.firstOrNull?.timestamp,
      evidenceSources: List.unmodifiable(
        sorted.map((reading) => reading.source).toSet(),
      ),
      containsDemoEvidence: sorted.any(
        (reading) => _hasDemoMarker([
          reading.id,
          reading.groupId ?? '',
          reading.note ?? '',
        ]),
      ),
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
    source: SignalSource.manual,
    evidenceSources: const [SignalSource.manual],
    containsDemoEvidence: _hasDemoMarker([checkIn.id, checkIn.note]),
  );

  static final _demoMarker = RegExp(
    r'(^|[^a-z])(seed(?:ed)?|synthetic|fake|demo|fixture|cohort)([^a-z]|$)',
    caseSensitive: false,
  );

  static bool _hasDemoMarker(Iterable<String> values) =>
      values.any(_demoMarker.hasMatch);

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
    if (inputCount == 0) return 0;
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
      'Hydration' || 'Exercise' || 'Movement' || 'Caffeine' =>
        'Recorded context only; this observation adds no score points or data coverage.',
      'Workload' || 'Study load' =>
        positive
            ? 'This study entry increases the experimental estimate under the existing rule.'
            : negative
            ? 'This study entry decreases the experimental estimate under the existing rule.'
            : 'Study load was close to the model’s neutral range.',
      'Screen time' =>
        positive
            ? 'This screen-time entry increases the experimental estimate under the existing rule.'
            : negative
            ? 'This screen-time entry decreases the experimental estimate under the existing rule.'
            : 'Screen exposure was close to the model’s neutral range.',
      'Reaction time' =>
        positive
            ? 'Reaction performance was faster than the current reference.'
            : negative
            ? 'Reaction performance was slower than the current reference.'
            : 'Reaction performance was close to the current reference.',
      'Mood' =>
        positive
            ? 'The latest mood check-in supported the experimental estimate.'
            : negative
            ? 'The latest mood check-in reduced the experimental estimate.'
            : 'The latest mood check-in had a neutral estimated effect.',
      'Stress' =>
        positive
            ? 'Lower reported stress supported the experimental estimate.'
            : negative
            ? 'Higher reported stress reduced the experimental estimate.'
            : 'Reported stress was close to the neutral range.',
      _ =>
        positive
            ? '$label supported today’s estimate.'
            : negative
            ? '$label reduced today’s estimate.'
            : '$label had a neutral estimated effect.',
    };
  }

  /// An uncalibrated experimental curve, not a physiological measurement.
  /// Sleep timing can shift the existing curve but sleep duration, naps,
  /// caffeine, fluid volume and exercise duration add no forecast points.
  static List<ForecastPoint> forecast(
    ScoreSnapshot score,
    DateTime day, {
    List<SignalReading> signals = const [],
    List<DailyCheckIn> checkIns = const [],
    UserProfile profile = const UserProfile(),
    DateTime? generatedAt,
  }) {
    final localDay = day.toLocal();
    final targetDay = DateTime(localDay.year, localDay.month, localDay.day);
    final targetEnd = DateTime(localDay.year, localDay.month, localDay.day + 1);
    final clock = generatedAt ?? DateTime.now();
    if (!score.canEstimateEnergy ||
        score.energyModelVersion != energyModelVersion) {
      return const [];
    }
    // A saved or manually constructed score cannot revive forecasts when its
    // supporting current observations were removed or are now from another day.
    final currentEvidence = FatigueEngine.score(
      signals: signals,
      checkIns: checkIns,
      now: clock,
      personalBaselines: score.personalBaselines,
    );
    if (!currentEvidence.canEstimateEnergy ||
        score.day != currentEvidence.day) {
      return const [];
    }
    final usualWakeHour = profile.wakeHour.isFinite
        ? profile.wakeHour.clamp(4.0, 11.0)
        : 7.0;
    final usualBedHour = profile.bedHour.isFinite
        ? profile.bedHour.clamp(20.0, 25.0)
        : 23.0;
    final evidenceCutoff = clock.isBefore(targetEnd) ? clock : targetEnd;
    final recentStart = DateTime(
      targetDay.year,
      targetDay.month,
      targetDay.day - 7,
    );
    final recentSignals =
        signals
            .where(
              (item) =>
                  !item.timestamp.isBefore(recentStart) &&
                  !item.timestamp.isAfter(evidenceCutoff) &&
                  _isUsableSignal(item),
            )
            .toList()
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    final recentCheckIns =
        checkIns
            .where(
              (item) =>
                  !item.timestamp.isBefore(currentEvidence.day!) &&
                  !item.timestamp.isAfter(evidenceCutoff) &&
                  _isUsableCheckIn(item),
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

    final sleepReadings = SleepSyncLogic.preferredSleepReadings(
      recentSignals,
    ).take(3).toList();
    final bedtimeReadings = SleepSyncLogic.preferredBedtimeReadings(
      recentSignals,
    ).take(5).toList();
    final observedBedtime = bedtimeReadings.isEmpty
        ? null
        : circularHourAverage(
            bedtimeReadings.map((item) {
              final local = item.timestamp.toUtc().toLocal();
              return local.hour + local.minute / 60;
            }),
          );
    final observedWake = sleepReadings.isEmpty
        ? null
        : average(
            sleepReadings.map(
              (item) =>
                  item.timestamp.toLocal().hour +
                  item.timestamp.toLocal().minute / 60,
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
              item.timestamp.isBefore(targetEnd),
        )
        .toList();
    ({double total, List<SignalReading> evidence}) modeledDailyTotal(
      SignalType type,
    ) {
      if (ActivitySyncLogic.supportedTypes.contains(type)) {
        final today = ActivitySyncLogic.aggregateForDay(
          recentSignals,
          type: type,
          day: targetDay,
        );
        if (today != null) {
          return (total: today.total, evidence: today.evidence);
        }
        final selectedDays = ActivitySyncLogic.aggregatesByDay(
          recentSignals,
          type: type,
          start: recentStart,
          end: targetEnd,
        ).take(3).toList(growable: false);
        return (
          total: average(selectedDays.map((item) => item.total)) ?? 0,
          evidence: selectedDays
              .expand((item) => item.evidence)
              .toList(growable: false),
        );
      }
      final sameDay = sameDaySignals
          .where((item) => item.type == type)
          .toList();
      if (sameDay.isNotEmpty) {
        return (
          total: sameDay.fold<double>(0, (sum, item) => sum + item.value),
          evidence: sameDay,
        );
      }
      final byDay = <String, List<SignalReading>>{};
      for (final item in readings(type)) {
        final key = _dayIdentifier(item.timestamp);
        byDay.putIfAbsent(key, () => []).add(item);
      }
      final selectedDays = byDay.values.take(3).toList(growable: false);
      final totals = selectedDays.map(
        (items) => items.fold<double>(0, (sum, item) => sum + item.value),
      );
      return (
        total: average(totals) ?? 0,
        evidence: selectedDays.expand((items) => items).toList(growable: false),
      );
    }

    final studyModel = modeledDailyTotal(SignalType.study);
    final studyHours = studyModel.total;
    final latestCheckIn = recentCheckIns.firstOrNull;
    final checkInAdjustment = latestCheckIn == null
        ? 0.0
        : ((latestCheckIn.energy - 5.5) * 1.1 +
                  (latestCheckIn.mood - 5.5) * .45 -
                  (latestCheckIn.stress - 5.5) * .65)
              .clamp(-8.0, 8.0);
    final workload = studyHours;

    final evidenceGroups = <bool>[
      sleepReadings.isNotEmpty,
      bedtimeReadings.isNotEmpty,
      readings(SignalType.study).isNotEmpty,
      latestCheckIn != null,
    ];
    final coverage = evidenceGroups.where((present) => present).length / 4;
    const forecastSignalTypes = {
      SignalType.sleep,
      SignalType.bedtime,
      SignalType.study,
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
    final linkedSignals = <String, SignalReading>{};
    for (final signal in [
      ...sleepReadings,
      ...bedtimeReadings,
      ...studyModel.evidence,
    ]) {
      if (signal.id.isNotEmpty) {
        linkedSignals.putIfAbsent(signal.id, () => signal);
      }
    }
    final signalEvidenceIds = linkedSignals.keys.toList(growable: false);
    final checkInEvidenceIds = latestCheckIn == null || latestCheckIn.id.isEmpty
        ? const <String>[]
        : <String>[latestCheckIn.id];
    final anchor = score.energy.toDouble();

    return List.generate(forecastEndHour - forecastStartHour + 1, (index) {
      final hour = forecastStartHour + index;
      final time = DateTime(
        targetDay.year,
        targetDay.month,
        targetDay.day,
        hour,
      );
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
      final energy =
          (anchor +
                  checkInAdjustment +
                  circadian -
                  sleepInertia -
                  afternoonDip +
                  rebound -
                  lateDayDecline -
                  workloadPenalty)
              .clamp(5.0, 98.0);
      final horizonHours = math.max(0, time.difference(clock).inMinutes / 60);
      final uncertainty =
          (5 + (1 - modelConfidence) * 24 + horizonHours / 24 * 2.5).clamp(
            5.0,
            35.0,
          );
      return ForecastPoint(
        time,
        energy,
        uncertainty,
        updatedAt: clock,
        rulesVersion: energyModelVersion,
        signalEvidenceIds: signalEvidenceIds,
        checkInEvidenceIds: checkInEvidenceIds,
      );
    });
  }

  static List<ForecastWindow> windows(
    List<ForecastPoint> points,
    ScoreSnapshot score, {
    List<SignalReading> signals = const [],
    List<DailyCheckIn> checkIns = const [],
  }) {
    if (points.isEmpty ||
        !score.canEstimateEnergy ||
        score.energyModelVersion != energyModelVersion) {
      return const [];
    }
    if (points.any((point) => point.rulesVersion != energyModelVersion)) {
      return const [];
    }
    final ordered = [...points]
      ..sort((left, right) => left.time.compareTo(right.time));
    final crashIndex = _crashIndex(ordered);
    final peakCandidates = ordered.take(math.max(1, crashIndex)).toList();
    final peak = peakCandidates.reduce(
      (left, right) =>
          left.energy - left.uncertainty * .15 >=
              right.energy - right.uncertainty * .15
          ? left
          : right,
    );
    final crash = ordered[crashIndex];
    final recoveryCandidates = ordered.skip(crashIndex + 1).toList();
    final recovery = recoveryCandidates.isEmpty
        ? crash
        : recoveryCandidates.reduce(
            (left, right) =>
                left.energy - left.uncertainty * .1 >=
                    right.energy - right.uncertainty * .1
                ? left
                : right,
          );
    final peakEvidence = _windowEvidence(
      ForecastWindowType.peak,
      ordered,
      signals,
      checkIns,
    );
    final crashEvidence = _windowEvidence(
      ForecastWindowType.crash,
      ordered,
      signals,
      checkIns,
    );
    final recoveryEvidence = _windowEvidence(
      ForecastWindowType.recovery,
      ordered,
      signals,
      checkIns,
    );
    final firstTime = ordered.first.time;
    final endLimit = ordered.last.time.add(const Duration(hours: 1));
    return [
      ForecastWindow(
        ForecastWindowType.peak,
        _notBefore(peak.time.subtract(const Duration(minutes: 30)), firstTime),
        _notAfter(peak.time.add(const Duration(minutes: 90)), endLimit),
        peak.energy.round(),
        _windowReason(ForecastWindowType.peak, peakEvidence, score),
        evidence: peakEvidence,
      ),
      ForecastWindow(
        ForecastWindowType.crash,
        _notBefore(crash.time.subtract(const Duration(minutes: 30)), firstTime),
        _notAfter(crash.time.add(const Duration(minutes: 60)), endLimit),
        crash.energy.round(),
        _windowReason(ForecastWindowType.crash, crashEvidence, score),
        evidence: crashEvidence,
      ),
      ForecastWindow(
        ForecastWindowType.recovery,
        _notBefore(
          recovery.time.subtract(const Duration(minutes: 30)),
          firstTime,
        ),
        _notAfter(recovery.time.add(const Duration(minutes: 60)), endLimit),
        recovery.energy.round(),
        _windowReason(ForecastWindowType.recovery, recoveryEvidence, score),
        evidence: recoveryEvidence,
      ),
    ];
  }

  static int _crashIndex(List<ForecastPoint> points) {
    if (points.length < 3) {
      return points.indexWhere(
        (point) =>
            point.energy == points.map((item) => item.energy).reduce(math.min),
      );
    }
    final candidates = <int>[
      for (var index = 1; index < points.length - 1; index++)
        if (points[index].time.hour >= 12) index,
    ];
    if (candidates.isEmpty) {
      return points.indexWhere(
        (point) =>
            point.energy == points.map((item) => item.energy).reduce(math.min),
      );
    }
    var bestIndex = candidates.first;
    var bestScore = double.negativeInfinity;
    for (final index in candidates) {
      final priorStart = math.max(0, index - 4);
      final priorHigh = points
          .sublist(priorStart, index)
          .map((point) => point.energy)
          .reduce(math.max);
      final followingEnd = math.min(points.length, index + 4);
      final followingHigh = points
          .sublist(index + 1, followingEnd)
          .map((point) => point.energy)
          .fold<double>(points[index].energy, math.max);
      final decline = priorHigh - points[index].energy;
      final rebound = followingHigh - points[index].energy;
      final score =
          decline +
          math.max(0, rebound) * .65 -
          points[index].uncertainty * .08;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  static List<ForecastEvidence> _windowEvidence(
    ForecastWindowType type,
    List<ForecastPoint> points,
    List<SignalReading> signals,
    List<DailyCheckIn> checkIns,
  ) {
    final linkedSignalIds = points
        .expand((point) => point.signalEvidenceIds)
        .toSet();
    final linkedCheckInIds = points
        .expand((point) => point.checkInEvidenceIds)
        .toSet();
    if (linkedSignalIds.isEmpty && linkedCheckInIds.isEmpty) return const [];

    final signalPriority = switch (type) {
      ForecastWindowType.peak => const {
        SignalType.sleep: 0,
        SignalType.bedtime: 2,
        SignalType.study: 5,
      },
      ForecastWindowType.crash => const {
        SignalType.study: 0,
        SignalType.sleep: 3,
        SignalType.bedtime: 4,
      },
      ForecastWindowType.recovery => const {
        SignalType.study: 0,
        SignalType.sleep: 3,
        SignalType.bedtime: 4,
      },
    };
    final candidates = <({int priority, ForecastEvidence evidence})>[];
    final seenTypes = <SignalType>{};
    final linkedSignals =
        signals.where((signal) => linkedSignalIds.contains(signal.id)).toList()
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    for (final signal in linkedSignals) {
      if (!seenTypes.add(signal.type)) continue;
      candidates.add((
        priority: signalPriority[signal.type] ?? 9,
        evidence: ForecastEvidence(
          id: signal.id,
          kind: ForecastEvidenceKind.signal,
          label: signal.type.label,
          detail: _signalEvidenceDetail(signal),
          timestamp: signal.timestamp,
          signalType: signal.type,
          source: signal.source,
        ),
      ));
    }
    final linkedCheckIns =
        checkIns
            .where((checkIn) => linkedCheckInIds.contains(checkIn.id))
            .toList()
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    if (linkedCheckIns.firstOrNull case final checkIn?) {
      candidates.add((
        priority: switch (type) {
          ForecastWindowType.peak => 1,
          ForecastWindowType.crash => 2,
          ForecastWindowType.recovery => 2,
        },
        evidence: ForecastEvidence(
          id: checkIn.id,
          kind: ForecastEvidenceKind.checkIn,
          label: '${checkIn.period.label} check-in',
          detail:
              'Energy ${checkIn.energy.round()}/10 · mood ${checkIn.mood.round()}/10 · stress ${checkIn.stress.round()}/10',
          timestamp: checkIn.timestamp,
        ),
      ));
    }
    candidates.sort((left, right) {
      final priority = left.priority.compareTo(right.priority);
      if (priority != 0) return priority;
      return right.evidence.timestamp.compareTo(left.evidence.timestamp);
    });
    return candidates
        .take(3)
        .map((candidate) => candidate.evidence)
        .toList(growable: false);
  }

  static String _windowReason(
    ForecastWindowType type,
    List<ForecastEvidence> evidence,
    ScoreSnapshot score,
  ) {
    if (evidence.isEmpty) {
      return 'Uncalibrated experimental curve; no linked observations were saved.';
    }
    final labels = evidence
        .take(2)
        .map((item) => item.label.toLowerCase())
        .join(' and ');
    return switch (type) {
      ForecastWindowType.peak =>
        'Experimental higher point in the curve, using $labels. Timing is unvalidated.',
      ForecastWindowType.crash =>
        'Experimental lower point in the curve, using $labels. A crash is not established.',
      ForecastWindowType.recovery =>
        'Experimental later rise in the curve, using $labels. Recovery is not established.',
    };
  }

  static String _signalEvidenceDetail(
    SignalReading signal,
  ) => switch (signal.type) {
    SignalType.bedtime => 'Bedtime ${_decimalHour(signal.value)}',
    SignalType.sleep =>
      'Main-sleep completion at ${_decimalHour(signal.timestamp.toLocal().hour + signal.timestamp.toLocal().minute / 60)}; timing only in this curve',
    SignalType.nap => '${(signal.value * 60).round()} min nap',
    SignalType.hydration => '${signal.value.toStringAsFixed(1)} L logged',
    SignalType.study => '${signal.value.toStringAsFixed(1)} hr study load',
    SignalType.exercise => '${signal.value.toStringAsFixed(1)} hr exercise',
    _ => '${signal.value.toStringAsFixed(1)} ${signal.type.unit}',
  };

  static String _decimalHour(double value) {
    final totalMinutes = ((value % 24) * 60).round() % (24 * 60);
    final hour24 = totalMinutes ~/ 60;
    final minute = totalMinutes % 60;
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour:${minute.toString().padLeft(2, '0')} ${hour24 >= 12 ? 'PM' : 'AM'}';
  }

  static DateTime _notBefore(DateTime value, DateTime minimum) =>
      value.isBefore(minimum) ? minimum : value;

  static DateTime _notAfter(DateTime value, DateTime maximum) =>
      value.isAfter(maximum) ? maximum : value;

  static List<Recommendation> recommendations(
    List<ForecastWindow> windows,
    ScoreSnapshot score, {
    DateTime? day,
    DateTime? generatedAt,
  }) {
    // Legacy forecast-timed nap/workout prescriptions are retired. The
    // schedule-aware daily planner is the supported suggestion path.
    return const [];
  }

  static List<RiskAlert> alerts(
    List<SignalReading> signals,
    List<DailyCheckIn> checkIns,
    ScoreSnapshot score, {
    DateTime? now,
    DateTime? day,
  }) {
    final clock = now ?? DateTime.now();
    final target = (day ?? clock).toLocal();
    final targetDay = DateTime(target.year, target.month, target.day);
    final rangeStart = DateTime(target.year, target.month, target.day - 6);
    final rangeEnd = DateTime(target.year, target.month, target.day + 1);
    final cutoff = clock.isBefore(rangeEnd) ? clock : rangeEnd;
    final recentCheckIns =
        checkIns
            .where(
              (item) =>
                  !item.timestamp.isBefore(rangeStart) &&
                  item.timestamp.isBefore(rangeEnd) &&
                  !item.timestamp.isAfter(cutoff) &&
                  _isUsableCheckIn(item),
            )
            .toList()
          ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    final alerts = <RiskAlert>[];
    // No age-agnostic sleep cutoff or exercise-hours diagnosis. Sleep facts
    // and age-supported comparisons are shown separately with coverage.
    final strainedByDay = <String, DailyCheckIn>{};
    for (final item in recentCheckIns.where(
      (item) => item.stress >= 7 && item.energy <= 4,
    )) {
      strainedByDay.putIfAbsent(_dayIdentifier(item.timestamp), () => item);
    }
    final strained = strainedByDay.values.toList();
    if (strained.length >= 3 &&
        strained.any((item) => !item.timestamp.isBefore(targetDay))) {
      alerts.add(
        RiskAlert(
          'Recent check-in observations',
          'On ${strained.length} recorded days this week, you reported Energy at or below 4/10 and stress at or above 7/10. These are check-in ratings, not a diagnosis.',
          AlertSeverity.info,
          id: '${_dayIdentifier(targetDay)}-fatigue-stress',
          category: RiskAlertCategory.fatigueStress,
          day: targetDay,
          detectedAt: clock,
          checkInEvidenceIds: strained
              .map((item) => item.id)
              .toList(growable: false),
          evidence: strained
              .map(_forecastEvidenceFromCheckIn)
              .take(4)
              .toList(growable: false),
        ),
      );
    }
    alerts.sort(
      (left, right) => right.severity.index.compareTo(left.severity.index),
    );
    return List.unmodifiable(alerts);
  }

  static ForecastEvidence _forecastEvidenceFromCheckIn(
    DailyCheckIn checkIn,
  ) => ForecastEvidence(
    id: checkIn.id,
    kind: ForecastEvidenceKind.checkIn,
    label: '${checkIn.period.label} check-in',
    detail:
        'Energy ${checkIn.energy.round()}/10 · mood ${checkIn.mood.round()}/10 · stress ${checkIn.stress.round()}/10',
    timestamp: checkIn.timestamp,
  );

  static String _dayIdentifier(DateTime day) {
    final local = day.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
