import 'dart:convert';

import 'cloud_schema.dart';
import 'models.dart';
import 'privacy_consent.dart';

class AccountSession {
  const AccountSession({
    required this.uid,
    required this.email,
    this.guardianConsentVerified = false,
  });

  final String uid;
  final String email;

  /// Trusted, current-version server Auth claim; never a profile checkbox.
  final bool guardianConsentVerified;
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

  /// Verifies the current account without signing in again or loading its data.
  Future<void> reauthenticate({required String password});
  Future<void> refreshPrivacyClaims();
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
  Future<void> reauthenticate({required String password}) async =>
      throw StateError('Firebase is not configured.');

  @override
  Future<void> refreshPrivacyClaims() async {}

  @override
  Future<void> deleteCurrentAccount() async {}
}

class MemoryAccountAuth implements AccountAuth {
  MemoryAccountAuth({
    this.session,
    this.configured = true,
    this.expectedPassword,
  });

  AccountSession? session;
  final bool configured;

  /// Optional deterministic credential check for tests; never persisted.
  String? expectedPassword;

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
    expectedPassword = password;
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
  Future<void> reauthenticate({required String password}) async {
    if (!configured || session == null || session!.email.isEmpty) {
      throw StateError('Sign in before verifying this account.');
    }
    if (password.isEmpty ||
        (expectedPassword != null && password != expectedPassword)) {
      throw StateError('The password could not be verified.');
    }
  }

  @override
  Future<void> refreshPrivacyClaims() async {}

  @override
  Future<void> deleteCurrentAccount() async {
    session = null;
  }
}

typedef AccountPrivacySnapshot = ({
  PrivacyConsent? consent,
  bool deletionPending,
  bool outcomeConsent,
  DateTime? outcomeConsentUpdatedAt,
});

abstract interface class CloudRepository {
  Future<CloudUserState?> readUser(String uid);
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid);

  /// Explicit acknowledgement only; returns the server-stamped receipt.
  Future<PrivacyConsent> savePrivacyConsent(String uid, PrivacyConsent receipt);

  /// Narrow optional-learning consent change, independent of profile sync.
  Future<DateTime> saveOutcomeConsent(String uid, bool enabled);

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

  Future<List<Recommendation>> recommendationsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  });

  Future<void> replaceRecommendationsForDay(
    String uid, {
    required DateTime day,
    required List<Recommendation> recommendations,
  });

  Future<void> setRecommendationStatus(
    String uid,
    String recommendationId, {
    required RecommendationStatus status,
  });

  Future<void> setRecommendationFeedback(
    String uid,
    String recommendationId, {
    required bool helpful,
  });

  Future<void> upsertOutcome(String uid, OutcomeRecord outcome);

  Future<List<OutcomeRecord>> outcomesByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  });

  Future<void> clearOutcomes(String uid);

  Future<void> deleteOutcome(String uid, String outcomeId);

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

/// The complete flat, client-writable Version 0.10-a user subtree. Keep this
/// list aligned with Security Rules. Firestore clients cannot discover unknown
/// collections or recursively enumerate administrator-created nested data.
const userDataChildCollections = <String>[
  'signals',
  'checkIns',
  'scoreSnapshots',
  'forecastPoints',
  'recommendations',
  'outcomes',
  'riskAlerts',
];

class UserDataDocument {
  const UserDataDocument(this.id, this.data);

  final String id;
  final Map<String, Object?> data;
}

/// Server-backed implementations must bypass cache and order pages by document
/// ID. The lifecycle rechecks ownership after every async boundary.
abstract interface class UserDataLifecycleStore {
  Future<Map<String, Object?>?> readUserDocument(String uid);

  /// Persist an owner-scoped deletion marker before deleting any documents.
  /// Security Rules block normal writes while the marker exists.
  Future<void> beginDeletion(String uid);
  Future<List<UserDataDocument>> readCollectionPage(
    String uid,
    String collection, {
    required int limit,
    String? afterId,
  });
  Future<void> deleteDocuments(String uid, String collection, List<String> ids);
  Future<void> deleteUserDocument(String uid);
}

/// Explicit, bounded privacy operations. Failures never return a partial
/// export; interrupted deletion is safe to retry and retains the root until
/// every known child collection has been confirmed empty on the server.
class AccountDataLifecycle {
  AccountDataLifecycle({
    required this.store,
    required this.currentUid,
    DateTime Function()? now,
    this.maxDocuments = 100000,
    this.maxExportBytes = 64 * 1024 * 1024,
    this.maxRequests = 5000,
  }) : now = now ?? DateTime.now;

  static const pageSize = 100;
  final UserDataLifecycleStore store;
  final String? Function() currentUid;
  final DateTime Function() now;
  final int maxDocuments;
  final int maxExportBytes;
  final int maxRequests;

  void _authorize(String uid) {
    if (uid.isEmpty || currentUid() != uid) {
      throw StateError('Account changed. The privacy operation was stopped.');
    }
  }

  Future<Map<String, Object?>> exportUser(String uid) async {
    _authorize(uid);
    var requests = 0;
    var documents = 0;
    var bytes = 0;
    void request() {
      _authorize(uid);
      if (++requests > maxRequests) {
        throw StateError(
          'Export exceeded its read limit. No file was created.',
        );
      }
    }

    void accountFor(Object? data) {
      bytes += utf8.encode(jsonEncode(_exportSafe(data))).length;
      if (bytes > maxExportBytes) {
        throw StateError(
          'Export exceeded its size limit. No file was created.',
        );
      }
    }

    request();
    final userDocument = await store.readUserDocument(uid);
    _authorize(uid);
    accountFor(userDocument);
    final collections = <String, Map<String, Object?>>{};
    for (final collection in userDataChildCollections) {
      final exported = <String, Object?>{};
      collections[collection] = exported;
      String? afterId;
      while (true) {
        request();
        final page = await store.readCollectionPage(
          uid,
          collection,
          limit: pageSize,
          afterId: afterId,
        );
        _authorize(uid);
        if (page.length > pageSize) {
          throw StateError(
            'Export returned an invalid page. No file was created.',
          );
        }
        for (final document in page) {
          if (document.id.isEmpty || exported.containsKey(document.id)) {
            throw StateError('Export pagination failed. No file was created.');
          }
          if (++documents > maxDocuments) {
            throw StateError(
              'Export exceeded its document limit. No file was created.',
            );
          }
          accountFor({document.id: document.data});
          exported[document.id] = _exportSafe(document.data);
          afterId = document.id;
        }
        if (page.length < pageSize) break;
      }
    }
    final result = buildUserDataExport(
      uid: uid,
      userDocument: userDocument,
      collections: collections,
      exportedAt: now(),
    );
    // Includes compatibility aliases; the complete generated JSON is bounded.
    if (utf8.encode(jsonEncode(result)).length > maxExportBytes) {
      throw StateError('Export exceeded its size limit. No file was created.');
    }
    _authorize(uid);
    return result;
  }

  Future<void> deleteUserTree(String uid) async {
    _authorize(uid);
    var requests = 0;
    var documents = 0;
    void request() {
      _authorize(uid);
      if (++requests > maxRequests) {
        throw StateError(
          'Deletion paused at its request limit. Retry to finish.',
        );
      }
    }

    request();
    await store.beginDeletion(uid);
    _authorize(uid);
    // The server marker blocks normal writes from every device. Re-scanning
    // also catches a write already in flight before the marker was committed.
    while (true) {
      for (final collection in userDataChildCollections) {
        while (true) {
          request();
          final page = await store.readCollectionPage(
            uid,
            collection,
            limit: pageSize,
          );
          _authorize(uid);
          if (page.isEmpty) break;
          if (page.length > pageSize ||
              page.any((document) => document.id.isEmpty)) {
            throw StateError(
              'Deletion received an invalid page. Retry to finish.',
            );
          }
          documents += page.length;
          if (documents > maxDocuments) {
            throw StateError(
              'Deletion paused at its document limit. Retry to finish.',
            );
          }
          request();
          await store.deleteDocuments(
            uid,
            collection,
            page.map((document) => document.id).toList(),
          );
          _authorize(uid);
        }
      }
      var allEmpty = true;
      for (final collection in userDataChildCollections) {
        request();
        final page = await store.readCollectionPage(uid, collection, limit: 1);
        _authorize(uid);
        if (page.isNotEmpty) {
          allEmpty = false;
          break;
        }
      }
      if (allEmpty) break;
    }
    request();
    await store.deleteUserDocument(uid);
    _authorize(uid);
  }
}

Map<String, Object?> buildUserDataExport({
  required String uid,
  required Map<String, Object?>? userDocument,
  required Map<String, Map<String, Object?>> collections,
  required DateTime exportedAt,
}) => {
  'exportVersion': 2,
  'uid': uid,
  'exportedAt': exportedAt.toUtc().toIso8601String(),
  'userDocument': _exportSafe(userDocument),
  'collections': _exportSafe(collections),
  'scope': {
    'collectionNames': userDataChildCollections,
    'nestedCollectionsIncluded': false,
    'pointInTimeSnapshot': false,
  },
  // Compatibility aliases for earlier Tonyo exports. Canonical raw records
  // above retain unknown fields, metadata and original Firestore document IDs.
  if (userDocument?['profile'] != null)
    'profile': _exportSafe(userDocument!['profile']),
  for (final collection in const ['signals', 'checkIns'])
    collection: [
      for (final entry in (collections[collection] ?? const {}).entries)
        {...(entry.value as Map).cast<String, Object?>(), 'id': entry.key},
    ],
  'reservedCollections': {
    for (final collection in userDataChildCollections.skip(2))
      collection: collections[collection] ?? const <String, Object?>{},
  },
};

/// A uid-enforcing repository for deterministic unit tests and offline demos.
class MemoryCloudRepository implements CloudRepository {
  MemoryCloudRepository({required this.signedInUid, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  String? signedInUid;
  final DateTime Function() _now;
  final Map<String, CloudUserState> _users = {};
  final Map<String, Map<String, ScoreSnapshot>> _scores = {};
  final Map<String, Map<String, ForecastPoint>> _forecasts = {};
  final Map<String, Map<String, Recommendation>> _recommendations = {};
  final Map<String, Map<String, OutcomeRecord>> _outcomes = {};
  final Map<String, Map<String, RiskAlert>> _riskAlerts = {};
  int replaceUserCallCount = 0;
  int scoreUpsertCallCount = 0;
  int forecastReplaceCallCount = 0;

  void seed(String uid, CloudUserState state) {
    _users[uid] = state;
  }

  void _authorize(String uid) {
    if (signedInUid == null || signedInUid != uid) {
      throw StateError('Cross-user repository access denied.');
    }
  }

  void _requireOutcomeConsent(String uid) {
    _authorize(uid);
    if (_users[uid]?.outcomeConsent != true) {
      throw StateError('Outcome collection requires explicit consent.');
    }
  }

  @override
  Future<CloudUserState?> readUser(String uid) async {
    _authorize(uid);
    return _users[uid];
  }

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) async {
    _authorize(uid);
    final state = _users[uid];
    if (state == null) {
      throw StateError('The account privacy record is unavailable.');
    }
    return (
      consent: state.privacyConsent,
      deletionPending: state.deletionPending,
      outcomeConsent: state.outcomeConsent,
      outcomeConsentUpdatedAt: state.outcomeConsentUpdatedAt,
    );
  }

  @override
  Future<PrivacyConsent> savePrivacyConsent(
    String uid,
    PrivacyConsent receipt,
  ) async {
    _authorize(uid);
    if (PrivacyConsent.tryParse(receipt.toJson()) == null) {
      throw ArgumentError(
        'A current explicit privacy acknowledgement is required.',
      );
    }
    final old = _users[uid];
    if (old?.privacyConsent != null &&
        !old!.privacyConsent!.sameIdentity(receipt)) {
      throw StateError(
        'Age band and region cannot be changed by a consent refresh.',
      );
    }
    if (old?.deletionPending == true) {
      throw StateError(
        'Account deletion is pending. Retry deletion to finish.',
      );
    }
    final now = _now().toUtc();
    final accepted = PrivacyConsent(
      ageBand: receipt.ageBand,
      region: receipt.region,
      acceptedAt: now,
    );
    _users[uid] =
        (old ??
                const CloudUserState(
                  profile: UserProfile(),
                  accountEmail: '',
                  onboardingComplete: false,
                  notificationsEnabled: false,
                  outcomeConsent: false,
                  healthAuthorized: false,
                  signals: [],
                  checkIns: [],
                ))
            .copyWith(
              privacyConsent: accepted,
              outcomeConsent: false,
              outcomeConsentUpdatedAt: now,
            );
    return accepted;
  }

  @override
  Future<DateTime> saveOutcomeConsent(String uid, bool enabled) async {
    _authorize(uid);
    final old = _users[uid];
    if (old == null || old.deletionPending) {
      throw StateError(
        'A current account is required to change outcome learning.',
      );
    }
    if (enabled && old.privacyConsent?.validAt(_now().toUtc()) != true) {
      throw StateError(
        'Review privacy and consent before enabling outcome learning.',
      );
    }
    final now = _now().toUtc();
    _users[uid] = old.copyWith(
      outcomeConsent: enabled,
      outcomeConsentUpdatedAt: now,
    );
    return now;
  }

  @override
  Future<void> replaceUser(String uid, CloudUserState state) async {
    _authorize(uid);
    replaceUserCallCount += 1;
    final existing = _users[uid];
    _users[uid] = state.copyWith(
      privacyConsent: existing?.privacyConsent,
      deletionPending: existing?.deletionPending,
      outcomeConsentUpdatedAt: existing?.outcomeConsentUpdatedAt,
    );
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
    scoreUpsertCallCount += 1;
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
    forecastReplaceCallCount += 1;
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
  Future<List<Recommendation>> recommendationsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    _authorize(uid);
    if (!end.isAfter(start)) {
      throw ArgumentError('Recommendation range end must follow start.');
    }
    final values = (_recommendations[uid]?.values ?? const <Recommendation>[])
        .where(
          (item) =>
              item.day != null &&
              !item.day!.isBefore(start) &&
              item.day!.isBefore(end),
        )
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
  Future<void> setRecommendationStatus(
    String uid,
    String recommendationId, {
    required RecommendationStatus status,
  }) async {
    _authorize(uid);
    final current = _recommendations[uid]?[recommendationId];
    if (current == null) {
      throw StateError('Recommendation $recommendationId does not exist.');
    }
    _recommendations[uid]![recommendationId] = current.copyWith(status: status);
  }

  @override
  Future<void> setRecommendationFeedback(
    String uid,
    String recommendationId, {
    required bool helpful,
  }) async {
    _authorize(uid);
    final current = _recommendations[uid]?[recommendationId];
    if (current == null) {
      throw StateError('Recommendation $recommendationId does not exist.');
    }
    _recommendations[uid]![recommendationId] = current.copyWith(
      helpful: helpful,
    );
  }

  @override
  Future<void> upsertOutcome(String uid, OutcomeRecord outcome) async {
    _requireOutcomeConsent(uid);
    _outcomes.putIfAbsent(uid, () => {})[outcome.id] = outcomeFromCloud(
      outcome.id,
      outcomeToCloud(outcome).cast<String, dynamic>(),
    );
  }

  @override
  Future<List<OutcomeRecord>> outcomesByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    _requireOutcomeConsent(uid);
    if (!end.isAfter(start)) {
      throw ArgumentError('Outcome range end must follow start.');
    }
    final values = (_outcomes[uid]?.values ?? const <OutcomeRecord>[])
        .where(
          (outcome) =>
              !outcome.observedAt.isBefore(start) &&
              outcome.observedAt.isBefore(end),
        )
        .toList();
    return values
      ..sort((left, right) => right.observedAt.compareTo(left.observedAt));
  }

  @override
  Future<void> clearOutcomes(String uid) async {
    _authorize(uid);
    _outcomes.remove(uid);
  }

  @override
  Future<void> deleteOutcome(String uid, String outcomeId) async {
    _authorize(uid);
    _outcomes[uid]?.remove(outcomeId);
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
    final state = _users[uid];
    final userDocument = state == null
        ? null
        : <String, Object?>{
            ...profileToCloud(
              profile: state.profile,
              email: state.accountEmail,
              onboardingComplete: state.onboardingComplete,
              notificationsEnabled: state.notificationsEnabled,
              crashNotificationsEnabled: state.crashNotificationsEnabled,
              recoveryNotificationsEnabled: state.recoveryNotificationsEnabled,
              notificationPrefsVersion: state.notificationPrefsVersion,
              outcomeConsent: state.outcomeConsent,
              healthAuthorized: state.healthAuthorized,
              lastSync: state.lastSync,
              healthSyncStatus: state.healthSyncStatus,
              lastHealthRefreshReason: state.lastHealthRefreshReason,
              lastHealthSyncAttempt: state.lastHealthSyncAttempt,
              lastHealthChangeAt: state.lastHealthChangeAt,
              healthBackgroundRefreshEnabled:
                  state.healthBackgroundRefreshEnabled,
              migrationVersion: state.migrationVersion,
              updatedAt: state.userUpdatedAt,
            ),
            if (state.personalizedEnergyModel != null)
              'personalizedEnergyModel': state.personalizedEnergyModel!
                  .toJson(),
            if (state.privacyConsent != null)
              'privacyConsent': state.privacyConsent!.toCloud(),
            if (state.privacyConsent != null)
              'consentFlags': {
                'wellnessOnlyAcknowledged':
                    state.privacyConsent!.wellnessAcknowledged,
                'outcomeCollection': state.outcomeConsent,
                'trainingRecordUse': state.outcomeConsent,
              },
            if (state.outcomeConsentUpdatedAt != null)
              'outcomeConsentUpdatedAt': state.outcomeConsentUpdatedAt,
            if (state.deletionPending) 'privacyDeletion': {'version': 1},
          };
    return buildUserDataExport(
      uid: uid,
      userDocument: userDocument,
      exportedAt: DateTime.now(),
      collections: {
        'signals': {
          for (final signal in state?.signals ?? const <SignalReading>[])
            signal.id: _exportSafe(signalToCloud(signal)),
        },
        'checkIns': {
          for (final checkIn in state?.checkIns ?? const <DailyCheckIn>[])
            checkIn.id: _exportSafe(checkInToCloud(checkIn)),
        },
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
        'outcomes': {
          for (final entry in (_outcomes[uid] ?? const {}).entries)
            entry.key: _exportSafe(outcomeToCloud(entry.value)),
        },
        'riskAlerts': {
          for (final entry in (_riskAlerts[uid] ?? const {}).entries)
            entry.key: _exportSafe(riskAlertToCloud(entry.value)),
        },
      },
    );
  }

  @override
  Future<void> deleteUserTree(String uid) async {
    _authorize(uid);
    _users.remove(uid);
    _scores.remove(uid);
    _forecasts.remove(uid);
    _recommendations.remove(uid);
    _outcomes.remove(uid);
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
