import 'local_day.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'cloud_repository.dart';
import 'heart_rate_cloud.dart';
import 'cloud_schema.dart';
import 'cloud_sync.dart';
import 'energy_model_repository.dart';
import 'energy_model_summary.dart';
import 'firebase_options.dart';
import 'firebase_emulator_options.dart';
import 'firestore_value_codec.dart';
import 'incremental_inputs.dart';
import 'forecast_day_store.dart';
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
    required this.heartRateCloudStore,
  });

  final AccountAuth auth;
  final CloudRepository repository;
  final HeartRateCloudStore heartRateCloudStore;
  final PrepDataSource prepSource;
  final EnergyModelMetadataWriter energyModelMetadataWriter;

  static Future<FirebaseRuntime?> initialize() async {
    final FirebaseApp app;
    if (TonyoFirebaseEmulatorOptions.enabled) {
      TonyoFirebaseEmulatorOptions.validate(
        isDebugBuild: kDebugMode,
        hasFirebaseConfiguration: TonyoFirebaseOptions.hasAnySuppliedValue,
      );
      // The current Firestore platform factory requires a default Core app even
      // when all Firestore/Auth clients below target a named app. Give that
      // scaffold the same synthetic demo options; never load real options.
      final scaffold = await Firebase.initializeApp(
        options: TonyoFirebaseEmulatorOptions.options,
      );
      if (scaffold.options.projectId !=
          TonyoFirebaseEmulatorOptions.projectId) {
        throw StateError('Local emulators require a synthetic default app.');
      }
      app = await Firebase.initializeApp(
        name: TonyoFirebaseEmulatorOptions.appName,
        options: TonyoFirebaseEmulatorOptions.options,
      );
    } else {
      if (!TonyoFirebaseOptions.isConfigured) return null;
      app = await Firebase.initializeApp(
        options: TonyoFirebaseOptions.currentPlatform,
      );
    }
    final firebaseAuth = FirebaseAuth.instanceFor(app: app);
    final firestore = FirebaseFirestore.instanceFor(app: app);
    if (TonyoFirebaseEmulatorOptions.enabled) {
      // Configure both native clients before any repository/listener can use
      // them. The named app also isolates its native Auth session/cache.
      await firebaseAuth.useAuthEmulator(
        TonyoFirebaseEmulatorOptions.host,
        TonyoFirebaseEmulatorOptions.authPort,
        automaticHostMapping: false,
      );
      firestore.settings = const Settings(persistenceEnabled: false);
      firestore.useFirestoreEmulator(
        TonyoFirebaseEmulatorOptions.host,
        TonyoFirebaseEmulatorOptions.firestorePort,
        automaticHostMapping: false,
      );
    }
    final auth = FirebaseAccountAuth(firebaseAuth);
    return FirebaseRuntime(
      auth: auth,
      heartRateCloudStore: FirestoreHeartRateCloudStore(
        firestore: firestore,
        auth: auth,
      ),
      energyModelMetadataWriter: FirestoreEnergyModelMetadataWriter(
        firestore: firestore,
        auth: auth,
      ),
      prepSource: FirestorePrepDataSource(firestore: firestore, auth: auth),
      repository: FirestoreCloudRepository(firestore: firestore, auth: auth),
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

  @override
  Future<void> sendPasswordReset({required String email}) =>
      _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());

  @override
  Future<String> verifyPasswordResetCode(String code) =>
      _auth.verifyPasswordResetCode(code.trim());

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) => _auth.confirmPasswordReset(code: code.trim(), newPassword: newPassword);

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final uid = _auth.currentUser?.uid;
    await reauthenticate(password: currentPassword);
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Account changed while changing the password.');
    }
    await user.updatePassword(newPassword);
  }

  static AccountSession _session(User? user) {
    final email = user?.email;
    if (user == null || email == null) {
      throw StateError('Firebase Auth returned an account without an email.');
    }
    return AccountSession(uid: user.uid, email: email);
  }
}

class FirestoreCloudRepository
    implements CloudRepository, EfficientInputRepository {
  FirestoreCloudRepository({
    required FirebaseFirestore firestore,
    required AccountAuth auth,
  }) : this._(firestore, auth);

  FirestoreCloudRepository._(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final AccountAuth _auth;
  String? _cachedInputsUid;
  CloudUserState? _cachedInputs;

  CloudUserState? _cachedInputState(String uid) {
    _authorize(uid);
    return _cachedInputsUid == uid ? _cachedInputs : null;
  }

  void _cacheInputState(String uid, CloudUserState state) {
    _authorize(uid);
    _cachedInputsUid = uid;
    _cachedInputs = state;
  }

  void _invalidateInputCache() {
    _cachedInputsUid = null;
    _cachedInputs = null;
  }

  late final ForecastDayStore _forecastDays = ForecastDayStore(
    loadDays: (uid, firstDate, lastDate) async {
      final snapshot = await _user(uid)
          .collection('forecastDays')
          .where('localDate', isGreaterThanOrEqualTo: firstDate)
          .where('localDate', isLessThanOrEqualTo: lastDate)
          .get(const GetOptions(source: Source.server));
      _authorize(uid);
      return {
        for (final document in snapshot.docs)
          document.id: _normalizeDates(document.data()),
      };
    },
    loadDay: (uid, id) async {
      final document = await _user(uid)
          .collection('forecastDays')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      _authorize(uid);
      final data = document.data();
      return data == null ? null : _normalizeDates(data);
    },
    loadLegacy: (uid, start, end) async {
      final snapshot = await _user(uid)
          .collection('forecastPoints')
          .where('time', isGreaterThanOrEqualTo: start)
          .where('time', isLessThan: end)
          .orderBy('time')
          .get(const GetOptions(source: Source.server));
      _authorize(uid);
      return snapshot.docs
          .map(
            (document) =>
                forecastPointFromCloud(_normalizeDates(document.data())),
          )
          .toList();
    },
    writeDay: (uid, id, data) => _user(
      uid,
    ).collection('forecastDays').doc(id).set(encodeFirestoreDocument(data)),
  );

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
    _invalidateInputCache();
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final before = await user.get(const GetOptions(source: Source.server));
        _authorize(uid);
        final beforeData = before.data();
        if (beforeData == null) return null;
        final readRevision = beforeData['inputSyncVersion'] == 1
            ? _inputRevision(beforeData)
            : null;
        final values = await Future.wait([
          user
              .collection('signals')
              .get(const GetOptions(source: Source.server)),
          user
              .collection('checkIns')
              .get(const GetOptions(source: Source.server)),
        ]);
        _authorize(uid);
        final confirmed = await user.get(
          const GetOptions(source: Source.server),
        );
        _authorize(uid);
        final confirmedData = confirmed.data();
        if (confirmedData == null) return null;
        try {
          if (readRevision == null) {
            // Legacy accounts have no journal cursor. This remains a full,
            // read-only restore; its first new write activates the protocol.
            if (confirmedData['inputSyncVersion'] == 1 ||
                !_sameCloudValue(beforeData, confirmedData)) {
              throw const InputRevisionChanged(0, 1);
            }
          } else {
            verifyStableInputRevision(
              readRevision: readRevision,
              confirmedRevision: _inputRevision(confirmedData),
            );
          }
        } on InputRevisionChanged {
          if (attempt == 2) rethrow;
          continue;
        }
        final state = _stateFromData(
          confirmedData,
          signals: values[0].docs
              .map(
                (document) => signalFromCloud(
                  document.id,
                  _normalizeDates(document.data()),
                ),
              )
              .toList(),
          checkIns: values[1].docs
              .map(
                (document) => checkInFromCloud(
                  document.id,
                  _normalizeDates(document.data()),
                ),
              )
              .toList(),
        );
        _cacheInputState(uid, state);
        return state;
      }
      throw StateError('Inputs changed during account restoration. Retry.');
    } on Object {
      _invalidateInputCache();
      rethrow;
    }
  }

  int _inputRevision(Map<String, dynamic> data) {
    if (data['inputSyncVersion'] != 1) {
      throw StateError('The account input sync version is unsupported.');
    }
    return parseInputRevision(data['inputRevision']);
  }

  @override
  Future<void> activateInputSync(String uid) async {
    final user = _user(uid);
    if (_cachedInputState(uid)?.inputSyncVersion == 1) return;
    final activated = await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(user);
      _authorize(uid);
      final data = current.data();
      if (data == null || _accountPrivacy(data).deletionPending) {
        throw StateError('The account is unavailable for syncing.');
      }
      if (data['inputSyncVersion'] == 1) {
        _inputRevision(data);
        return false;
      }
      if (data['inputSyncVersion'] != null && data['inputSyncVersion'] != 0) {
        throw StateError('This account requires a newer sync version.');
      }
      transaction.set(user, {
        'inputSyncVersion': 1,
        'inputRevision': 0,
      }, SetOptions(merge: true));
      return true;
    });
    _authorize(uid);
    if (activated) _invalidateInputCache();
  }

  @override
  Future<void> finishHeartRateMigration(String uid) async {
    final user = _user(uid);
    if (_cachedInputState(uid)?.heartRateStorageVersion == 1) return;
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(user);
      _authorize(uid);
      final data = current.data();
      if (data == null || _accountPrivacy(data).deletionPending) {
        throw StateError('The account is unavailable for syncing.');
      }
      _inputRevision(data);
      if (data['heartRateStorageVersion'] == 1) return;
      transaction.set(user, {
        'heartRateStorageVersion': 1,
      }, SetOptions(merge: true));
    });
    _authorize(uid);
    final cached = _cachedInputState(uid);
    if (cached != null) {
      _cacheInputState(uid, cached.copyWith(heartRateStorageVersion: 1));
    }
  }

  @override
  Future<CloudUserState?> readUserSince(
    String uid, {
    required InputSyncSnapshot baseline,
    required int revision,
  }) async {
    final user = _user(uid);
    parseInputRevision(revision);
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final before = await user.get(const GetOptions(source: Source.server));
        _authorize(uid);
        final beforeData = before.data();
        if (beforeData == null) {
          _invalidateInputCache();
          return null;
        }
        if (beforeData['inputSyncVersion'] != 1) return readUser(uid);
        final readRevision = _inputRevision(beforeData);
        if (readRevision < revision) return readUser(uid);
        final changes = <InputChangeRecord>[];
        QueryDocumentSnapshot<Map<String, dynamic>>? after;
        if (readRevision > revision) {
          while (true) {
            Query<Map<String, dynamic>> query = user
                .collection('inputChanges')
                .where('revision', isGreaterThan: revision)
                .where('revision', isLessThanOrEqualTo: readRevision)
                .orderBy('revision')
                .orderBy(FieldPath.documentId)
                .limit(400);
            if (after != null) query = query.startAfterDocument(after);
            final page = await query.get(
              const GetOptions(source: Source.server),
            );
            _authorize(uid);
            for (final document in page.docs) {
              final change = InputChangeRecord.fromJson(
                _normalizeDates(document.data()),
              );
              if (document.id !=
                  inputChangeDocumentId(change.collection, change.id)) {
                throw const FormatException('Input change identity mismatch.');
              }
              changes.add(change);
            }
            if (page.docs.length < 400) break;
            after = page.docs.last;
          }
        }
        final confirmed = await user.get(
          const GetOptions(source: Source.server),
        );
        _authorize(uid);
        final confirmedData = confirmed.data();
        if (confirmedData == null) {
          _invalidateInputCache();
          return null;
        }
        final authoritative = _stateFromData(confirmedData);
        InputReadResult result;
        try {
          result = reduceIncrementalInputs(
            baseline: baseline,
            baselineRevision: revision,
            root: InputSyncSnapshot.fromState(authoritative).root,
            readRevision: readRevision,
            confirmedRevision: _inputRevision(confirmedData),
            changes: changes,
          );
        } on InputRevisionChanged {
          if (attempt == 2) rethrow;
          continue;
        }
        final state = result.snapshot.toState(authoritative);
        _cacheInputState(uid, state);
        return state;
      }
      throw StateError('Inputs changed during cloud refresh. Retry.');
    } on Object {
      _invalidateInputCache();
      rethrow;
    }
  }

  CloudUserState _stateFromData(
    Map<String, dynamic> data, {
    List<SignalReading> signals = const [],
    List<DailyCheckIn> checkIns = const [],
  }) {
    final privacy = _accountPrivacy(data);
    final prefs = (data['prefs'] as Map?)?.cast<String, dynamic>() ?? const {};
    final notificationPrefsVersion =
        (prefs['notificationPreferencesVersion'] as num?)?.round() ?? 0;
    final consent =
        (data['consentFlags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final healthSync =
        (data['healthSync'] as Map?)?.cast<String, dynamic>() ?? const {};
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
      coachPlanNotificationsEnabled:
          prefs['coachPlanNotificationsEnabled'] as bool? ?? false,
      studyLogNotificationsEnabled:
          prefs['studyLogNotificationsEnabled'] as bool? ?? false,
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
      inputRevision: data['inputSyncVersion'] == 1
          ? _inputRevision(data)
          : null,
      inputSyncVersion: (data['inputSyncVersion'] as num?)?.toInt() ?? 0,
      heartRateStorageVersion:
          (data['heartRateStorageVersion'] as num?)?.toInt() ?? 0,
      privacyConsent: privacy.consent,
      deletionPending: privacy.deletionPending,
      outcomeConsentUpdatedAt: privacy.outcomeConsentUpdatedAt,
      signals: signals,
      checkIns: checkIns,
    );
  }

  @override
  Future<void> replaceUser(String uid, CloudUserState state) async {
    final user = _user(uid);
    _invalidateInputCache();
    final existing = await user.get(const GetOptions(source: Source.server));
    _authorize(uid);
    if (existing.data()?['inputSyncVersion'] == 1) {
      final remote = await readUser(uid);
      _authorize(uid);
      if (remote == null) throw StateError('The account is unavailable.');
      await applyInputPatch(
        uid,
        InputSyncPatch(
          InputSyncSnapshot.fromState(remote),
          InputSyncSnapshot.fromState(state),
        ),
      );
      return;
    }
    await user.set(
      profileToCloud(
        profile: state.profile,
        email: state.accountEmail,
        onboardingComplete: state.onboardingComplete,
        notificationsEnabled: state.notificationsEnabled,
        crashNotificationsEnabled: state.crashNotificationsEnabled,
        recoveryNotificationsEnabled: state.recoveryNotificationsEnabled,
        coachPlanNotificationsEnabled: state.coachPlanNotificationsEnabled,
        studyLogNotificationsEnabled: state.studyLogNotificationsEnabled,
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

  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    if (patch.isEmpty) return;
    final user = _user(uid);
    final cached = _cachedInputState(uid);
    var cacheCanAdvance = cached?.inputSyncVersion == 1;
    var expectedRevision = cached?.inputRevision;
    CloudUserState? authoritative;
    final edits = [
      for (final edit in patch.signals) (collection: 'signals', edit: edit),
      for (final edit in patch.checkIns) (collection: 'checkIns', edit: edit),
    ];
    // Chunk commits are idempotent: retry accepts an already-applied value.
    // Never enumerate or delete documents that were not explicitly edited.
    // Each source write checks its journal document in Security Rules.
    // Sixteen edits plus cached root lookups fit the 20-access-call budget.
    const chunkSize = 16;
    try {
      for (
        var offset = 0;
        offset < edits.length || offset == 0;
        offset += chunkSize
      ) {
        _authorize(uid);
        final chunk = edits.skip(offset).take(chunkSize).toList();
        final last = offset + chunk.length >= edits.length;
        final committed = await _firestore.runTransaction((transaction) async {
          _authorize(uid);
          final account = await transaction.get(user);
          if (!account.exists ||
              _accountPrivacy(account.data()!).deletionPending) {
            throw StateError('The account is unavailable for syncing.');
          }
          final accountData = account.data()!;
          if (accountData['inputSyncVersion'] != null &&
              accountData['inputSyncVersion'] != 0 &&
              accountData['inputSyncVersion'] != 1) {
            throw StateError('This account requires a newer sync version.');
          }
          final beforeRevision = accountData['inputSyncVersion'] == 1
              ? _inputRevision(accountData)
              : 0;
          final nextRevision = parseInputRevision(beforeRevision + 1);
          if (last) {
            final actual = InputSyncSnapshot.fromState(
              _stateFromData(account.data()!),
            );
            patch.checkRootAgainst(actual);
          }
          final snapshots = [
            for (final item in chunk)
              await transaction.get(
                user.collection(item.collection).doc(item.edit.id),
              ),
          ];
          for (var i = 0; i < chunk.length; i++) {
            final item = chunk[i];
            final data = snapshots[i].data();
            // Canonical serializers preserve legacy defaults while comparing only
            // the writable input schema. Unknown fields survive merged writes.
            final actual = data == null
                ? null
                : item.collection == 'signals'
                ? signalToCloud(
                    signalFromCloud(item.edit.id, _normalizeDates(data)),
                  )
                : checkInToCloud(
                    checkInFromCloud(item.edit.id, _normalizeDates(data)),
                  );
            checkSyncValue(
              item.collection == 'signals' ? 'signal' : 'check-in',
              actual,
              item.edit.before,
              item.edit.after,
            );
          }
          _authorize(uid);
          for (var i = 0; i < chunk.length; i++) {
            final item = chunk[i];
            final ref = user.collection(item.collection).doc(item.edit.id);
            final nextData = item.edit.after == null
                ? null
                : {
                    // Canonical sync snapshots omit nulls, while merge writes
                    // retain them on the source. Include those fields in the
                    // journal so it faithfully represents the final record.
                    for (final entry
                        in (snapshots[i].data() ?? <String, dynamic>{}).entries)
                      if (entry.value == null) entry.key: null,
                    ...syncMergedData(item.edit.before, item.edit.after!),
                    ...(item.collection == 'signals'
                        ? signalToCloud(
                            signalFromCloud(item.edit.id, item.edit.after!),
                          )
                        : checkInToCloud(
                            checkInFromCloud(item.edit.id, item.edit.after!),
                          )),
                    'schemaVersion': cloudSchemaVersion,
                  };
            if (item.edit.after == null) {
              transaction.delete(ref);
            } else {
              transaction.set(
                ref,
                encodeFirestoreDocument(nextData!),
                SetOptions(merge: true),
              );
            }
            transaction.set(
              user
                  .collection('inputChanges')
                  .doc(inputChangeDocumentId(item.collection, item.edit.id)),
              encodeFirestoreDocument({
                'collection': item.collection,
                'id': item.edit.id,
                'revision': nextRevision,
                'after': nextData,
              }),
            );
          }
          transaction.set(
            user,
            encodeFirestoreDocument({
              if (last && patch.root.isNotEmpty)
                ...syncMergedData(
                  patch.rootData(useBefore: true),
                  patch.rootData(),
                ),
              'schemaVersion': cloudSchemaVersion,
              'inputSyncVersion': 1,
              'inputRevision': nextRevision,
              'updatedAt': FieldValue.serverTimestamp(),
            }),
            SetOptions(merge: true),
          );
          return (
            before: beforeRevision,
            after: nextRevision,
            metadata: _stateFromData({
              ...accountData,
              'inputSyncVersion': 1,
              'inputRevision': nextRevision,
            }),
          );
        });
        _authorize(uid);
        if (committed.before != expectedRevision) cacheCanAdvance = false;
        expectedRevision = committed.after;
        authoritative = committed.metadata;
        if (last) break;
      }
      if (cacheCanAdvance && cached != null && authoritative != null) {
        _cacheInputState(
          uid,
          InputSyncSnapshot.fromState(
            cached,
          ).overlay(patch).toState(authoritative),
        );
      } else {
        _invalidateInputCache();
      }
    } on Object {
      // Some chunks may already be committed. Only a complete confirmed read
      // can supply the next baseline after a partial write or conflict.
      _invalidateInputCache();
      rethrow;
    }
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
    bool includeHeartRate = true,
  }) async {
    final cached = _cachedInputState(uid);
    if (cached != null) {
      final values = cached.signals
          .where(
            (reading) =>
                !reading.timestamp.isBefore(start) &&
                reading.timestamp.isBefore(end) &&
                (includeHeartRate || reading.type != SignalType.heartRate) &&
                (type == null || reading.type == type),
          )
          .toList();
      return values..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    Query<Map<String, dynamic>> query = _user(uid)
        .collection('signals')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThan: end);
    if (type != null) {
      if (!includeHeartRate && type == SignalType.heartRate) return [];
      query = query.where('type', isEqualTo: type.name);
    } else if (!includeHeartRate) {
      // Regular heart rate is displayed from the hydrated device history, but
      // is not an input to scores, forecasts or Coach. Filter on the
      // server so each refresh does not bill reads for thousands of raw samples.
      // Uses the existing type ASC / timestamp DESC collection index.
      query = query.where(
        'type',
        whereIn: [
          for (final value in SignalType.values)
            if (value != SignalType.heartRate) value.name,
        ],
      );
    }
    final snapshot = await query.orderBy('timestamp', descending: true).get();
    _authorize(uid);
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
    final cached = _cachedInputState(uid);
    if (cached != null) {
      final values = cached.checkIns
          .where(
            (reading) =>
                !reading.timestamp.isBefore(start) &&
                reading.timestamp.isBefore(end),
          )
          .toList();
      return values..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    final snapshot = await _user(uid)
        .collection('checkIns')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThan: end)
        .orderBy('timestamp', descending: true)
        .get();
    _authorize(uid);
    return snapshot.docs
        .map(
          (document) =>
              checkInFromCloud(document.id, _normalizeDates(document.data())),
        )
        .toList();
  }

  @override
  Future<DailyCheckIn?> latestCheckIn(String uid) async {
    final cached = _cachedInputState(uid);
    if (cached != null) {
      final values = [...cached.checkIns]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return values.firstOrNull;
    }
    final snapshot = await _user(uid)
        .collection('checkIns')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    _authorize(uid);
    if (snapshot.docs.isEmpty) return null;
    final document = snapshot.docs.single;
    return checkInFromCloud(document.id, _normalizeDates(document.data()));
  }

  @override
  Future<List<SignalReading>> reactionBaselineWindow(
    String uid, {
    int limit = 14,
  }) async {
    final cached = _cachedInputState(uid);
    if (cached != null) {
      final values =
          cached.signals
              .where((reading) => reading.type == SignalType.reactionTime)
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return values.take(limit).toList();
    }
    final snapshot = await _user(uid)
        .collection('signals')
        .where('type', isEqualTo: SignalType.reactionTime.name)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    _authorize(uid);
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
    _authorize(uid);
    final points = await _forecastDays.readRange(uid, start: start, end: end);
    _authorize(uid);
    return points;
  }

  @override
  Future<void> replaceForecastPoints(
    String uid, {
    required DateTime day,
    required List<ForecastPoint> points,
  }) async {
    _authorize(uid);
    await _forecastDays.replaceDay(uid, day: day, points: points);
    _authorize(uid);
  }

  @override
  Future<List<Recommendation>> recommendationsForDay(
    String uid,
    DateTime day,
  ) async {
    final start = localDay(day);
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
    final start = localDay(day);
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
  Future<void> applyRecommendationAction(
    String uid,
    Recommendation record, {
    RecommendationStatus? status,
    bool? helpful,
  }) async {
    if (record.id.isEmpty ||
        record.id.contains('/') ||
        record.day == null ||
        (status == null && helpful == null)) {
      throw ArgumentError('A valid recommendation and action are required.');
    }
    final reference = _user(uid).collection('recommendations').doc(record.id);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      final changes = <String, Object?>{
        if (status != null) 'status': status.name,
        'feedback': ?helpful,
      };
      if (existing.exists) {
        transaction.update(reference, changes);
      } else {
        transaction.set(reference, {
          ...recommendationToCloud(record),
          ...changes,
        });
      }
    });
  }

  @override
  Future<void> applyRiskAlertDismissal(String uid, RiskAlert record) async {
    if (record.id.isEmpty || record.id.contains('/') || record.day == null) {
      throw ArgumentError('A valid alert is required.');
    }
    final reference = _user(uid).collection('riskAlerts').doc(record.id);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) {
        transaction.update(reference, {'dismissed': true});
      } else {
        transaction.set(reference, riskAlertToCloud(record, dismissed: true));
      }
    });
  }

  @override
  Future<void> upsertOutcome(String uid, OutcomeRecord outcome) async {
    await _requireOutcomeConsent(uid);
    await _user(uid)
        .collection('outcomes')
        .doc(outcome.id)
        .set(encodeFirestoreDocument(outcomeToCloud(outcome)));
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
    final start = localDay(day);
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
    final start = localDay(day);
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
    _authorize(uid);
    _forecastDays.clearOwner(uid);
    try {
      for (final collectionName in const [
        'recommendations',
        'riskAlerts',
        'forecastPoints',
        'forecastDays',
      ]) {
        final collection = _user(uid).collection(collectionName);
        while (true) {
          final page = await collection
              .limit(100)
              .get(const GetOptions(source: Source.server));
          _authorize(uid);
          if (page.docs.isEmpty) break;
          final batch = _firestore.batch();
          for (final document in page.docs) {
            batch.delete(document.reference);
          }
          await batch.commit();
        }
      }
    } finally {
      _forecastDays.clearOwner(uid);
    }
  }

  @override
  Future<Map<String, Object?>> exportUser(String uid) =>
      _dataLifecycle.exportUser(uid);

  @override
  Future<void> deleteUserTree(String uid) async {
    _authorize(uid);
    _invalidateInputCache();
    _forecastDays.clearOwner(uid);
    try {
      await _dataLifecycle.deleteUserTree(uid);
    } finally {
      _invalidateInputCache();
      _forecastDays.clearOwner(uid);
    }
  }

  AccountDataLifecycle get _dataLifecycle => AccountDataLifecycle(
    store: _FirestoreUserDataLifecycleStore(_firestore, _auth),
    currentUid: () => _auth.currentSession?.uid,
  );

  static Map<String, dynamic> _normalizeDates(Map<String, dynamic> data) =>
      normalizeFirestoreDocument(data);

  // Compare complete SDK snapshots without sending optional/unknown metadata
  // through the stricter domain serializer. Invalid optional model maps still
  // need to be readable, and Timestamp equality must retain nanoseconds.
  static bool _sameCloudValue(Object? left, Object? right) {
    if (identical(left, right) || left == right) return true;
    if (left is double && right is double && left.isNaN && right.isNaN) {
      return true;
    }
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) =>
                right.containsKey(key) &&
                _sameCloudValue(left[key], right[key]),
          );
    }
    if (left is Iterable && right is Iterable) {
      final leftValues = left.iterator;
      final rightValues = right.iterator;
      while (leftValues.moveNext()) {
        if (!rightValues.moveNext() ||
            !_sameCloudValue(leftValues.current, rightValues.current)) {
          return false;
        }
      }
      return !rightValues.moveNext();
    }
    return false;
  }

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
