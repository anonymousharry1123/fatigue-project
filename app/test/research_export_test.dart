import 'dart:convert';

import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/models.dart';
import 'package:app/src/research_export.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 10, 20);

DailyCheckIn _report({
  String id = 'private-response-id',
  double? energy = 7,
  String note = 'PRIVATE NOTE',
  DateTime? recordedAt,
}) => DailyCheckIn(
  id: id,
  timestamp: _now,
  recordedAt: recordedAt ?? _now,
  period: CheckInPeriod.evening,
  energy: energy,
  fatigue: 4,
  mood: null,
  stress: null,
  localDate: '2026-10-10',
  utcOffsetMinutes: 0,
  timezone: 'Etc/UTC',
  questionnaireVersion: CheckInMeasurement.currentVersion,
  questionnaireLanguage: 'en',
  source: 'selfReport',
  note: note,
  questionnaireSnapshot: CheckInMeasurement.snapshot(
    language: 'en',
    translate: (text) => text,
  ),
);

ResearchExportBundle _export(
  List<DailyCheckIn> rows, {
  List<SignalReading> signals = const [],
}) => ResearchExport.build(
  checkIns: rows,
  signals: signals,
  studyCode: 'P001',
  generatedAt: _now,
);

void main() {
  test(
    'raw partial rows, dictionary and definitions export without identifying notes or IDs',
    () {
      final report = _report();
      final original = jsonEncode(report.toJson());
      final result = _export([report]);
      final data = jsonDecode(result.json) as Map;
      final row = (data['responses'] as List).single as Map;
      expect(row['energy_1_to_10'], 7);
      expect(row['fatigue_1_to_10'], 4);
      expect(row['focus_1_to_10'], isNull);
      expect(row['completion_status'], 'partial');
      expect(row['answered_item_count'], 2);
      expect(row['observed_at_utc'], _now.toIso8601String());
      expect(row['period'], 'evening');
      expect(data['researchProtocolApproved'], false);
      expect((data['dataDictionary'] as Map).keys.toSet(), row.keys.toSet());
      expect(
        (data['questionnaireDefinitions'] as Map)[row['definition_ref']],
        report.questionnaireSnapshot,
      );
      expect(result.json, isNot(contains('PRIVATE NOTE')));
      expect(result.json, isNot(contains(report.id)));
      expect(result.csv, isNot(contains(report.id)));
      expect(result.csv.split('\r\n')[1], contains('"7","4",,,,,'));
      expect(jsonEncode(report.toJson()), original);
    },
  );

  test(
    'retains repeated submissions and partial rows; duplicate IDs resolve before eligibility',
    () {
      final first = _report();
      final cleared = _report(energy: null);
      final older = _report(
        recordedAt: _now.subtract(const Duration(seconds: 1)),
      );
      // Old record has impossible availability and is replaced before export.
      final result = _export([older, cleared, _report(id: 'second')]);
      final rows = (jsonDecode(result.json)['responses'] as List).cast<Map>();
      expect(rows.length, 2);
      expect(rows.first['energy_1_to_10'], isNull);
      expect(result.partialCount, 2);
      expect(result.excludedCount, 1);
      expect(_export([first, cleared]).responseCount, 0);
      expect(_export([cleared, first]).responseCount, 0);
    },
  );

  test(
    'invalid, legacy, demo and future rows are counted but not relabeled',
    () {
      final result = _export([
        _report(),
        _report(id: 'demo-1'),
        _report(id: 'syn-1'),
        _report(id: 'invalid', energy: 0),
        _report(id: 'later', recordedAt: _now.add(const Duration(seconds: 1))),
        DailyCheckIn(id: 'legacy', timestamp: _now, energy: 4),
      ]);
      expect(result.responseCount, 1);
      expect(result.excludedCount, 5);
      expect(jsonDecode(result.json)['excludedCounts'], {
        'synthetic': 2,
        'invalid': 1,
        'future_or_unavailable': 1,
        'legacy': 1,
      });
    },
  );

  test(
    'sleep pair preserves raw source and unknown availability without raw IDs',
    () {
      final sleep = SignalReading(
        id: 'private-health-uuid',
        type: SignalType.sleep,
        value: 7.75,
        timestamp: _now.subtract(const Duration(hours: 12)),
        source: SignalSource.healthKit,
      );
      final result = _export([_report()], signals: [sleep]);
      final data = jsonDecode(result.json);
      final paired = (data['sleepObservations'] as List).single as Map;
      expect(paired['duration_hours'], 7.75);
      expect(paired['source'], 'healthKit');
      expect(paired['record_available_at_utc'], isNull);
      expect(paired['availability_known'], false);
      expect(
        (data['responses'] as List).single['sleep_ref'],
        paired['sleep_ref'],
      );
      expect(result.json, isNot(contains('private-health-uuid')));
      expect(result.pairedCount, 1);
    },
  );

  test(
    'no sleep, future sleep and naps remain unpaired with explicit reasons',
    () {
      final result = _export(
        [_report()],
        signals: [
          SignalReading(
            id: 'nap',
            type: SignalType.nap,
            value: 1,
            timestamp: _now.subtract(const Duration(hours: 2)),
          ),
          SignalReading(
            id: 'future',
            type: SignalType.sleep,
            value: 8,
            timestamp: _now.add(const Duration(hours: 1)),
          ),
        ],
      );
      final row = (jsonDecode(result.json)['responses'] as List).single;
      expect(row['sleep_hours'], isNull);
      expect(row['sleep_ref'], isNull);
      expect(row['sleep_match_status'], isNotEmpty);
      expect(result.pairedCount, 0);
    },
  );

  test(
    'study codes are explicit and resist CSV formulas or accidental emails',
    () {
      for (final code in [
        '',
        '=HYPERLINK()',
        '+abc',
        'person@example.com',
        'two words',
        'A' * 33,
      ]) {
        expect(
          () => ResearchExport.build(
            checkIns: [],
            signals: [],
            studyCode: code,
            generatedAt: _now,
          ),
          throwsArgumentError,
        );
      }
      expect(ResearchExport.validStudyCode('Study_014-a'), true);
    },
  );

  test(
    'empty export is valid and preparation has no state retained between exports',
    () {
      final empty = _export([]);
      expect(empty.responseCount, 0);
      expect(jsonDecode(empty.json)['responses'], isEmpty);
      _export([_report(), _report(energy: null)]);
      expect(_export([_report()]).responseCount, 1);
      expect(empty.csv, endsWith('\r\n'));
    },
  );
}
