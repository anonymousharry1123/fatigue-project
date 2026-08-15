import 'cloud_schema.dart';
import 'models.dart';

class AccountSession {
  const AccountSession({required this.uid, required this.email});

  final String uid;
  final String email;
}

abstract interface class AccountAuth {
  bool get isConfigured;
  AccountSession? get currentSession;

  Future<AccountSession> register({
    required String email,
    required String password,
  });

  Future<AccountSession> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();
  Future<void> deleteCurrentAccount();
}

/// Used when Firebase environment values have not been supplied.
class LocalOnlyAccountAuth implements AccountAuth {
  const LocalOnlyAccountAuth();

  @override
  bool get isConfigured => false;

  @override
  AccountSession? get currentSession => null;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) => throw StateError('Firebase is not configured.');

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => throw StateError('Firebase is not configured.');

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteCurrentAccount() async {}
}

class MemoryAccountAuth implements AccountAuth {
  MemoryAccountAuth({this.session, this.configured = true});

  AccountSession? session;
  final bool configured;

  @override
  bool get isConfigured => configured;

  @override
  AccountSession? get currentSession => session;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    if (!configured) throw StateError('Firebase is not configured.');
    session = AccountSession(
      uid: 'test-uid',
      email: email.trim().toLowerCase(),
    );
    return session!;
  }

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => register(email: email, password: password);

  @override
  Future<void> signOut() async {
    session = null;
  }

  @override
  Future<void> deleteCurrentAccount() async {
    session = null;
  }
}

abstract interface class CloudRepository {
  Future<CloudUserState?> readUser(String uid);

  /// Replaces the user profile, signals, and check-ins with a single logical
  /// snapshot. Implementations must reject a uid other than the signed-in uid.
  Future<void> replaceUser(String uid, CloudUserState state);

  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
  });

  Future<List<DailyCheckIn>> checkInsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  });

  Future<DailyCheckIn?> latestCheckIn(String uid);

  Future<List<SignalReading>> reactionBaselineWindow(
    String uid, {
    int limit = 14,
  });

  Future<void> upsertScoreSnapshot(String uid, ScoreSnapshot snapshot);

  Future<ScoreSnapshot?> scoreSnapshotForDay(String uid, DateTime day);

  /// Deletes all persisted scoreSnapshots under the user (keeps profile).
  Future<void> clearScoreSnapshots(String uid);
  Future<List<ForecastPoint>> forecastPointsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  });

  /// Replaces only the target day's hourly points. Other days are retained.
  Future<void> replaceForecastPoints(
    String uid, {
    required DateTime day,
    required List<ForecastPoint> points,
  });

  Future<List<Recommendation>> recommendationsForDay(String uid, DateTime day);

  Future<void> replaceRecommendationsForDay(
    String uid, {
    required DateTime day,
    required List<Recommendation> recommendations,
  });

  Future<List<RiskAlert>> riskAlertsForDay(String uid, DateTime day);

  Future<void> replaceRiskAlertsForDay(
    String uid, {
    required DateTime day,
    required List<RiskAlert> alerts,
  });

  Future<void> setRiskAlertDismissed(
    String uid,
    String alertId, {
    required bool dismissed,
  });

  Future<void> clearGuidance(String uid);

  Future<Map<String, Object?>> exportUser(String uid);
  Future<void> deleteUserTree(String uid);
}

/// A uid-enforcing repository for deterministic unit tests and offline demos.
class MemoryCloudRepository implements CloudRepository {
  MemoryCloudRepository({required this.signedInUid});

  String? signedInUid;
  final Map<String, CloudUserState> _users = {};
  final Map<String, Map<String, ScoreSnapshot>> _scores = {};
  final Map<String, Map<String, ForecastPoint>> _forecasts = {};
  final Map<String, Map<String, Recommendation>> _recommendations = {};
  final Map<String, Map<String, RiskAlert>> _riskAlerts = {};

  void seed(String uid, CloudUserState state) {
    _users[uid] = state;
  }

  void _authorize(String uid) {
    if (signedInUid == null || signedInUid != uid) {
      throw StateError('Cross-user repository access denied.');
    }
  }

  @override
  Future<CloudUserState?> readUser(String uid) async {
    _authorize(uid);
    return _users[uid];
  }

  @override
  Future<void> replaceUser(String uid, CloudUserState state) async {
    _authorize(uid);
    _users[uid] = state;
  }

  @override
  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
  }) async {
    _authorize(uid);
    final matches = (_users[uid]?.signals ?? const <SignalReading>[])
        .where(
          (reading) =>
              !reading.timestamp.isBefore(start) &&
              reading.timestamp.isBefore(end) &&
              (type == null || reading.type == type),
        )
        .toList();
    return matches..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<List<DailyCheckIn>> checkInsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    _authorize(uid);
    final matches = (_users[uid]?.checkIns ?? const <DailyCheckIn>[])
        .where(
          (checkIn) =>
              !checkIn.timestamp.isBefore(start) &&
              checkIn.timestamp.isBefore(end),
        )
        .toList();
    return matches..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<DailyCheckIn?> latestCheckIn(String uid) async {
    _authorize(uid);
    final values = [...?_users[uid]?.checkIns]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return values.firstOrNull;
  }

  @override
  Future<List<SignalReading>> reactionBaselineWindow(
    String uid, {
    int limit = 14,
  }) async {
    _authorize(uid);
    final values =
        (_users[uid]?.signals ?? const <SignalReading>[])
            .where((reading) => reading.type == SignalType.reactionTime)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return values.take(limit).toList();
  }

  @override
  Future<void> upsertScoreSnapshot(String uid, ScoreSnapshot snapshot) async {
    _authorize(uid);
    final day = snapshot.day;
    if (day == null) throw ArgumentError('A score snapshot requires a day.');
    _scores.putIfAbsent(uid, () => {})[scoreSnapshotId(
      day,
    )] = scoreSnapshotFromCloud(
      scoreSnapshotToCloud(snapshot: snapshot, day: day),
    );
  }

  @override
  Future<ScoreSnapshot?> scoreSnapshotForDay(String uid, DateTime day) async {
    _authorize(uid);
    return _scores[uid]?[scoreSnapshotId(day)];
  }

  @override
  Future<void> clearScoreSnapshots(String uid) async {
    _authorize(uid);
    _scores.remove(uid);
  }

  @override
  Future<List<ForecastPoint>> forecastPointsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    _authorize(uid);
    final points = (_forecasts[uid]?.values ?? const <ForecastPoint>[])
        .where(
          (point) => !point.time.isBefore(start) && point.time.isBefore(end),
        )
        .toList();
    return points..sort((left, right) => left.time.compareTo(right.time));
  }

  @override
  Future<void> replaceForecastPoints(
    String uid, {
    required DateTime day,
    required List<ForecastPoint> points,
  }) async {
    _authorize(uid);
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    if (points.any(
      (point) => point.time.isBefore(start) || !point.time.isBefore(end),
    )) {
      throw ArgumentError(
        'Every forecast point must belong to the target day.',
      );
    }
    final stored = _forecasts.putIfAbsent(uid, () => {});
    stored.removeWhere(
      (_, point) => !point.time.isBefore(start) && point.time.isBefore(end),
    );
    for (final point in points) {
      stored[forecastPointId(point.time)] = forecastPointFromCloud(
        forecastPointToCloud(point),
      );
    }
  }

  @override
  Future<List<Recommendation>> recommendationsForDay(
    String uid,
    DateTime day,
  ) async {
    _authorize(uid);
    final values = (_recommendations[uid]?.values ?? const <Recommendation>[])
        .where((item) => item.day != null && _sameDay(item.day!, day))
        .toList();
    return values..sort((left, right) {
      final leftTime = left.scheduledAt ?? left.day!;
      final rightTime = right.scheduledAt ?? right.day!;
      return leftTime.compareTo(rightTime);
    });
  }

  @override
  Future<void> replaceRecommendationsForDay(
    String uid, {
    required DateTime day,
    required List<Recommendation> recommendations,
  }) async {
    _authorize(uid);
    if (recommendations.any(
      (item) => item.day == null || !_sameDay(item.day!, day),
    )) {
      throw ArgumentError(
        'Every recommendation must belong to the target day.',
      );
    }
    final stored = _recommendations.putIfAbsent(uid, () => {});
    stored.removeWhere(
      (_, recommendation) =>
          recommendation.day != null && _sameDay(recommendation.day!, day),
    );
    for (final recommendation in recommendations) {
      stored[recommendation.id] = recommendationFromCloud(
        recommendation.id,
        recommendationToCloud(recommendation).cast<String, dynamic>(),
      );
    }
  }

  @override
  Future<List<RiskAlert>> riskAlertsForDay(String uid, DateTime day) async {
    _authorize(uid);
    final values = (_riskAlerts[uid]?.values ?? const <RiskAlert>[])
        .where((item) => item.day != null && _sameDay(item.day!, day))
        .toList();
    return values..sort(
      (left, right) => right.severity.index.compareTo(left.severity.index),
    );
  }

  @override
  Future<void> replaceRiskAlertsForDay(
    String uid, {
    required DateTime day,
    required List<RiskAlert> alerts,
  }) async {
    _authorize(uid);
    if (alerts.any((item) => item.day == null || !_sameDay(item.day!, day))) {
      throw ArgumentError('Every risk alert must belong to the target day.');
    }
    final stored = _riskAlerts.putIfAbsent(uid, () => {});
    stored.removeWhere(
      (_, alert) => alert.day != null && _sameDay(alert.day!, day),
    );
    for (final alert in alerts) {
      stored[alert.id] = riskAlertFromCloud(
        alert.id,
        riskAlertToCloud(alert).cast<String, dynamic>(),
      );
    }
  }

  @override
  Future<void> setRiskAlertDismissed(
    String uid,
    String alertId, {
    required bool dismissed,
  }) async {
    _authorize(uid);
    final alert = _riskAlerts[uid]?[alertId];
    if (alert != null) {
      _riskAlerts[uid]![alertId] = alert.copyWith(dismissed: dismissed);
    }
  }

  @override
  Future<void> clearGuidance(String uid) async {
    _authorize(uid);
    _recommendations.remove(uid);
    _riskAlerts.remove(uid);
  }

  @override
  Future<Map<String, Object?>> exportUser(String uid) async {
    _authorize(uid);
    return {
      'uid': uid,
      if (_users[uid] case final state?) ...state.toExportJson(),
      'reservedCollections': {
        'scoreSnapshots': {
          for (final entry in (_scores[uid] ?? const {}).entries)
            entry.key: _exportSafe(
              scoreSnapshotToCloud(
                snapshot: entry.value,
                day: entry.value.day!,
              ),
            ),
        },
        'forecastPoints': {
          for (final entry in (_forecasts[uid] ?? const {}).entries)
            entry.key: _exportSafe(forecastPointToCloud(entry.value)),
        },
        'recommendations': {
          for (final entry in (_recommendations[uid] ?? const {}).entries)
            entry.key: _exportSafe(recommendationToCloud(entry.value)),
        },
        'riskAlerts': {
          for (final entry in (_riskAlerts[uid] ?? const {}).entries)
            entry.key: _exportSafe(riskAlertToCloud(entry.value)),
        },
      },
    };
  }

  @override
  Future<void> deleteUserTree(String uid) async {
    _authorize(uid);
    _users.remove(uid);
    _scores.remove(uid);
    _forecasts.remove(uid);
    _recommendations.remove(uid);
    _riskAlerts.remove(uid);
  }
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String scoreSnapshotId(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

String forecastPointId(DateTime time) =>
    '${scoreSnapshotId(time)}-'
    '${time.hour.toString().padLeft(2, '0')}-'
    '${time.minute.toString().padLeft(2, '0')}';

Object? _exportSafe(Object? value) => switch (value) {
  DateTime dateTime => dateTime.toIso8601String(),
  Map map => map.map(
    (key, child) => MapEntry(key.toString(), _exportSafe(child)),
  ),
  Iterable iterable => iterable.map(_exportSafe).toList(),
  _ => value,
};
