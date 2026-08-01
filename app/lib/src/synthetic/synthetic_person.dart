import '../models.dart';

/// One CSV row mapped into Tonyo signals, check-ins, and a computed score.
class SyntheticPerson {
  const SyntheticPerson({
    required this.id,
    required this.age,
    required this.gender,
    required this.education,
    required this.ageRange,
    required this.role,
    required this.avgSleepHours,
    required this.screenTimeHours,
    required this.socialMediaHours,
    required this.studyHours,
    required this.exerciseHoursWeekly,
    required this.caffeineDrinks,
    required this.stressLevel,
    required this.anxietyScore,
    required this.gpa,
    required this.usesSleepApp,
    required this.feelsBurnedOut,
    required this.signals,
    required this.checkIns,
    required this.score,
    this.sourceCsvRow = 0,
  });

  final String id;
  final int age;
  final String gender;
  final String education;
  final String ageRange;
  final String role;
  final double avgSleepHours;
  final double screenTimeHours;
  final double socialMediaHours;
  final double studyHours;
  final double exerciseHoursWeekly;
  final double caffeineDrinks;
  final double stressLevel;
  final double anxietyScore;
  final double gpa;
  final bool usesSleepApp;
  final bool feelsBurnedOut;
  final List<SignalReading> signals;
  final List<DailyCheckIn> checkIns;
  final ScoreSnapshot score;
  final int sourceCsvRow;

  double get exerciseHoursDaily => exerciseHoursWeekly / 7;
  double get foldedScreenHours => screenTimeHours + socialMediaHours;

  Map<String, Object?> metaToCloud() => {
    'age': age,
    'gender': gender,
    'education': education,
    'ageRange': ageRange,
    'role': role,
    'sourceCsvRow': sourceCsvRow,
    'avgSleepHours': avgSleepHours,
    'screenTimeHours': screenTimeHours,
    'socialMediaHours': socialMediaHours,
    'studyHours': studyHours,
    'exerciseHoursWeekly': exerciseHoursWeekly,
    'caffeineDrinks': caffeineDrinks,
    'stressLevel': stressLevel,
    'anxietyScore': anxietyScore,
    'gpa': gpa,
    'usesSleepApp': usesSleepApp,
    'feelsBurnedOut': feelsBurnedOut,
  };

  Map<String, Object?> toExportJson() => {
    'id': id,
    'meta': metaToCloud(),
    'signals': signals.map((value) => value.toJson()).toList(),
    'checkIns': checkIns.map((value) => value.toJson()).toList(),
    'score': {
      'energy': score.energy,
      'cognitive': score.cognitive,
      'confidence': score.confidence,
      'drivers': score.drivers
          .map(
            (driver) => {
              'label': driver.label,
              'contribution': driver.contribution,
              'detail': driver.detail,
            },
          )
          .toList(),
    },
  };
}
