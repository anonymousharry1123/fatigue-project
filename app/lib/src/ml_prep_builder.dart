import 'oura_data.dart';
import 'dart:math' as math;

import 'fatigue_engine.dart';
import 'heart_derivation_logic.dart';
import 'ml_prep_models.dart';
import 'models.dart';
import 'personal_baseline_logic.dart';
import 'screen_time_logic.dart';

/// A local inspection row. Cognitive rows retain milliseconds and have no
/// score target/reference; this preparation module never fits a model.
class TrainingExample {
  const TrainingExample({
    required this.outcomeId,
    required this.head,
    required this.day,
    required this.observedAt,
    required this.label,
    required this.labelUnit,
    required this.target,
    required this.reference,
    required this.features,
    required this.featureSources,
    required this.featureAgeHours,
    required this.warnings,
    required this.consentVersion,
    this.split = 'unassigned',
  });

  final String outcomeId;
  final String head;
  final String day;
  final DateTime observedAt;
  final double label;
  final String labelUnit;
  final double? target;
  final double? reference;
  final Map<String, double?> features;
  final Map<String, List<String>> featureSources;
  final Map<String, double?> featureAgeHours;
  final List<String> warnings;
  final int consentVersion;
  final String split;

  Map<String, bool> get missingness => {
    for (final entry in features.entries) entry.key: entry.value == null,
  };

  TrainingExample _withSplit(String value) => TrainingExample(
    outcomeId: outcomeId,
    head: head,
    day: day,
    observedAt: observedAt,
    label: label,
    labelUnit: labelUnit,
    target: target,
    reference: reference,
    features: features,
    featureSources: featureSources,
    featureAgeHours: featureAgeHours,
    warnings: warnings,
    consentVersion: consentVersion,
    split: value,
  );

  Map<String, Object?> toJson() => {
    'outcomeId': outcomeId,
    'head': head,
    'day': day,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'label': label,
    'labelUnit': labelUnit,
    'target': target,
    'targetUnit': target == null ? null : 'score_0_100',
    'deterministicReference': reference,
    'features': features,
    'missingness': missingness,
    'featureSources': featureSources,
    'featureAgeHours': featureAgeHours,
    'warnings': warnings,
    'consentVersion': consentVersion,
    'split': split,
  };
}

class PrepReport {
  const PrepReport._({
    required this.energyReady,
    required this.cognitiveReady,
    required this.examples,
    required this._summary,
  });

  final bool energyReady;
  final bool cognitiveReady;
  final List<TrainingExample> examples;
  final Map<String, Object?> _summary;

  /// Small identity check for the training kernel without exporting/copying
  /// all example maps and evidence arrays again.
  Map<String, Object?> get identity => {
    for (final key in [
      'fingerprint',
      'schemaVersion',
      'reportVersion',
      'hostTimezoneCompatible',
      'window',
    ])
      key: _summary[key],
  };

  Map<String, Object?> toJson() => {
    ..._summary,
    'examples': examples.map((row) => row.toJson()).toList(),
  };
}

/// Bounded, pure account preparation. No repository, network, or write path.
abstract final class MlPrepBuilder {
  static const energyFeatureNames = [
    'sleepDeviation',
    'movement',
    'hydration',
    'studyScreenLoad',
    'caffeine',
    'mood',
    'stress',
    'recoveryDeviation',
  ];
  static const cognitiveFeatureNames = [
    'sleepDeviation',
    'priorReactionTrend',
    'study',
    'screenTime',
    'caffeine',
    'mood',
    'stress',
    'recoveryDeviation',
  ];

  /// Reuse precisely the training feature definitions for a live prediction.
  /// This bounded local view creates no label and never reads the database.
  static TrainingExample? energyInput({
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
    required DateTime at,
    required String timezone,
  }) {
    final probe = PrepWindow.endingOn(at.toLocal(), timezone: timezone);
    final window = PrepWindow.endingOn(probe.localTime(at), timezone: timezone);
    if (!_hostTimezoneMatches(window)) return null;
    final selectedSignals = signals
        .where(
          (row) =>
              row.type != SignalType.heartRate &&
              !HeartDerivationLogic.isEstimatedRestingHeartRate(row) &&
              window.contains(row.timestamp) &&
              !row.timestamp.isAfter(at),
        )
        .toList();
    final researchCheckInIds = checkIns
        .where((row) => row.isResearchCheckIn)
        .map((row) => row.id)
        .toSet();
    final selectedChecks = checkIns
        .where(
          (row) =>
              !researchCheckInIds.contains(row.id) &&
              window.contains(row.timestamp) &&
              !row.timestamp.isAfter(at),
        )
        .toList();
    if (selectedSignals.length >= PrepCollection.signals.maximumDocuments ||
        selectedChecks.length >= PrepCollection.checkIns.maximumDocuments) {
      return null;
    }
    final snapshot = PrepSnapshot(
      uid: 'local-inference',
      window: window,
      consent: const PrepConsent(
        collection: true,
        trainingUse: true,
        version: 1,
      ),
      fetchedAt: at,
      schemaVersion: 1,
      signals: selectedSignals.map((row) => row.toJson()).toList(),
      checkIns: selectedChecks.map((row) => row.toJson()).toList(),
      outcomes: [],
    );
    final records = <String, Map<String, _Record>>{};
    for (final collection in {
      'signals': snapshot.signals,
      'checkIns': snapshot.checkIns,
    }.entries) {
      records[collection.key] = {};
      final conflictingIds = _conflictingIds(collection.value);
      for (final raw in collection.value) {
        if (conflictingIds.contains(raw['id'])) continue;
        try {
          final origin = _provenance(raw, collection.key);
          if (origin != 'genuine') continue;
          final row = _parse(window, raw, collection.key, origin);
          records[collection.key]![row.id] = row;
        } on Object {
          // Invalid or unknown inputs contribute no learned effect.
        }
      }
    }
    return _example(
      snapshot,
      OutcomeRecord(
        id: 'inference-only',
        type: OutcomeType.observedEnergy,
        value: 1,
        observedAt: at,
        recordedAt: at,
        source: OutcomeSource.checkIn,
        sourceId: '',
        consentVersion: 1,
      ),
      records,
      hostTimezoneCompatible: true,
    );
  }

  static PrepReport build(PrepSnapshot snapshot) {
    final hostTimezoneCompatible = _hostTimezoneMatches(snapshot.window);
    final rejected = <Map<String, String>>[];
    final provenance = <String, Map<String, int>>{};
    // Reject both research rows and any old outcome referencing their IDs.
    // These custom measurement versions are not compatible legacy labels,
    // including when an incomplete or duplicated source cannot be parsed.
    final researchCheckInIds = {
      for (final raw in snapshot.checkIns)
        if (DailyCheckIn.researchFields.any(raw.containsKey) &&
            raw['id'] is String)
          raw['id'] as String,
    };
    final collections = {
      'signals': snapshot.signals,
      'checkIns': snapshot.checkIns,
      'outcomes': snapshot.outcomes,
    };
    final records = <String, Map<String, _Record>>{};
    for (final collection in collections.entries) {
      final counts = {'genuine': 0, 'synthetic': 0, 'uncertain': 0};
      final parsed = <String, _Record>{};
      final conflictingIds = _conflictingIds(collection.value);
      final orderedRows = [...collection.value]
        ..sort((a, b) => canonicalPrepJson(a).compareTo(canonicalPrepJson(b)));
      for (final raw in orderedRows) {
        final id = raw['id']?.toString() ?? '';
        final origin = _provenance(raw, collection.key);
        counts[origin] = counts[origin]! + 1;
        void reject(String reason) => rejected.add({
          'collection': collection.key,
          'id': id,
          'reason': reason,
        });
        if (raw['_prepForeignAccount'] == true ||
            raw['uid'] != null && raw['uid'] != snapshot.uid) {
          reject('foreign_account');
          continue;
        }
        if (conflictingIds.contains(id)) {
          reject('conflicting_duplicate_document_id');
          continue;
        }
        if (parsed.containsKey(id)) {
          reject('duplicate_document_id');
          continue;
        }
        if (collection.key == 'checkIns' &&
            (DailyCheckIn.researchFields.any(raw.containsKey) ||
                researchCheckInIds.contains(id))) {
          reject('research_measurement_not_compatible');
          continue;
        }
        try {
          final record = _parse(snapshot.window, raw, collection.key, origin);
          if (!snapshot.window.contains(record.at)) {
            reject('outside_window');
          } else if (record.at.isAfter(snapshot.fetchedAt) ||
              record.availableAt?.isAfter(snapshot.fetchedAt) == true) {
            reject('future_or_unavailable');
          } else {
            parsed[id] = record;
            if (origin != 'genuine') reject('${origin}_provenance');
          }
        } on Object {
          reject('invalid_record');
        }
      }
      provenance[collection.key] = counts;
      records[collection.key] = parsed;
    }

    final capped = snapshot.isTruncated;
    final rows = <TrainingExample>[];
    final outcomes = records['outcomes']!.values.toList()
      ..sort((a, b) {
        final time = a.at.compareTo(b.at);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    final sourceKeys = <String>{};
    for (final record in outcomes) {
      final outcome = record.outcome!;
      String? reason;
      if (!snapshot.consent.allowed) {
        reason = 'consent_required';
      } else if (capped) {
        reason = 'document_cap_reached';
      } else if (record.provenance != 'genuine') {
        continue; // Already counted with its provenance rejection.
      } else if (outcome.consentVersion != snapshot.consent.version) {
        reason = 'consent_version_mismatch';
      } else {
        reason = _sourceProblem(outcome, records, researchCheckInIds);
      }
      final key =
          '${outcome.type.name}/${outcome.source.name}/${outcome.sourceId}';
      if (reason == null && !sourceKeys.add(key)) {
        reason = 'duplicate_source_label';
      }
      if (reason != null) {
        rejected.add({
          'collection': 'outcomes',
          'id': record.id,
          'reason': reason,
        });
        continue;
      }
      rows.add(
        _example(
          snapshot,
          outcome,
          records,
          hostTimezoneCompatible: hostTimezoneCompatible,
        ),
      );
    }

    final readiness = <String, Map<String, Object?>>{};
    final missing = <String, Map<String, Object?>>{};
    final finalRows = <TrainingExample>[];
    for (final head in ['energy', 'cognitive']) {
      final selected = rows.where((row) => row.head == head).toList();
      final days = selected.map((row) => row.day).toSet().toList()..sort();
      final holdoutCount = math.min(
        days.length,
        math.max(3, (days.length * .2).ceil()),
      );
      final trainingDays = days.take(days.length - holdoutCount).toList();
      final holdoutDays = days.skip(days.length - holdoutCount).toList();
      final reasons = <String>[
        if (!snapshot.consent.allowed) 'consent_required',
        if (capped) 'document_cap_reached',
        if (!hostTimezoneCompatible) 'host_timezone_mismatch',
        if (head == 'energy' && days.length < 14) 'fewer_than_14_labeled_days',
        if (head == 'cognitive') 'target_units_undefined',
        if (head == 'cognitive' && selected.length < 10)
          'fewer_than_10_reaction_outcomes',
        if (trainingDays.isEmpty) 'no_training_days',
        if (holdoutDays.length < 3) 'fewer_than_3_holdout_days',
        if (selected.isEmpty ||
            selected.any(
              (row) => row.features.values.whereType<double>().length < 4,
            ))
          'insufficient_feature_coverage',
        if (selected.any(
          (row) => row.warnings.contains('historical_availability_unknown'),
        ))
          'historical_availability_unknown',
      ];
      readiness[head] = {
        'ready': reasons.isEmpty,
        'reasons': reasons,
        'trainingDays': trainingDays,
        'holdoutDays': holdoutDays,
        'minimumPresentFeaturesPerRow': 4,
      };
      missing[head] = {
        for (final name
            in head == 'energy' ? energyFeatureNames : cognitiveFeatureNames)
          name: {
            'missing': selected
                .where((row) => row.features[name] == null)
                .length,
            'total': selected.length,
          },
      };
      finalRows.addAll(
        selected.map(
          (row) => row._withSplit(
            holdoutDays.contains(row.day) ? 'holdout' : 'training',
          ),
        ),
      );
    }
    finalRows.sort((a, b) {
      final time = a.observedAt.compareTo(b.observedAt);
      return time != 0 ? time : a.outcomeId.compareTo(b.outcomeId);
    });
    final energyRows = rows.where((row) => row.head == 'energy');
    final cognitiveRows = rows.where((row) => row.head == 'cognitive');
    rejected.sort(
      (a, b) => canonicalPrepJson(a).compareTo(canonicalPrepJson(b)),
    );
    return PrepReport._(
      energyReady: readiness['energy']!['ready'] == true,
      cognitiveReady: false,
      examples: List.unmodifiable(finalRows),
      summary: {
        'reportVersion': 1,
        'window': snapshot.window.toJson(),
        'fetchedAt': snapshot.fetchedAt.toUtc().toIso8601String(),
        'fingerprint': snapshot.fingerprint,
        'schemaVersion': snapshot.schemaVersion,
        'hostTimezoneCompatible': hostTimezoneCompatible,
        'consent': {
          'collection': snapshot.consent.collection,
          'trainingUse': snapshot.consent.trainingUse,
          'version': snapshot.consent.version,
        },
        'counts': {
          'signals': snapshot.signals.length,
          'checkIns': snapshot.checkIns.length,
          'outcomes': snapshot.outcomes.length,
          'eligibleEnergyLabels': energyRows.length,
          'eligibleCognitiveLabels': cognitiveRows.length,
          'energyLabeledDays': energyRows.map((row) => row.day).toSet().length,
          'cognitiveLabeledDays': cognitiveRows
              .map((row) => row.day)
              .toSet()
              .length,
        },
        'readiness': readiness,
        'featureMissingness': missing,
        'provenance': provenance,
        'rejectedRows': rejected,
        'normalization': {
          'version': 2,
          'method': 'fixed_constants_no_fitted_parameters',
          'featureBounds': [-1, 1],
          'energyTarget': '(rating - 1) * 100 / 9',
          'sleepDeviation': 'retired_phase1_null_context_only',
          'movement': 'retired_phase1_null_context_only',
          'hydration': 'retired_phase1_null_context_only',
          'studyScreenLoad':
              'mean(study_hours / 8, screen_hours / 8); both required',
          'study': 'hours / 8',
          'screenTime': 'hours / 8',
          'caffeine': 'retired_phase1_null_context_only',
          'mood': '(rating - 5.5) / 4.5',
          'stress': '(rating - 5.5) / 4.5',
          'priorReactionTrend':
              '(prior_ready_baseline - latest_prior_reaction) / prior_ready_baseline / 0.25',
          'recoveryDeviation':
              'mean(HRV relative deviation, negative resting-HR relative deviation) / 0.25; both ready baselines required',
          'missingValues': 'null; never imputed to a measured zero',
        },
        'limitations': [
          'Thirty-day history only; earlier rows can lack mature personal baselines.',
          'Unknown feature availability permits inspection but blocks readiness.',
          'Synthetic and uncertain records do not contribute training evidence.',
          'Coach labels need source provenance not present in this three-collection snapshot.',
          'Cognitive reaction milliseconds have no score target or residual.',
          'Readiness is a data check; no model is trained or promoted.',
          'Historical account/device UTC offsets must match for deterministic helper replay. Otherwise references are approximate and readiness is blocked.',
        ],
      },
    );
  }

  // Neither preparation nor serving has an authoritative revision history.
  // Conflicting copies must not select arbitrary values or availability.
  static Set<String> _conflictingIds(Iterable<Map<String, dynamic>> rows) {
    final payloadsById = <String, Set<String>>{};
    for (final raw in rows) {
      final id = raw['id'];
      if (id is String) {
        payloadsById.putIfAbsent(id, () => {}).add(canonicalPrepJson(raw));
      }
    }
    return payloadsById.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toSet();
  }

  static String? _sourceProblem(
    OutcomeRecord outcome,
    Map<String, Map<String, _Record>> records,
    Set<String> researchCheckInIds,
  ) {
    if (outcome.source == OutcomeSource.coach) {
      // Completed recommendation provenance is outside the bounded snapshot.
      // A typed outcome alone cannot establish that its source was real.
      return 'coach_source_unverified';
    }
    if (outcome.source == OutcomeSource.checkIn &&
        researchCheckInIds.contains(outcome.sourceId)) {
      return 'research_measurement_not_compatible';
    }
    final collection = outcome.source == OutcomeSource.checkIn
        ? 'checkIns'
        : 'signals';
    final source = records[collection]![outcome.sourceId];
    if (source == null) return 'missing_source';
    if (source.provenance != 'genuine') return '${source.provenance}_source';
    if (!source.at.isAtSameMomentAs(outcome.observedAt)) {
      return 'source_time_mismatch';
    }
    final valid = outcome.source == OutcomeSource.checkIn
        ? outcome.type == OutcomeType.observedEnergy &&
              source.checkIn?.energy == outcome.value
        : outcome.type == OutcomeType.cognitiveReaction &&
              source.signal?.type == SignalType.reactionTime &&
              source.signal?.value == outcome.value;
    return valid ? null : 'source_value_or_type_mismatch';
  }

  static TrainingExample _example(
    PrepSnapshot snapshot,
    OutcomeRecord outcome,
    Map<String, Map<String, _Record>> records, {
    required bool hostTimezoneCompatible,
  }) {
    final window = snapshot.window;
    final now = _wall(window, outcome.observedAt);
    final start = DateTime(now.year, now.month, now.day);
    final sourceCollection = outcome.source == OutcomeSource.checkIn
        ? 'checkIns'
        : 'signals';
    bool usable(_Record row) =>
        row.provenance == 'genuine' &&
        !(row.collection == sourceCollection && row.id == outcome.sourceId) &&
        !row.at.isAfter(outcome.observedAt) &&
        (row.availableAt == null ||
            !row.availableAt!.isAfter(outcome.observedAt));
    final signalRows = records['signals']!.values
        .where(
          (row) =>
              usable(row) &&
              row.signal != null &&
              !OuraData.isOuraOrigin(row.signal!),
        )
        .toList();
    final checkRows = records['checkIns']!.values.where(usable).toList();
    final signals = signalRows.map((row) => row.signal!).toList()
      ..sort((a, b) {
        final time = b.timestamp.compareTo(a.timestamp);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    final checkIns = checkRows.map((row) => row.checkIn!).toList()
      ..sort((a, b) {
        final time = b.timestamp.compareTo(a.timestamp);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    final today = signals
        .where((row) => !row.timestamp.isBefore(start))
        .toList();
    final baseline = PersonalBaselineLogic.build(signals: signals, asOf: now);
    final evidenceById = {
      for (final row in [...signalRows, ...checkRows])
        '${row.collection}/${row.id}': row,
    };
    List<SignalReading> ofType(SignalType type) =>
        today.where((row) => row.type == type).toList();
    final featureEvidence = <String, List<_Record>>{};
    double? feature(String name, double? value, Iterable<String> ids) {
      featureEvidence[name] = value == null
          ? []
          : ids
                .toSet()
                .map((id) => evidenceById[id])
                .whereType<_Record>()
                .toList();
      return value?.clamp(-1, 1).toDouble();
    }

    double? total(List<SignalReading> rows) => rows.isEmpty
        ? null
        : rows.fold<double>(0, (sum, row) => sum + row.value);
    Iterable<String> ids(Iterable<SignalReading> rows) =>
        rows.map((row) => 'signals/${row.id}');
    // Phase 1 retires sleep/exposure-to-readiness mappings. Keep the eight
    // artifact slots stable for metadata, but these slots have no value or
    // freshness and can never contribute to fitting or live corrections.
    final features = <String, double?>{
      'sleepDeviation': feature('sleepDeviation', null, const []),
    };
    final study = ofType(SignalType.study);
    final screen = ScreenTimeLogic.modelReadings(ofType(SignalType.screenTime));
    if (outcome.type == OutcomeType.observedEnergy) {
      features['movement'] = feature('movement', null, const []);
      features['hydration'] = feature('hydration', null, const []);
      features['studyScreenLoad'] = feature(
        'studyScreenLoad',
        study.isEmpty || screen.isEmpty
            ? null
            : (total(study)! + total(screen)!) / 16,
        ids([...study, ...screen]),
      );
    } else {
      final reactions = signals
          .where(
            (row) =>
                row.type == SignalType.reactionTime &&
                row.timestamp.isBefore(now),
          )
          .toList();
      final metric = baseline.metric(PersonalBaselineType.reactionTime);
      final trend = reactions.isEmpty || metric?.isReady != true
          ? null
          : (metric!.value! - reactions.first.value) / metric.value! / .25;
      features['priorReactionTrend'] = feature(
        'priorReactionTrend',
        trend,
        ids(reactions),
      );
      features['study'] = feature(
        'study',
        total(study) == null ? null : total(study)! / 8,
        ids(study),
      );
      features['screenTime'] = feature(
        'screenTime',
        total(screen) == null ? null : total(screen)! / 8,
        ids(screen),
      );
    }
    features['caffeine'] = feature('caffeine', null, const []);
    final checkIn = checkIns
        .where((row) => !row.timestamp.isBefore(start))
        .firstOrNull;
    features['mood'] = feature(
      'mood',
      checkIn == null ? null : (checkIn.mood! - 5.5) / 4.5,
      checkIn == null ? [] : ['checkIns/${checkIn.id}'],
    );
    features['stress'] = feature(
      'stress',
      checkIn == null ? null : (checkIn.stress! - 5.5) / 4.5,
      checkIn == null ? [] : ['checkIns/${checkIn.id}'],
    );
    double? heartDifference(PersonalBaselineType type) =>
        PersonalBaselineLogic.differencePercent(
          current: PersonalBaselineLogic.currentValue(
            type,
            signals: today,
            day: start,
          ),
          baseline: baseline.metric(type),
        );
    final hrv = heartDifference(PersonalBaselineType.hrv);
    final rhr = heartDifference(PersonalBaselineType.restingHeartRate);
    features['recoveryDeviation'] = feature(
      'recoveryDeviation',
      hrv == null || rhr == null ? null : (hrv - rhr) / 50,
      ids(
        signals.where(
          (row) =>
              row.type == SignalType.hrv ||
              row.type == SignalType.restingHeartRate,
        ),
      ),
    );
    final reference = FatigueEngine.score(
      signals: signals,
      checkIns: checkIns,
      now: now,
      personalBaselines: baseline,
    );
    // Audit only inputs that can affect the Energy reference. Context-only
    // sleep, fluid and activity records remain in the raw snapshot but cannot
    // make an otherwise eligible row fail historical-availability checks.
    final referenceIds = <String>{
      if (outcome.type == OutcomeType.observedEnergy) ...{
        ...ids(study),
        ...ids(screen),
        // FatigueEngine can use each heart baseline independently even when the
        // combined learned feature is absent. Keep that baseline provenance.
        ...ids(
          signals.where(
            (row) =>
                row.type == SignalType.hrv ||
                row.type == SignalType.restingHeartRate,
          ),
        ),
        if (checkIn != null) 'checkIns/${checkIn.id}',
      },
    };
    final used = <_Record>{
      ...featureEvidence.values.expand((rows) => rows),
      ...referenceIds.map((id) => evidenceById[id]).whereType<_Record>(),
    };
    final warnings = <String>[
      if (!hostTimezoneCompatible) 'host_timezone_mismatch',
      if (used.any((row) => row.availableAt == null))
        'historical_availability_unknown',
      if (features['recoveryDeviation'] == null)
        'baseline_cold_start_or_missing',
    ];
    return TrainingExample(
      outcomeId: outcome.id,
      head: outcome.type == OutcomeType.observedEnergy ? 'energy' : 'cognitive',
      day: window.dayKey(outcome.observedAt),
      observedAt: outcome.observedAt,
      label: outcome.value,
      labelUnit: outcome.type.unit,
      target: outcome.type == OutcomeType.observedEnergy
          ? (outcome.value - 1) * 100 / 9
          : null,
      reference: outcome.type == OutcomeType.observedEnergy
          ? reference.energy.toDouble()
          : null,
      features: Map.unmodifiable(features),
      featureSources: {
        for (final entry in featureEvidence.entries)
          entry.key: entry.value
              .map((row) => '${row.collection}/${row.id}:${row.source}')
              .toList(),
      },
      featureAgeHours: {
        for (final entry in featureEvidence.entries)
          entry.key: entry.value.isEmpty
              ? null
              : entry.value
                    .map(
                      (row) =>
                          outcome.observedAt.difference(row.at).inMinutes / 60,
                    )
                    .reduce(math.max),
      },
      warnings: warnings,
      consentVersion: outcome.consentVersion,
    );
  }

  static _Record _parse(
    PrepWindow window,
    Map<String, dynamic> raw,
    String collection,
    String provenance,
  ) {
    final id = raw['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Missing id');
    }
    final at = window.parseTime(
      raw[collection == 'outcomes' ? 'observedAt' : 'timestamp'],
    );
    if (at == null) throw const FormatException('Missing time');
    final times = ['recordedAt', 'createdAt', 'updatedAt', 'syncedAt']
        .where((key) => raw[key] != null)
        .map((key) {
          final parsed = window.parseTime(raw[key]);
          if (parsed == null) {
            throw const FormatException('Invalid availability');
          }
          return parsed;
        })
        .toList();
    final availability = times.isEmpty
        ? null
        : times.reduce((a, b) => a.isAfter(b) ? a : b);
    SignalReading? signal;
    DailyCheckIn? checkIn;
    OutcomeRecord? outcome;
    if (collection == 'signals') {
      final type = SignalType.values.byName(raw['type'] as String);
      final value = _number(raw['value']);
      if (raw['unit'] != null && raw['unit'] != type.unit ||
          value < 0 ||
          type == SignalType.reactionTime && (value < 100 || value > 1500)) {
        throw const FormatException('Invalid signal');
      }
      final quality = raw['quality'] == null ? 1.0 : _number(raw['quality']);
      if (quality <= 0 || quality > 1) {
        throw const FormatException('Invalid quality');
      }
      signal = SignalReading(
        id: id,
        type: type,
        value: value,
        timestamp: _wall(window, at),
        source: SignalSource.values.byName(
          (raw['source'] as String?) ?? 'manual',
        ),
        quality: quality,
        note: raw['note'] as String?,
        groupId: raw['groupId'] as String?,
        sourceName: raw['sourceName'] as String?,
        sourceBundleId: raw['sourceBundleId'] as String?,
        sourceRecordId: raw['sourceRecordId'] as String?,
        sourceDay: raw['sourceDay'] as String?,
        measurementMethod: raw['measurementMethod'] as String?,
      );
    } else if (collection == 'checkIns') {
      if (DailyCheckIn.researchFields.any(raw.containsKey)) {
        throw const FormatException('Incompatible research measurement.');
      }
      final energy = _rating(raw['energy']);
      final mood = _rating(raw['mood']);
      final stress = _rating(raw['stress']);
      final local = _wall(window, at);
      checkIn = DailyCheckIn(
        id: id,
        timestamp: local,
        energy: energy,
        mood: mood,
        stress: stress,
        note: (raw['note'] as String?) ?? '',
        period: raw['period'] == null
            ? (local.hour < 14 ? CheckInPeriod.morning : CheckInPeriod.evening)
            : CheckInPeriod.values.byName(raw['period'] as String),
      );
    } else {
      final type = OutcomeType.values.byName(raw['type'] as String);
      final value = _number(raw['value']);
      final recordedAt = window.parseTime(raw['recordedAt']);
      final version = raw['consentVersion'];
      final sourceId = raw['sourceId'];
      if (recordedAt == null ||
          recordedAt.isBefore(at) ||
          version is! int ||
          version < 1 ||
          sourceId is! String ||
          sourceId.isEmpty ||
          raw['unit'] != null && raw['unit'] != type.unit ||
          (type == OutcomeType.observedEnergy
              ? value < 1 || value > 10
              : value < 100 || value > 1500)) {
        throw const FormatException('Invalid outcome');
      }
      outcome = OutcomeRecord(
        id: id,
        type: type,
        value: value,
        observedAt: at,
        recordedAt: recordedAt,
        source: OutcomeSource.values.byName(raw['source'] as String),
        sourceId: sourceId,
        consentVersion: version,
        recommendationId: raw['recommendationId'] as String?,
      );
    }
    return _Record(
      id: id,
      collection: collection,
      at: at,
      availableAt: availability,
      provenance: provenance,
      source: raw['source']?.toString() ?? 'manual',
      signal: signal,
      checkIn: checkIn,
      outcome: outcome,
    );
  }

  static String _provenance(Map<String, dynamic> raw, String collection) {
    final marker = [
      'id',
      'sourceId',
      'groupId',
      'note',
      'provenance',
    ].map((key) => raw[key]?.toString() ?? '').join(' ').toLowerCase();
    if (raw['synthetic'] == true ||
        raw['isSynthetic'] == true ||
        raw['source'] == 'model' ||
        RegExp(
          r'(^|[^a-z])(seed(?:ed)?|synthetic|fake|demo|fixture|cohort)([^a-z]|$)',
        ).hasMatch(marker)) {
      return 'synthetic';
    }
    if (['observed', 'real'].contains(raw['provenance']) ||
        raw['source'] == 'healthKit' ||
        RegExp(
          r'^(manual|checkin|activity|sleep)-\d{10,}',
        ).hasMatch(raw['id']?.toString() ?? '') ||
        collection == 'outcomes') {
      return 'genuine';
    }
    return 'uncertain';
  }

  static double _number(Object? value) {
    if (value is! num || !value.isFinite) {
      throw const FormatException('Invalid number');
    }
    return value.toDouble();
  }

  static double _rating(Object? value) {
    final rating = _number(value);
    if (rating < 1 || rating > 10) {
      throw const FormatException('Invalid rating');
    }
    return rating;
  }

  // Existing helpers use device-local DateTime constructors and Duration day
  // arithmetic. A calendar remap alone cannot guarantee identical cutoffs when
  // the account and device have different offset/DST histories. Inspect each
  // hour across the bounded window, including its exclusive end boundary.
  static bool _hostTimezoneMatches(PrepWindow window) {
    for (
      var at = window.start;
      !at.isAfter(window.end);
      at = at.add(const Duration(hours: 1))
    ) {
      if (window.localTime(at).timeZoneOffset != at.toLocal().timeZoneOffset) {
        return false;
      }
    }
    return window.localTime(window.end).timeZoneOffset ==
        window.end.toLocal().timeZoneOffset;
  }

  // Existing deterministic helpers construct host-local day boundaries. Give
  // them consistently remapped calendar values, never mixed absolute UTC and
  // account-local dates; retain real instants for filtering and report export.
  static DateTime _wall(PrepWindow window, DateTime value) {
    final local = window.localTime(value);
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    );
  }
}

class _Record {
  const _Record({
    required this.id,
    required this.collection,
    required this.at,
    required this.availableAt,
    required this.provenance,
    required this.source,
    this.signal,
    this.checkIn,
    this.outcome,
  });
  final String id;
  final String collection;
  final DateTime at;
  final DateTime? availableAt;
  final String provenance;
  final String source;
  final SignalReading? signal;
  final DailyCheckIn? checkIn;
  final OutcomeRecord? outcome;
}
