import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'cloud_repository.dart';
import 'cloud_schema.dart';
import 'energy_model_repository.dart';
import 'energy_model_summary.dart';
import 'firebase_options.dart';
import 'models.dart';
import 'privacy_consent.dart';
import 'ml_prep_models.dart';
import 'ml_prep_repository.dart';

class FirebaseRuntime {
  const FirebaseRuntime({
    required this.auth,
    required this.repository,
    required this.prepSource,
    required this.energyModelMetadataWriter,
  });

  final AccountAuth auth;
  final CloudRepository repository;
  final PrepDataSource prepSource;
  final EnergyModelMetadataWriter energyModelMetadataWriter;

  static Future<FirebaseRuntime?> initialize() async {
    if (!TonyoFirebaseOptions.isConfigured) return null;
    await Firebase.initializeApp(options: TonyoFirebaseOptions.currentPlatform);
    final auth = FirebaseAccountAuth(FirebaseAuth.instance);
    return FirebaseRuntime(
      auth: auth,
      energyModelMetadataWriter: FirestoreEnergyModelMetadataWriter(
        firestore: FirebaseFirestore.instance,
        auth: auth,
      ),
      prepSource: FirestorePrepDataSource(
        firestore: FirebaseFirestore.instance,
        auth: auth,
      ),
      repository: FirestoreCloudRepository(
        firestore: FirebaseFirestore.instance,
        auth: auth,
      ),
    );
  }
}

class FirebaseAccountAuth implements AccountAuth {
  FirebaseAccountAuth(this._auth);

  final FirebaseAuth _auth;
  String? _verifiedGuardianUid;
  bool _guardianConsentVerified = false;
  int _privacyClaimsGeneration = 0;

  @override
  bool get isConfigured => true;

  @override
  AccountSession? get currentSession {
    final user = _auth.currentUser;
    final email = user?.email;
    return user == null || email == null
        ? null
        : AccountSession(
            uid: user.uid,
            email: email,
            guardianConsentVerified:
                _verifiedGuardianUid == user.uid && _guardianConsentVerified,
          );
  }

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    _clearPrivacyClaims();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return _session(credential.user);
  }

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    _clearPrivacyClaims();
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return _session(credential.user);
  }

  @override
  Future<void> signOut() async {
    _clearPrivacyClaims();
    await _auth.signOut();
  }

  void _clearPrivacyClaims() {
    _privacyClaimsGeneration++;
    _verifiedGuardianUid = null;
    _guardianConsentVerified = false;
  }

  @override
  Future<void> refreshPrivacyClaims() async {
    _clearPrivacyClaims();
    final generation = _privacyClaimsGeneration;
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final token = await user.getIdTokenResult(true);
    if (_auth.currentUser?.uid != uid ||
        generation != _privacyClaimsGeneration) {
      throw StateError('Account changed while verifying privacy permissions.');
    }
    _verifiedGuardianUid = uid;
    _guardianConsentVerified =
        token.claims?['guardianConsentVerified'] == true &&
        token.claims?['guardianConsentPolicyVersion'] == 1;
  }

  @override
  Future<void> reauthenticate({required String password}) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw StateError('Sign in before verifying this account.');
    }
    if (password.isEmpty) {
      throw ArgumentError('Enter the account password to continue.');
    }
    final uid = user.uid;
    final result = await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    if (_auth.currentUser?.uid != uid || result.user?.uid != uid) {
      throw StateError('Account changed while verifying the password.');
    }
  }

  @override
  Future<void> deleteCurrentAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before deleting this account.');
    await user.delete();
  }

  static AccountSession _session(User? user) {
    final email = user?.email;
    if (user == null || email == null) {
      throw StateError('Firebase Auth returned an account without an email.');
    }
    return AccountSession(uid: user.uid, email: email);
  }
}

class FirestoreCloudRepository implements CloudRepository {
  FirestoreCloudRepository({
    required FirebaseFirestore firestore,
    required AccountAuth auth,
  }) : this._(firestore, auth);

  FirestoreCloudRepository._(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final AccountAuth _auth;

  DocumentReference<Map<String, dynamic>> _user(String uid) {
    _authorize(uid);
    return _firestore.collection('users').doc(uid);
  }

  void _authorize(String uid) {
    if (_auth.currentSession?.uid != uid) {
      throw StateError('Cross-user repository access denied.');
    }
  }

  Future<void> _requireOutcomeConsent(String uid) async {
    final snapshot = await _user(uid).get();
    final consent =
        (snapshot.data()?['consentFlags'] as Map?)?.cast<String, dynamic>() ??
        const {};
    if (consent['outcomeCollection'] != true ||
        consent['trainingRecordUse'] != true) {
      throw StateError('Outcome collection requires explicit consent.');
    }
  }

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) async {
    final snapshot = await _user(
      uid,
    ).get(const GetOptions(source: Source.server));
    _authorize(uid);
    final data = snapshot.data();
    if (data == null) {
      throw StateError('The account privacy record is unavailable.');
    }
    return _accountPrivacy(data);
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
    final user = _user(uid);
    await user.set({
      'privacyConsent': {
        ...receipt.toCloud(),
        'acceptedAt': FieldValue.serverTimestamp(),
      },
      'consentFlags': {
        'outcomeCollection': false,
        'trainingRecordUse': false,
        'wellnessOnlyAcknowledged': true,
      },
      'outcomeConsentUpdatedAt': FieldValue.serverTimestamp(),
      'schemaVersion': cloudSchemaVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _authorize(uid);
    final snapshot = await user.get(const GetOptions(source: Source.server));
    _authorize(uid);
    final data = snapshot.data();
    final saved = data == null ? null : _accountPrivacy(data);
    final accepted = saved?.consent;
    if (accepted == null ||
        !accepted.sameIdentity(receipt) ||
        saved!.deletionPending ||
        saved.outcomeConsentUpdatedAt == null) {
      throw StateError(
        'The server could not confirm the privacy acknowledgement.',
      );
    }
    return accepted;
  }

  @override
  Future<DateTime> saveOutcomeConsent(String uid, bool enabled) async {
    final user = _user(uid);
    await user.set({
      'consentFlags': {
        'outcomeCollection': enabled,
        'trainingRecordUse': enabled,
      },
      'outcomeConsentUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _authorize(uid);
    final snapshot = await user.get(const GetOptions(source: Source.server));
    _authorize(uid);
    final data = snapshot.data();
    final saved = data == null ? null : _accountPrivacy(data);
    final flags = data?['consentFlags'];
    if (saved == null ||
        saved.deletionPending ||
        saved.outcomeConsentUpdatedAt == null ||
        flags is! Map ||
        flags['outcomeCollection'] != enabled ||
        flags['trainingRecordUse'] != enabled) {
      throw StateError(
        'The server could not confirm the outcome-learning choice.',
      );
    }
    return saved.outcomeConsentUpdatedAt!;
  }

  static AccountPrivacySnapshot _accountPrivacy(Map<String, dynamic> data) {
    final flags = data['consentFlags'];
    return (
      consent: PrivacyConsent.tryParse(
        _normalizeCloudValue(data['privacyConsent']),
      ),
      deletionPending: data.containsKey('privacyDeletion'),
      outcomeConsent:
          flags is Map &&
          flags['outcomeCollection'] == true &&
          flags['trainingRecordUse'] == true,
      outcomeConsentUpdatedAt: _dateTimeOrNull(
        data['outcomeConsentUpdatedAt'],
      )?.toUtc(),
    );
  }

  @override
  Future<CloudUserState?> readUser(String uid) async {
    final user = _user(uid);
    final values = await Future.wait([
      user.get(const GetOptions(source: Source.server)),
      user.collection('signals').get(),
      user.collection('checkIns').get(),
    ]);
    _authorize(uid);
    final profileSnapshot = values[0] as DocumentSnapshot<Map<String, dynamic>>;
    if (!profileSnapshot.exists) return null;
    final data = profileSnapshot.data()!;
    final privacy = _accountPrivacy(data);
    final prefs = (data['prefs'] as Map?)?.cast<String, dynamic>() ?? const {};
    final notificationPrefsVersion =
        (prefs['notificationPreferencesVersion'] as num?)?.round() ?? 0;
    final consent =
        (data['consentFlags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final healthSync =
        (data['healthSync'] as Map?)?.cast<String, dynamic>() ?? const {};
    final signalSnapshot = values[1] as QuerySnapshot<Map<String, dynamic>>;
    final checkInSnapshot = values[2] as QuerySnapshot<Map<String, dynamic>>;
    return CloudUserState(
      profile: data['profile'] is Map
          ? UserProfile.fromJson(
              (data['profile'] as Map).cast<String, dynamic>(),
            )
          : const UserProfile(),
      accountEmail:
          data['accountEmail'] as String? ?? _auth.currentSession!.email,
      onboardingComplete: data['onboardingComplete'] as bool? ?? false,
      notificationsEnabled:
          notificationPrefsVersion >= notificationPreferencesVersion &&
          (prefs['notificationsEnabled'] as bool? ?? false),
      crashNotificationsEnabled:
          prefs['crashNotificationsEnabled'] as bool? ?? true,
      recoveryNotificationsEnabled:
          prefs['recoveryNotificationsEnabled'] as bool? ?? true,
      notificationPrefsVersion: notificationPrefsVersion,
      outcomeConsent:
          consent['outcomeCollection'] == true &&
          consent['trainingRecordUse'] == true,
      healthAuthorized: prefs['healthAuthorized'] as bool? ?? false,
      lastSync: _dateTimeOrNull(data['lastHealthSync']),
      healthSyncStatus:
          HealthSyncStatus.values
              .where((value) => value.name == healthSync['status'])
              .firstOrNull ??
          HealthSyncStatus.idle,
      lastHealthRefreshReason: HealthRefreshReason.values
          .where((value) => value.name == healthSync['reason'])
          .firstOrNull,
      lastHealthSyncAttempt: _dateTimeOrNull(healthSync['lastAttemptAt']),
      lastHealthChangeAt: _dateTimeOrNull(healthSync['lastMeaningfulChangeAt']),
      healthBackgroundRefreshEnabled:
          healthSync['backgroundRefreshEnabled'] as bool? ?? false,
      migrationVersion: data['localMigrationVersion'] as int? ?? 0,
      personalizedEnergyModel: _readEnergyModelSummary(
        data['personalizedEnergyModel'],
      ),
      userUpdatedAt: _dateTimeOrNull(data['updatedAt'])?.toUtc(),
      privacyConsent: privacy.consent,
      deletionPending: privacy.deletionPending,
      outcomeConsentUpdatedAt: privacy.outcomeConsentUpdatedAt,
      signals: signalSnapshot.docs
          .map(
            (document) =>
                signalFromCloud(document.id, _normalizeDates(document.data())),
          )
          .toList(),
      checkIns: checkInSnapshot.docs
          .map(
            (document) =>
                checkInFromCloud(document.id, _normalizeDates(document.data())),
          )
          .toList(),
    );
  }

  @override
  Future<void> replaceUser(String uid, CloudUserState state) async {
    final user = _user(uid);
    await user.set(
      profileToCloud(
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
        healthBackgroundRefreshEnabled: state.healthBackgroundRefreshEnabled,
        migrationVersion: state.migrationVersion,
      ),
      SetOptions(merge: true),
    );
    await _replaceCollection(
      user.collection('signals'),
      state.signals.map((value) => (value.id, signalToCloud(value))),
    );
    await _replaceCollection(
      user.collection('checkIns'),
      state.checkIns.map((value) => (value.id, checkInToCloud(value))),
    );
  }

  Future<void> _replaceCollection(
    CollectionReference<Map<String, dynamic>> collection,
    Iterable<(String, Map<String, Object?>)> values,
  ) async {
    final desired = {for (final value in values) value.$1: value.$2};
    final existing = await collection.get();
    final operations =
        <(DocumentReference<Map<String, dynamic>>, Map<String, Object?>?)>[
          for (final document in existing.docs)
            if (!desired.containsKey(document.id)) (document.reference, null),
          for (final entry in desired.entries)
            (collection.doc(entry.key), entry.value),
        ];
    const chunkSize = 450;
    for (var offset = 0; offset < operations.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, operations.length);
      final batch = _firestore.batch();
      for (final operation in operations.sublist(offset, end)) {
        final data = operation.$2;
        if (data == null) {
          batch.delete(operation.$1);
        } else {
          batch.set(operation.$1, data);
        }
      }
      await batch.commit();
    }
  }

  @override
  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
  }) async {
    Query<Map<String, dynamic>> query = _user(uid)
        .collection('signals')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThan: end);
    if (type != null) query = query.where('type', isEqualTo: type.name);
    final snapshot = await query.orderBy('timestamp', descending: true).get();
    return snapshot.docs
        .map(
          (document) =>
              signalFromCloud(document.id, _normalizeDates(document.data())),
        )
        .toList();
  }

  @override
  Future<List<DailyCheckIn>> checkInsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    final snapshot = await _user(uid)
        .collection('checkIns')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThan: end)
        .orderBy('timestamp', descending: true)
        .get();
    return snapshot.docs
        .map(
          (document) =>
              checkInFromCloud(document.id, _normalizeDates(document.data())),
        )
        .toList();
  }

  @override
  Future<DailyCheckIn?> latestCheckIn(String uid) async {
    final snapshot = await _user(uid)
        .collection('checkIns')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final document = snapshot.docs.single;
    return checkInFromCloud(document.id, _normalizeDates(document.data()));
  }

  @override
  Future<List<SignalReading>> reactionBaselineWindow(
    String uid, {
    int limit = 14,
  }) async {
    final snapshot = await _user(uid)
        .collection('signals')
        .where('type', isEqualTo: SignalType.reactionTime.name)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map(
          (document) =>
              signalFromCloud(document.id, _normalizeDates(document.data())),
        )
        .toList();
  }

  @override
  Future<void> upsertScoreSnapshot(String uid, ScoreSnapshot snapshot) async {
    final day = snapshot.day;
    if (day == null) throw ArgumentError('A score snapshot requires a day.');
    await _user(uid)
        .collection('scoreSnapshots')
        .doc(scoreSnapshotId(day))
        .set(
          scoreSnapshotToCloud(snapshot: snapshot, day: day),
          SetOptions(merge: true),
        );
  }

  @override
  Future<ScoreSnapshot?> scoreSnapshotForDay(String uid, DateTime day) async {
    final document = await _user(
      uid,
    ).collection('scoreSnapshots').doc(scoreSnapshotId(day)).get();
    final data = document.data();
    return data == null ? null : scoreSnapshotFromCloud(_normalizeDates(data));
  }

  @override
  Future<void> clearScoreSnapshots(String uid) async {
    final collection = _user(uid).collection('scoreSnapshots');
    while (true) {
      final page = await collection.limit(100).get();
      if (page.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final document in page.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
  }

  @override
  Future<List<ForecastPoint>> forecastPointsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    final snapshot = await _user(uid)
        .collection('forecastPoints')
        .where('time', isGreaterThanOrEqualTo: start)
        .where('time', isLessThan: end)
        .orderBy('time')
        .get();
    return snapshot.docs
        .map(
          (document) =>
              forecastPointFromCloud(_normalizeDates(document.data())),
        )
        .toList();
  }

  @override
  Future<void> replaceForecastPoints(
    String uid, {
    required DateTime day,
    required List<ForecastPoint> points,
  }) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    if (points.any(
      (point) => point.time.isBefore(start) || !point.time.isBefore(end),
    )) {
      throw ArgumentError(
        'Every forecast point must belong to the target day.',
      );
    }
    final collection = _user(uid).collection('forecastPoints');
    final existing = await collection
        .where('time', isGreaterThanOrEqualTo: start)
        .where('time', isLessThan: end)
        .get();
    final desired = {
      for (final point in points) forecastPointId(point.time): point,
    };
    final batch = _firestore.batch();
    for (final document in existing.docs) {
      if (!desired.containsKey(document.id)) batch.delete(document.reference);
    }
    for (final entry in desired.entries) {
      batch.set(collection.doc(entry.key), forecastPointToCloud(entry.value));
    }
    await batch.commit();
  }

  @override
  Future<List<Recommendation>> recommendationsForDay(
    String uid,
    DateTime day,
  ) async {
    final start = DateTime(day.year, day.month, day.day);
    final snapshot = await _user(
      uid,
    ).collection('recommendations').where('day', isEqualTo: start).get();
    final values = snapshot.docs
        .map(
          (document) => recommendationFromCloud(
            document.id,
            _normalizeDates(document.data()),
          ),
        )
        .toList();
    return values..sort((left, right) {
      final leftTime = left.scheduledAt ?? start;
      final rightTime = right.scheduledAt ?? start;
      return leftTime.compareTo(rightTime);
    });
  }

  @override
  Future<List<Recommendation>> recommendationsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('Recommendation range end must follow start.');
    }
    final snapshot = await _user(uid)
        .collection('recommendations')
        .where('day', isGreaterThanOrEqualTo: start)
        .where('day', isLessThan: end)
        .get();
    final values = snapshot.docs
        .map(
          (document) => recommendationFromCloud(
            document.id,
            _normalizeDates(document.data()),
          ),
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
    final start = DateTime(day.year, day.month, day.day);
    if (recommendations.any(
      (item) => item.day == null || !_sameDay(item.day!, start),
    )) {
      throw ArgumentError(
        'Every recommendation must belong to the target day.',
      );
    }
    final collection = _user(uid).collection('recommendations');
    final existing = await collection.where('day', isEqualTo: start).get();
    final desired = {for (final item in recommendations) item.id: item};
    final batch = _firestore.batch();
    for (final document in existing.docs) {
      if (!desired.containsKey(document.id)) batch.delete(document.reference);
    }
    for (final entry in desired.entries) {
      batch.set(collection.doc(entry.key), recommendationToCloud(entry.value));
    }
    await batch.commit();
  }

  @override
  Future<void> setRecommendationStatus(
    String uid,
    String recommendationId, {
    required RecommendationStatus status,
  }) => _user(uid).collection('recommendations').doc(recommendationId).update({
    'status': status.name,
  });

  @override
  Future<void> setRecommendationFeedback(
    String uid,
    String recommendationId, {
    required bool helpful,
  }) => _user(uid).collection('recommendations').doc(recommendationId).update({
    'feedback': helpful,
  });

  @override
  Future<void> upsertOutcome(String uid, OutcomeRecord outcome) async {
    await _requireOutcomeConsent(uid);
    await _user(
      uid,
    ).collection('outcomes').doc(outcome.id).set(outcomeToCloud(outcome));
  }

  @override
  Future<List<OutcomeRecord>> outcomesByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    if (!end.isAfter(start)) {
      throw ArgumentError('Outcome range end must follow start.');
    }
    await _requireOutcomeConsent(uid);
    final snapshot = await _user(uid)
        .collection('outcomes')
        .where('observedAt', isGreaterThanOrEqualTo: start)
        .where('observedAt', isLessThan: end)
        .get();
    final values = snapshot.docs
        .map(
          (document) =>
              outcomeFromCloud(document.id, _normalizeDates(document.data())),
        )
        .toList();
    return values
      ..sort((left, right) => right.observedAt.compareTo(left.observedAt));
  }

  @override
  Future<void> clearOutcomes(String uid) async {
    final collection = _user(uid).collection('outcomes');
    while (true) {
      final page = await collection.limit(100).get();
      if (page.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final document in page.docs) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
  }

  @override
  Future<void> deleteOutcome(String uid, String outcomeId) =>
      _user(uid).collection('outcomes').doc(outcomeId).delete();

  @override
  Future<List<RiskAlert>> riskAlertsForDay(String uid, DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final snapshot = await _user(
      uid,
    ).collection('riskAlerts').where('day', isEqualTo: start).get();
    final values = snapshot.docs
        .map(
          (document) =>
              riskAlertFromCloud(document.id, _normalizeDates(document.data())),
        )
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
    final start = DateTime(day.year, day.month, day.day);
    if (alerts.any((item) => item.day == null || !_sameDay(item.day!, start))) {
      throw ArgumentError('Every risk alert must belong to the target day.');
    }
    final collection = _user(uid).collection('riskAlerts');
    final existing = await collection.where('day', isEqualTo: start).get();
    final desired = {for (final item in alerts) item.id: item};
    final batch = _firestore.batch();
    for (final document in existing.docs) {
      if (!desired.containsKey(document.id)) batch.delete(document.reference);
    }
    for (final entry in desired.entries) {
      batch.set(collection.doc(entry.key), riskAlertToCloud(entry.value));
    }
    await batch.commit();
  }

  @override
  Future<void> setRiskAlertDismissed(
    String uid,
    String alertId, {
    required bool dismissed,
  }) => _user(uid).collection('riskAlerts').doc(alertId).set({
    'dismissed': dismissed,
  }, SetOptions(merge: true));

  @override
  Future<void> clearGuidance(String uid) async {
    for (final collectionName in const ['recommendations', 'riskAlerts']) {
      final collection = _user(uid).collection(collectionName);
      while (true) {
        final page = await collection.limit(100).get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final document in page.docs) {
          batch.delete(document.reference);
        }
        await batch.commit();
      }
    }
  }

  @override
  Future<Map<String, Object?>> exportUser(String uid) =>
      _dataLifecycle.exportUser(uid);

  @override
  Future<void> deleteUserTree(String uid) => _dataLifecycle.deleteUserTree(uid);

  AccountDataLifecycle get _dataLifecycle => AccountDataLifecycle(
    store: _FirestoreUserDataLifecycleStore(_firestore, _auth),
    currentUid: () => _auth.currentSession?.uid,
  );

  static Map<String, dynamic> _normalizeDates(Map<String, dynamic> data) =>
      data.map(
        (key, value) =>
            MapEntry(key, value is Timestamp ? value.toDate() : value),
      );

  static Object? _normalizeCloudValue(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate().toUtc(),
    Map map => map.map(
      (key, child) => MapEntry(key.toString(), _normalizeCloudValue(child)),
    ),
    Iterable iterable => iterable.map(_normalizeCloudValue).toList(),
    _ => value,
  };

  static EnergyModelSummary? _readEnergyModelSummary(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) return null;
    final normalized = _normalizeDates(value.cast<String, dynamic>());
    final window = normalized['window'];
    if (window is Map && window.keys.every((key) => key is String)) {
      normalized['window'] = _normalizeDates(window.cast<String, dynamic>());
    }
    return EnergyModelSummary.tryParse(normalized);
  }

  static DateTime? _dateTimeOrNull(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    String string => DateTime.tryParse(string),
    _ => null,
  };

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static Object? _jsonSafe(Object? value) => switch (value) {
    // Preserve Firestore's nanoseconds and special values without silently
    // truncating or dropping unknown metadata from the canonical raw export.
    Timestamp timestamp => {
      '__firestoreType': 'timestamp',
      'seconds': timestamp.seconds,
      'nanoseconds': timestamp.nanoseconds,
      'iso8601': timestamp.toDate().toUtc().toIso8601String(),
    },
    GeoPoint point => {
      '__firestoreType': 'geopoint',
      'latitude': point.latitude,
      'longitude': point.longitude,
    },
    Blob blob => {
      '__firestoreType': 'bytes',
      'base64': base64Encode(blob.bytes),
    },
    DocumentReference reference => {
      '__firestoreType': 'reference',
      'projectId': reference.firestore.app.options.projectId,
      'databaseId': reference.firestore.databaseId,
      'path': reference.path,
    },
    double number when !number.isFinite => {
      '__firestoreType': 'double',
      'value': number.toString(),
    },
    DateTime dateTime => dateTime.toIso8601String(),
    Map map => map.map(
      (key, child) => MapEntry(key.toString(), _jsonSafe(child)),
    ),
    Iterable iterable => iterable.map(_jsonSafe).toList(),
    _ => value,
  };
}

class _FirestoreUserDataLifecycleStore implements UserDataLifecycleStore {
  _FirestoreUserDataLifecycleStore(this.firestore, this.auth);

  final FirebaseFirestore firestore;
  final AccountAuth auth;

  void _authorize(String uid) {
    if (uid.isEmpty || auth.currentSession?.uid != uid) {
      throw StateError('Cross-user repository access denied.');
    }
  }

  DocumentReference<Map<String, dynamic>> _user(String uid) {
    _authorize(uid);
    return firestore.collection('users').doc(uid);
  }

  CollectionReference<Map<String, dynamic>> _collection(
    String uid,
    String name,
  ) {
    if (!userDataChildCollections.contains(name)) {
      throw ArgumentError('Unknown user data collection.');
    }
    return _user(uid).collection(name);
  }

  @override
  Future<void> beginDeletion(String uid) async {
    await _user(uid).set({
      'privacyDeletion': {
        'version': 1,
        'requestedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
    _authorize(uid);
  }

  @override
  Future<Map<String, Object?>?> readUserDocument(String uid) async {
    final document = await _user(
      uid,
    ).get(const GetOptions(source: Source.server));
    _authorize(uid);
    final data = document.data();
    return data == null
        ? null
        : (FirestoreCloudRepository._jsonSafe(data) as Map)
              .cast<String, Object?>();
  }

  @override
  Future<List<UserDataDocument>> readCollectionPage(
    String uid,
    String collection, {
    required int limit,
    String? afterId,
  }) async {
    if (limit < 1 || limit > AccountDataLifecycle.pageSize) {
      throw ArgumentError('Invalid user data page size.');
    }
    Query<Map<String, dynamic>> query = _collection(
      uid,
      collection,
    ).orderBy(FieldPath.documentId).limit(limit);
    if (afterId != null) query = query.startAfter([afterId]);
    final page = await query.get(const GetOptions(source: Source.server));
    _authorize(uid);
    return page.docs
        .map(
          (document) => UserDataDocument(
            document.id,
            (FirestoreCloudRepository._jsonSafe(document.data()) as Map)
                .cast<String, Object?>(),
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteDocuments(
    String uid,
    String collection,
    List<String> ids,
  ) async {
    _authorize(uid);
    if (ids.isEmpty || ids.length > AccountDataLifecycle.pageSize) {
      throw ArgumentError('Invalid user data deletion batch size.');
    }
    final documents = _collection(uid, collection);
    final batch = firestore.batch();
    for (final id in ids) {
      batch.delete(documents.doc(id));
    }
    _authorize(uid);
    await batch.commit();
    _authorize(uid);
  }

  @override
  Future<void> deleteUserDocument(String uid) async {
    await _user(uid).delete();
    _authorize(uid);
  }
}
