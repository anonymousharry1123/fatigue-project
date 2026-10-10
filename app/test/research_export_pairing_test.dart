import 'dart:convert';

import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/models.dart';
import 'package:app/src/research_export.dart';
import 'package:app/src/self_report_trends_logic.dart';
import 'package:flutter_test/flutter_test.dart';

final _exportTime = DateTime.utc(2026, 10, 10, 20);

DailyCheckIn _report(
  String id,
  DateTime observedAt, {
  bool recordingTimeMissing = false,
}) => DailyCheckIn(
  id: id,
  timestamp: observedAt,
  recordedAt: recordingTimeMissing ? null : observedAt,
  energy: 7,
  fatigue: 3,
  period: CheckInPeriod.morning,
  localDate: '2026-10-10',
  utcOffsetMinutes: 0,
  timezone: 'Etc/UTC',
  questionnaireVersion: CheckInMeasurement.currentVersion,
  questionnaireLanguage: 'en',
  questionnaireSnapshot: CheckInMeasurement.snapshot(
    language: 'en',
    translate: (value) => value,
  ),
  source: 'selfReport',
);

ResearchExportBundle _export(
  List<DailyCheckIn> reports, {
  List<SignalReading> signals = const [],
}) => ResearchExport.build(
  checkIns: reports,
  signals: signals,
  studyCode: 'Participant014',
  generatedAt: _exportTime,
);

void main() {
  test('shared raw sleep preserves each response pairing availability', () {
    final earlier = _report('earlier', DateTime.utc(2026, 10, 10, 10));
    final later = _report('later', DateTime.utc(2026, 10, 10, 15));
    final savedAt = DateTime.utc(2026, 10, 10, 8);
    final signals = [
      SignalReading(
        id: 'private-manual-sleep',
        type: SignalType.sleep,
        value: 8,
        timestamp: DateTime.utc(2026, 10, 10, 7),
        recordedAt: savedAt,
        groupId: 'private-manual-group',
      ),
      SignalReading(
        id: 'private-manual-bedtime',
        type: SignalType.bedtime,
        value: 23,
        timestamp: DateTime.utc(2026, 10, 9, 23),
        groupId: 'private-manual-group',
      ),
      SignalReading(
        id: 'private-health-sleep',
        type: SignalType.sleep,
        value: 7,
        timestamp: DateTime.utc(2026, 10, 10, 11),
        syncedAt: DateTime.utc(2026, 10, 10, 12),
        source: SignalSource.healthKit,
        groupId: 'healthkit-sleep-2026-10-10',
      ),
      SignalReading(
        id: 'private-health-bedtime',
        type: SignalType.bedtime,
        value: 0,
        timestamp: DateTime.utc(2026, 10, 10),
        source: SignalSource.healthKit,
        groupId: 'healthkit-sleep-2026-10-10',
      ),
    ];
    final earlierMatch = SelfReportTrendsLogic.matchSleep(
      earlier,
      signals,
      _exportTime,
    );
    final laterMatch = SelfReportTrendsLogic.matchSleep(
      later,
      signals,
      _exportTime,
    );
    expect(earlierMatch.reading!.id, laterMatch.reading!.id);
    expect(earlierMatch.availabilityKnown, isTrue);
    expect(earlierMatch.availableAt, savedAt);
    expect(laterMatch.availabilityKnown, isFalse);
    expect(laterMatch.availableAt, isNull);

    final bundle = _export([later, earlier], signals: signals);
    final data = jsonDecode(bundle.json) as Map;
    final rawSleep = (data['sleepObservations'] as List).single as Map;
    final rows = (data['responses'] as List).cast<Map>();
    expect(rawSleep['availability_known'], isTrue);
    expect(rawSleep['record_available_at_utc'], savedAt.toIso8601String());
    expect(rows.first['sleep_ref'], rawSleep['sleep_ref']);
    expect(rows.last['sleep_ref'], rawSleep['sleep_ref']);
    expect(rows.first['sleep_pair_availability_known'], isTrue);
    expect(
      rows.first['sleep_pair_available_at_utc'],
      savedAt.toIso8601String(),
    );
    expect(rows.last['sleep_pair_availability_known'], isFalse);
    expect(rows.last['sleep_pair_available_at_utc'], isNull);
    expect(bundle.csv, contains('"sleep_pair_available_at_utc"'));
    expect(bundle.csv, contains('"sleep_pair_availability_known"'));
    expect(bundle.json, isNot(contains('private-manual-sleep')));
    expect(bundle.json, isNot(contains('private-health-bedtime')));
    expect(bundle.pairedCount, 2);
  });

  test('unmatched responses keep both pair availability fields absent', () {
    final bundle = _export([
      _report('unpaired', DateTime.utc(2026, 10, 10, 10)),
    ]);
    final row = (jsonDecode(bundle.json)['responses'] as List).single as Map;
    expect(row.containsKey('sleep_pair_available_at_utc'), isTrue);
    expect(row.containsKey('sleep_pair_availability_known'), isTrue);
    expect(row['sleep_pair_available_at_utc'], isNull);
    expect(row['sleep_pair_availability_known'], isNull);
    expect(row['sleep_ref'], isNull);
  });

  test(
    'null-versus-explicit duplicate recording times fail closed in any order',
    () {
      final at = DateTime.utc(2026, 10, 10, 10);
      final valid = _report('same-private-id', at);
      final missing = _report(
        'same-private-id',
        at,
        recordingTimeMissing: true,
      );
      for (final rows in [
        [valid, missing],
        [missing, valid],
      ]) {
        final result = _export(rows);
        final data = jsonDecode(result.json) as Map;
        expect(result.responseCount, 0);
        expect(result.excludedCount, 2);
        expect(data['responses'], isEmpty);
        expect(data['excludedCounts'], {
          'duplicate_id': 1,
          'conflicting_duplicate_id': 1,
        });
      }
    },
  );
}
