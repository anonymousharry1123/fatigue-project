import 'models.dart';

/// Firestore schema version introduced in Version 0.10-a.
const int cloudSchemaVersion = 1;

/// SharedPreferences-to-Firestore migration version.
const int localMigrationVersion = 1;

DateTime cloudDateTime(Object? value, {required String field}) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.parse(value);
  throw FormatException('$field must be a DateTime or ISO-8601 string.');
}

Map<String, Object?> signalToCloud(SignalReading signal) => {
  'type': signal.type.name,
  'value': signal.value,
  'unit': signal.type.unit,
  'timestamp': signal.timestamp,
  'source': signal.source.name,
  'quality': signal.quality,
  'note': signal.note,
  'groupId': signal.groupId,
  'schemaVersion': cloudSchemaVersion,
};

SignalReading signalFromCloud(String id, Map<String, dynamic> data) {
  final type = SignalType.values.byName(data['type'] as String);
  final storedUnit = data['unit'] as String?;
  if (storedUnit != null && storedUnit != type.unit) {
    throw FormatException(
      'Signal $id uses unit "$storedUnit"; expected "${type.unit}".',
    );
  }
  return SignalReading(
    id: id,
    type: type,
    value: (data['value'] as num).toDouble(),
    timestamp: cloudDateTime(data['timestamp'], field: 'timestamp'),
    source: SignalSource.values.byName(
      (data['source'] as String?) ?? SignalSource.manual.name,
    ),
    quality: (data['quality'] as num?)?.toDouble() ?? 1,
    note: data['note'] as String?,
    groupId: data['groupId'] as String?,
  );
}

Map<String, Object?> checkInToCloud(DailyCheckIn checkIn) => {
  'period': checkIn.period.name,
  'energy': checkIn.energy,
  'mood': checkIn.mood,
  'stress': checkIn.stress,
  'note': checkIn.note,
  'timestamp': checkIn.timestamp,
  'schemaVersion': cloudSchemaVersion,
};

DailyCheckIn checkInFromCloud(String id, Map<String, dynamic> data) =>
    DailyCheckIn(
      id: id,
      period: CheckInPeriod.values.byName(data['period'] as String),
      energy: (data['energy'] as num).toDouble(),
      mood: (data['mood'] as num).toDouble(),
      stress: (data['stress'] as num).toDouble(),
      note: (data['note'] as String?) ?? '',
      timestamp: cloudDateTime(data['timestamp'], field: 'timestamp'),
    );

Map<String, Object?> profileToCloud({
  required UserProfile profile,
  required String email,
  required bool onboardingComplete,
  required bool notificationsEnabled,
  required bool outcomeConsent,
  required bool healthAuthorized,
  DateTime? lastSync,
  DateTime? updatedAt,
  int migrationVersion = localMigrationVersion,
}) => {
  'profile': profile.toJson(),
  'accountEmail': email,
  'prefs': {
    'notificationsEnabled': notificationsEnabled,
    'healthAuthorized': healthAuthorized,
  },
  'consentFlags': {
    'wellnessOnlyAcknowledged': true,
    'outcomeCollection': outcomeConsent,
  },
  'onboardingComplete': onboardingComplete,
  'lastHealthSync': lastSync,
  'localMigrationVersion': migrationVersion,
  'schemaVersion': cloudSchemaVersion,
  'updatedAt': updatedAt ?? DateTime.now().toUtc(),
};

class CloudUserState {
  const CloudUserState({
    required this.profile,
    required this.accountEmail,
    required this.onboardingComplete,
    required this.notificationsEnabled,
    required this.outcomeConsent,
    required this.healthAuthorized,
    required this.signals,
    required this.checkIns,
    this.lastSync,
    this.migrationVersion = 0,
  });

  final UserProfile profile;
  final String accountEmail;
  final bool onboardingComplete;
  final bool notificationsEnabled;
  final bool outcomeConsent;
  final bool healthAuthorized;
  final DateTime? lastSync;
  final int migrationVersion;
  final List<SignalReading> signals;
  final List<DailyCheckIn> checkIns;

  CloudUserState copyWith({int? migrationVersion}) => CloudUserState(
    profile: profile,
    accountEmail: accountEmail,
    onboardingComplete: onboardingComplete,
    notificationsEnabled: notificationsEnabled,
    outcomeConsent: outcomeConsent,
    healthAuthorized: healthAuthorized,
    lastSync: lastSync,
    migrationVersion: migrationVersion ?? this.migrationVersion,
    signals: signals,
    checkIns: checkIns,
  );

  Map<String, Object?> toExportJson() => {
    'schemaVersion': cloudSchemaVersion,
    'localMigrationVersion': migrationVersion,
    'accountEmail': accountEmail,
    'onboardingComplete': onboardingComplete,
    'notificationsEnabled': notificationsEnabled,
    'outcomeConsent': outcomeConsent,
    'healthAuthorized': healthAuthorized,
    'lastSync': lastSync?.toIso8601String(),
    'profile': profile.toJson(),
    'signals': signals.map((value) => value.toJson()).toList(),
    'checkIns': checkIns.map((value) => value.toJson()).toList(),
  };
}

/// Version 0.11+ shared daily Energy and Cognitive Score document.
Map<String, Object?> scoreSnapshotToCloud({
  required ScoreSnapshot snapshot,
  required DateTime day,
}) => {
  'energy': snapshot.energy,
  'cognitive': snapshot.cognitive,
  'confidence': snapshot.confidence,
  'cognitiveConfidence': snapshot.cognitiveConfidence,
  'inputCount': snapshot.inputCount,
  'cognitiveInputCount': snapshot.cognitiveInputCount,
  'isEstimate': snapshot.isEstimate,
  'drivers': snapshot.drivers
      .map(
        (driver) => {
          'label': driver.label,
          'contribution': driver.contribution,
          'detail': driver.detail,
        },
      )
      .toList(),
  'cognitiveDrivers': snapshot.cognitiveDrivers
      .map(
        (driver) => {
          'label': driver.label,
          'contribution': driver.contribution,
          'detail': driver.detail,
        },
      )
      .toList(),
  'previousCognitive': snapshot.previousCognitive,
  'cognitiveDelta': snapshot.cognitiveChange,
  'day': day,
  'calculatedAt': snapshot.calculatedAt ?? DateTime.now().toUtc(),
  'schemaVersion': cloudSchemaVersion,
};

ScoreSnapshot scoreSnapshotFromCloud(Map<String, dynamic> data) =>
    ScoreSnapshot(
      energy: (data['energy'] as num).round(),
      cognitive: (data['cognitive'] as num?)?.round() ?? 0,
      confidence: (data['confidence'] as num).toDouble(),
      cognitiveConfidence:
          (data['cognitiveConfidence'] as num?)?.toDouble() ?? .2,
      inputCount: (data['inputCount'] as num?)?.round() ?? 0,
      cognitiveInputCount: (data['cognitiveInputCount'] as num?)?.round() ?? 0,
      hasCognitiveScore: data.containsKey('cognitive'),
      previousCognitive: (data['previousCognitive'] as num?)?.round(),
      isEstimate: data['isEstimate'] as bool? ?? true,
      day: cloudDateTime(data['day'], field: 'day'),
      calculatedAt: data['calculatedAt'] == null
          ? null
          : cloudDateTime(data['calculatedAt'], field: 'calculatedAt'),
      drivers: ((data['drivers'] as List?) ?? const []).map((raw) {
        final driver = (raw as Map).cast<String, dynamic>();
        return ScoreDriver(
          driver['label'] as String,
          (driver['contribution'] as num).toDouble(),
          driver['detail'] as String,
        );
      }).toList(),
      cognitiveDrivers: ((data['cognitiveDrivers'] as List?) ?? const []).map((
        raw,
      ) {
        final driver = (raw as Map).cast<String, dynamic>();
        return ScoreDriver(
          driver['label'] as String,
          (driver['contribution'] as num).toDouble(),
          driver['detail'] as String,
        );
      }).toList(),
    );

/// Reserved Version 0.15+ forecast document.
Map<String, Object?> forecastPointToCloud(ForecastPoint point) => {
  'time': point.time,
  'energy': point.energy,
  'uncertainty': point.uncertainty,
  'schemaVersion': cloudSchemaVersion,
};

/// Reserved Version 0.18+ recommendation document.
Map<String, Object?> recommendationToCloud(
  Recommendation recommendation, {
  Object? feedback,
}) => {
  'title': recommendation.title,
  'detail': recommendation.detail,
  'timeLabel': recommendation.timeLabel,
  'category': recommendation.category,
  'status': recommendation.status.name,
  'feedback': feedback,
  'schemaVersion': cloudSchemaVersion,
};

/// Reserved Version 0.19+ risk-alert document.
Map<String, Object?> riskAlertToCloud(
  RiskAlert alert, {
  bool dismissed = false,
}) => {
  'title': alert.title,
  'detail': alert.detail,
  'severity': alert.severity.name,
  'dismissed': dismissed,
  'schemaVersion': cloudSchemaVersion,
};
