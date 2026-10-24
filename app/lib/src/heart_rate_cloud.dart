import 'package:cloud_firestore/cloud_firestore.dart';

import 'cloud_repository.dart';
import 'firestore_value_codec.dart';
import 'heart_rate_summary.dart';
import 'privacy_consent.dart';

/// The first writer owns a UTC day's complete sample set. A second device may
/// acknowledge identical data but must never add overlapping summary counts or
/// replace the day with its smaller local subset.
class StoredHeartRateDay {
  const StoredHeartRateDay({required this.writerId, required this.summary});

  final String writerId;
  final HeartRateDailySummary summary;

  Map<String, Object?> toJson() => {...summary.toJson(), 'writerId': writerId};

  factory StoredHeartRateDay.fromJson(Map<String, dynamic> json) {
    final writer = json['writerId'];
    if (writer is! String) {
      throw const FormatException('The heart-rate summary writer is missing.');
    }
    _validateWriter(writer);
    return StoredHeartRateDay(
      writerId: writer,
      summary: HeartRateDailySummary.fromJson(json),
    );
  }
}

class HeartRateSummaryAcknowledgement {
  const HeartRateSummaryAcknowledgement({
    required this.storedDay,
    required this.changed,
  });

  final StoredHeartRateDay storedDay;
  final bool changed;
  String get writerId => storedDay.writerId;
  HeartRateDailySummary get summary => storedDay.summary;
}

class HeartRateSummaryOwnershipConflict implements Exception {
  const HeartRateSummaryOwnershipConflict(this.day);
  final String day;

  @override
  String toString() =>
      'Heart-rate history for $day is maintained by another device. '
      'Local observations remain saved.';
}

class HeartRateSummaryRevisionConflict implements Exception {
  const HeartRateSummaryRevisionConflict(this.day);
  final String day;

  @override
  String toString() =>
      'Heart-rate history for $day changed before this upload. '
      'Refresh its summary before retrying.';
}

abstract interface class HeartRateCloudStore {
  Future<List<StoredHeartRateDay>> readDays(String uid);

  /// Deletes a day after the owning device intentionally removed its final
  /// local sample. Server absence is an idempotent acknowledgement.
  Future<bool> deleteDay(
    String uid,
    String day, {
    required String writerId,
    required String expectedDigest,
  });

  /// Explicit account history erasure, including days written by other devices.
  Future<void> clearDays(String uid);

  /// Acknowledgement follows server commit (or an identical server snapshot).
  /// expectedDigest is null only for creation. An existing same-writer day
  /// needs a matching previous digest, unless it already equals this upload.
  /// This method never deletes raw observations or updates migration markers.
  Future<HeartRateSummaryAcknowledgement> saveDay(
    String uid, {
    required String writerId,
    required HeartRateDailySummary summary,
    String? expectedDigest,
  });
}

class MemoryHeartRateCloudStore implements HeartRateCloudStore {
  MemoryHeartRateCloudStore({AccountAuth? auth}) : this._(auth);

  MemoryHeartRateCloudStore._(this._auth);

  final AccountAuth? _auth;
  final values = <String, Map<String, StoredHeartRateDay>>{};
  int reads = 0;
  int writes = 0;

  @override
  Future<bool> deleteDay(
    String uid,
    String day, {
    required String writerId,
    required String expectedDigest,
  }) async {
    _authorize(uid, _auth);
    _validateDay(day);
    _validateWriter(writerId);
    reads += 1;
    final previous = values[uid]?[day];
    _checkDelete(previous, day, writerId, expectedDigest);
    if (previous == null) return false;
    values[uid]!.remove(day);
    writes += 1;
    return true;
  }

  @override
  Future<void> clearDays(String uid) async {
    _authorize(uid, _auth);
    reads += 1;
    writes += values[uid]?.length ?? 0;
    values.remove(uid);
  }

  @override
  Future<List<StoredHeartRateDay>> readDays(String uid) async {
    _authorize(uid, _auth);
    reads += 1;
    return (values[uid]?.values.toList() ?? [])
      ..sort((a, b) => a.summary.day.compareTo(b.summary.day));
  }

  @override
  Future<HeartRateSummaryAcknowledgement> saveDay(
    String uid, {
    required String writerId,
    required HeartRateDailySummary summary,
    String? expectedDigest,
  }) async {
    _authorize(uid, _auth);
    _validateWriter(writerId);
    final validated = HeartRateDailySummary.fromJson(summary.toJson());
    reads += 1;
    final decision = _decideWrite(
      previous: values[uid]?[summary.id],
      writerId: writerId,
      summary: validated,
      expectedDigest: expectedDigest,
    );
    if (decision.changed) {
      values.putIfAbsent(uid, () => {})[summary.id] = decision.storedDay;
      writes += 1;
    }
    return decision;
  }
}

class FirestoreHeartRateCloudStore implements HeartRateCloudStore {
  FirestoreHeartRateCloudStore({
    required FirebaseFirestore firestore,
    required AccountAuth auth,
  }) : this._(firestore, auth);

  FirestoreHeartRateCloudStore._(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final AccountAuth _auth;

  @override
  Future<bool> deleteDay(
    String uid,
    String day, {
    required String writerId,
    required String expectedDigest,
  }) async {
    _authorize(uid, _auth);
    _validateDay(day);
    _validateWriter(writerId);
    final reference = _firestore
        .collection('users')
        .doc(uid)
        .collection('heartRateDays')
        .doc(day);
    final changed = await _firestore.runTransaction((transaction) async {
      _authorize(uid, _auth);
      final existing = await transaction.get(reference);
      _authorize(uid, _auth);
      final previous = existing.exists
          ? StoredHeartRateDay.fromJson(existing.data()!)
          : null;
      _checkDelete(previous, day, writerId, expectedDigest);
      if (previous == null) return false;
      transaction.delete(reference);
      return true;
    });
    _authorize(uid, _auth);
    return changed;
  }

  @override
  Future<void> clearDays(String uid) async {
    _authorize(uid, _auth);
    final collection = _firestore
        .collection('users')
        .doc(uid)
        .collection('heartRateDays');
    while (true) {
      final page = await collection
          .limit(400)
          .get(const GetOptions(source: Source.server));
      _authorize(uid, _auth);
      if (page.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final day in page.docs) {
        batch.delete(day.reference);
      }
      await batch.commit();
      _authorize(uid, _auth);
    }
  }

  @override
  Future<List<StoredHeartRateDay>> readDays(String uid) async {
    _authorize(uid, _auth);
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('heartRateDays')
        .get(const GetOptions(source: Source.server));
    _authorize(uid, _auth);
    return snapshot.docs.map((document) {
      final day = StoredHeartRateDay.fromJson(document.data());
      if (day.summary.id != document.id) {
        throw const FormatException(
          'Heart-rate summary day does not match its ID.',
        );
      }
      return day;
    }).toList()..sort((a, b) => a.summary.day.compareTo(b.summary.day));
  }

  @override
  Future<HeartRateSummaryAcknowledgement> saveDay(
    String uid, {
    required String writerId,
    required HeartRateDailySummary summary,
    String? expectedDigest,
  }) async {
    _authorize(uid, _auth);
    _validateWriter(writerId);
    final validated = HeartRateDailySummary.fromJson(summary.toJson());
    final user = _firestore.collection('users').doc(uid);
    final reference = user.collection('heartRateDays').doc(summary.id);
    final acknowledgement = await _firestore.runTransaction((
      transaction,
    ) async {
      _authorize(uid, _auth);
      final account = await transaction.get(user);
      final accountData = account.data();
      final consent = accountData == null
          ? null
          : PrivacyConsent.tryParse(
              normalizeFirestoreDocument(accountData)['privacyConsent'],
            );
      if (accountData == null ||
          accountData.containsKey('privacyDeletion') ||
          consent == null ||
          !consent.validAt(DateTime.now().toUtc()) ||
          (consent.guardianRequired &&
              _auth.currentSession?.guardianConsentVerified != true)) {
        throw StateError('The account is unavailable for heart-rate syncing.');
      }
      final existing = await transaction.get(reference);
      _authorize(uid, _auth);
      final previous = existing.exists
          ? StoredHeartRateDay.fromJson(existing.data()!)
          : null;
      if (previous != null && previous.summary.id != summary.id) {
        throw const FormatException(
          'Heart-rate summary day does not match its ID.',
        );
      }
      final decision = _decideWrite(
        previous: previous,
        writerId: writerId,
        summary: validated,
        expectedDigest: expectedDigest,
      );
      if (decision.changed) {
        transaction.set(reference, decision.storedDay.toJson());
      }
      return decision;
    });
    _authorize(uid, _auth);
    return acknowledgement;
  }
}

HeartRateSummaryAcknowledgement _decideWrite({
  required StoredHeartRateDay? previous,
  required String writerId,
  required HeartRateDailySummary summary,
  required String? expectedDigest,
}) {
  if (previous != null &&
      previous.summary.contentDigest == summary.contentDigest &&
      previous.summary.sampleIdDigest == summary.sampleIdDigest &&
      previous.summary.sampleCount == summary.sampleCount) {
    if (!sameHeartRateSummaryStatistics(previous.summary, summary)) {
      throw const FormatException(
        'The saved heart-rate digest does not match its summary.',
      );
    }
    return HeartRateSummaryAcknowledgement(storedDay: previous, changed: false);
  }
  if (previous != null && previous.writerId != writerId) {
    throw HeartRateSummaryOwnershipConflict(summary.day);
  }
  if (previous?.summary.contentDigest != expectedDigest) {
    throw HeartRateSummaryRevisionConflict(summary.day);
  }
  return HeartRateSummaryAcknowledgement(
    storedDay: StoredHeartRateDay(writerId: writerId, summary: summary),
    changed: true,
  );
}

void _validateWriter(String writerId) {
  if (writerId.trim().isEmpty ||
      writerId.length > 128 ||
      writerId.contains('/')) {
    throw const FormatException('Invalid heart-rate summary writer.');
  }
}

void _validateDay(String day) {
  final value = DateTime.tryParse('${day}T00:00:00Z');
  if (value == null || HeartRateSummary.dayId(value) != day) {
    throw const FormatException('Invalid heart-rate summary day.');
  }
}

void _checkDelete(
  StoredHeartRateDay? previous,
  String day,
  String writerId,
  String expectedDigest,
) {
  if (previous == null) return;
  if (previous.summary.day != day) {
    throw const FormatException(
      'Heart-rate summary day does not match its ID.',
    );
  }
  if (previous.writerId != writerId) {
    throw HeartRateSummaryOwnershipConflict(day);
  }
  if (previous.summary.contentDigest != expectedDigest) {
    throw HeartRateSummaryRevisionConflict(day);
  }
}

void _authorize(String uid, AccountAuth? auth) {
  if (uid.trim().isEmpty || uid.length > 128 || uid.contains('/')) {
    throw const FormatException('Invalid heart-rate account.');
  }
  if (auth != null && (!auth.isConfigured || auth.currentSession?.uid != uid)) {
    throw StateError(
      'Heart-rate history requires the authenticated owner account.',
    );
  }
}
