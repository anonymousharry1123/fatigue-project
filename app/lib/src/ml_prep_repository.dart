import 'package:cloud_firestore/cloud_firestore.dart';

import 'cloud_repository.dart';
import 'ml_prep_models.dart';

/// The bounded query used by an explicit account-preparation run.
///
/// Limits are enforced here even if a caller requests more documents. Reaching
/// the effective limit must be treated as potentially truncated by the caller.
class PrepQuerySpec {
  PrepQuerySpec({
    required String uid,
    required String? authenticatedUid,
    required this.collection,
    required PrepWindow window,
    required int requestedLimit,
  }) : start = window.start,
       end = window.end,
       limit = requestedLimit.clamp(1, collection.maximumDocuments) {
    requireAccount(uid, authenticatedUid);
    if (requestedLimit < 1) {
      throw ArgumentError.value(requestedLimit, 'requestedLimit');
    }
    if (!start.isUtc || !end.isUtc || !end.isAfter(start)) {
      throw ArgumentError('Prep bounds must be an increasing UTC window.');
    }
  }

  final PrepCollection collection;
  final DateTime start;
  final DateTime end;
  final int limit;

  String get timestampField => collection.timeField;

  static void requireAccount(String uid, String? authenticatedUid) {
    if (uid.isEmpty || uid.contains('/') || uid != authenticatedUid) {
      throw StateError('Prep requires the currently authenticated account.');
    }
  }
}

/// Read-only Firebase adapter dedicated to preparation, independent of the
/// general account snapshot/replacement workflow. It never starts listeners.
class FirestorePrepDataSource implements PrepDataSource {
  FirestorePrepDataSource({
    required FirebaseFirestore firestore,
    required AccountAuth auth,
  }) : this._(firestore, auth);

  FirestorePrepDataSource._(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final AccountAuth _auth;

  @override
  String? get currentUid =>
      _auth.isConfigured ? _auth.currentSession?.uid : null;

  @override
  Future<PrepAccountMetadata> readAccount(String uid) async {
    PrepQuerySpec.requireAccount(uid, currentUid);
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    PrepQuerySpec.requireAccount(uid, currentUid);
    final data = snapshot.data();
    if (data == null) {
      throw StateError('The authenticated account has no saved profile.');
    }
    final flags = data['consentFlags'];
    final consent = flags is Map ? flags : const <String, dynamic>{};
    final collection = consent['outcomeCollection'] == true;
    final trainingUse = consent['trainingRecordUse'] == true;
    final rawVersion = consent['version'] ?? consent['consentVersion'];
    return PrepAccountMetadata(
      consent: PrepConsent(
        collection: collection,
        trainingUse: trainingUse,
        // Current Version 0.31 stores both flags without an explicit version;
        // its outcome records use consent version 1.
        version: rawVersion == null
            ? (collection && trainingUse ? 1 : 0)
            : _nonNegativeInteger(rawVersion),
      ),
      schemaVersion: _nonNegativeInteger(data['schemaVersion']),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> readCollection(
    String uid,
    PrepCollection collection,
    PrepWindow window, {
    required int limit,
  }) async {
    final spec = PrepQuerySpec(
      uid: uid,
      authenticatedUid: currentUid,
      collection: collection,
      window: window,
      requestedLimit: limit,
    );
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection(collection.name)
        .where(spec.timestampField, isGreaterThanOrEqualTo: spec.start)
        .where(spec.timestampField, isLessThan: spec.end)
        .orderBy(spec.timestampField)
        .limit(spec.limit)
        .get(const GetOptions(source: Source.server));
    PrepQuerySpec.requireAccount(uid, currentUid);
    return [
      for (final document in snapshot.docs)
        {
          ..._normalizeMap(document.data()),
          // A payload cannot impersonate another document's identity.
          'id': document.id,
        },
    ];
  }

  static int _nonNegativeInteger(Object? value) =>
      value is num && value.isFinite && value >= 0 && value == value.round()
      ? value.toInt()
      : 0;

  static Map<String, dynamic> _normalizeMap(Map<String, dynamic> value) => {
    for (final entry in value.entries) entry.key: _normalize(entry.value),
  };

  static Object? _normalize(Object? value) => switch (value) {
    Timestamp() => value.toDate().toUtc().toIso8601String(),
    DateTime() => value.toUtc().toIso8601String(),
    Map() => _normalizeMap(value.cast<String, dynamic>()),
    List() => value.map(_normalize).toList(),
    _ => value,
  };
}
