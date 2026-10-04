import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/daily_history_logic.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

DailyCheckIn response({double? energy = 7, double? fatigue = 3}) =>
    DailyCheckIn(
      id: 'checkin-research',
      timestamp: DateTime.utc(2026, 10, 5, 1),
      recordedAt: DateTime.utc(2026, 10, 5, 1, 1),
      period: CheckInPeriod.morning,
      energy: energy,
      fatigue: fatigue,
      localDate: '2026-10-04',
      timezone: 'America/Los_Angeles',
      utcOffsetMinutes: -420,
      questionnaireVersion: CheckInMeasurement.currentVersion,
      questionnaireLanguage: 'en',
      source: 'selfReport',
      questionnaireSnapshot: CheckInMeasurement.snapshot(
        language: 'en',
        translate: (text) => text,
      ),
    );

void main() {
  test('history groups reports by their captured local date after travel', () {
    final raw = response().toJson()
      ..addAll({
        'timestamp': '2026-10-04T20:00:00Z',
        'recordedAt': '2026-10-04T20:01:00Z',
        'localDate': '2026-10-05',
        'timezone': 'Asia/Shanghai',
        'utcOffsetMinutes': 480,
      });
    final report = DailyCheckIn.fromJson(raw);
    final days = DailyHistoryLogic.build(
      signals: [],
      checkIns: [report],
      activityLogs: [],
      sleepLogs: [],
    );
    expect(days.single.date, DateTime(2026, 10, 5));
    expect(report.timestamp.toUtc(), DateTime.utc(2026, 10, 4, 20));
  });
  test('removing the version cannot disguise a new response as legacy', () {
    for (final remove in [true, false]) {
      final malformed = response().toJson();
      if (remove) {
        malformed.remove('questionnaireVersion');
      } else {
        malformed['questionnaireVersion'] = null;
      }
      expect(() => DailyCheckIn.fromJson(malformed), throwsFormatException);
    }
    final partial = DailyCheckIn(
      id: 'missing-version',
      timestamp: DateTime(2026),
      energy: 7,
      mood: 6,
      stress: 4,
      fatigue: 3,
    );
    expect(partial.isResearchCheckIn, isTrue);
    expect(() => partial.toJson(), throwsFormatException);
  });
  test(
    'partial six-measure response keeps skipped answers and integer wire values',
    () {
      final original = response();
      final json = original.toJson();
      expect(json['energy'], isA<int>());
      expect(json['fatigue'], 3);
      expect(json['sleepiness'], isNull);
      expect(json['focus'], isNull);
      expect(json['mood'], isNull);
      expect(json['stress'], isNull);
      final loaded = DailyCheckIn.fromJson(json);
      expect(loaded.isResearchCheckIn, isTrue);
      expect(loaded.answeredItemCount, 2);
      expect(loaded.completionStatus, 'partial');
      expect(loaded.toJson(), json);
    },
  );

  test('explicit morning remains morning even when local clock is evening', () {
    final loaded = checkInFromCloud(
      'checkin-research',
      checkInToCloud(response()),
    );
    expect(loaded.period, CheckInPeriod.morning);
    expect(loaded.timestamp.toUtc(), DateTime.utc(2026, 10, 5, 1));
    expect(loaded.localDate, '2026-10-04');
    expect(loaded.timezone, 'America/Los_Angeles');
    expect(loaded.utcOffsetMinutes, -420);
    expect(loaded.recordedAt!.toUtc(), DateTime.utc(2026, 10, 5, 1, 1));
  });

  test('complete status is derived from all six independent answers', () {
    final json = response().toJson()
      ..addAll({
        'sleepiness': 2,
        'focus': 8,
        'mood': 6,
        'stress': 4,
        'answeredItemCount': 6,
        'completionStatus': 'complete',
      });
    final loaded = DailyCheckIn.fromJson(json);
    expect(loaded.completionStatus, 'complete');
    expect(loaded.ratings.values, [7, 3, 2, 8, 6, 4]);
  });

  test(
    'zero, fractional and out-of-range research ratings are rejected rather than clamped',
    () {
      for (final invalid in [
        0.0,
        -1.0,
        11.0,
        7.5,
        double.nan,
        double.infinity,
      ]) {
        expect(() => response(energy: invalid).toJson(), throwsFormatException);
      }
      expect(
        () => response(energy: null, fatigue: null).toJson(),
        throwsFormatException,
      );
    },
  );

  test(
    'unknown timezone stays unknown while captured offset and date survive',
    () {
      final json = response().toJson()..['timezone'] = null;
      final loaded = checkInFromCloud('checkin-research', {
        ...json,
        'timestamp': DateTime.utc(2026, 10, 5, 1),
        'recordedAt': DateTime.utc(2026, 10, 5, 1, 1),
      });
      expect(loaded.timezone, isNull);
      expect(loaded.localDate, '2026-10-04');
      expect(loaded.utcOffsetMinutes, -420);
    },
  );

  test(
    'inconsistent completeness, date or missing explicit period fails closed',
    () {
      for (final patch in [
        {'completionStatus': 'complete'},
        {'answeredItemCount': 6},
        {'localDate': '2026-10-05'},
        {'localDate': '2026-02-30'},
        {'utcOffsetMinutes': 900},
        {'period': null},
        {'recordedAt': '2026-10-04T00:00:00Z'},
      ]) {
        expect(
          () => DailyCheckIn.fromJson({...response().toJson(), ...patch}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'questionnaire language and exact wording survive local and cloud reload',
    () {
      final json = response().toJson();
      final snapshot = CheckInMeasurement.snapshot(
        language: 'zh-Hant',
        translate: (text) => '翻譯：$text',
      );
      json.addAll({
        'questionnaireLanguage': 'zh-Hant',
        'questionnaireSnapshot': snapshot,
      });
      final loaded = DailyCheckIn.fromJson(json);
      expect(
        checkInFromCloud(
          loaded.id,
          checkInToCloud(loaded),
        ).questionnaireSnapshot,
        snapshot,
      );
      expect(loaded.questionnaireLanguage, 'zh-Hant');
    },
  );

  test('mismatched or oversized questionnaire definitions are rejected', () {
    for (final mutation in [
      (Map<String, dynamic> value) => value['language'] = 'es',
      (Map<String, dynamic> value) => value['items'] = [],
      (Map<String, dynamic> value) => value['extra'] = true,
      (Map<String, dynamic> value) => value['recallPeriodText'] = 'x' * 101,
    ]) {
      final json = response().toJson();
      mutation(json['questionnaireSnapshot'] as Map<String, dynamic>);
      expect(() => DailyCheckIn.fromJson(json), throwsFormatException);
    }
  });

  test(
    'legacy 1–5 responses retain original raw values through repeated local/cloud serialization',
    () {
      final raw = <String, dynamic>{
        'id': 'old',
        'timestamp': '2026-07-20T08:00:00.000Z',
        'energy': 4,
        'mood': 3,
        'stress': 2,
      };
      final legacy = DailyCheckIn.fromJson(raw);
      expect(legacy.energy, 8); // Explicit old scoring/display projection.
      expect(legacy.originalLegacyRatings, {
        'energy': 4,
        'mood': 3,
        'stress': 2,
      });
      expect(legacy.toJson()['energy'], 4);
      expect(legacy.toJson(), isNot(contains('period')));
      final loaded = checkInFromCloud(legacy.id, checkInToCloud(legacy));
      expect(loaded.toJson()['energy'], 4);
      expect(loaded.energy, 8);
      expect(loaded.questionnaireVersion, isNull);
      expect(loaded.questionnaireLanguage, isNull);
      expect(loaded.localDate, isNull);
      expect(loaded.timezone, isNull);
      expect(loaded.completionStatus, isNull);
    },
  );

  test('legacy fractional values are preserved without research metadata', () {
    final old = DailyCheckIn(
      id: 'old-current',
      timestamp: DateTime(2026, 10, 4),
      energy: 6.75,
      mood: 7.2,
      stress: 3.5,
    );
    final loaded = checkInFromCloud(old.id, checkInToCloud(old));
    expect(loaded.energy, 6.75);
    expect(loaded.isResearchCheckIn, isFalse);
    expect(loaded.toJson(), isNot(contains('fatigue')));
    expect(loaded.toJson(), isNot(contains('questionnaireVersion')));
  });

  test(
    'clearing a selected answer emits null under the existing merge protocol',
    () {
      final before = (syncCanonical(checkInToCloud(response())) as Map)
          .cast<String, dynamic>();
      final after =
          (syncCanonical(checkInToCloud(response(energy: null))) as Map)
              .cast<String, dynamic>();
      final patch = syncMergedData(before, after);
      expect(patch.containsKey('energy'), isTrue);
      expect(patch['energy'], isNull);
      final merged = {...checkInToCloud(response()), ...patch};
      final loaded = checkInFromCloud('checkin-research', merged);
      expect(loaded.energy, isNull);
      expect(loaded.fatigue, 3);
      expect(loaded.answeredItemCount, 1);
    },
  );
}
