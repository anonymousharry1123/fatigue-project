import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/evidence_provenance.dart';
import 'package:app/src/firebase_emulator_options.dart';
import 'package:app/src/models.dart';
import 'package:app/src/research_export.dart';
import 'package:app/src/self_report_reference_logic.dart';
import 'package:app/src/self_report_trends_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Artificial acceptance records for the guarded native emulator harness only.
/// Normal storage/source fields exercise inclusion paths. They never represent
/// participant observations, and this helper refuses a normal app configuration.
const measurementAcceptanceNote = 'Isolated acceptance data only';
const measurementAcceptanceCurrentId = 'acceptance-current-morning';
const measurementAcceptanceHistoryDays = 8;

Map<String, dynamic> _definition() =>
    CheckInMeasurement.snapshot(language: 'en', translate: (text) => text);

Map<String, double?> _ratings(int day) => {
  'energy': day + 1.0,
  'fatigue': day == 8 ? null : 10.0 - day,
  'sleepiness': day <= 6 ? 2.0 + day % 5 : null,
  'focus': (day * 2) % 10 + 1.0,
  'mood': day == 3 ? null : 4.0 + day % 4,
  'stress': day.isOdd ? 9.0 - day : null,
};

const _currentRatings = <String, double?>{
  'energy': 8,
  'fatigue': 4,
  'sleepiness': 3,
  'focus': null,
  'mood': 6,
  'stress': 2,
};

Future<void> seedMeasurementHistory(AppController controller) async {
  if (!TonyoFirebaseEmulatorOptions.enabled ||
      controller.cloudUid == null ||
      !controller.canExportDeviceBackup ||
      !controller.privacyFeaturesAllowed) {
    throw StateError(
      'Acceptance data requires the isolated consented emulator.',
    );
  }
  expect(controller.outcomeConsent, isFalse);
  expect(controller.healthAuthorized, isFalse);
  final beforeOutcomes = controller.outcomes
      .map((row) => row.toJson())
      .toList();
  final anchor = controller.currentTime.toLocal();
  for (var day = measurementAcceptanceHistoryDays; day >= 1; day--) {
    // Calendar constructors preserve the chosen local day across DST. Sleep
    // uses the existing entry API, including its stored bedtime and end time.
    final observation = DateTime(
      anchor.year,
      anchor.month,
      anchor.day - day,
      9,
    );
    final wake = DateTime(anchor.year, anchor.month, anchor.day - day, 8);
    await controller.addSleep(
      id: 'acceptance-sleep-$day',
      bedtime: wake.subtract(Duration(minutes: 360 + day * 15)),
      wakeTime: wake,
      quality: 4,
    );
    expect(controller.cloudSyncError, isNull);
    final values = _ratings(day);
    await controller.saveSelfReportCheckIn(
      id: 'acceptance-morning-$day',
      timestamp: observation,
      period: CheckInPeriod.morning,
      energy: values['energy'],
      fatigue: values['fatigue'],
      sleepiness: values['sleepiness'],
      focus: values['focus'],
      mood: values['mood'],
      stress: values['stress'],
      note: measurementAcceptanceNote,
      questionnaireLanguage: 'en',
      questionnaireSnapshot: _definition(),
    );
    expect(controller.cloudSyncError, isNull);
  }
  // Save last so today's English morning panel uses this explicit response,
  // after the separate form acceptance walkthrough has finished.
  await controller.saveSelfReportCheckIn(
    id: measurementAcceptanceCurrentId,
    timestamp: anchor,
    period: CheckInPeriod.morning,
    energy: _currentRatings['energy'],
    fatigue: _currentRatings['fatigue'],
    sleepiness: _currentRatings['sleepiness'],
    focus: _currentRatings['focus'],
    mood: _currentRatings['mood'],
    stress: _currentRatings['stress'],
    note: measurementAcceptanceNote,
    questionnaireLanguage: 'en',
    questionnaireSnapshot: _definition(),
  );
  expect(controller.cloudSyncError, isNull);
  expect(
    controller.outcomes.map((row) => row.toJson()).toList(),
    beforeOutcomes,
  );
  expectMeasurementHistory(controller.checkIns, controller.signals);
}

/// Reused on actual preferences before hydration, fresh native server reads,
/// and the reconstructed controller. Expected observations use the *captured*
/// date and offset, rather than rewriting them from a later device timezone.
void expectMeasurementHistory(
  List<DailyCheckIn> checkIns,
  List<SignalReading> signals,
) {
  final current = checkIns.singleWhere(
    (row) => row.id == measurementAcceptanceCurrentId,
  );
  _expectReport(current, _currentRatings);
  final anchor = DateTime.parse('${current.localDate}T00:00:00Z');
  final history = checkIns.where(
    (row) => row.id.startsWith('acceptance-morning-'),
  );
  expect(history, hasLength(measurementAcceptanceHistoryDays));
  expect(
    history.map((row) => row.localDate).toSet(),
    hasLength(measurementAcceptanceHistoryDays),
  );
  for (var day = 1; day <= measurementAcceptanceHistoryDays; day++) {
    final response = checkIns.singleWhere(
      (row) => row.id == 'acceptance-morning-$day',
    );
    _expectReport(response, _ratings(day));
    expect(response.timezone, current.timezone);
    final expectedDate = anchor.subtract(Duration(days: day));
    expect(response.localDate, _dateText(expectedDate));
    final observedAtCapturedOffset = response.timestamp.toUtc().add(
      Duration(minutes: response.utcOffsetMinutes!),
    );
    expect(
      observedAtCapturedOffset,
      expectedDate.add(const Duration(hours: 9)),
    );
    final duration = signals.singleWhere(
      (row) => row.id == 'acceptance-sleep-$day-duration',
    );
    final bedtime = signals.singleWhere(
      (row) => row.id == 'acceptance-sleep-$day-bedtime',
    );
    expect(duration.groupId, 'acceptance-sleep-$day');
    expect(bedtime.groupId, duration.groupId);
    expect(duration.type, SignalType.sleep);
    expect(bedtime.type, SignalType.bedtime);
    expect(duration.source, SignalSource.manual);
    expect(bedtime.source, SignalSource.manual);
    expect(duration.quality, 0.8);
    expect(duration.syncedAt, isNull);
    expect(bedtime.syncedAt, isNull);
    expect(duration.recordedAt, isNotNull);
    expect(bedtime.recordedAt, duration.recordedAt);
    expect(duration.recordedAt!.isBefore(duration.timestamp), isFalse);
    expect(duration.timestamp.isBefore(response.timestamp), isTrue);
    expect(
      response.timestamp.difference(duration.timestamp),
      const Duration(hours: 1),
    );
    expect(
      duration.value,
      duration.timestamp.difference(bedtime.timestamp).inMinutes / 60,
    );
    expect(duration.value, inInclusiveRange(0.5, 16));
    expect(duration.value, 6 + day * 0.25);
    expect(EvidenceProvenance.signalIsDemo(duration), isFalse);
  }
}

void _expectReport(DailyCheckIn report, Map<String, double?> ratings) {
  expect(report.ratings, ratings);
  expect(report.isValidResearchResponse, isTrue);
  expect(report.period, CheckInPeriod.morning);
  expect(report.questionnaireVersion, CheckInMeasurement.currentVersion);
  expect(report.questionnaireLanguage, 'en');
  expect(report.questionnaireSnapshot, _definition());
  expect(report.source, 'selfReport');
  expect(report.note, measurementAcceptanceNote);
  expect(report.localDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  expect(report.utcOffsetMinutes, isNotNull);
  expect(report.recordedAt, isNotNull);
  expect(report.recordedAt!.isBefore(report.timestamp), isFalse);
  expect(report.originalLegacyRatings, isNull);
  expect(report.legacyPeriodMissing, isFalse);
  final count = ratings.values.where((value) => value != null).length;
  expect(report.answeredItemCount, count);
  expect(report.completionStatus, count == 6 ? 'complete' : 'partial');
  expect(EvidenceProvenance.hasDemoMarker([report.id, report.note]), isFalse);
  expect(DailyCheckIn.fromJson(report.toJson()).toJson(), report.toJson());
}

/// Read-only checks over the controller's already-loaded owner records. No
/// fetch, save, consent change, prediction generation or training is performed.
void verifyMeasurementReadModels(AppController controller) {
  expectMeasurementHistory(controller.checkIns, controller.signals);
  final before = _rawSnapshot(controller);
  final current = controller.checkIns.singleWhere(
    (row) => row.id == measurementAcceptanceCurrentId,
  );
  final now = controller.currentTime;
  final reference = SelfReportReferenceLogic.build(
    checkIns: controller.checkIns,
    current: current,
    asOf: now,
  );
  expect(reference.currentCompatible, isTrue);
  expect(reference.metrics['energy']!.sampleCount, 8);
  expect(reference.metrics['energy']!.average, 5.5);
  expect(reference.metrics['energy']!.currentValue, 8);
  expect(reference.metrics['energy']!.difference, 2.5);
  expect(reference.metrics['fatigue']!.sampleCount, 7);
  expect(reference.metrics['fatigue']!.average, 6);
  expect(reference.metrics['fatigue']!.difference, -2);
  expect(reference.metrics['sleepiness']!.sampleCount, 6);
  expect(reference.metrics['sleepiness']!.average, isNull);
  expect(reference.metrics['focus']!.sampleCount, 8);
  expect(reference.metrics['focus']!.average, 5);
  expect(reference.metrics['focus']!.currentValue, isNull);
  expect(reference.metrics['focus']!.difference, isNull);
  expect(reference.metrics['mood']!.sampleCount, 7);
  expect(reference.metrics['stress']!.sampleCount, 4);
  expect(reference.metrics['stress']!.average, isNull);

  final trends = SelfReportTrendsLogic.build(
    checkIns: controller.checkIns,
    signals: controller.signals,
    now: now,
    period: CheckInPeriod.morning,
    questionnaireLanguage: 'en',
    endDate: current.localDate,
  );
  expect(trends.days, hasLength(28));
  expect(trends.selectedReportCount, 9);
  expect(trends.days.last.response!.id, measurementAcceptanceCurrentId);
  expect(trends.series['energy']!.answeredCount, 9);
  expect(trends.series['energy']!.matchedCount, greaterThanOrEqualTo(8));
  expect(trends.series['fatigue']!.answeredCount, 8);
  expect(trends.series['sleepiness']!.answeredCount, 7);
  expect(trends.series['focus']!.answeredCount, 8);
  expect(trends.series['focus']!.values.last, isNull);
  expect(trends.series['stress']!.answeredCount, 5);
  expect(trends.series['energy']!.values.take(19), everyElement(isNull));
  for (var day = 1; day <= measurementAcceptanceHistoryDays; day++) {
    final row = trends.days.singleWhere(
      (row) => row.response?.id == 'acceptance-morning-$day',
    );
    expect(row.matchedSleep!.isMatched, isTrue);
    expect(row.matchedSleep!.reading!.id, 'acceptance-sleep-$day-duration');
    expect(row.matchedSleep!.source, SignalSource.manual);
    expect(row.matchedSleep!.availabilityKnown, isTrue);
    expect(row.matchedSleep!.availableAt, isNotNull);
  }
  expect(
    trends.days
        .where((day) => day.matchedSleep?.isMatched == true)
        .map((day) => day.matchedSleep!.durationHours)
        .toSet()
        .length,
    greaterThan(1),
  );

  final export = ResearchExport.build(
    checkIns: controller.checkIns,
    signals: controller.signals,
    studyCode: 'AcceptanceOnly',
    generatedAt: now,
  );
  final data = jsonDecode(export.json) as Map<String, dynamic>;
  final rows = (data['responses'] as List).cast<Map<String, dynamic>>();
  final definitions = data['questionnaireDefinitions'] as Map;
  final sleeps = (data['sleepObservations'] as List)
      .cast<Map<String, dynamic>>();
  expect(data['exportVersion'], ResearchExport.version);
  expect(data['researchProtocolApproved'], isFalse);
  expect(rows.length, export.responseCount);
  expect(export.responseCount, greaterThanOrEqualTo(11));
  expect(export.pairedCount, greaterThanOrEqualTo(8));
  expect(export.partialCount, greaterThan(0));
  expect(export.csv, startsWith('"study_code","response_ref"'));
  expect(export.csv, endsWith('\r\n'));
  expect(export.csv, contains('"sleep_pair_available_at_utc"'));
  expect(export.json, isNot(contains(measurementAcceptanceNote)));
  if (controller.cloudUid != null) {
    expect(export.json, isNot(contains(controller.cloudUid!)));
    expect(export.csv, isNot(contains(controller.cloudUid!)));
  }
  for (final report in controller.checkIns.where(
    (row) =>
        row.id.startsWith('acceptance-morning-') ||
        row.id == measurementAcceptanceCurrentId,
  )) {
    final row = rows.singleWhere(
      (row) =>
          row['observed_at_utc'] ==
              report.timestamp.toUtc().toIso8601String() &&
          row['period'] == report.period.name &&
          row['questionnaire_language'] == 'en',
    );
    expect(row.keys.toSet(), (data['dataDictionary'] as Map).keys.toSet());
    expect(row['study_code'], 'AcceptanceOnly');
    expect(
      row['recorded_at_utc'],
      report.recordedAt!.toUtc().toIso8601String(),
    );
    expect(row['local_date'], report.localDate);
    expect(row['timezone'], report.timezone);
    expect(row['utc_offset_minutes'], report.utcOffsetMinutes);
    expect(row['questionnaire_version'], report.questionnaireVersion);
    expect(row['source'], 'selfReport');
    expect(row['completion_status'], report.completionStatus);
    expect(row['answered_item_count'], report.answeredItemCount);
    expect(definitions[row['definition_ref']], report.questionnaireSnapshot);
    for (final entry in report.ratings.entries) {
      expect(row['${entry.key}_1_to_10'], entry.value);
    }
    expect(export.json, isNot(contains(report.id)));
    expect(export.csv, isNot(contains(report.id)));
    if (report.id != measurementAcceptanceCurrentId) {
      final pair = SelfReportTrendsLogic.matchSleep(
        report,
        controller.signals,
        now,
      );
      final rawSleep = sleeps.singleWhere(
        (sleep) => sleep['sleep_ref'] == row['sleep_ref'],
      );
      expect(row['sleep_match_status'], 'matched');
      expect(row['sleep_hours'], pair.durationHours);
      expect(row['sleep_pair_availability_known'], isTrue);
      expect(
        row['sleep_pair_available_at_utc'],
        pair.availableAt!.toUtc().toIso8601String(),
      );
      expect(
        rawSleep.keys.toSet(),
        (data['sleepObservationDictionary'] as Map).keys.toSet(),
      );
      expect(rawSleep['source'], 'manual');
      expect(rawSleep['duration_hours'], pair.reading!.value);
      expect(
        rawSleep['sleep_end_at_utc'],
        pair.endTime!.toUtc().toIso8601String(),
      );
      expect(
        rawSleep['recorded_at_utc'],
        pair.reading!.recordedAt!.toUtc().toIso8601String(),
      );
      expect(rawSleep['synced_at_utc'], isNull);
      expect(rawSleep['availability_known'], isTrue);
      expect(export.json, isNot(contains(pair.reading!.id)));
    }
  }
  expect(
    controller.outcomes.where((row) => row.sourceId.startsWith('acceptance-')),
    isEmpty,
  );
  expect(controller.outcomeConsent, isFalse);
  expect(controller.healthAuthorized, isFalse);
  expect(_rawSnapshot(controller), before);
}

String _rawSnapshot(AppController controller) => jsonEncode({
  'checkIns': controller.checkIns.map((row) => row.toJson()).toList(),
  'signals': controller.signals.map((row) => row.toJson()).toList(),
  'outcomes': controller.outcomes.map((row) => row.toJson()).toList(),
});

String _dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
