enum SignalType {
  sleep,
  bedtime,
  hydration,
  study,
  exercise,
  screenTime,
  reactionTime,
  hrv,
  restingHeartRate,
  sleepCore,
  sleepDeep,
  sleepRem,
}

enum SignalSource { manual, healthKit, model }

extension SignalTypeInfo on SignalType {
  String get label => switch (this) {
    SignalType.sleep => 'Sleep',
    SignalType.bedtime => 'Bedtime',
    SignalType.hydration => 'Hydration',
    SignalType.study => 'Study',
    SignalType.exercise => 'Exercise',
    SignalType.screenTime => 'Screen time',
    SignalType.reactionTime => 'Reaction time',
    SignalType.hrv => 'HRV',
    SignalType.restingHeartRate => 'Resting HR',
    SignalType.sleepCore => 'Core sleep',
    SignalType.sleepDeep => 'Deep sleep',
    SignalType.sleepRem => 'REM sleep',
  };

  String get unit => switch (this) {
    SignalType.sleep ||
    SignalType.study ||
    SignalType.exercise ||
    SignalType.screenTime ||
    SignalType.sleepCore ||
    SignalType.sleepDeep ||
    SignalType.sleepRem => 'hr',
    SignalType.bedtime => 'hour',
    SignalType.hydration => 'L',
    SignalType.reactionTime => 'ms',
    SignalType.hrv => 'ms',
    SignalType.restingHeartRate => 'bpm',
  };
}

class SignalReading {
  const SignalReading({
    required this.id,
    required this.type,
    required this.value,
    required this.timestamp,
    this.source = SignalSource.manual,
    this.quality = 1,
    this.note,
  });

  final String id;
  final SignalType type;
  final double value;
  final DateTime timestamp;
  final SignalSource source;
  final double quality;
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'value': value,
    'timestamp': timestamp.toIso8601String(),
    'source': source.name,
    'quality': quality,
    'note': note,
  };

  factory SignalReading.fromJson(Map<String, dynamic> json) => SignalReading(
    id: json['id'] as String,
    type: SignalType.values.byName(json['type'] as String),
    value: (json['value'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
    source: SignalSource.values.byName((json['source'] as String?) ?? 'manual'),
    quality: (json['quality'] as num?)?.toDouble() ?? 1,
    note: json['note'] as String?,
  );
}

enum CheckInPeriod { morning, evening }

extension CheckInPeriodLabel on CheckInPeriod {
  String get label => switch (this) {
    CheckInPeriod.morning => 'Morning',
    CheckInPeriod.evening => 'Evening',
  };
}

class DailyCheckIn {
  const DailyCheckIn({
    required this.id,
    required this.timestamp,
    required this.energy,
    required this.mood,
    required this.stress,
    this.period = CheckInPeriod.morning,
    this.note = '',
  });

  /// Energy, mood, and stress use an intuitive 1–10 scale.
  final String id;
  final DateTime timestamp;
  final double energy;
  final double mood;
  final double stress;
  final CheckInPeriod period;
  final String note;

  Map<String, Object?> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'energy': energy,
    'mood': mood,
    'stress': stress,
    'period': period.name,
    'note': note,
  };

  factory DailyCheckIn.fromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.parse(json['timestamp'] as String);
    final periodName = json['period'] as String?;
    final legacyScale = periodName == null;
    final period = periodName != null
        ? CheckInPeriod.values.byName(periodName)
        : timestamp.hour < 14
        ? CheckInPeriod.morning
        : CheckInPeriod.evening;
    return DailyCheckIn(
      id: json['id'] as String,
      timestamp: timestamp,
      energy: _ratingFromJson(json['energy'], legacyScale: legacyScale),
      mood: _ratingFromJson(json['mood'], legacyScale: legacyScale),
      stress: _ratingFromJson(json['stress'], legacyScale: legacyScale),
      period: period,
      note: (json['note'] as String?) ?? '',
    );
  }

  /// Migrates pre-0.8 1–5 ratings (no period field) onto the 1–10 scale.
  static double _ratingFromJson(Object? raw, {required bool legacyScale}) {
    final value = (raw as num).toDouble();
    if (legacyScale && value > 0 && value <= 5) {
      return (value * 2).clamp(1, 10);
    }
    return value.clamp(1, 10);
  }
}

class UserProfile {
  const UserProfile({
    this.name = 'Maya',
    this.ageRange = '16–18',
    this.role = 'Student athlete',
    this.goal = 'Balance focus and training',
    this.wakeHour = 7,
    this.bedHour = 23,
  });

  final String name;
  final String ageRange;
  final String role;
  final String goal;
  final double wakeHour;
  final double bedHour;

  UserProfile copyWith({
    String? name,
    String? ageRange,
    String? role,
    String? goal,
    double? wakeHour,
    double? bedHour,
  }) => UserProfile(
    name: name ?? this.name,
    ageRange: ageRange ?? this.ageRange,
    role: role ?? this.role,
    goal: goal ?? this.goal,
    wakeHour: wakeHour ?? this.wakeHour,
    bedHour: bedHour ?? this.bedHour,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'ageRange': ageRange,
    'role': role,
    'goal': goal,
    'wakeHour': wakeHour,
    'bedHour': bedHour,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: (json['name'] as String?) ?? 'Maya',
    ageRange: (json['ageRange'] as String?) ?? '16–18',
    role: (json['role'] as String?) ?? 'Student athlete',
    goal: (json['goal'] as String?) ?? 'Balance focus and training',
    wakeHour: (json['wakeHour'] as num?)?.toDouble() ?? 7,
    bedHour: (json['bedHour'] as num?)?.toDouble() ?? 23,
  );
}

class ScoreDriver {
  const ScoreDriver(this.label, this.contribution, this.detail);
  final String label;
  final double contribution;
  final String detail;
}

class ScoreSnapshot {
  const ScoreSnapshot({
    required this.energy,
    required this.cognitive,
    required this.confidence,
    required this.drivers,
  });
  final int energy;
  final int cognitive;
  final double confidence;
  final List<ScoreDriver> drivers;
}

class ForecastPoint {
  const ForecastPoint(this.time, this.energy, this.uncertainty);
  final DateTime time;
  final double energy;
  final double uncertainty;
}

enum ForecastWindowType { peak, crash, recovery }

class ForecastWindow {
  const ForecastWindow(
    this.type,
    this.start,
    this.end,
    this.energy,
    this.reason,
  );
  final ForecastWindowType type;
  final DateTime start;
  final DateTime end;
  final int energy;
  final String reason;
}

enum RecommendationStatus { suggested, accepted, completed, dismissed }

class Recommendation {
  const Recommendation({
    required this.id,
    required this.title,
    required this.detail,
    required this.timeLabel,
    required this.category,
    this.status = RecommendationStatus.suggested,
  });
  final String id;
  final String title;
  final String detail;
  final String timeLabel;
  final String category;
  final RecommendationStatus status;

  Recommendation copyWith({RecommendationStatus? status}) => Recommendation(
    id: id,
    title: title,
    detail: detail,
    timeLabel: timeLabel,
    category: category,
    status: status ?? this.status,
  );
}

enum AlertSeverity { info, caution, high }

class RiskAlert {
  const RiskAlert(this.title, this.detail, this.severity);
  final String title;
  final String detail;
  final AlertSeverity severity;
}
