import '../fatigue_engine.dart';
import '../models.dart';
import 'synthetic_person.dart';

/// Maps synthetic CSV rows into Tonyo signals, check-ins, and scores.
///
/// Screen + social media hours are folded into one [SignalType.screenTime]
/// value so [FatigueEngine] sees a single screen input. Weekly exercise is
/// converted to a daily load (`/ 7`) before scoring.
abstract final class SyntheticCohortMapper {
  static List<SyntheticPerson> mapCsv(String csv, {required DateTime now}) {
    final lines = csv
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    final header = _parseLine(lines.first);
    final index = {
      for (var i = 0; i < header.length; i++) header[i].trim(): i,
    };

    final people = <SyntheticPerson>[];
    for (var row = 1; row < lines.length; row++) {
      final cols = _parseLine(lines[row]);
      if (cols.isEmpty) continue;
      people.add(
        mapRow(cols, index: index, sourceCsvRow: row, now: now),
      );
    }
    return people;
  }

  static SyntheticPerson mapRow(
    List<String> cols, {
    required Map<String, int> index,
    required int sourceCsvRow,
    required DateTime now,
  }) {
    String cell(String key, {String fallback = ''}) {
      final i = index[key];
      if (i == null || i >= cols.length) return fallback;
      return cols[i].trim();
    }

    double numCell(String key, {double fallback = 0}) =>
        double.tryParse(cell(key)) ?? fallback;

    bool boolCell(String key) {
      final raw = cell(key).toLowerCase();
      return raw == 'true' || raw == '1' || raw == 'yes';
    }

    final id = cell('student_id', fallback: '$sourceCsvRow');
    final age = numCell('age').round();
    final gender = cell('gender', fallback: 'Unknown');
    final education = cell('education_level', fallback: 'Unknown');
    final sleep = numCell('avg_sleep_hours');
    final screen = numCell('screen_time_hours');
    final social = numCell('social_media_hours');
    final study = numCell('study_hours_per_day');
    final exerciseWeekly = numCell('exercise_hours_per_week');
    final caffeine = numCell('caffeine_drinks_per_day');
    final stress = numCell('stress_level', fallback: 5).clamp(1, 10);
    final anxiety = numCell('anxiety_score', fallback: 5).clamp(1, 10);
    final gpa = numCell('gpa');
    final usesSleepApp = boolCell('uses_sleep_app');
    final burnedOut = boolCell('feels_burned_out');

    final stamp = now.subtract(const Duration(hours: 8));
    final exerciseDaily = exerciseWeekly / 7;
    final foldedScreen = screen + social;

    final signals = <SignalReading>[
      SignalReading(
        id: 'syn-$id-sleep',
        type: SignalType.sleep,
        value: sleep,
        timestamp: stamp,
        source: SignalSource.model,
        note: 'Synthetic avg nightly sleep',
      ),
      SignalReading(
        id: 'syn-$id-screen',
        type: SignalType.screenTime,
        value: foldedScreen,
        timestamp: stamp,
        source: SignalSource.model,
        note: 'socialMediaHours=$social; screenOnly=$screen',
      ),
      SignalReading(
        id: 'syn-$id-study',
        type: SignalType.study,
        value: study,
        timestamp: stamp,
        source: SignalSource.model,
      ),
      SignalReading(
        id: 'syn-$id-exercise',
        type: SignalType.exercise,
        value: exerciseDaily,
        timestamp: stamp,
        source: SignalSource.model,
        note: 'weeklyHours=$exerciseWeekly',
      ),
      SignalReading(
        id: 'syn-$id-caffeine',
        type: SignalType.caffeine,
        value: caffeine,
        timestamp: stamp,
        source: SignalSource.model,
      ),
    ];

    // Derive check-in ratings from CSV stress/anxiety/burnout so cognitive
    // scoring has mood/stress drivers without inventing separate surveys.
    final energy = burnedOut
        ? (4.0 - (stress - 5).clamp(0, 3) * 0.4).clamp(1, 10)
        : (6.5 - (stress - 5) * 0.35).clamp(1, 10);
    final mood = (11 - anxiety).clamp(1, 10).toDouble();
    final checkIns = [
      DailyCheckIn(
        id: 'syn-$id-checkin',
        timestamp: stamp.add(const Duration(hours: 2)),
        energy: energy.toDouble(),
        mood: mood,
        stress: stress.toDouble(),
        period: CheckInPeriod.evening,
        note: burnedOut ? 'feels_burned_out' : '',
      ),
    ];

    final score = FatigueEngine.score(
      signals: signals,
      checkIns: checkIns,
      now: now,
    );

    return SyntheticPerson(
      id: id,
      age: age,
      gender: gender,
      education: education,
      ageRange: ageRangeFor(age),
      role: roleFor(education),
      avgSleepHours: sleep,
      screenTimeHours: screen,
      socialMediaHours: social,
      studyHours: study,
      exerciseHoursWeekly: exerciseWeekly,
      caffeineDrinks: caffeine,
      stressLevel: stress.toDouble(),
      anxietyScore: anxiety.toDouble(),
      gpa: gpa,
      usesSleepApp: usesSleepApp,
      feelsBurnedOut: burnedOut,
      signals: signals,
      checkIns: checkIns,
      score: score,
      sourceCsvRow: sourceCsvRow,
    );
  }

  static String ageRangeFor(int age) {
    if (age <= 15) return '13–15';
    if (age <= 18) return '16–18';
    return '18+';
  }

  static String roleFor(String education) {
    final normalized = education.toLowerCase();
    if (normalized.contains('athlete')) return 'Student athlete';
    return 'Student';
  }

  static List<String> _parseLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (char == ',' && !inQuotes) {
        values.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    values.add(buffer.toString());
    return values;
  }
}
