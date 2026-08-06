import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'cloud_repository.dart';
import 'cloud_schema.dart';
import 'firebase_options.dart';
import 'models.dart';

class FirebaseRuntime {
  const FirebaseRuntime({required this.auth, required this.repository});

  final AccountAuth auth;
  final CloudRepository repository;

  static Future<FirebaseRuntime?> initialize() async {
    if (!TonyoFirebaseOptions.isConfigured) return null;
    await Firebase.initializeApp(options: TonyoFirebaseOptions.currentPlatform);
    final auth = FirebaseAccountAuth(FirebaseAuth.instance);
    return FirebaseRuntime(
      auth: auth,
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

  @override
  bool get isConfigured => true;

  @override
  AccountSession? get currentSession {
    final user = _auth.currentUser;
    final email = user?.email;
    return user == null || email == null
        ? null
        : AccountSession(uid: user.uid, email: email);
  }

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
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
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return _session(credential.user);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteCurrentAccount() async {
    await _auth.currentUser?.delete();
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

  static const _childCollections = [
    'signals',
    'checkIns',
    'scoreSnapshots',
    'forecastPoints',
    'recommendations',
    'riskAlerts',
  ];

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

  @override
  Future<CloudUserState?> readUser(String uid) async {
    final user = _user(uid);
    final values = await Future.wait([
      user.get(),
      user.collection('signals').get(),
      user.collection('checkIns').get(),
    ]);
    final profileSnapshot = values[0] as DocumentSnapshot<Map<String, dynamic>>;
    if (!profileSnapshot.exists) return null;
    final data = profileSnapshot.data()!;
    final prefs = (data['prefs'] as Map?)?.cast<String, dynamic>() ?? const {};
    final consent =
        (data['consentFlags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final signalSnapshot = values[1] as QuerySnapshot<Map<String, dynamic>>;
    final checkInSnapshot = values[2] as QuerySnapshot<Map<String, dynamic>>;
    return CloudUserState(
      profile: UserProfile.fromJson(
        (data['profile'] as Map).cast<String, dynamic>(),
      ),
      accountEmail: data['accountEmail'] as String,
      onboardingComplete: data['onboardingComplete'] as bool? ?? true,
      notificationsEnabled: prefs['notificationsEnabled'] as bool? ?? true,
      outcomeConsent: consent['outcomeCollection'] as bool? ?? false,
      healthAuthorized: prefs['healthAuthorized'] as bool? ?? false,
      lastSync: _dateTimeOrNull(data['lastHealthSync']),
      migrationVersion: data['localMigrationVersion'] as int? ?? 0,
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
        outcomeConsent: state.outcomeConsent,
        healthAuthorized: state.healthAuthorized,
        lastSync: state.lastSync,
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
  Future<Map<String, Object?>> exportUser(String uid) async {
    final state = await readUser(uid);
    final export = <String, Object?>{
      'uid': uid,
      if (state != null) ...state.toExportJson(),
      'reservedCollections': <String, Object?>{},
    };
    final reserved = export['reservedCollections']! as Map<String, Object?>;
    for (final collectionName in _childCollections.skip(2)) {
      final snapshot = await _user(uid).collection(collectionName).get();
      reserved[collectionName] = {
        for (final document in snapshot.docs)
          document.id: _jsonSafe(document.data()),
      };
    }
    return export;
  }

  @override
  Future<void> deleteUserTree(String uid) async {
    final user = _user(uid);
    for (final collectionName in _childCollections) {
      while (true) {
        final snapshot = await user.collection(collectionName).limit(100).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final document in snapshot.docs) {
          batch.delete(document.reference);
        }
        await batch.commit();
      }
    }
    await user.delete();
  }

  static Map<String, dynamic> _normalizeDates(Map<String, dynamic> data) =>
      data.map(
        (key, value) =>
            MapEntry(key, value is Timestamp ? value.toDate() : value),
      );

  static DateTime? _dateTimeOrNull(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    String string => DateTime.tryParse(string),
    _ => null,
  };

  static Object? _jsonSafe(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate().toIso8601String(),
    DateTime dateTime => dateTime.toIso8601String(),
    Map map => map.map(
      (key, child) => MapEntry(key.toString(), _jsonSafe(child)),
    ),
    Iterable iterable => iterable.map(_jsonSafe).toList(),
    _ => value,
  };
}
