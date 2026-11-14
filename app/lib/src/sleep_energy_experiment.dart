import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as tz;

import 'check_in_measurement.dart';
import 'evidence_provenance.dart';
import 'models.dart';
import 'research_export.dart';
import 'self_report_trends_logic.dart';
import 'timezone_database.dart';

/// Device-local, exploratory experiment. Never supplies the ordinary Energy
/// score. Retrospective fits and genuinely issued future predictions remain
/// separate evidence; all raw ratings stay on their original 1–10 scale.
abstract final class SleepEnergyExperiment {
  static const version = 'tonyo-local-sleep-energy-v1';
  static const pairingPolicy = 'flexible-evening-retrospective-v1';
  static const activityMinimumPairs = 25;

  static SleepEnergyReadiness prepare({
    required Iterable<DailyCheckIn> checkIns,
    required Iterable<SignalReading> signals,
    required DateTime now,
  }) {
    initializeTimezoneDatabase();
    final reports = checkIns.toList();
    final readings = signals.toList();
    final export =
        jsonDecode(
              ResearchExport.build(
                checkIns: reports,
                signals: readings,
                studyCode: 'Local',
                generatedAt: now,
              ).json,
            )
            as Map<String, dynamic>;
    final retained = _retained(reports, now);
    final rows = (export['responses'] as List).cast<Map<String, dynamic>>();
    // ResearchExport's ordered, retained reports define export-local references.
    // Original identities are used only in private dependency fingerprints.
    if (retained.length != rows.length) {
      throw StateError('Research export identity mapping changed.');
    }
    final responseByRef = <String, DailyCheckIn>{
      for (var i = 0; i < rows.length; i++)
        rows[i]['response_ref'] as String: retained[i],
    };
    final exclusions = <String, int>{
      for (final e in (export['excludedCounts'] as Map).entries)
        'export_${e.key}': e.value as int,
    };
    void exclude(String key, [int count = 1]) {
      if (count > 0) {
        exclusions.update(key, (v) => v + count, ifAbsent: () => count);
      }
    }

    final definitions = export['questionnaireDefinitions'] as Map;
    final definitionsByRef = <String, String?>{
      for (final e in definitions.entries)
        e.key as String: _definitionHash(e.value),
    };
    final sleeps = <String, Map<String, dynamic>>{
      for (final row in export['sleepObservations'] as List)
        row['sleep_ref'] as String: Map<String, dynamic>.from(row as Map),
    };
    final candidates = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      if (row['questionnaire_version'] != CheckInMeasurement.currentVersion ||
          row['questionnaire_language'] != 'en' ||
          row['source'] != 'selfReport' ||
          row['period'] != 'evening') {
        exclude('incompatible_measurement_source_or_period');
        continue;
      }
      if (definitionsByRef[row['definition_ref']] == null) {
        exclude('missing_or_invalid_definition');
        continue;
      }
      final report = responseByRef[row['response_ref']]!;
      if (!_validTiming(report, now)) {
        exclude('invalid_response_date_timezone_or_timing');
        continue;
      }
      candidates.putIfAbsent(row['local_date'] as String, () => []).add(row);
    }
    final selected = <Map<String, dynamic>>[];
    for (final group in candidates.values) {
      group.sort(_compareExportRows);
      selected.add(group.first);
      exclude('later_compatible_response_same_date', group.length - 1);
    }
    selected.sort(_compareExportRows);
    final usedSleeps = <String>{};
    final pairs = <SleepEnergyPair>[];
    for (final row in selected) {
      final sleepRef = row['sleep_ref'] as String?;
      final sleep = sleeps[sleepRef];
      if (row['sleep_match_status'] == 'matched' && sleep != null) {
        if (!usedSleeps.add(sleepRef!)) {
          exclude('sleep_already_selected_by_earlier_response');
          continue;
        }
      }
      if (row['energy_1_to_10'] == null) {
        exclude('selected_first_response_missing_energy');
        continue;
      }
      final ratings = [
        for (final id in DailyCheckIn.measurementIds) row['${id}_1_to_10'],
      ].where((v) => v != null).toList();
      if (ratings.any(
            (v) =>
                v is! num || !v.isFinite || v < 1 || v > 10 || v.toInt() != v,
          ) ||
          row['answered_item_count'] != ratings.length ||
          row['completion_status'] !=
              (ratings.length == 6 ? 'complete' : 'partial')) {
        exclude('selected_response_invalid_ratings_or_completeness');
        continue;
      }
      if (row['sleep_match_status'] != 'matched' || sleep == null) {
        exclude('selected_response_sleep_unmatched');
        continue;
      }
      final source = sleep['source'];
      final duration = sleep['duration_hours'];
      final quality = sleep['quality'];
      if (!['manual', 'healthKit'].contains(source) ||
          duration is! num ||
          !duration.isFinite ||
          duration < .5 ||
          duration > 16 ||
          row['sleep_hours'] is! num ||
          ((row['sleep_hours'] as num) - duration).abs() > 1e-9 ||
          quality is! num ||
          !quality.isFinite ||
          quality <= 0 ||
          quality > 1) {
        exclude('selected_response_invalid_sleep');
        continue;
      }
      if (sleep['availability_known'] != true ||
          row['sleep_pair_availability_known'] != true) {
        exclude('sleep_availability_unknown');
        continue;
      }
      final ended = _utc(sleep['sleep_end_at_utc']);
      final available = _utc(sleep['record_available_at_utc']);
      final pairAvailable = _utc(row['sleep_pair_available_at_utc']);
      final availabilityParts = [
        sleep['recorded_at_utc'],
        sleep['synced_at_utc'],
      ].where((v) => v != null).map(_utc).toList();
      final report = responseByRef[row['response_ref']]!;
      if (ended == null ||
          available == null ||
          pairAvailable == null ||
          availabilityParts.isEmpty ||
          availabilityParts.any((v) => v == null || v.isBefore(ended)) ||
          available !=
              (availabilityParts.whereType<DateTime>().toList()..sort()).last ||
          available.isAfter(pairAvailable) ||
          pairAvailable.isAfter(now)) {
        exclude('invalid_sleep_availability_metadata');
        continue;
      }
      if (ended.isAfter(report.timestamp)) {
        exclude('sleep_ended_after_response');
        continue;
      }
      if (report.timestamp.difference(ended) > const Duration(hours: 24)) {
        exclude('sleep_ended_more_than_24_hours_before_response');
        continue;
      }
      final definitionHash = definitionsByRef[row['definition_ref']]!;
      final zone = report.timezone!;
      final measurementKey =
          '${CheckInMeasurement.currentVersion}:en:$pairingPolicy:${_hashText('$definitionHash|$zone')}';
      final match = SelfReportTrendsLogic.matchSleep(report, readings, now);
      final rawSleep = match.reading!;
      final activity = pairAvailable.isAfter(report.timestamp)
          ? null
          : _previousActivity(readings, report.localDate!, zone, pairAvailable);
      final fingerprint = _hash({
        'response': report.toJson(),
        'sleep': rawSleep.toJson(),
        'pairingDependencies': _sleepDependencies(
          readings,
          report.timestamp,
          now,
        ),
        'pairAvailable': pairAvailable.toIso8601String(),
        'measurementKey': measurementKey,
      });
      pairs.add(
        SleepEnergyPair(
          responseId: report.id,
          sleepId: rawSleep.id,
          localDate: report.localDate!,
          cohortKey: '$source|$measurementKey',
          measurementKey: measurementKey,
          sleepSource: source as String,
          timezone: zone,
          sleepHours: duration.toDouble(),
          energy: (row['energy_1_to_10'] as num).toDouble(),
          fingerprint: fingerprint,
          definition: Map<String, dynamic>.from(
            definitions[row['definition_ref']] as Map,
          ),
          activityHours: activity?.value,
          activityFingerprint: activity == null
              ? null
              : _hash(activity.toJson()),
        ),
      );
    }
    pairs.sort((a, b) => a.localDate.compareTo(b.localDate));
    final grouped = _groups(pairs);
    final cohorts = [
      for (final entry in grouped.entries)
        SleepEnergyCohort(
          key: entry.key,
          sleepSource: entry.value.first.sleepSource,
          timezone: entry.value.first.timezone,
          pairCount: entry.value.length,
          activityPairCount: entry.value
              .where((p) => p.activityHours != null)
              .length,
          blocker: _fitBlocker(entry.value),
        ),
    ];
    return SleepEnergyReadiness(
      savedCheckInCount: reports.length,
      savedSleepCount: readings.where((s) => s.type == SignalType.sleep).length,
      savedActivityCount: readings
          .where(
            (s) =>
                s.source == SignalSource.manual &&
                ActivityLogEntry.allowedTypes.contains(s.type),
          )
          .map((s) => s.groupId ?? s.id)
          .toSet()
          .length,
      pairs: List.unmodifiable(pairs),
      exclusions: Map.unmodifiable(exclusions),
      cohorts: List.unmodifiable(cohorts),
      fingerprint: _hash([
        for (final p in pairs) [p.fingerprint, p.activityFingerprint],
      ]),
    );
  }

  static SleepEnergyRun train(
    SleepEnergyReadiness readiness, {
    required DateTime trainedAt,
  }) {
    final groups = _groups(readiness.pairs);
    return SleepEnergyRun(
      trainedAt: trainedAt.toUtc(),
      readinessFingerprint: readiness.fingerprint,
      fits: [for (final rows in groups.values) _fit(rows)],
      activityComparisons: [
        for (final rows in groups.values) _activityComparison(rows),
      ],
      dependencies: {
        for (final p in readiness.pairs) p.responseId: p.fingerprint,
      },
      activityDependencies: {
        for (final p in readiness.pairs)
          if (p.activityFingerprint != null)
            p.responseId: p.activityFingerprint!,
      },
    );
  }

  /// Added dates are allowed; deleted/edited source examples invalidate a run.
  /// New responses which change first-response selection also invalidate it.
  static bool isRunCurrent(SleepEnergyRun run, SleepEnergyReadiness readiness) {
    final pairs = {for (final p in readiness.pairs) p.responseId: p};
    return run.dependencies.entries.every(
          (e) => pairs[e.key]?.fingerprint == e.value,
        ) &&
        run.activityDependencies.entries.every(
          (e) => pairs[e.key]?.activityFingerprint == e.value,
        );
  }

  static SleepEnergyPredictionDraftResult draftPrediction({
    required SleepEnergyRun run,
    required SleepEnergyReadiness readiness,
    required Iterable<DailyCheckIn> checkIns,
    required Iterable<SignalReading> signals,
    required DateTime now,
    required String timezone,
  }) {
    initializeTimezoneDatabase();
    SleepEnergyPredictionDraftResult blocked(String reason) =>
        SleepEnergyPredictionDraftResult(reason: reason);
    if (!isRunCurrent(run, readiness)) return blocked('training_data_changed');
    if (run.trainedAt.isAfter(now)) return blocked('training_time_in_future');
    tz.Location zone;
    try {
      zone = tz.getLocation(timezone);
    } catch (_) {
      return blocked('unknown_timezone');
    }
    final local = tz.TZDateTime.from(now, zone);
    final day = _dateText(local);
    // Any existing Evening-labelled answer prevents retrospective issuance,
    // even a different language, legacy definition or missing Energy.
    if (checkIns.any(
      (r) =>
          r.period == CheckInPeriod.evening &&
          (r.localDate == day ||
              _dateText(tz.TZDateTime.from(r.timestamp, zone)) == day),
    )) {
      return blocked('evening_response_already_exists');
    }
    final readings = signals.toList();
    final candidates = <SleepEnergyPrediction>[];
    for (final fit in run.fits.where(
      (f) => f.fitted && f.timezone == timezone,
    )) {
      // All data consulted by the saved experiment, including holdout, must be
      // strictly earlier dates. The old holdout is never refit into the model.
      if (fit.holdoutEndDate == null ||
          fit.holdoutEndDate!.compareTo(day) >= 0) {
        continue;
      }
      final probe = DailyCheckIn(
        id: 'prediction-candidate',
        timestamp: now,
        recordedAt: now,
        period: CheckInPeriod.evening,
        fatigue: 1,
        localDate: day,
        timezone: timezone,
        utcOffsetMinutes: local.timeZoneOffset.inMinutes,
        questionnaireVersion: CheckInMeasurement.currentVersion,
        questionnaireLanguage: 'en',
        source: 'selfReport',
        questionnaireSnapshot: fit.definition,
      );
      final match = SelfReportTrendsLogic.matchSleep(probe, readings, now);
      final sleep = match.reading;
      if (!match.isMatched ||
          sleep == null ||
          !match.availabilityKnown ||
          match.availableAt == null ||
          match.availableAt!.isAfter(now) ||
          sleep.source.name != fit.sleepSource ||
          _dateText(tz.TZDateTime.from(sleep.timestamp, zone)) != day) {
        continue;
      }
      final dependencyIds = readiness.pairs
          .where(
            (p) =>
                p.cohortKey == fit.cohortKey &&
                run.dependencies.containsKey(p.responseId),
          )
          .map((p) => p.responseId)
          .toSet();
      final dependencies = {
        for (final id in dependencyIds) id: run.dependencies[id]!,
      };
      final fingerprint = _hash(fit.toJson());
      candidates.add(
        SleepEnergyPrediction(
          id: _hash([
            fingerprint,
            day,
            now.toUtc().toIso8601String(),
            sleep.id,
          ]),
          localDate: day,
          createdAt: now.toUtc(),
          source: fit.sleepSource,
          cohortKey: fit.cohortKey,
          modelFingerprint: fingerprint,
          timezone: timezone,
          definition: fit.definition,
          sleepId: sleep.id,
          sleepFingerprint: _hash(sleep.toJson()),
          sleepPairAvailableAt: match.availableAt!.toUtc(),
          sleepHours: sleep.value,
          modelPrediction: _clip(fit.intercept! + fit.slope! * sleep.value),
          meanPrediction: fit.trainingMean!,
          lastPrediction: fit.lastTrainingEnergy!,
          dependencies: dependencies,
          signalDependencies: _sleepDependencies(readings, now, now),
        ),
      );
    }
    if (candidates.length != 1) {
      return blocked(
        candidates.isEmpty
            ? 'no_eligible_frozen_fit_or_known_sleep'
            : 'ambiguous_model_cohort',
      );
    }
    return SleepEnergyPredictionDraftResult(draft: candidates.single);
  }

  static SleepEnergyPredictionEvaluation evaluatePrediction(
    SleepEnergyPrediction prediction, {
    required Iterable<DailyCheckIn> checkIns,
    required Iterable<SignalReading> signals,
    required DateTime now,
  }) {
    SleepEnergyPredictionEvaluation result(
      String status,
      String? reason, {
      SleepEnergyPrediction? record,
      double? actual,
    }) => SleepEnergyPredictionEvaluation(
      prediction: status == 'invalidated'
          ? (record ?? prediction).invalidate(reason!, now)
          : record ?? prediction,
      status: status,
      reason: reason,
      actual: actual,
    );
    if (prediction.invalidatedAt != null) {
      return result('invalidated', prediction.invalidationReason);
    }
    final receipt = prediction.receiptAt;
    if (receipt == null) {
      return result('pending_receipt', 'prediction_not_durably_committed');
    }
    if (receipt.isBefore(prediction.createdAt) || receipt.isAfter(now)) {
      return result('invalidated', 'invalid_receipt_time');
    }
    final reports = checkIns.toList();
    final readings = signals.toList();
    final readiness = prepare(checkIns: reports, signals: readings, now: now);
    final pairMap = {
      for (final p in readiness.pairs) p.responseId: p.fingerprint,
    };
    if (!prediction.dependencies.entries.every(
      (e) => pairMap[e.key] == e.value,
    )) {
      return result('invalidated', 'training_example_edited_or_deleted');
    }
    final rawSleep = readings.where((s) => s.id == prediction.sleepId).toList();
    if (rawSleep.isEmpty ||
        rawSleep.any(
          (s) => _signalFingerprint(s) != prediction.sleepFingerprint,
        )) {
      return result('invalidated', 'prediction_sleep_edited_or_deleted');
    }
    final currentSignals = <String, List<String>>{};
    for (final signal in readings) {
      if (!prediction.signalDependencies.containsKey(signal.id)) continue;
      currentSignals
          .putIfAbsent(signal.id, () => [])
          .add(_signalFingerprint(signal));
    }
    if (!prediction.signalDependencies.entries.every(
      (e) => currentSignals[e.key]?.every((hash) => hash == e.value) == true,
    )) {
      return result(
        'invalidated',
        'prediction_sleep_dependency_edited_or_deleted',
      );
    }
    final retained = _retained(reports, now);
    final references = {
      for (var i = 0; i < retained.length; i++)
        retained[i].id: 'response-${i + 1}',
    };
    final compatible =
        retained
            .where(
              (r) =>
                  r.period == CheckInPeriod.evening &&
                  r.localDate == prediction.localDate &&
                  r.timezone == prediction.timezone &&
                  _validTiming(r, now) &&
                  _definitionHash(r.questionnaireSnapshot) ==
                      _definitionHash(prediction.definition),
            )
            .toList()
          ..sort((a, b) {
            final order = _compareReports(a, b);
            return order == 0
                ? references[a.id]!.compareTo(references[b.id]!)
                : order;
          });
    final target = compatible.firstOrNull;
    if (prediction.targetId != null &&
        (target == null ||
            target.id != prediction.targetId ||
            _hash(target.toJson()) != prediction.targetFingerprint)) {
      return result('invalidated', 'first_target_edited_or_deleted');
    }
    if (target == null) return result('awaiting_evening', null);
    final sealed = prediction.withTarget(target, now);
    if (!target.timestamp.isAfter(receipt) ||
        !target.recordedAt!.isAfter(receipt)) {
      return result(
        'invalidated',
        'target_not_observed_and_saved_after_receipt',
        record: sealed,
      );
    }
    if (target.energy == null) {
      return result(
        'excluded',
        'first_evening_response_missing_energy',
        record: sealed,
      );
    }
    return result('scored', null, record: sealed, actual: target.energy);
  }

  static SleepEnergyFit _fit(List<SleepEnergyPair> rows) {
    final held = (rows.length / 5).ceil().clamp(1, rows.length);
    final count = rows.length - held;
    final blocker = _fitBlocker(rows);
    final training = rows.take(count).toList();
    final testing = rows.skip(count).toList();
    final coefficients = blocker == null
        ? _ols(
            training.map((r) => r.sleepHours).toList(),
            training.map((r) => r.energy).toList(),
          )
        : null;
    final mean = count == 0 ? null : _mean(training.map((r) => r.energy));
    final last = training.lastOrNull?.energy;
    return SleepEnergyFit(
      cohortKey: rows.first.cohortKey,
      sleepSource: rows.first.sleepSource,
      timezone: rows.first.timezone,
      pairCount: rows.length,
      trainingCount: count,
      holdoutCount: held,
      blocker: blocker,
      slope: coefficients?.$2,
      intercept: coefficients?.$1,
      trainingMean: mean,
      lastTrainingEnergy: last,
      modelMae: coefficients == null
          ? null
          : _mean(
              testing.map(
                (r) =>
                    (_clip(coefficients.$1 + coefficients.$2 * r.sleepHours) -
                            r.energy)
                        .abs(),
              ),
            ),
      meanMae: coefficients == null
          ? null
          : _mean(testing.map((r) => (mean! - r.energy).abs())),
      previousMae: coefficients == null
          ? null
          : _mean(testing.map((r) => (last! - r.energy).abs())),
      trainingEndDate: training.lastOrNull?.localDate,
      holdoutStartDate: testing.firstOrNull?.localDate,
      holdoutEndDate: testing.lastOrNull?.localDate,
      definition: rows.first.definition,
    );
  }

  static SleepEnergyActivityComparison _activityComparison(
    List<SleepEnergyPair> group,
  ) {
    final rows = group.where((p) => p.activityHours != null).toList();
    final held = math.max<int>(1, (rows.length / 5).ceil());
    final count = math.max<int>(0, rows.length - held);
    SleepEnergyActivityComparison blocked(String reason) =>
        SleepEnergyActivityComparison(
          cohortKey: group.first.cohortKey,
          completePairCount: rows.length,
          trainingCount: count,
          holdoutCount: rows.isEmpty ? 0 : held,
          blocker: reason,
        );
    if (rows.length < activityMinimumPairs) {
      return blocked('fewer_than_25_complete_pairs');
    }
    if (held < 5) return blocked('fewer_than_five_holdout_rows');
    final training = rows.take(count).toList();
    final testing = rows.skip(count).toList();
    final x = training.map((p) => p.sleepHours).toList();
    final z = training.map((p) => p.activityHours!).toList();
    final y = training.map((p) => p.energy).toList();
    final base = _ols(x, y);
    final mx = _mean(x), mz = _mean(z), my = _mean(y);
    double covariance(List<double> a, double ma, List<double> b, double mb) {
      var sum = 0.0;
      for (var i = 0; i < a.length; i++) {
        sum += (a[i] - ma) * (b[i] - mb);
      }
      return sum;
    }

    final xx = covariance(x, mx, x, mx), zz = covariance(z, mz, z, mz);
    final xz = covariance(x, mx, z, mz),
        xy = covariance(x, mx, y, my),
        zy = covariance(z, mz, y, my);
    final determinant = xx * zz - xz * xz;
    if (base == null ||
        xx <= 0 ||
        zz <= 0 ||
        determinant <= 1e-10 * math.max(1.0, xx * zz)) {
      return blocked('insufficient_training_variation');
    }
    final a = (xy * zz - zy * xz) / determinant,
        b = (zy * xx - xy * xz) / determinant;
    final intercept = my - a * mx - b * mz;
    return SleepEnergyActivityComparison(
      cohortKey: group.first.cohortKey,
      completePairCount: rows.length,
      trainingCount: count,
      holdoutCount: held,
      sleepOnlyMae: _mean(
        testing.map(
          (p) => (_clip(base.$1 + base.$2 * p.sleepHours) - p.energy).abs(),
        ),
      ),
      sleepActivityMae: _mean(
        testing.map(
          (p) =>
              (_clip(intercept + a * p.sleepHours + b * p.activityHours!) -
                      p.energy)
                  .abs(),
        ),
      ),
      meanMae: _mean(testing.map((p) => (my - p.energy).abs())),
      previousMae: _mean(testing.map((p) => (y.last - p.energy).abs())),
    );
  }
}

class SleepEnergyReadiness {
  const SleepEnergyReadiness({
    required this.savedCheckInCount,
    required this.savedSleepCount,
    required this.savedActivityCount,
    required this.pairs,
    required this.exclusions,
    required this.cohorts,
    required this.fingerprint,
  });
  final int savedCheckInCount, savedSleepCount, savedActivityCount;
  final List<SleepEnergyPair> pairs;
  final Map<String, int> exclusions;
  final List<SleepEnergyCohort> cohorts;
  final String fingerprint;
  int get pairCount => pairs.length;
  bool get canTrain => cohorts.any((c) => c.canTrain);
}

class SleepEnergyCohort {
  const SleepEnergyCohort({
    required this.key,
    required this.sleepSource,
    required this.timezone,
    required this.pairCount,
    required this.activityPairCount,
    this.blocker,
  });
  final String key, sleepSource, timezone;
  final int pairCount, activityPairCount;
  final String? blocker;
  bool get canTrain => blocker == null;
}

class SleepEnergyPair {
  SleepEnergyPair({
    required this.responseId,
    required this.sleepId,
    required this.localDate,
    required this.cohortKey,
    required this.measurementKey,
    required this.sleepSource,
    required this.timezone,
    required this.sleepHours,
    required this.energy,
    required this.fingerprint,
    required Map<String, dynamic> definition,
    this.activityHours,
    this.activityFingerprint,
  }) : definition = _frozenMap(definition);
  final String responseId,
      sleepId,
      localDate,
      cohortKey,
      measurementKey,
      sleepSource,
      timezone,
      fingerprint;
  final double sleepHours, energy;
  final Map<String, dynamic> definition;
  final double? activityHours;
  final String? activityFingerprint;
}

class SleepEnergyRun {
  SleepEnergyRun({
    required this.trainedAt,
    required this.readinessFingerprint,
    required List<SleepEnergyFit> fits,
    required List<SleepEnergyActivityComparison> activityComparisons,
    required Map<String, String> dependencies,
    required Map<String, String> activityDependencies,
  }) : fits = List.unmodifiable(fits),
       activityComparisons = List.unmodifiable(activityComparisons),
       dependencies = Map.unmodifiable(dependencies),
       activityDependencies = Map.unmodifiable(activityDependencies);
  final DateTime trainedAt;
  final String readinessFingerprint;
  final List<SleepEnergyFit> fits;
  final List<SleepEnergyActivityComparison> activityComparisons;
  final Map<String, String> dependencies, activityDependencies;
  Map<String, Object?> toJson() => {
    'version': SleepEnergyExperiment.version,
    'trainedAt': trainedAt.toUtc().toIso8601String(),
    'readinessFingerprint': readinessFingerprint,
    'fits': fits.map((f) => f.toJson()).toList(),
    'activityComparisons': activityComparisons.map((c) => c.toJson()).toList(),
    'dependencies': dependencies,
    'activityDependencies': activityDependencies,
  };
  factory SleepEnergyRun.fromJson(Map<String, dynamic> value) {
    if (value['version'] != SleepEnergyExperiment.version) {
      throw const FormatException('Unknown sleep experiment version');
    }
    final run = SleepEnergyRun(
      trainedAt: _time(value, 'trainedAt'),
      readinessFingerprint: _string(value, 'readinessFingerprint'),
      fits: _list(
        value,
        'fits',
      ).map((v) => SleepEnergyFit.fromJson(_map(v))).toList(),
      activityComparisons: _list(
        value,
        'activityComparisons',
      ).map((v) => SleepEnergyActivityComparison.fromJson(_map(v))).toList(),
      dependencies: _stringMap(value['dependencies']),
      activityDependencies: _stringMap(value['activityDependencies']),
    );
    if (!_isHash(run.readinessFingerprint) ||
        run.dependencies.length !=
            run.fits.fold<int>(0, (n, fit) => n + fit.pairCount) ||
        run.fits.map((fit) => fit.cohortKey).toSet().length !=
            run.fits.length ||
        run.activityComparisons.map((c) => c.cohortKey).toSet().length !=
            run.activityComparisons.length ||
        run.activityComparisons.length != run.fits.length ||
        !run.activityComparisons.every(
          (c) => run.fits.any(
            (fit) =>
                fit.cohortKey == c.cohortKey &&
                c.completePairCount <= fit.pairCount,
          ),
        ) ||
        !run.activityDependencies.keys.every(run.dependencies.containsKey) ||
        [
          ...run.dependencies.values,
          ...run.activityDependencies.values,
        ].any((v) => !_isHash(v))) {
      throw const FormatException('Invalid saved run dependencies');
    }
    return run;
  }
}

class SleepEnergyFit {
  SleepEnergyFit({
    required this.cohortKey,
    required this.sleepSource,
    required this.timezone,
    required this.pairCount,
    required this.trainingCount,
    required this.holdoutCount,
    required Map<String, dynamic> definition,
    this.blocker,
    this.slope,
    this.intercept,
    this.trainingMean,
    this.lastTrainingEnergy,
    this.modelMae,
    this.meanMae,
    this.previousMae,
    this.trainingEndDate,
    this.holdoutStartDate,
    this.holdoutEndDate,
  }) : definition = _frozenMap(definition);
  final String cohortKey, sleepSource, timezone;
  final int pairCount, trainingCount, holdoutCount;
  final String? blocker, trainingEndDate, holdoutStartDate, holdoutEndDate;
  final double? slope,
      intercept,
      trainingMean,
      lastTrainingEnergy,
      modelMae,
      meanMae,
      previousMae;
  final Map<String, dynamic> definition;
  bool get fitted => blocker == null && slope != null && intercept != null;
  Map<String, Object?> toJson() => {
    'cohortKey': cohortKey,
    'sleepSource': sleepSource,
    'timezone': timezone,
    'pairCount': pairCount,
    'trainingCount': trainingCount,
    'holdoutCount': holdoutCount,
    'definition': definition,
    'blocker': blocker,
    'slope': slope,
    'intercept': intercept,
    'trainingMean': trainingMean,
    'lastTrainingEnergy': lastTrainingEnergy,
    'modelMae': modelMae,
    'meanMae': meanMae,
    'previousMae': previousMae,
    'trainingEndDate': trainingEndDate,
    'holdoutStartDate': holdoutStartDate,
    'holdoutEndDate': holdoutEndDate,
  };
  factory SleepEnergyFit.fromJson(Map<String, dynamic> v) {
    final fit = SleepEnergyFit(
      cohortKey: _string(v, 'cohortKey'),
      sleepSource: _source(v, 'sleepSource'),
      timezone: _zone(v),
      pairCount: _integer(v, 'pairCount'),
      trainingCount: _integer(v, 'trainingCount'),
      holdoutCount: _integer(v, 'holdoutCount'),
      definition: _definition(v),
      blocker: _nullableString(v, 'blocker'),
      slope: _number(v, 'slope'),
      intercept: _number(v, 'intercept'),
      trainingMean: _number(v, 'trainingMean'),
      lastTrainingEnergy: _number(v, 'lastTrainingEnergy'),
      modelMae: _number(v, 'modelMae'),
      meanMae: _number(v, 'meanMae'),
      previousMae: _number(v, 'previousMae'),
      trainingEndDate: _nullableDate(v, 'trainingEndDate'),
      holdoutStartDate: _nullableDate(v, 'holdoutStartDate'),
      holdoutEndDate: _nullableDate(v, 'holdoutEndDate'),
    );
    if (fit.pairCount != fit.trainingCount + fit.holdoutCount ||
        fit.pairCount < 1 ||
        fit.holdoutCount != (fit.pairCount / 5).ceil() ||
        fit.cohortKey !=
            _cohortKey(fit.sleepSource, fit.timezone, fit.definition) ||
        [
          fit.modelMae,
          fit.meanMae,
          fit.previousMae,
        ].whereType<double>().any((n) => n < 0 || n > 9) ||
        [
          fit.trainingMean,
          fit.lastTrainingEnergy,
        ].whereType<double>().any((n) => n < 1 || n > 10) ||
        fit.lastTrainingEnergy != null &&
            fit.lastTrainingEnergy != fit.lastTrainingEnergy!.roundToDouble() ||
        fit.holdoutStartDate == null ||
        fit.holdoutEndDate == null ||
        fit.holdoutStartDate!.compareTo(fit.holdoutEndDate!) > 0 ||
        fit.blocker == null &&
            (fit.trainingCount < 2 ||
                [
                  fit.slope,
                  fit.intercept,
                  fit.trainingMean,
                  fit.lastTrainingEnergy,
                  fit.modelMae,
                  fit.meanMae,
                  fit.previousMae,
                ].any((n) => n == null) ||
                fit.trainingEndDate == null ||
                fit.trainingEndDate!.compareTo(fit.holdoutStartDate!) >= 0)) {
      throw const FormatException('Invalid saved sleep fit');
    }
    return fit;
  }
}

class SleepEnergyActivityComparison {
  const SleepEnergyActivityComparison({
    required this.cohortKey,
    required this.completePairCount,
    required this.trainingCount,
    required this.holdoutCount,
    this.blocker,
    this.sleepOnlyMae,
    this.sleepActivityMae,
    this.meanMae,
    this.previousMae,
  });
  final String cohortKey;
  final int completePairCount, trainingCount, holdoutCount;
  final String? blocker;
  final double? sleepOnlyMae, sleepActivityMae, meanMae, previousMae;
  int get minimumPairCount => SleepEnergyExperiment.activityMinimumPairs;
  bool get fitted => blocker == null && sleepActivityMae != null;
  Map<String, Object?> toJson() => {
    'cohortKey': cohortKey,
    'completePairCount': completePairCount,
    'trainingCount': trainingCount,
    'holdoutCount': holdoutCount,
    'blocker': blocker,
    'sleepOnlyMae': sleepOnlyMae,
    'sleepActivityMae': sleepActivityMae,
    'meanMae': meanMae,
    'previousMae': previousMae,
  };
  factory SleepEnergyActivityComparison.fromJson(Map<String, dynamic> v) {
    final c = SleepEnergyActivityComparison(
      cohortKey: _string(v, 'cohortKey'),
      completePairCount: _integer(v, 'completePairCount'),
      trainingCount: _integer(v, 'trainingCount'),
      holdoutCount: _integer(v, 'holdoutCount'),
      blocker: _nullableString(v, 'blocker'),
      sleepOnlyMae: _number(v, 'sleepOnlyMae'),
      sleepActivityMae: _number(v, 'sleepActivityMae'),
      meanMae: _number(v, 'meanMae'),
      previousMae: _number(v, 'previousMae'),
    );
    if (c.completePairCount != c.trainingCount + c.holdoutCount ||
        c.holdoutCount != (c.completePairCount / 5).ceil() ||
        [
          c.sleepOnlyMae,
          c.sleepActivityMae,
          c.meanMae,
          c.previousMae,
        ].whereType<double>().any((n) => n < 0 || n > 9) ||
        c.blocker == null &&
            (c.completePairCount < 25 ||
                c.holdoutCount < 5 ||
                [
                  c.sleepOnlyMae,
                  c.sleepActivityMae,
                  c.meanMae,
                  c.previousMae,
                ].any((n) => n == null))) {
      throw const FormatException('Invalid activity comparison');
    }
    return c;
  }
}

class SleepEnergyPredictionDraftResult {
  const SleepEnergyPredictionDraftResult({this.draft, this.reason});
  final SleepEnergyPrediction? draft;
  final String? reason;
}

class SleepEnergyPrediction {
  SleepEnergyPrediction({
    required this.id,
    required this.localDate,
    required this.createdAt,
    required this.source,
    required this.cohortKey,
    required this.modelFingerprint,
    required this.timezone,
    required Map<String, dynamic> definition,
    required this.sleepId,
    required this.sleepFingerprint,
    required this.sleepPairAvailableAt,
    required this.sleepHours,
    required this.modelPrediction,
    required this.meanPrediction,
    required this.lastPrediction,
    required Map<String, String> dependencies,
    Map<String, String> signalDependencies = const {},
    this.receiptAt,
    this.targetId,
    this.targetFingerprint,
    this.actual,
    this.evaluatedAt,
    this.invalidatedAt,
    this.invalidationReason,
  }) : definition = _frozenMap(definition),
       dependencies = Map.unmodifiable(dependencies),
       signalDependencies = Map.unmodifiable(signalDependencies);
  final String id,
      localDate,
      source,
      cohortKey,
      modelFingerprint,
      timezone,
      sleepId,
      sleepFingerprint;
  final DateTime createdAt, sleepPairAvailableAt;
  final DateTime? receiptAt, evaluatedAt, invalidatedAt;
  final Map<String, dynamic> definition;
  final Map<String, String> dependencies, signalDependencies;
  final double sleepHours, modelPrediction, meanPrediction, lastPrediction;
  final String? targetId, targetFingerprint, invalidationReason;
  final double? actual;
  SleepEnergyPrediction withReceipt(DateTime at) {
    if (receiptAt != null || at.isBefore(createdAt)) {
      throw StateError('Prediction receipt cannot be changed.');
    }
    return SleepEnergyPrediction.fromJson({
      ...toJson(),
      'receiptAt': at.toUtc().toIso8601String(),
    });
  }

  SleepEnergyPrediction withTarget(DailyCheckIn target, DateTime now) =>
      targetId != null
      ? this
      : SleepEnergyPrediction.fromJson({
          ...toJson(),
          'targetId': target.id,
          'targetFingerprint': _hash(target.toJson()),
          'actual': target.energy,
          'evaluatedAt': now.toUtc().toIso8601String(),
        });
  SleepEnergyPrediction invalidate(String reason, DateTime now) =>
      invalidatedAt != null
      ? this
      : SleepEnergyPrediction.fromJson({
          ...toJson(),
          'invalidatedAt': now.toUtc().toIso8601String(),
          'invalidationReason': reason,
        });
  Map<String, Object?> toJson() => {
    'version': SleepEnergyExperiment.version,
    'id': id,
    'localDate': localDate,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'receiptAt': receiptAt?.toUtc().toIso8601String(),
    'source': source,
    'cohortKey': cohortKey,
    'modelFingerprint': modelFingerprint,
    'timezone': timezone,
    'definition': definition,
    'sleepId': sleepId,
    'sleepFingerprint': sleepFingerprint,
    'sleepPairAvailableAt': sleepPairAvailableAt.toUtc().toIso8601String(),
    'sleepHours': sleepHours,
    'modelPrediction': modelPrediction,
    'meanPrediction': meanPrediction,
    'lastPrediction': lastPrediction,
    'dependencies': dependencies,
    'signalDependencies': signalDependencies,
    'targetId': targetId,
    'targetFingerprint': targetFingerprint,
    'actual': actual,
    'evaluatedAt': evaluatedAt?.toUtc().toIso8601String(),
    'invalidatedAt': invalidatedAt?.toUtc().toIso8601String(),
    'invalidationReason': invalidationReason,
  };
  factory SleepEnergyPrediction.fromJson(Map<String, dynamic> v) {
    if (v['version'] != SleepEnergyExperiment.version) {
      throw const FormatException('Unknown prediction version');
    }
    final p = SleepEnergyPrediction(
      id: _string(v, 'id'),
      localDate:
          _nullableDate(v, 'localDate') ??
          (throw const FormatException('Missing prediction date')),
      createdAt: _time(v, 'createdAt'),
      receiptAt: v['receiptAt'] == null ? null : _time(v, 'receiptAt'),
      source: _source(v, 'source'),
      cohortKey: _string(v, 'cohortKey'),
      modelFingerprint: _string(v, 'modelFingerprint'),
      timezone: _zone(v),
      definition: _definition(v),
      sleepId: _string(v, 'sleepId'),
      sleepFingerprint: _string(v, 'sleepFingerprint'),
      sleepPairAvailableAt: _time(v, 'sleepPairAvailableAt'),
      sleepHours: _requiredNumber(v, 'sleepHours'),
      modelPrediction: _requiredNumber(v, 'modelPrediction'),
      meanPrediction: _requiredNumber(v, 'meanPrediction'),
      lastPrediction: _requiredNumber(v, 'lastPrediction'),
      dependencies: _stringMap(v['dependencies']),
      signalDependencies: _stringMap(v['signalDependencies']),
      targetId: _nullableString(v, 'targetId'),
      targetFingerprint: _nullableString(v, 'targetFingerprint'),
      actual: _number(v, 'actual'),
      evaluatedAt: v['evaluatedAt'] == null ? null : _time(v, 'evaluatedAt'),
      invalidatedAt: v['invalidatedAt'] == null
          ? null
          : _time(v, 'invalidatedAt'),
      invalidationReason: _nullableString(v, 'invalidationReason'),
    );
    if (![
          p.id,
          p.modelFingerprint,
          p.sleepFingerprint,
          ...p.dependencies.values,
          ...p.signalDependencies.values,
          if (p.targetFingerprint != null) p.targetFingerprint!,
        ].every(_isHash) ||
        p.cohortKey != _cohortKey(p.source, p.timezone, p.definition) ||
        p.sleepHours < .5 ||
        p.sleepHours > 16 ||
        p.sleepPairAvailableAt.isAfter(p.createdAt) ||
        [
          p.modelPrediction,
          p.meanPrediction,
          p.lastPrediction,
          if (p.actual != null) p.actual!,
        ].any((n) => n < 1 || n > 10) ||
        p.receiptAt != null && p.receiptAt!.isBefore(p.createdAt) ||
        (p.targetId == null) != (p.targetFingerprint == null) ||
        (p.targetId == null) != (p.evaluatedAt == null) ||
        p.actual != null && p.targetId == null ||
        p.actual != null && p.actual != p.actual!.roundToDouble() ||
        (p.invalidatedAt == null) != (p.invalidationReason == null) ||
        p.dependencies.isEmpty) {
      throw const FormatException('Invalid prediction');
    }
    return p;
  }
}

class SleepEnergyPredictionEvaluation {
  const SleepEnergyPredictionEvaluation({
    required this.prediction,
    required this.status,
    this.reason,
    this.actual,
  });
  final SleepEnergyPrediction prediction;
  final String status;
  final String? reason;
  final double? actual;
  bool get scored => status == 'scored' && actual != null;
  double? get modelAbsoluteError =>
      scored ? (prediction.modelPrediction - actual!).abs() : null;
  double? get meanAbsoluteError =>
      scored ? (prediction.meanPrediction - actual!).abs() : null;
  double? get lastAbsoluteError =>
      scored ? (prediction.lastPrediction - actual!).abs() : null;
}

List<DailyCheckIn> _retained(List<DailyCheckIn> reports, DateTime now) {
  final unique = <String, DailyCheckIn>{};
  final ambiguous = <String>{};
  for (final r in reports) {
    final old = unique[r.id];
    if (old == null) {
      unique[r.id] = r;
      continue;
    }
    final order = (r.recordedAt ?? r.timestamp).compareTo(
      old.recordedAt ?? old.timestamp,
    );
    if (order > 0) {
      unique[r.id] = r;
      ambiguous.remove(r.id);
    }
    if (order == 0 && _hash(_reportKey(r)) != _hash(_reportKey(old))) {
      ambiguous.add(r.id);
    }
  }
  return unique.values
      .where(
        (r) =>
            !ambiguous.contains(r.id) &&
            !r.id.toLowerCase().startsWith('syn-') &&
            !EvidenceProvenance.hasDemoMarker([r.id, r.note]) &&
            r.isResearchCheckIn &&
            r.isValidResearchResponse &&
            r.questionnaireVersion == CheckInMeasurement.currentVersion &&
            !r.timestamp.isAfter(now) &&
            !r.recordedAt!.isAfter(now),
      )
      .toList()
    ..sort((a, b) {
      final order = a.timestamp.compareTo(b.timestamp);
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
}

// Invalid or cleared responses cannot be serialized while resolving revisions.
Map<String, Object?> _reportKey(DailyCheckIn r) => {
  'timestamp': r.timestamp.toUtc().toIso8601String(),
  'recordedAt': r.recordedAt?.toUtc().toIso8601String(),
  'ratings': r.ratings,
  'period': r.period.name,
  'localDate': r.localDate,
  'offset': r.utcOffsetMinutes,
  'timezone': r.timezone,
  'version': r.questionnaireVersion,
  'language': r.questionnaireLanguage,
  'definition': r.questionnaireSnapshot,
  'source': r.source,
  'note': r.note,
  'legacyRatings': r.originalLegacyRatings,
  'legacyPeriodMissing': r.legacyPeriodMissing,
};

// Includes saved bedtimes and stages used by pairing. 42h covers a 24h-old
// main sleep plus its maximum 18h bedtime. Unrelated activity is excluded.
Map<String, String> _sleepDependencies(
  List<SignalReading> signals,
  DateTime observed,
  DateTime asOf,
) {
  const types = {
    SignalType.sleep,
    SignalType.bedtime,
    SignalType.sleepAwake,
    SignalType.sleepCore,
    SignalType.sleepDeep,
    SignalType.sleepRem,
    SignalType.sleepUnspecified,
  };
  final values = <String, List<String>>{};
  for (final s in signals) {
    if (!types.contains(s.type) ||
        s.id.isEmpty ||
        !s.value.isFinite ||
        !s.quality.isFinite ||
        s.quality <= 0 ||
        s.quality > 1 ||
        s.timestamp.isAfter(observed) ||
        observed.difference(s.timestamp) > const Duration(hours: 42) ||
        s.source == SignalSource.model ||
        EvidenceProvenance.signalIsDemo(s) ||
        s.id.toLowerCase().startsWith('syn-') ||
        [s.recordedAt, s.syncedAt].whereType<DateTime>().any(
          (at) => at.isAfter(asOf) || at.isBefore(s.timestamp),
        )) {
      continue;
    }
    values.putIfAbsent(s.id, () => []).add(_hash(s.toJson()));
  }
  return {
    for (final e in values.entries)
      e.key: e.value.toSet().length == 1
          ? e.value.first
          : _hash(e.value..sort()),
  };
}

bool _validTiming(DailyCheckIn r, DateTime now) {
  try {
    final local = tz.TZDateTime.from(r.timestamp, tz.getLocation(r.timezone!));
    return _dateText(local) == r.localDate &&
        local.timeZoneOffset.inMinutes == r.utcOffsetMinutes &&
        r.recordedAt != null &&
        !r.recordedAt!.isBefore(r.timestamp) &&
        !r.recordedAt!.isAfter(now);
  } catch (_) {
    return false;
  }
}

String? _definitionHash(Object? value) {
  if (value is! Map<String, dynamic> ||
      !DailyCheckIn.validQuestionnaireSnapshot(
        value,
        version: CheckInMeasurement.currentVersion,
        language: 'en',
      ) ||
      value['recallPeriodText'] != 'right now') {
    return null;
  }
  return _hash(value);
}

SignalReading? _previousActivity(
  List<SignalReading> readings,
  String day,
  String timezone,
  DateTime availableBy,
) {
  final previous = _dateText(
    DateTime.parse('${day}T00:00:00Z').subtract(const Duration(days: 1)),
  );
  final zone = tz.getLocation(timezone);
  // A manual daily total has explicit semantics; HealthKit exercise minutes and
  // workouts may overlap, so this experiment never sums or substitutes them.
  final candidates = readings
      .where(
        (s) =>
            s.type == SignalType.exercise &&
            s.source == SignalSource.manual &&
            s.groupId != null &&
            s.groupId!.startsWith('activity-') &&
            !s.id.toLowerCase().startsWith('syn-') &&
            !EvidenceProvenance.signalIsDemo(s) &&
            s.value.isFinite &&
            s.value >= 0 &&
            s.value <= 12 &&
            s.quality.isFinite &&
            s.quality > 0 &&
            s.quality <= 1 &&
            s.recordedAt != null &&
            !s.recordedAt!.isBefore(s.timestamp) &&
            !s.recordedAt!.isAfter(availableBy) &&
            (s.syncedAt == null ||
                !s.syncedAt!.isBefore(s.timestamp) &&
                    !s.syncedAt!.isAfter(availableBy)) &&
            _dateText(tz.TZDateTime.from(s.timestamp, zone)) == previous,
      )
      .toList();
  // Multiple saved totals or revisions are ambiguous; missing is never zero.
  return candidates.length == 1 ? candidates.single : null;
}

Map<String, List<SleepEnergyPair>> _groups(Iterable<SleepEnergyPair> pairs) {
  final result = <String, List<SleepEnergyPair>>{};
  for (final pair in pairs) {
    result.putIfAbsent(pair.cohortKey, () => []).add(pair);
  }
  for (final rows in result.values) {
    rows.sort((a, b) => a.localDate.compareTo(b.localDate));
  }
  return Map.fromEntries(
    result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

String? _fitBlocker(List<SleepEnergyPair> rows) {
  final count = rows.length - math.max<int>(1, (rows.length / 5).ceil());
  if (count < 2) return 'fewer_than_two_training_rows';
  final training = rows.take(count).toList();
  if (training.map((p) => p.sleepHours).toSet().length < 2) {
    return 'no_sleep_variation_in_training';
  }
  return _ols(
            training.map((p) => p.sleepHours).toList(),
            training.map((p) => p.energy).toList(),
          ) ==
          null
      ? 'unresolvable_training_sleep_variation'
      : null;
}

(double, double)? _ols(List<double> x, List<double> y) {
  final mx = _mean(x), my = _mean(y);
  var xx = 0.0, xy = 0.0;
  for (var i = 0; i < x.length; i++) {
    xx += (x[i] - mx) * (x[i] - mx);
    xy += (x[i] - mx) * (y[i] - my);
  }
  if (xx <= 0) return null;
  final slope = xy / xx, intercept = my - slope * mx;
  return slope.isFinite && intercept.isFinite ? (intercept, slope) : null;
}

double _mean(Iterable<double> values) {
  final list = values.toList();
  return list.fold<double>(0, (a, b) => a + b) / list.length;
}

double _clip(double n) => n.clamp(1.0, 10.0);
String _dateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
int _compareExportRows(Map<String, dynamic> a, Map<String, dynamic> b) {
  for (final key in ['observed_at_utc', 'recorded_at_utc']) {
    final c = DateTime.parse(
      a[key] as String,
    ).compareTo(DateTime.parse(b[key] as String));
    if (c != 0) return c;
  }
  return (a['response_ref'] as String).compareTo(b['response_ref'] as String);
}

int _compareReports(DailyCheckIn a, DailyCheckIn b) {
  for (final c in [
    a.timestamp.compareTo(b.timestamp),
    a.recordedAt!.compareTo(b.recordedAt!),
  ]) {
    if (c != 0) return c;
  }
  return 0;
}

DateTime? _utc(Object? value) {
  if (value is! String || !(value.endsWith('Z') || value.endsWith('+00:00'))) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

bool _isHash(String text) => RegExp(r'^[a-f0-9]{64}$').hasMatch(text);
String _signalFingerprint(SignalReading s) =>
    !s.value.isFinite || !s.quality.isFinite ? 'invalid' : _hash(s.toJson());
String _cohortKey(
  String source,
  String zone,
  Map<String, dynamic> definition,
) =>
    '$source|${CheckInMeasurement.currentVersion}:en:${SleepEnergyExperiment.pairingPolicy}:${_hashText('${_definitionHash(definition)}|$zone')}';
String _hashText(String text) => sha256.convert(utf8.encode(text)).toString();
String _hash(Object? value) => _hashText(jsonEncode(_canonical(value)));
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: _canonical(value[k])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected object');
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _frozenMap(Map<String, dynamic> value) {
  Object? freeze(Object? v) => v is Map
      ? Map<String, dynamic>.unmodifiable(
          v.map((k, item) => MapEntry(k as String, freeze(item))),
        )
      : v is List
      ? List<Object?>.unmodifiable(v.map(freeze))
      : v;
  return freeze(value) as Map<String, dynamic>;
}

String _string(Map v, String k) {
  final s = v[k];
  if (s is! String || s.isEmpty || s.length > 10000) {
    throw FormatException('Invalid $k');
  }
  return s;
}

String? _nullableString(Map v, String k) => v[k] == null ? null : _string(v, k);
String? _nullableDate(Map v, String k) {
  final s = _nullableString(v, k);
  if (s != null &&
      (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ||
          DateTime.tryParse('${s}T00:00:00Z') == null ||
          _dateText(DateTime.parse('${s}T00:00:00Z')) != s)) {
    throw FormatException('Invalid $k');
  }
  return s;
}

double? _number(Map v, String k) {
  final n = v[k];
  if (n == null) return null;
  if (n is! num || !n.isFinite) throw FormatException('Invalid $k');
  return n.toDouble();
}

double _requiredNumber(Map v, String k) =>
    _number(v, k) ?? (throw FormatException('Missing $k'));
int _integer(Map v, String k) {
  final n = v[k];
  if (n is! int || n < 0) throw FormatException('Invalid $k');
  return n;
}

DateTime _time(Map v, String k) =>
    _utc(v[k]) ?? (throw FormatException('Invalid $k'));
List _list(Map v, String k) {
  final l = v[k];
  if (l is! List || l.length > 50000) throw FormatException('Invalid $k');
  return l;
}

Map<String, String> _stringMap(Object? value) {
  final m = _map(value);
  return {for (final k in m.keys) k: _string(m, k)};
}

String _source(Map v, String k) {
  final source = _string(v, k);
  if (!['manual', 'healthKit'].contains(source)) {
    throw FormatException('Invalid $k');
  }
  return source;
}

String _zone(Map v) {
  initializeTimezoneDatabase();
  final zone = _string(v, 'timezone');
  try {
    tz.getLocation(zone);
  } catch (_) {
    throw const FormatException('Unknown timezone');
  }
  return zone;
}

Map<String, dynamic> _definition(Map v) {
  final d = _map(v['definition']);
  if (_definitionHash(d) == null) {
    throw const FormatException('Invalid definition');
  }
  return d;
}
