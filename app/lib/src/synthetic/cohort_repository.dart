import 'package:cloud_firestore/cloud_firestore.dart';

import '../cloud_schema.dart';
import '../models.dart';
import 'cohort_stats.dart';
import 'synthetic_person.dart';

/// Publishes / hydrates the synthetic cohort under a dedicated Firestore tree.
///
/// Paths (separate from real `users/{uid}`):
/// - `syntheticUsers/{studentId}`
/// - `syntheticUsers/{studentId}/signals/{id}`
/// - `syntheticUsers/{studentId}/scoreSnapshots/latest`
/// - `syntheticCohort/summary`
class SyntheticCohortRepository {
  SyntheticCohortRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const usersCollection = 'syntheticUsers';
  static const cohortCollection = 'syntheticCohort';
  static const summaryDocId = 'summary';
  static const maxBatchOps = 400;

  DocumentReference<Map<String, dynamic>> get _summaryRef =>
      _firestore.collection(cohortCollection).doc(summaryDocId);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(usersCollection);

  Future<void> publish(
    List<SyntheticPerson> people, {
    void Function(int done, int total)? onProgress,
  }) async {
    final summary = CohortStats.summarize(people);
    await _summaryRef.set(summary.toCloud());

    var pending = <Future<void>>[];
    var opsInBatch = 0;
    WriteBatch batch = _firestore.batch();
    var done = 0;

    Future<void> flush() async {
      if (opsInBatch == 0) return;
      pending.add(batch.commit());
      if (pending.length >= 4) {
        await Future.wait(pending);
        pending = [];
      }
      batch = _firestore.batch();
      opsInBatch = 0;
    }

    for (final person in people) {
      final userRef = _users.doc(person.id);
      batch.set(userRef, {
        'meta': person.metaToCloud(),
        'displayName': 'Synthetic ${person.id}',
        'schemaVersion': cloudSchemaVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      opsInBatch++;

      for (final signal in person.signals) {
        batch.set(
          userRef.collection('signals').doc(signal.id),
          signalToCloud(signal),
        );
        opsInBatch++;
        if (opsInBatch >= maxBatchOps) await flush();
      }

      for (final checkIn in person.checkIns) {
        batch.set(
          userRef.collection('checkIns').doc(checkIn.id),
          checkInToCloud(checkIn),
        );
        opsInBatch++;
        if (opsInBatch >= maxBatchOps) await flush();
      }

      batch.set(
        userRef.collection('scoreSnapshots').doc('latest'),
        scoreSnapshotToCloud(snapshot: person.score, day: DateTime.now()),
      );
      opsInBatch++;
      if (opsInBatch >= maxBatchOps) await flush();

      done++;
      onProgress?.call(done, people.length);
    }

    await flush();
    if (pending.isNotEmpty) await Future.wait(pending);
  }

  Future<CohortSummary?> readSummary() async {
    final snap = await _summaryRef.get();
    if (!snap.exists || snap.data() == null) return null;
    return CohortSummary.fromCloud(snap.data()!);
  }

  Future<List<SyntheticPerson>> readPeople({int limit = 100}) async {
    final snapshot = await _users.limit(limit).get();
    final people = <SyntheticPerson>[];
    for (final doc in snapshot.docs) {
      final person = await _readPerson(doc.id, doc.data());
      if (person != null) people.add(person);
    }
    return people;
  }

  Future<SyntheticPerson?> readPerson(String id) async {
    final doc = await _users.doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return _readPerson(id, doc.data()!);
  }

  Future<void> clearPublished({
    void Function(int done)? onProgress,
  }) async {
    var done = 0;
    while (true) {
      final page = await _users.limit(50).get();
      if (page.docs.isEmpty) break;
      for (final doc in page.docs) {
        await _deleteTree(doc.reference);
        done++;
        onProgress?.call(done);
      }
    }
    await _summaryRef.delete();
  }

  Future<SyntheticPerson?> _readPerson(
    String id,
    Map<String, dynamic> data,
  ) async {
    final meta = Map<String, dynamic>.from(
      (data['meta'] as Map?) ?? const {},
    );
    final userRef = _users.doc(id);
    final signalsSnap = await userRef.collection('signals').get();
    final checkInsSnap = await userRef.collection('checkIns').get();
    final scoreSnap = await userRef
        .collection('scoreSnapshots')
        .doc('latest')
        .get();

    final signals = signalsSnap.docs
        .map((doc) => signalFromCloud(doc.id, doc.data()))
        .toList();
    final checkIns = checkInsSnap.docs
        .map((doc) => checkInFromCloud(doc.id, doc.data()))
        .toList();

    final ScoreSnapshot score =
        scoreSnap.exists && scoreSnap.data() != null
        ? scoreSnapshotFromCloud(scoreSnap.data()!)
        : const ScoreSnapshot(
            energy: 0,
            cognitive: 0,
            confidence: 0,
            drivers: [],
          );

    return SyntheticPerson(
      id: id,
      age: (meta['age'] as num?)?.toInt() ?? 0,
      gender: (meta['gender'] as String?) ?? 'Unknown',
      education: (meta['education'] as String?) ?? 'Unknown',
      ageRange: (meta['ageRange'] as String?) ?? '18+',
      role: (meta['role'] as String?) ?? 'Student',
      avgSleepHours: (meta['avgSleepHours'] as num?)?.toDouble() ?? 0,
      screenTimeHours: (meta['screenTimeHours'] as num?)?.toDouble() ?? 0,
      socialMediaHours: (meta['socialMediaHours'] as num?)?.toDouble() ?? 0,
      studyHours: (meta['studyHours'] as num?)?.toDouble() ?? 0,
      exerciseHoursWeekly:
          (meta['exerciseHoursWeekly'] as num?)?.toDouble() ?? 0,
      caffeineDrinks: (meta['caffeineDrinks'] as num?)?.toDouble() ?? 0,
      stressLevel: (meta['stressLevel'] as num?)?.toDouble() ?? 5,
      anxietyScore: (meta['anxietyScore'] as num?)?.toDouble() ?? 5,
      gpa: (meta['gpa'] as num?)?.toDouble() ?? 0,
      usesSleepApp: meta['usesSleepApp'] == true,
      feelsBurnedOut: meta['feelsBurnedOut'] == true,
      signals: signals,
      checkIns: checkIns,
      score: score,
      sourceCsvRow: (meta['sourceCsvRow'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> _deleteTree(DocumentReference<Map<String, dynamic>> ref) async {
    for (final name in const ['signals', 'checkIns', 'scoreSnapshots']) {
      while (true) {
        final page = await ref.collection(name).limit(100).get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }
    await ref.delete();
  }
}
