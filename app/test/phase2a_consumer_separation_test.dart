import 'package:app/src/cloud_schema.dart';
import 'package:app/src/daily_plan_logic.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 7, 21, 20);
  DailyCheckIn checkIn({
    String? id,
    DateTime? timestamp,
    double? energy = 2,
    double? mood = 1,
    double? stress = 10,
    bool research = false,
  }) {
    final when = timestamp ?? at;
    return DailyCheckIn(
      id: id ?? 'checkin-${when.microsecondsSinceEpoch}',
      timestamp: when,
      recordedAt: when,
      energy: energy,
      mood: mood,
      stress: stress,
      fatigue: research ? 10 : null,
      sleepiness: research ? 10 : null,
      focus: research ? 1 : null,
      questionnaireVersion: research ? 'tonyo-self-report-draft-v1' : null,
    );
  }

  ScoreSnapshot score(List<DailyCheckIn> rows) =>
      FatigueEngine.score(signals: const [], checkIns: rows, now: at);

  List<ForecastPoint> forecast(List<DailyCheckIn> rows) =>
      FatigueEngine.forecast(
        score(rows),
        at,
        signals: const [],
        checkIns: rows,
        generatedAt: at,
      );

  test(
    'research-only reports create no legacy estimates, curves or Coach plan',
    () {
      final rows = [checkIn(research: true)];
      final snapshot = score(rows);
      expect(snapshot.canEstimateEnergy, isFalse);
      expect(snapshot.canEstimateCognitive, isFalse);
      expect(snapshot.inputCount, 0);
      expect(snapshot.cognitiveInputCount, 0);
      expect(forecast(rows), isEmpty);
      expect(
        DailyPlanLogic.build(
          windows: FatigueEngine.windows(
            forecast(rows),
            snapshot,
            checkIns: rows,
          ),
          score: snapshot,
          profile: const UserProfile(),
          day: at,
          generatedAt: at,
        ),
        isEmpty,
      );
    },
  );

  test(
    'later research reports leave all legacy score and forecast values unchanged',
    () {
      final legacy = checkIn(
        timestamp: at.subtract(const Duration(hours: 1)),
        energy: 7,
        mood: 6,
        stress: 4,
      );
      final original = [legacy];
      final mixed = [legacy, checkIn(research: true)];
      expect(score(original).canEstimateEnergy, isTrue);
      expect(
        scoreSnapshotToCloud(snapshot: score(mixed), day: at),
        scoreSnapshotToCloud(snapshot: score(original), day: at),
      );
      List<Object?> values(List<DailyCheckIn> rows) => [
        for (final point in forecast(rows))
          [
            point.time,
            point.energy,
            point.uncertainty,
            point.checkInEvidenceIds,
          ],
      ];
      expect(values(mixed), values(original));
      expect(
        forecast(mixed).expand((point) => point.checkInEvidenceIds).toSet(),
        {legacy.id},
      );
    },
  );

  test(
    'partial and malformed legacy reports abstain without midpoint filling',
    () {
      final invalid = [
        checkIn(energy: null),
        checkIn(mood: null),
        checkIn(stress: null),
        checkIn(energy: 0),
        checkIn(mood: double.nan),
        checkIn(stress: double.infinity),
      ];
      for (final row in invalid) {
        final snapshot = score([row]);
        expect(snapshot.canEstimateEnergy, isFalse);
        expect(snapshot.canEstimateCognitive, isFalse);
        expect(forecast([row]), isEmpty);
      }
    },
  );

  test(
    'research observations cannot contribute legacy fatigue-stress alerts',
    () {
      List<DailyCheckIn> history(bool research) => [
        for (var days = 0; days < 3; days++)
          checkIn(
            timestamp: at.subtract(Duration(days: days)),
            research: research,
          ),
      ];
      final legacy = history(false);
      final research = history(true);
      expect(
        FatigueEngine.alerts([], legacy, score(legacy), now: at),
        hasLength(1),
      );
      expect(
        FatigueEngine.alerts([], research, score(research), now: at),
        isEmpty,
      );
      final mixed = [legacy.first, ...research.skip(1)];
      expect(FatigueEngine.alerts([], mixed, score(mixed), now: at), isEmpty);
    },
  );

  test(
    'cached links cannot present research or partial rows as forecast evidence',
    () {
      final research = checkIn(research: true);
      final partial = checkIn(id: 'partial', mood: null);
      final legacy = checkIn(id: 'legacy');
      final points = [
        ForecastPoint(
          at,
          60,
          20,
          rulesVersion: FatigueEngine.energyModelVersion,
          checkInEvidenceIds: [research.id, partial.id],
        ),
      ];
      final windows = FatigueEngine.windows(
        points,
        score([legacy]),
        checkIns: [research, partial],
      );
      expect(windows, isNotEmpty);
      expect(windows.expand((window) => window.evidence), isEmpty);
      expect(
        DailyPlanLogic.build(
          windows: windows,
          score: score([legacy]),
          profile: const UserProfile(),
          day: at,
          generatedAt: at,
        ),
        isEmpty,
      );
    },
  );

  PrepSnapshot snapshot({
    required List<Map<String, dynamic>> checkIns,
    List<Map<String, dynamic>> outcomes = const [],
    List<Map<String, dynamic>> signals = const [],
  }) => PrepSnapshot(
    uid: 'phase2a-isolated-account',
    window: PrepWindow.endingOn(DateTime(2026, 7, 31), timezone: 'UTC'),
    consent: const PrepConsent(collection: true, trainingUse: true, version: 1),
    fetchedAt: DateTime.utc(2026, 8, 1),
    schemaVersion: cloudSchemaVersion,
    signals: signals,
    checkIns: checkIns,
    outcomes: outcomes,
  );

  Map<String, dynamic> raw(int hour, {bool research = false}) => {
    'id': 'checkin-${DateTime.utc(2026, 7, 21, hour).microsecondsSinceEpoch}',
    'timestamp': DateTime.utc(2026, 7, 21, hour).toIso8601String(),
    'recordedAt': DateTime.utc(2026, 7, 21, hour).toIso8601String(),
    'period': hour < 14 ? 'morning' : 'evening',
    'energy': 2,
    'mood': 1,
    'stress': 10,
    if (research) ...{
      'questionnaireVersion': 'tonyo-self-report-draft-v1',
      'fatigue': 10,
      'sleepiness': 10,
      'focus': 1,
    },
  };

  Map<String, dynamic> outcome(Map<String, dynamic> row) => {
    'id': 'energy-${row['id']}',
    'type': 'observedEnergy',
    'value': row['energy'],
    'unit': 'rating_1_10',
    'observedAt': row['timestamp'],
    'recordedAt': row['timestamp'],
    'source': 'checkIn',
    'sourceId': row['id'],
    'consentVersion': 1,
  };

  test(
    'old Energy outcomes referencing research rows cannot become labels',
    () {
      final research = raw(20, research: true);
      for (final source in [
        research,
        {...research, 'mood': null},
      ]) {
        final report = MlPrepBuilder.build(
          snapshot(checkIns: [source], outcomes: [outcome(source)]),
        );
        expect(report.examples, isEmpty);
        expect(report.energyReady, isFalse);
        final rejected = report.toJson()['rejectedRows'] as List;
        expect(
          rejected,
          contains(
            equals({
              'collection': 'outcomes',
              'id': 'energy-${source['id']}',
              'reason': 'research_measurement_not_compatible',
            }),
          ),
        );
      }
    },
  );

  test(
    'research and incomplete legacy context cannot change old preparation',
    () {
      final target = raw(20);
      final original = MlPrepBuilder.build(
        snapshot(checkIns: [target], outcomes: [outcome(target)]),
      );
      for (final context in [
        raw(8, research: true),
        {...raw(8), 'energy': null},
        {...raw(8), 'mood': null},
        {...raw(8), 'stress': null},
      ]) {
        final mixed = MlPrepBuilder.build(
          snapshot(checkIns: [context, target], outcomes: [outcome(target)]),
        );
        expect(
          mixed.examples.single.toJson(),
          original.examples.single.toJson(),
        );
        expect(mixed.examples.single.features['mood'], isNull);
        expect(mixed.examples.single.features['stress'], isNull);
      }
      final compatible = MlPrepBuilder.build(
        snapshot(checkIns: [raw(8), target], outcomes: [outcome(target)]),
      );
      expect(compatible.examples.single.features['mood'], -1);
      expect(compatible.examples.single.features['stress'], 1);
    },
  );

  test(
    'duplicated research IDs cannot masquerade as old labels or features',
    () {
      final research = raw(8, research: true);
      final legacyDuplicate = raw(8);
      final target = raw(20);
      final report = MlPrepBuilder.build(
        snapshot(
          checkIns: [research, legacyDuplicate, target],
          outcomes: [outcome(legacyDuplicate), outcome(target)],
        ),
      );
      expect(report.examples, hasLength(1));
      expect(report.examples.single.outcomeId, 'energy-${target['id']}');
      expect(report.examples.single.features['mood'], isNull);
      expect(report.examples.single.features['stress'], isNull);
    },
  );

  test('research context is excluded from cognitive preparation too', () {
    final research = raw(8, research: true);
    final reaction = {
      'id': 'manual-${DateTime.utc(2026, 7, 21, 20).microsecondsSinceEpoch}',
      'timestamp': DateTime.utc(2026, 7, 21, 20).toIso8601String(),
      'recordedAt': DateTime.utc(2026, 7, 21, 20).toIso8601String(),
      'type': 'reactionTime',
      'value': 300,
      'source': 'manual',
    };
    final report = MlPrepBuilder.build(
      snapshot(
        checkIns: [research],
        signals: [reaction],
        outcomes: [
          {
            'id': 'reaction-outcome',
            'type': 'cognitiveReaction',
            'value': 300,
            'unit': 'ms',
            'observedAt': reaction['timestamp'],
            'recordedAt': reaction['recordedAt'],
            'source': 'reactionSignal',
            'sourceId': reaction['id'],
            'consentVersion': 1,
          },
        ],
      ),
    );
    expect(report.examples.single.head, 'cognitive');
    expect(report.examples.single.features['mood'], isNull);
    expect(report.examples.single.features['stress'], isNull);
    expect(
      report.examples.single.featureSources.values.expand((ids) => ids),
      isEmpty,
    );
  });

  test(
    'live inference ignores research reports and keeps the legacy features',
    () {
      // Match the same supported host-zone fixture used by existing live-input tests.
      final zone = at.timeZoneOffset.inHours == -7
          ? 'America/Los_Angeles'
          : 'Etc/UTC';
      final legacy = checkIn(timestamp: at.subtract(const Duration(hours: 1)));
      TrainingExample? input(List<DailyCheckIn> rows) =>
          MlPrepBuilder.energyInput(
            signals: const [],
            checkIns: rows,
            at: at,
            timezone: zone,
          );
      final original = input([legacy]);
      expect(original, isNotNull);
      expect(
        input([legacy, checkIn(research: true)])!.toJson(),
        original!.toJson(),
      );
      expect(input([checkIn(research: true)])!.features['mood'], isNull);
      expect(input([checkIn(research: true)])!.features['stress'], isNull);
    },
  );
}
