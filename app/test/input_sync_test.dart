import 'dart:async';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'privacy_test_support.dart';

final when = DateTime(2026, 9, 19, 12);
SignalReading signal(String id, [double value = 1]) => SignalReading(
  id: id,
  type: SignalType.hydration,
  value: value,
  timestamp: when,
  recordedAt: when,
);
CloudUserState state({
  List<SignalReading> signals = const [],
  bool consent = false,
  UserProfile profile = const UserProfile(name: 'Owner'),
}) => CloudUserState(
  profile: profile,
  accountEmail: 'owner@example.com',
  onboardingComplete: false,
  notificationsEnabled: false,
  outcomeConsent: consent,
  healthAuthorized: false,
  signals: signals,
  checkIns: const [],
  migrationVersion: localMigrationVersion,
  notificationPrefsVersion: notificationPreferencesVersion,
  privacyConsent: testAdultPrivacyConsent,
);

class Repository extends MemoryCloudRepository {
  Repository() : super(signedInUid: 'owner');
  bool offline = false;
  int patches = 0;
  Completer<void>? gate;
  final started = Completer<void>();
  void Function()? beforePatch;
  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    patches++;
    if (!started.isCompleted) started.complete();
    final pending = gate;
    gate = null;
    if (pending != null) await pending.future;
    if (offline) throw StateError('offline');
    beforePatch?.call();
    await super.applyInputPatch(uid, patch);
  }
}

AppController controller(Repository repo) => AppController(
  cloudRepository: repo,
  accountAuth: MemoryAccountAuth(
    session: const AccountSession(uid: 'owner', email: 'owner@example.com'),
  ),
  initialPrivacyConsent: testAdultPrivacyConsent,
  clock: () => when,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'ordinary saves preserve unseen records and protected consent',
    () async {
      final repo = Repository()..seed('owner', state(signals: [signal('a')]));
      final app = controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.seed(
        'owner',
        state(signals: [signal('a'), signal('other-phone')], consent: true),
      );
      await app.addSignal(SignalType.study, 2);
      final remote = (await repo.readUser('owner'))!;
      expect(
        remote.signals.map((item) => item.id),
        containsAll(['a', 'other-phone']),
      );
      expect(
        remote.signals.where((item) => item.type == SignalType.study),
        hasLength(1),
      );
      expect(remote.outcomeConsent, true);
      expect(repo.replaceUserCallCount, 0);
      expect(app.hasPendingCloudChanges, false);
    },
  );

  test(
    'same-record conflict preserves both copies until explicit cloud recovery',
    () async {
      final repo = Repository()..seed('owner', state(signals: [signal('a')]));
      final app = controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.seed('owner', state(signals: [signal('a', 2)]));
      await app.deleteSignal('a');
      expect(app.signals, isEmpty);
      expect(app.cloudSyncConflict, true);
      expect(app.hasPendingCloudChanges, true);
      expect((await repo.readUser('owner'))!.signals.single.value, 2);
      await app.retryCloudSync();
      expect(app.cloudSyncConflict, true);
      await app.useCloudInputs();
      expect(app.signals.single.value, 2);
      expect(app.hasPendingCloudChanges, false);
      expect(app.cloudSyncConflict, false);
    },
  );

  test(
    'offline additions and deletions survive restart without losing remote additions',
    () async {
      final repo = Repository()..seed('owner', state(signals: [signal('a')]));
      final app = controller(repo);
      await app.load();
      repo.offline = true;
      await app.deleteSignal('a');
      await app.addSignal(SignalType.study, 2);
      final localId = app.signals.single.id;
      expect(app.hasPendingCloudChanges, true);
      app.dispose();
      repo.seed('owner', state(signals: [signal('a'), signal('other-phone')]));
      repo.offline = false;
      final restarted = controller(repo);
      addTearDown(restarted.dispose);
      await restarted.load();
      final ids = (await repo.readUser(
        'owner',
      ))!.signals.map((item) => item.id).toSet();
      expect(ids, {localId, 'other-phone'});
      expect(restarted.signals.map((item) => item.id).toSet(), ids);
      expect(restarted.hasPendingCloudChanges, false);
      expect(restarted.cloudSyncError, isNull);
    },
  );

  test(
    'queued edits serialize and retain edits made during an earlier request',
    () async {
      final repo = Repository()..seed('owner', state());
      final app = controller(repo);
      addTearDown(app.dispose);
      await app.load();
      final gate = Completer<void>();
      repo.gate = gate;
      final first = app.addSignal(SignalType.study, 1);
      await repo.started.future;
      final second = app.addSignal(SignalType.hydration, 2);
      await Future<void>.delayed(Duration.zero);
      expect(repo.patches, 1);
      gate.complete();
      await Future.wait([first, second]);
      expect((await repo.readUser('owner'))!.signals, hasLength(2));
      expect(repo.patches, 2);
      expect(app.hasPendingCloudChanges, false);
    },
  );

  test(
    'replayed patches are idempotent including deletes and timestamp journals',
    () async {
      final before = state(signals: [signal('a')]);
      final after = state(signals: [signal('b')]);
      final original = InputSyncSnapshot.fromState(before);
      final restored = InputSyncSnapshot.fromJson(original.toJson());
      final patch = InputSyncPatch(
        restored,
        InputSyncSnapshot.fromState(after),
      );
      final repo = Repository()..seed('owner', before);
      await repo.applyInputPatch('owner', patch);
      await repo.applyInputPatch('owner', patch);
      expect((await repo.readUser('owner'))!.signals.single.id, 'b');
      expect(
        syncFirestoreData(patch.signals.last.after!)['timestamp'],
        isA<DateTime>(),
      );
      expect(patch.root.keys, isNot(contains('consentFlags')));
    },
  );

  test(
    'legacy migration changes only metadata and preserves concurrent additions',
    () async {
      final legacy = state(
        signals: [signal('a')],
      ).copyWith(migrationVersion: 0);
      final repo = Repository()..seed('owner', legacy);
      repo.beforePatch = () => repo.seed(
        'owner',
        state(
          signals: [signal('a'), signal('other-phone')],
        ).copyWith(migrationVersion: 0),
      );
      final app = controller(repo);
      addTearDown(app.dispose);
      await app.load();
      final remote = (await repo.readUser('owner'))!;
      expect(remote.migrationVersion, localMigrationVersion);
      expect(remote.signals.map((item) => item.id), contains('other-phone'));
      expect(repo.replaceUserCallCount, 0);
      expect(app.hasPendingCloudChanges, false);
    },
  );

  test(
    'merge payload clears removed nullable fields and preserves unknown fields',
    () {
      final before = <String, dynamic>{
        'note': 'old note',
        'recordedAt': when.toUtc().toIso8601String(),
        'healthSync': {
          'reason': 'manual',
          'lastAttemptAt': when.toUtc().toIso8601String(),
        },
      };
      final after = <String, dynamic>{
        'healthSync': {'status': 'idle'},
      };
      final payload = syncMergedData(before, after);
      expect(payload.containsKey('note'), true);
      expect(payload['note'], isNull);
      expect(payload.containsKey('recordedAt'), true);
      expect(payload['recordedAt'], isNull);
      expect(payload['healthSync'], {
        'reason': null,
        'lastAttemptAt': null,
        'status': 'idle',
      });
      expect(payload.containsKey('unknownServerField'), false);
      // Once normalized from Firestore, cleared nulls compare identically to
      // omitted fields in the durable journal, avoiding a false retry conflict.
      expect(sameSyncValue(payload, after), true);
    },
  );

  test(
    'cloud recovery waits for an active upload before adopting remote state',
    () async {
      final repo = Repository()..seed('owner', state());
      final app = controller(repo);
      addTearDown(app.dispose);
      await app.load();
      final gate = Completer<void>();
      repo.gate = gate;
      final save = app.addSignal(SignalType.study, 2);
      await repo.started.future;
      var recovered = false;
      final recovery = app.useCloudInputs().then((_) => recovered = true);
      await Future<void>.delayed(Duration.zero);
      expect(recovered, false);
      gate.complete();
      await Future.wait([save, recovery]);
      expect(app.signals, hasLength(1));
      expect(app.hasPendingCloudChanges, false);
      expect((await repo.readUser('owner'))!.signals, hasLength(1));
    },
  );

  test(
    'pending input edits drive local views without uploading stale derived data',
    () async {
      final repo = Repository()..seed('owner', state());
      final app = controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = true; // Reject input writes; reads still work.
      await app.addSignal(SignalType.study, 2);
      final scoreWrites = repo.scoreUpsertCallCount;
      final forecastWrites = repo.forecastReplaceCallCount;
      await app.refreshScores(forceRecalculate: true);
      await app.refreshForecasts(forceRecalculate: true);
      await app.refreshGuidance();
      await app.refreshInsights();
      expect(app.hasPendingCloudChanges, true);
      expect(
        app.todaySignalSummaries
            .firstWhere((item) => item.type == SignalType.study)
            .readingCount,
        1,
      );
      expect(app.forecastError, contains('saved device inputs'));
      expect(app.guidanceError, contains('saved device inputs'));
      expect(app.insightsError, contains('saved device inputs'));
      expect(repo.scoreUpsertCallCount, scoreWrites);
      expect(repo.forecastReplaceCallCount, forecastWrites);
    },
  );
}
