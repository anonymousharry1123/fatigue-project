import 'package:app/src/cloud_quota_gate.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/models.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final quotaFailure = isA<FirebaseException>().having(
    (error) => error.code,
    'code',
    'resource-exhausted',
  );
  final empty = InputSyncSnapshot(root: {}, signals: {}, checkIns: {});
  late DateTime now;
  late CloudQuotaGate gate;
  late _CountingRepository inner;
  late QuotaCloudRepository repository;

  setUp(() {
    now = DateTime.utc(2026, 10, 24, 12);
    gate = CloudQuotaGate(clock: () => now);
    inner = _CountingRepository();
    repository = QuotaCloudRepository(inner, gate: gate);
  });

  test(
    'a quota read stops subsequent reads and writes across methods',
    () async {
      inner.nextError = 'resource-exhausted';
      await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
      expect(inner.calls, ['readUser owner']);
      await expectLater(
        repository.signalsByRange(
          'owner',
          start: now,
          end: now.add(const Duration(days: 1)),
        ),
        throwsA(quotaFailure),
      );
      await expectLater(
        repository.readAccountPrivacy('owner'),
        throwsA(quotaFailure),
      );
      await expectLater(
        repository.applyInputPatch('owner', InputSyncPatch(empty, empty)),
        throwsA(quotaFailure),
      );
      await expectLater(
        repository.replaceForecastPoints('owner', day: now, points: []),
        throwsA(quotaFailure),
      );
      expect(inner.calls, ['readUser owner']);
      expect(gate.retryAt('owner'), now.add(const Duration(hours: 1)));
    },
  );

  test('a quota write also stops unrelated reads', () async {
    inner.nextError = 'resource-exhausted';
    await expectLater(
      repository.applyInputPatch('owner', InputSyncPatch(empty, empty)),
      throwsA(quotaFailure),
    );
    await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
    expect(inner.calls, ['applyInputPatch owner']);
  });

  test(
    'explicit Retry allows a fresh attempt then re-closes on quota',
    () async {
      inner.nextError = 'resource-exhausted';
      await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
      gate.retryNow('owner');
      inner.nextError = 'resource-exhausted';
      await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
      await expectLater(
        repository.applyInputPatch('owner', InputSyncPatch(empty, empty)),
        throwsA(quotaFailure),
      );
      expect(inner.calls, ['readUser owner', 'readUser owner']);
      gate.retryNow('owner');
      expect(await repository.readUser('owner'), isNull);
      expect(gate.paused('owner'), isFalse);
      expect(inner.calls.length, 3);
    },
  );

  test(
    'cooldown expires after one hour without repeated calls extending it',
    () async {
      inner.nextError = 'resource-exhausted';
      await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
      final retryAt = gate.retryAt('owner');
      now = now.add(const Duration(minutes: 59, seconds: 59));
      await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
      expect(gate.retryAt('owner'), retryAt);
      expect(inner.calls.length, 1);
      now = now.add(const Duration(seconds: 1));
      expect(await repository.readUser('owner'), isNull);
      expect(inner.calls.length, 2);
      expect(gate.toJson(), isEmpty);
    },
  );

  test(
    'persisted cooldown survives a new gate and ignores expired entries',
    () async {
      inner.nextError = 'resource-exhausted';
      await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
      final persisted = gate.toJson();
      now = now.add(const Duration(minutes: 20));
      final restored = CloudQuotaGate(clock: () => now)
        ..restore({
          ...persisted,
          'expired': now.subtract(const Duration(seconds: 1)).toIso8601String(),
          'invalid': 'not-a-date',
        });
      final resumed = QuotaCloudRepository(inner, gate: restored);
      await expectLater(resumed.readUser('owner'), throwsA(quotaFailure));
      expect(restored.retryAt('owner'), gate.retryAt('owner'));
      expect(restored.paused('expired'), isFalse);
      expect(restored.paused('invalid'), isFalse);
      expect(inner.calls.length, 1);
      now = now.add(const Duration(minutes: 40));
      expect(await resumed.readUser('owner'), isNull);
      expect(inner.calls.length, 2);
    },
  );

  test(
    'cooldown and explicit retries remain isolated to their account',
    () async {
      inner.nextError = 'resource-exhausted';
      await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
      inner.signedInUid = 'other';
      expect(await repository.readUser('other'), isNull);
      gate.retryNow('other');
      inner.signedInUid = 'owner';
      await expectLater(repository.readUser('owner'), throwsA(quotaFailure));
      expect(inner.calls, ['readUser owner', 'readUser other']);
      expect(gate.toJson().keys, ['owner']);
    },
  );

  test('network and permission failures do not masquerade as quota', () async {
    for (final code in ['unavailable', 'permission-denied']) {
      inner.nextError = code;
      await expectLater(
        repository.readUser('owner'),
        throwsA(
          isA<FirebaseException>().having((error) => error.code, 'code', code),
        ),
      );
      expect(gate.paused('owner'), isFalse);
      expect(await repository.readUser('owner'), isNull);
    }
    expect(inner.calls.length, 4);
  });
}

class _CountingRepository extends MemoryCloudRepository {
  _CountingRepository() : super(signedInUid: 'owner');
  final calls = <String>[];
  String? nextError;

  void _visit(String method, String uid) {
    calls.add('$method $uid');
    final error = nextError;
    nextError = null;
    if (error != null) {
      throw FirebaseException(plugin: 'cloud_firestore', code: error);
    }
  }

  @override
  Future<CloudUserState?> readUser(String uid) async {
    _visit('readUser', uid);
    return super.readUser(uid);
  }

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) async {
    _visit('readAccountPrivacy', uid);
    return super.readAccountPrivacy(uid);
  }

  @override
  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
    bool includeHeartRate = true,
  }) async {
    _visit('signalsByRange', uid);
    return super.signalsByRange(
      uid,
      start: start,
      end: end,
      type: type,
      includeHeartRate: includeHeartRate,
    );
  }

  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    _visit('applyInputPatch', uid);
    return super.applyInputPatch(uid, patch);
  }

  @override
  Future<void> replaceForecastPoints(
    String uid, {
    required DateTime day,
    required List<ForecastPoint> points,
  }) async {
    _visit('replaceForecastPoints', uid);
    return super.replaceForecastPoints(uid, day: day, points: points);
  }
}
