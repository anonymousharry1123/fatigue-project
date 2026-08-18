enum SignalType {
  sleep,
  bedtime,
  hydration,
  study,
  exercise,
  steps,
  screenTime,
  caffeine,
  reactionTime,
  hrv,
  restingHeartRate,
  sleepAwake,
  sleepCore,
  sleepDeep,
  sleepRem,
  sleepUnspecified,
}

enum SignalSource { manual, healthKit, model }

extension SignalTypeInfo on SignalType {
  String get label => switch (this) {
    SignalType.sleep => 'Sleep',
    SignalType.bedtime => 'Bedtime',
    SignalType.hydration => 'Hydration',
    SignalType.study => 'Study',
    SignalType.exercise => 'Exercise',
    SignalType.steps => 'Steps',
    SignalType.screenTime => 'Screen time',
    SignalType.caffeine => 'Caffeine',
    SignalType.reactionTime => 'Reaction time',
    SignalType.hrv => 'HRV',
    SignalType.restingHeartRate => 'Resting HR',
    SignalType.sleepAwake => 'Awake',
    SignalType.sleepCore => 'Core sleep',
    SignalType.sleepDeep => 'Deep sleep',
    SignalType.sleepRem => 'REM sleep',
    SignalType.sleepUnspecified => 'Unspecified sleep',
  };

  String get unit => switch (this) {
    SignalType.sleep ||
    SignalType.study ||
    SignalType.exercise ||
    SignalType.screenTime ||
    SignalType.sleepAwake ||
    SignalType.sleepCore ||
    SignalType.sleepDeep ||
    SignalType.sleepRem ||
    SignalType.sleepUnspecified => 'hr',
    SignalType.bedtime => 'hour',
    SignalType.hydration => 'L',
    SignalType.caffeine => 'drinks',
    SignalType.reactionTime => 'ms',
    SignalType.hrv => 'ms',
    SignalType.restingHeartRate => 'bpm',
    SignalType.steps => 'steps',
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
    this.groupId,
  });

  final String id;
  final SignalType type;
  final double value;
  final DateTime timestamp;
  final SignalSource source;
  final double quality;
  final String? note;
  final String? groupId;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'value': value,
    'timestamp': timestamp.toIso8601String(),
    'source': source.name,
    'quality': quality,
    'note': note,
    'groupId': groupId,
  };

  factory SignalReading.fromJson(Map<String, dynamic> json) => SignalReading(
    id: json['id'] as String,
    type: SignalType.values.byName(json['type'] as String),
    value: (json['value'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
    source: SignalSource.values.byName((json['source'] as String?) ?? 'manual'),
    quality: (json['quality'] as num?)?.toDouble() ?? 1,
    note: json['note'] as String?,
    groupId: json['groupId'] as String?,
  );
}

enum CheckInPeriod { morning, evening }

extension CheckInPeriodLabel on CheckInPeriod {
  String get label => switch (this) {
    CheckInPeriod.morning => 'Morning',
    CheckInPeriod.evening => 'Evening',
  };
}

class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.timestamp,
    required this.hydrationLiters,
    required this.studyHours,
    required this.exerciseHours,
    required this.screenTimeHours,
  });

  static const allowedTypes = {
    SignalType.hydration,
    SignalType.study,
    SignalType.exercise,
    SignalType.screenTime,
  };

  final String id;
  final DateTime timestamp;
  final double? hydrationLiters;
  final double? studyHours;
  final double? exerciseHours;
  final double? screenTimeHours;

  static String? validationMessage(SignalType type, double value) {
    if (!value.isFinite) return 'Enter a valid number.';
    final range = switch (type) {
      SignalType.hydration => (minimum: 0.0, maximum: 10.0, unit: 'liters'),
      SignalType.study => (minimum: 0.0, maximum: 18.0, unit: 'hours'),
      SignalType.exercise => (minimum: 0.0, maximum: 12.0, unit: 'hours'),
      SignalType.screenTime => (minimum: 0.0, maximum: 24.0, unit: 'hours'),
      _ => null,
    };
    if (range == null) return 'This is not an activity-log value.';
    if (value < range.minimum || value > range.maximum) {
      return 'Enter ${range.minimum.toStringAsFixed(0)}–${range.maximum.toStringAsFixed(0)} ${range.unit}.';
    }
    return null;
  }
}

class SleepLogEntry {
  const SleepLogEntry({
    required this.id,
    required this.bedtime,
    required this.wakeTime,
    required this.quality,
  });

  final String id;
  final DateTime bedtime;
  final DateTime wakeTime;
  final double quality;

  Duration get duration => wakeTime.difference(bedtime);
  double get durationHours => duration.inMinutes / 60;

  /// Places bedtime and wake on one overnight sleep using wake's calendar day
  /// as the anchor (the morning you woke up).
  ///
  /// Time pickers keep the previous widget date when only the clock changes, so
  /// picking 1:00 AM on a "yesterday 11 PM" field would otherwise stay on
  /// yesterday and inflate duration to ~31 hours against today's wake.
  static (DateTime bedtime, DateTime wakeTime) normalizeOvernightPair({
    required DateTime bedtime,
    required DateTime wakeTime,
  }) {
    final wake = DateTime(
      wakeTime.year,
      wakeTime.month,
      wakeTime.day,
      wakeTime.hour,
      wakeTime.minute,
    );
    var bed = DateTime(
      wake.year,
      wake.month,
      wake.day,
      bedtime.hour,
      bedtime.minute,
    );
    // Evening bedtimes (e.g. 23:00) fall after wake on the same calendar day,
    // so they belong to the previous evening.
    if (!bed.isBefore(wake)) {
      bed = bed.subtract(const Duration(days: 1));
    }
    return (bed, wake);
  }

  static String? validationMessage({
    required DateTime bedtime,
    required DateTime wakeTime,
    required double quality,
  }) {
    if (!quality.isFinite || quality < 1 || quality > 5) {
      return 'Sleep quality must be between 1 and 5.';
    }
    final duration = wakeTime.difference(bedtime);
    if (duration < const Duration(minutes: 30) ||
        duration > const Duration(hours: 16)) {
      return 'Sleep duration must be between 30 minutes and 16 hours.';
    }
    return null;
  }

  static double bedtimeConsistencyMinutes(Iterable<SleepLogEntry> entries) {
    final bedtimeMinutes = entries.map((entry) {
      final time = entry.bedtime;
      final minutes = time.hour * 60 + time.minute;
      return minutes < 12 * 60 ? minutes + 24 * 60 : minutes;
    }).toList();
    if (bedtimeMinutes.length < 2) return 0;
    final average =
        bedtimeMinutes.reduce((left, right) => left + right) /
        bedtimeMinutes.length;
    return bedtimeMinutes
            .map((minutes) => (minutes - average).abs())
            .reduce((left, right) => left + right) /
        bedtimeMinutes.length;
  }
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
  const ScoreDriver(
    this.label,
    this.contribution,
    this.detail, {
    this.explanation = '',
    this.freshness,
    this.source,
    this.evidenceAt,
  });

  final String label;
  final double contribution;
  final String detail;
  final String explanation;
  final double? freshness;
  final SignalSource? source;
  final DateTime? evidenceAt;

  bool get isPositive => contribution > .01;
  bool get isNegative => contribution < -.01;
  bool get isNeutral => !isPositive && !isNegative;
}

class ScoreSnapshot {
  const ScoreSnapshot({
    required this.energy,
    required this.cognitive,
    required this.confidence,
    required this.drivers,
    this.cognitiveConfidence = .2,
    this.cognitiveDrivers = const [],
    this.cognitiveInputCount = 0,
    this.hasCognitiveScore = true,
    this.previousCognitive,
    this.day,
    this.calculatedAt,
    this.inputCount = 0,
    this.isEstimate = true,
    this.freshness,
    this.cognitiveFreshness,
  });

  final int energy;
  final int cognitive;
  final double confidence;
  final List<ScoreDriver> drivers;
  final double cognitiveConfidence;
  final List<ScoreDriver> cognitiveDrivers;
  final int cognitiveInputCount;
  final bool hasCognitiveScore;
  final int? previousCognitive;
  final DateTime? day;
  final DateTime? calculatedAt;
  final int inputCount;
  final bool isEstimate;
  final double? freshness;
  final double? cognitiveFreshness;

  int? get cognitiveChange =>
      previousCognitive == null ? null : cognitive - previousCognitive!;
  double get completeness => (inputCount / 7).clamp(0, 1);
  double get cognitiveCompleteness => (cognitiveInputCount / 6).clamp(0, 1);
  List<ScoreDriver> get energyPositiveDrivers =>
      drivers.where((driver) => driver.isPositive).toList(growable: false);
  List<ScoreDriver> get energyNegativeDrivers =>
      drivers.where((driver) => driver.isNegative).toList(growable: false);
  List<ScoreDriver> get energyNeutralDrivers =>
      drivers.where((driver) => driver.isNeutral).toList(growable: false);
  List<ScoreDriver> get cognitivePositiveDrivers => cognitiveDrivers
      .where((driver) => driver.isPositive)
      .toList(growable: false);
  List<ScoreDriver> get cognitiveNegativeDrivers => cognitiveDrivers
      .where((driver) => driver.isNegative)
      .toList(growable: false);
  List<ScoreDriver> get cognitiveNeutralDrivers => cognitiveDrivers
      .where((driver) => driver.isNeutral)
      .toList(growable: false);
}

class ForecastPoint {
  const ForecastPoint(
    this.time,
    this.energy,
    this.uncertainty, {
    this.updatedAt,
    this.signalEvidenceIds = const [],
    this.checkInEvidenceIds = const [],
  });
  final DateTime time;
  final double energy;
  final double uncertainty;
  final DateTime? updatedAt;
  final List<String> signalEvidenceIds;
  final List<String> checkInEvidenceIds;
}

class ForecastDaySummary {
  const ForecastDaySummary({
    required this.day,
    required this.averageEnergy,
    required this.lowEnergy,
    required this.peakEnergy,
    required this.peakTime,
    required this.averageUncertainty,
    required this.updatedAt,
  });

  final DateTime day;
  final double averageEnergy;
  final double lowEnergy;
  final double peakEnergy;
  final DateTime peakTime;
  final double averageUncertainty;
  final DateTime? updatedAt;

  bool get isLowConfidence => averageUncertainty >= 18;

  bool isStaleAt(
    DateTime now, {
    Duration maximumAge = const Duration(hours: 12),
  }) {
    final calculated = updatedAt;
    return calculated == null || now.difference(calculated) > maximumAge;
  }

  factory ForecastDaySummary.fromPoints(
    DateTime day,
    List<ForecastPoint> points,
  ) {
    if (points.isEmpty) {
      throw ArgumentError('A daily forecast summary requires points.');
    }
    final peak = points.reduce(
      (left, right) => left.energy >= right.energy ? left : right,
    );
    final low = points.reduce(
      (left, right) => left.energy <= right.energy ? left : right,
    );
    final updatedValues = points
        .map((point) => point.updatedAt)
        .whereType<DateTime>()
        .toList();
    final updatedAt = updatedValues.length != points.length
        ? null
        : updatedValues.reduce(
            (left, right) => left.isBefore(right) ? left : right,
          );
    return ForecastDaySummary(
      day: DateTime(day.year, day.month, day.day),
      averageEnergy:
          points.fold<double>(0, (sum, point) => sum + point.energy) /
          points.length,
      lowEnergy: low.energy,
      peakEnergy: peak.energy,
      peakTime: peak.time,
      averageUncertainty:
          points.fold<double>(0, (sum, point) => sum + point.uncertainty) /
          points.length,
      updatedAt: updatedAt,
    );
  }
}

enum ForecastWindowType { peak, crash, recovery }

enum ForecastEvidenceKind { signal, checkIn }

class ForecastEvidence {
  const ForecastEvidence({
    required this.id,
    required this.kind,
    required this.label,
    required this.detail,
    required this.timestamp,
    this.signalType,
    this.source,
  });

  final String id;
  final ForecastEvidenceKind kind;
  final String label;
  final String detail;
  final DateTime timestamp;
  final SignalType? signalType;
  final SignalSource? source;
}

class ForecastWindow {
  const ForecastWindow(
    this.type,
    this.start,
    this.end,
    this.energy,
    this.reason, {
    this.evidence = const [],
  });
  final ForecastWindowType type;
  final DateTime start;
  final DateTime end;
  final int energy;
  final String reason;
  final List<ForecastEvidence> evidence;
}

enum RecommendationStatus { suggested, accepted, completed, dismissed }

enum RecommendationPriority { routine, important }

class Recommendation {
  const Recommendation({
    required this.id,
    required this.title,
    required this.detail,
    required this.timeLabel,
    required this.category,
    this.status = RecommendationStatus.suggested,
    this.priority = RecommendationPriority.routine,
    this.windowType,
    this.scheduledAt,
    this.day,
    this.generatedAt,
    this.signalEvidenceIds = const [],
    this.checkInEvidenceIds = const [],
    this.evidence = const [],
  });
  final String id;
  final String title;
  final String detail;
  final String timeLabel;
  final String category;
  final RecommendationStatus status;
  final RecommendationPriority priority;
  final ForecastWindowType? windowType;
  final DateTime? scheduledAt;
  final DateTime? day;
  final DateTime? generatedAt;
  final List<String> signalEvidenceIds;
  final List<String> checkInEvidenceIds;
  final List<ForecastEvidence> evidence;

  bool get isGrounded =>
      signalEvidenceIds.isNotEmpty || checkInEvidenceIds.isNotEmpty;

  Recommendation copyWith({
    RecommendationStatus? status,
    List<ForecastEvidence>? evidence,
  }) => Recommendation(
    id: id,
    title: title,
    detail: detail,
    timeLabel: timeLabel,
    category: category,
    status: status ?? this.status,
    priority: priority,
    windowType: windowType,
    scheduledAt: scheduledAt,
    day: day,
    generatedAt: generatedAt,
    signalEvidenceIds: signalEvidenceIds,
    checkInEvidenceIds: checkInEvidenceIds,
    evidence: evidence ?? this.evidence,
  );
}

enum AlertSeverity { info, caution, high }

enum RiskAlertCategory { sleepDebt, trainingLoad, fatigueStress }

class RiskAlert {
  const RiskAlert(
    this.title,
    this.detail,
    this.severity, {
    this.id = '',
    this.category = RiskAlertCategory.fatigueStress,
    this.dismissed = false,
    this.day,
    this.detectedAt,
    this.signalEvidenceIds = const [],
    this.checkInEvidenceIds = const [],
    this.evidence = const [],
  });

  final String id;
  final String title;
  final String detail;
  final AlertSeverity severity;
  final RiskAlertCategory category;
  final bool dismissed;
  final DateTime? day;
  final DateTime? detectedAt;
  final List<String> signalEvidenceIds;
  final List<String> checkInEvidenceIds;
  final List<ForecastEvidence> evidence;

  RiskAlert copyWith({bool? dismissed, List<ForecastEvidence>? evidence}) =>
      RiskAlert(
        title,
        detail,
        severity,
        id: id,
        category: category,
        dismissed: dismissed ?? this.dismissed,
        day: day,
        detectedAt: detectedAt,
        signalEvidenceIds: signalEvidenceIds,
        checkInEvidenceIds: checkInEvidenceIds,
        evidence: evidence ?? this.evidence,
      );
}
