import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _OutcomeRepository extends MemoryCloudRepository {
  _OutcomeRepository() : super(signedInUid: 'owner');

  bool failWrites = false;
  bool failDeletes = false;
  final writes = <({String uid, String id, double value})>[];
  Completer<void>? writeGate;
  Completer<void>? writeStarted;
  Completer<void>? readGate;
  Completer<void>? readStarted;

  @override
  Future<void> upsertOutcome(String uid, OutcomeRecord outcome) async {
    writes.add((uid: uid, id: outcome.id, value: outcome.value));
    final gate = writeGate;
    writeGate = null;
    writeStarted?.complete();
    writeStarted = null;
    if (gate != null) await gate.future;
    if (failWrites) throw StateError('Offline outcome upload');
    await super.upsertOutcome(uid, outcome);
  }

  @override
  Future<void> deleteOutcome(String uid, String outcomeId) async {
    if (failDeletes) throw StateError('Offline outcome deletion');
    await super.deleteOutcome(uid, outcomeId);
  }

  @override
  Future<List<OutcomeRecord>> outcomesByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    final result = await super.outcomesByRange(uid, start: start, end: end);
    final gate = readGate;
    readGate = null;
    readStarted?.complete();
    readStarted = null;
    if (gate != null) await gate.future;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 19, 12);
  final receipt = DateTime.utc(2026, 9, 1, 12);
  late _OutcomeRepository repository;
  late MemoryAccountAuth auth;

  CloudUserState state({String email = 'owner@example.com'}) => CloudUserState(
    privacyConsent: testAdultPrivacyConsent,
    profile: const UserProfile(),
    accountEmail: email,
    onboardingComplete: false,
    notificationsEnabled: false,
    outcomeConsent: true,
    // Firestore and the cache may represent this instant in different zones.
    outcomeConsentUpdatedAt: receipt.toLocal(),
    healthAuthorized: false,
    migrationVersion: localMigrationVersion,
    signals: const [],
    checkIns: const [],
  );

  Future<AppController> load() async {
    final controller = AppController(
      accountAuth: auth,
      cloudRepository: repository,
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  Future<List<OutcomeRecord>> remote({String uid = 'owner'}) =>
      repository.outcomesByRange(
        uid,
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(days: 1)),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = _OutcomeRepository()..seed('owner', state());
    auth = MemoryAccountAuth(
      session: const AccountSession(uid: 'owner', email: 'owner@example.com'),
    );
  });

  test(
    'pending uploads survive readable cloud refresh and process restart',
    () async {
      final first = await load();
      repository.failWrites = true;
      await first.recordObservedEnergy(7, observedAt: now);
      expect(first.outcomes.single.value, 7);
      expect(first.hasPendingOutcomeChanges, isTrue);
      await first.refreshOutcomes();
      expect(first.outcomes.single.value, 7);
      expect(await remote(), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      final cache = jsonDecode(prefs.getString('tonyo_state_v1')!) as Map;
      expect((cache['outcomeSync'] as Map)['uid'], 'owner');
      expect((cache['outcomeSync'] as Map)['version'], 1);

      final restarted = await load();
      expect(restarted.outcomes.single.value, 7);
      expect(restarted.hasPendingOutcomeChanges, isTrue);
      repository.failWrites = false;
      await restarted.refreshOutcomes();
      expect((await remote()).single.value, 7);
      expect(restarted.hasPendingOutcomeChanges, isFalse);
      expect(restarted.outcomeError, isNull);
      final successfulWrites = repository.writes.length;
      await restarted.refreshOutcomes();
      expect(repository.writes, hasLength(successfulWrites));
      expect((await remote()), hasLength(1));
    },
  );

  test('pending deletes stay hidden and retry after restart', () async {
    final first = await load();
    await first.addReactionResult(
      250,
      resultId: 'stable-reaction',
      observedAt: now,
    );
    expect(await remote(), hasLength(1));
    repository.failDeletes = true;
    await first.deleteSignal('stable-reaction');
    expect(first.outcomes, isEmpty);
    expect(first.hasPendingOutcomeChanges, isTrue);
    await first.refreshOutcomes();
    expect(first.outcomes, isEmpty);
    expect(await remote(), hasLength(1));

    final restarted = await load();
    expect(restarted.outcomes, isEmpty);
    expect(restarted.hasPendingOutcomeChanges, isTrue);
    repository.failDeletes = false;
    await restarted.refreshOutcomes();
    expect(await remote(), isEmpty);
    expect(restarted.hasPendingOutcomeChanges, isFalse);
  });

  test(
    'temporarily unavailable authentication retains the owner journal',
    () async {
      final first = await load();
      repository.failWrites = true;
      await first.recordObservedEnergy(7, observedAt: now);
      final attempts = repository.writes.length;
      auth.session = null;
      final waitingForAuth = await load();
      expect(waitingForAuth.hasPendingOutcomeChanges, isFalse);
      expect(repository.writes, hasLength(attempts));
      final waitingState = jsonDecode(waitingForAuth.exportJson()) as Map;
      expect((waitingState['outcomeSync'] as Map)['uid'], 'owner');
      expect((waitingState['outcomeSync'] as Map)['writes'], hasLength(1));
      // Reload the same process once authentication has resolved. The pending
      // record must remain recoverable even though identity was absent earlier.
      auth.session = const AccountSession(
        uid: 'owner',
        email: 'owner@example.com',
      );
      repository.failWrites = false;
      await waitingForAuth.load();
      expect((await remote()).single.value, 7);
      expect(waitingForAuth.hasPendingOutcomeChanges, isFalse);
    },
  );

  test(
    'server revocation drops pending uploads before a later consent grant',
    () async {
      final first = await load();
      repository.failWrites = true;
      await first.recordObservedEnergy(7, observedAt: now);
      final attempts = repository.writes.length;
      await repository.saveOutcomeConsent('owner', false);
      repository.failWrites = false;
      final restarted = await load();
      expect(restarted.outcomeConsent, isFalse);
      expect(restarted.hasPendingOutcomeChanges, isFalse);
      expect(restarted.outcomes, isEmpty);
      await restarted.setOutcomeConsent(true);
      expect(repository.writes, hasLength(attempts));
      expect(await remote(), isEmpty);
    },
  );

  test(
    'a different consent receipt does not replay previous pending outcomes',
    () async {
      final first = await load();
      repository.failWrites = true;
      await first.recordObservedEnergy(7, observedAt: now);
      final attempts = repository.writes.length;
      await repository.saveOutcomeConsent('owner', false);
      await repository.saveOutcomeConsent('owner', true);
      repository.failWrites = false;
      final restarted = await load();
      expect(restarted.outcomeConsent, isTrue);
      expect(restarted.hasPendingOutcomeChanges, isFalse);
      expect(restarted.outcomes, isEmpty);
      expect(repository.writes, hasLength(attempts));
    },
  );

  test('another account never uploads the previous owner journal', () async {
    final first = await load();
    repository.failWrites = true;
    await first.recordObservedEnergy(7, observedAt: now);
    final attempts = repository.writes.length;
    repository.signedInUid = 'other';
    repository.seed('other', state(email: 'other@example.com'));
    auth.session = const AccountSession(
      uid: 'other',
      email: 'other@example.com',
    );
    repository.failWrites = false;
    final other = await load();
    expect(other.outcomes, isEmpty);
    expect(other.hasPendingOutcomeChanges, isFalse);
    expect(repository.writes, hasLength(attempts));
    expect(await remote(uid: 'other'), isEmpty);
  });

  test('late failed upload cannot change status after sign-out', () async {
    final controller = await load();
    final gate = repository.writeGate = Completer<void>();
    final started = repository.writeStarted = Completer<void>();
    final save = controller.recordObservedEnergy(7, observedAt: now);
    final stopped = expectLater(save, throwsStateError);
    await started.future;
    await controller.signOut();
    gate.completeError(StateError('Disconnected'));
    await stopped;
    expect(controller.isSignedOut, isTrue);
    expect(controller.outcomeError, isNull);
  });

  test(
    'an older remote read cannot overwrite a concurrent completed save',
    () async {
      final controller = await load();
      final gate = repository.readGate = Completer<void>();
      final started = repository.readStarted = Completer<void>();
      final refresh = controller.refreshOutcomes();
      await started.future;
      await controller.recordObservedEnergy(8, observedAt: now);
      gate.complete();
      await refresh;
      expect(controller.outcomes.single.value, 8);
      expect(controller.isOutcomeLoading, isFalse);
      expect(controller.hasPendingOutcomeChanges, isFalse);
    },
  );

  test(
    'a newer edit survives acknowledgement of an older in-flight upload',
    () async {
      final controller = await load();
      final gate = repository.writeGate = Completer<void>();
      final started = repository.writeStarted = Completer<void>();
      final first = controller.recordObservedEnergy(5, observedAt: now);
      await started.future;
      final second = controller.recordObservedEnergy(8, observedAt: now);
      gate.complete();
      await Future.wait([first, second]);
      expect((await remote()).single.value, 8);
      expect(controller.outcomes.single.value, 8);
      expect(controller.hasPendingOutcomeChanges, isFalse);
    },
  );

  test(
    'clearing tracking waits for an issued upload and cannot resurrect it',
    () async {
      final controller = await load();
      final gate = repository.writeGate = Completer<void>();
      final started = repository.writeStarted = Completer<void>();
      final save = controller.recordObservedEnergy(7, observedAt: now);
      await started.future;
      final clear = controller.clearTrackingData();
      gate.complete();
      await Future.wait([save, clear]);
      expect(await remote(), isEmpty);
      expect(controller.outcomes, isEmpty);
      expect(controller.hasPendingOutcomeChanges, isFalse);
    },
  );
}
