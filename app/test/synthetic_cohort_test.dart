import 'package:app/src/models.dart';
import 'package:app/src/synthetic/cohort_mapper.dart';
import 'package:app/src/synthetic/cohort_stats.dart';
import 'package:app/src/synthetic/csv_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleCsv = '''
student_id,age,gender,education_level,avg_sleep_hours,screen_time_hours,social_media_hours,study_hours_per_day,exercise_hours_per_week,caffeine_drinks_per_day,stress_level,anxiety_score,gpa,uses_sleep_app,feels_burned_out
1,21,Non-binary,High School,8.0,4.9,3.7,5.0,4.8,1,7,7,3.35,False,True
2,19,Female,Undergraduate,7.3,7.7,5.3,2.8,4.2,1,8,8,2.81,True,True
''';

void main() {
  final now = DateTime(2026, 8, 1, 12);

  group('SyntheticCohortMapper', () {
    test('maps the two sample rows into folded screen and daily exercise', () {
      final people = SyntheticCsvLoader.parseCsv(_sampleCsv, now: now);
      expect(people, hasLength(2));

      final first = people.first;
      expect(first.id, '1');
      expect(first.age, 21);
      expect(first.gender, 'Non-binary');
      expect(first.education, 'High School');
      expect(first.ageRange, '18+');
      expect(first.role, 'Student');
      expect(first.foldedScreenHours, closeTo(8.6, 0.001));
      expect(first.exerciseHoursDaily, closeTo(4.8 / 7, 0.0001));

      final screen = first.signals.singleWhere(
        (s) => s.type == SignalType.screenTime,
      );
      expect(screen.value, closeTo(8.6, 0.001));
      expect(screen.note, contains('socialMediaHours=3.7'));

      final exercise = first.signals.singleWhere(
        (s) => s.type == SignalType.exercise,
      );
      expect(exercise.value, closeTo(4.8 / 7, 0.0001));

      final caffeine = first.signals.singleWhere(
        (s) => s.type == SignalType.caffeine,
      );
      expect(caffeine.value, 1);
      expect(caffeine.type.unit, 'drinks');

      expect(first.score.energy, inInclusiveRange(0, 100));
      expect(first.score.cognitive, inInclusiveRange(0, 100));
      expect(first.checkIns, isNotEmpty);
    });

    test('maps age ranges and second sample row', () {
      final people = SyntheticCsvLoader.parseCsv(_sampleCsv, now: now);
      final second = people[1];
      expect(second.id, '2');
      expect(second.gender, 'Female');
      expect(second.education, 'Undergraduate');
      expect(second.ageRange, '18+');
      expect(second.foldedScreenHours, closeTo(13.0, 0.001));
      expect(SyntheticCohortMapper.ageRangeFor(14), '13–15');
      expect(SyntheticCohortMapper.ageRangeFor(17), '16–18');
      expect(SyntheticCohortMapper.ageRangeFor(19), '18+');
    });
  });

  group('CohortStats', () {
    test('summarizes mean, histogram, and groups', () {
      final people = SyntheticCsvLoader.parseCsv(_sampleCsv, now: now);
      final summary = CohortStats.summarize(people, scatterSample: 10);
      expect(summary.n, 2);
      expect(summary.meanEnergy, greaterThan(0));
      expect(summary.meanCognitive, greaterThan(0));
      expect(summary.energyHistogram, isNotEmpty);
      expect(summary.byEducation, isNotEmpty);
      expect(summary.byGender, isNotEmpty);
      expect(summary.sleepVsEnergy, hasLength(2));
      expect(summary.caffeineVsEnergy, hasLength(2));
    });
  });
}
