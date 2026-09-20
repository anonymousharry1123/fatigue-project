import 'dart:async';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/sync_conflict_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

final _when = DateTime(2026, 9, 19, 12);
SignalReading _signal(String id, [double value = 1]) => SignalReading(
  id: id,
  type: SignalType.hydration,
  value: value,
  timestamp: _when,
  recordedAt: _when,
);
DailyCheckIn _checkIn(String id, [double energy = 5]) =>
    DailyCheckIn(id: id, timestamp: _when, energy: energy, mood: 5, stress: 5);
CloudUserState _state({
  List<SignalReading> signals = const [],
  List<DailyCheckIn> checkIns = const [],
  UserProfile profile = const UserProfile(name: 'Original'),
  bool outcomeConsent = false,
  DateTime? lastSync,
  bool healthAuthorized = false,
  bool healthBackgroundRefreshEnabled = false,
}) => CloudUserState(
  profile: profile,
  accountEmail: 'owner@example.com',
  onboardingComplete: false,
  notificationsEnabled: false,
  outcomeConsent: outcomeConsent,
  healthAuthorized: healthAuthorized,
  healthBackgroundRefreshEnabled: healthBackgroundRefreshEnabled,
  lastSync: lastSync,
  signals: signals,
  checkIns: checkIns,
  migrationVersion: localMigrationVersion,
  notificationPrefsVersion: notificationPreferencesVersion,
  privacyConsent: testAdultPrivacyConsent,
);

class _Repository extends MemoryCloudRepository {
  _Repository() : super(signedInUid: 'owner');
  bool offline = false;
  bool outcomesOffline = false;
  Completer<void>? outcomeGate;
  Completer<void>? outcomeStarted;
  void Function()? beforePatch;
  Completer<void>? readGate;
  Completer<void>? readStarted;
  Completer<void>? privacyGate;
  Completer<void>? privacyStarted;
  int patches = 0;

  @override
  Future<void> upsertOutcome(String uid, OutcomeRecord outcome) async {
    final gate = outcomeGate;
    outcomeGate = null;
    if (gate != null) {
      outcomeStarted?.complete();
      await gate.future;
    }
    if (outcomesOffline) throw StateError('offline');
    await super.upsertOutcome(uid, outcome);
  }

  @override
  Future<void> deleteOutcome(String uid, String outcomeId) async {
    if (outcomesOffline) throw StateError('offline');
    await super.deleteOutcome(uid, outcomeId);
  }

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) async {
    final result = await super.readAccountPrivacy(uid);
    final gate = privacyGate;
    privacyGate = null;
    if (gate != null) {
      privacyStarted?.complete();
      await gate.future;
    }
    return result;
  }

  @override
  Future<CloudUserState?> readUser(String uid) async {
    final result = await super.readUser(uid);
    final gate = readGate;
    readGate = null;
    if (gate != null) {
      readStarted?.complete();
      await gate.future;
    }
    return result;
  }

  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    patches++;
    if (offline) throw StateError('offline');
    beforePatch?.call();
    await super.applyInputPatch(uid, patch);
  }
}

AppController _controller(_Repository repo) => AppController(
  cloudRepository: repo,
  accountAuth: MemoryAccountAuth(
    session: const AccountSession(uid: 'owner', email: 'owner@example.com'),
  ),
  initialPrivacyConsent: testAdultPrivacyConsent,
  clock: () => _when,
);

Future<({_Repository repo, AppController app})> _profileConflict() async {
  final repo = _Repository()..seed('owner', _state());
  final app = _controller(repo);
  await app.load();
  repo.offline = true;
  await app.updateProfile(
    app.profile.copyWith(name: 'Phone name', role: 'Phone role'),
  );
  repo.seed(
    'owner',
    _state(
      profile: const UserProfile(name: 'Cloud name', goal: 'Cloud goal'),
    ),
  );
  return (repo: repo, app: app);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'field choices retain unrelated local edits, cloud fields and protected consent',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      repo.seed(
        'owner',
        _state(
          profile: const UserProfile(name: 'Cloud name', goal: 'Cloud goal'),
          signals: [_signal('remote-only')],
          outcomeConsent: true,
        ),
      );
      final review = await app.reviewInputConflicts();
      expect(review.items.map((item) => item.key), ['profile:profile.name']);
      expect(review.items.single.phoneDescription, 'Phone name');
      expect(review.items.single.cloudDescription, 'Cloud name');
      repo.offline = false;
      await app.resolveInputConflicts(review, {review.items.single.key: false});
      final remote = (await repo.readUser('owner'))!;
      expect(remote.profile.name, 'Cloud name');
      expect(remote.profile.role, 'Phone role');
      expect(remote.profile.goal, 'Cloud goal');
      expect(remote.signals.single.id, 'remote-only');
      expect(remote.outcomeConsent, true);
      expect(app.outcomeConsent, true);
      expect(app.hasPendingCloudChanges, false);
      expect(repo.replaceUserCallCount, 0);
    },
  );

  test(
    'mixed record choices preserve unrelated additions and allow explicit deletion',
    () async {
      final repo = _Repository()
        ..seed(
          'owner',
          _state(
            signals: [_signal('signal')],
            checkIns: [_checkIn('check-in')],
          ),
        );
      final app = _controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = true;
      await app.deleteSignal('signal');
      await app.deleteCheckIn('check-in');
      await app.addSignal(SignalType.study, 2);
      final phoneOnly = app.signals.single.id;
      repo.seed(
        'owner',
        _state(
          signals: [_signal('signal', 3), _signal('cloud-only')],
          checkIns: [_checkIn('check-in', 8), _checkIn('other-check-in')],
        ),
      );
      final review = await app.reviewInputConflicts();
      expect(review.items, hasLength(2));
      expect(
        review.items.every((item) => item.phoneDescription == 'Deleted'),
        true,
      );
      expect(review.items.first.title, contains('Hydration'));
      repo.offline = false;
      await app.resolveInputConflicts(review, {
        'signal:signal': true,
        'check-in:check-in': false,
      });
      final remote = (await repo.readUser('owner'))!;
      expect(remote.signals.map((item) => item.id).toSet(), {
        'cloud-only',
        phoneOnly,
      });
      expect(remote.checkIns.map((item) => item.id).toSet(), {
        'check-in',
        'other-check-in',
      });
      expect(
        remote.checkIns.firstWhere((item) => item.id == 'check-in').energy,
        8,
      );
      expect(app.hasPendingCloudChanges, false);
    },
  );

  test(
    'choosing cloud for every edit clears conflict status even without an upload',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      await app.updateProfile(
        app.profile.copyWith(role: const UserProfile().role),
      );
      repo.offline = false;
      await app.retryCloudSync();
      expect(app.cloudSyncConflict, true);
      expect(app.cloudSyncFailureKind, CloudSyncFailureKind.conflict);
      final review = await app.reviewInputConflicts();
      await app.resolveInputConflicts(review, {review.items.single.key: false});
      expect(app.cloudSyncConflict, false);
      expect(app.cloudSyncFailureKind, isNull);
      expect(app.cloudSyncError, isNull);
      expect(app.isCloudSyncing, false);
      expect(app.hasPendingCloudChanges, false);
    },
  );

  test(
    'matching phone and cloud versions need no choice and preserve all other edits',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      repo.seed(
        'owner',
        _state(
          profile: const UserProfile(name: 'Phone name', goal: 'Cloud goal'),
          signals: [_signal('remote-only')],
        ),
      );
      final review = await app.reviewInputConflicts();
      expect(review.items, isEmpty);
      repo.offline = false;
      await app.resolveInputConflicts(review, {});
      final remote = (await repo.readUser('owner'))!;
      expect(remote.profile.name, 'Phone name');
      expect(remote.profile.role, 'Phone role');
      expect(remote.profile.goal, 'Cloud goal');
      expect(remote.signals.single.id, 'remote-only');
      expect(app.hasPendingCloudChanges, false);
    },
  );

  test(
    'keeping cloud check-in fixes pending linked outcome and preserves unrelated learning',
    () async {
      final repo = _Repository()
        ..seed(
          'owner',
          _state(checkIns: [_checkIn('c')], outcomeConsent: true),
        );
      final app = _controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = true;
      repo.outcomesOffline = true;
      await app.addCheckIn(
        id: 'c',
        energy: 3,
        mood: 5,
        stress: 5,
        timestamp: _when,
      );
      await app.recordObservedEnergy(
        7,
        observedAt: _when.add(const Duration(minutes: 1)),
      );
      repo.seed(
        'owner',
        _state(checkIns: [_checkIn('c', 8)], outcomeConsent: true),
      );
      final review = await app.reviewInputConflicts();
      repo.offline = false;
      repo.outcomesOffline = false;
      await app.resolveInputConflicts(review, {'check-in:c': false});
      final outcomes = await repo.outcomesByRange(
        'owner',
        start: _when.subtract(const Duration(days: 1)),
        end: _when.add(const Duration(days: 1)),
      );
      expect(
        outcomes.firstWhere((item) => item.id == 'energy-checkin-c').value,
        8,
      );
      expect(
        outcomes
            .singleWhere((item) => item.source == OutcomeSource.coach)
            .value,
        7,
      );
      expect(
        app.outcomes.firstWhere((item) => item.id == 'energy-checkin-c').value,
        8,
      );
      expect(app.checkIns.single.energy, 8);
      expect(app.hasPendingOutcomeChanges, false);
    },
  );

  test(
    'keeping cloud reaction repairs an already-uploaded phone outcome',
    () async {
      SignalReading reaction(double value) => SignalReading(
        id: 'r',
        type: SignalType.reactionTime,
        value: value,
        timestamp: _when,
      );
      final repo = _Repository()
        ..seed('owner', _state(signals: [reaction(400)], outcomeConsent: true));
      final app = _controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = true;
      await app.addReactionResult(300, resultId: 'r', observedAt: _when);
      repo.seed(
        'owner',
        _state(signals: [reaction(500)], outcomeConsent: true),
      );
      final review = await app.reviewInputConflicts();
      repo.offline = false;
      await app.resolveInputConflicts(review, {'signal:r': false});
      final outcomes = await repo.outcomesByRange(
        'owner',
        start: _when.subtract(const Duration(days: 1)),
        end: _when.add(const Duration(days: 1)),
      );
      expect(outcomes.single.id, 'reaction-r');
      expect(outcomes.single.value, 500);
      expect(app.signals.single.value, 500);
      expect(app.hasPendingOutcomeChanges, false);
    },
  );

  test(
    'keeping a cloud check-in rebuilds its result after phone deletion already uploaded',
    () async {
      final repo = _Repository()
        ..seed(
          'owner',
          _state(checkIns: [_checkIn('c')], outcomeConsent: true),
        );
      await repo.upsertOutcome(
        'owner',
        OutcomeRecord(
          id: 'energy-checkin-c',
          type: OutcomeType.observedEnergy,
          value: 5,
          observedAt: _when,
          recordedAt: _when,
          source: OutcomeSource.checkIn,
          sourceId: 'c',
        ),
      );
      final app = _controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = true;
      await app.deleteCheckIn('c');
      expect(app.outcomes, isEmpty);
      expect(app.hasPendingOutcomeChanges, false);
      repo.seed(
        'owner',
        _state(checkIns: [_checkIn('c', 8)], outcomeConsent: true),
      );
      final review = await app.reviewInputConflicts();
      repo.offline = false;
      await app.resolveInputConflicts(review, {'check-in:c': false});
      final outcomes = await repo.outcomesByRange(
        'owner',
        start: _when.subtract(const Duration(days: 1)),
        end: _when.add(const Duration(days: 1)),
      );
      expect(outcomes.single.value, 8);
      expect(app.checkIns.single.energy, 8);
    },
  );

  test(
    'keeping a cloud deletion deletes the already-uploaded linked phone outcome',
    () async {
      final repo = _Repository()
        ..seed(
          'owner',
          _state(checkIns: [_checkIn('c')], outcomeConsent: true),
        );
      final app = _controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = true;
      await app.addCheckIn(
        id: 'c',
        energy: 3,
        mood: 5,
        stress: 5,
        timestamp: _when,
      );
      repo.seed('owner', _state(outcomeConsent: true));
      final review = await app.reviewInputConflicts();
      repo.offline = false;
      await app.resolveInputConflicts(review, {'check-in:c': false});
      final outcomes = await repo.outcomesByRange(
        'owner',
        start: _when.subtract(const Duration(days: 1)),
        end: _when.add(const Duration(days: 1)),
      );
      expect(outcomes, isEmpty);
      expect(app.checkIns, isEmpty);
      expect(app.outcomes, isEmpty);
      expect(app.hasPendingOutcomeChanges, false);
    },
  );

  test(
    'cloud choice waits for an in-flight linked outcome upload before reconciling it',
    () async {
      final repo = _Repository()
        ..seed(
          'owner',
          _state(checkIns: [_checkIn('c')], outcomeConsent: true),
        );
      final app = _controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = true;
      final gate = Completer<void>();
      final started = Completer<void>();
      repo.outcomeGate = gate;
      repo.outcomeStarted = started;
      final saving = app.addCheckIn(
        id: 'c',
        energy: 3,
        mood: 5,
        stress: 5,
        timestamp: _when,
      );
      await started.future;
      repo.seed(
        'owner',
        _state(checkIns: [_checkIn('c', 8)], outcomeConsent: true),
      );
      final review = await app.reviewInputConflicts();
      repo.offline = false;
      var resolved = false;
      final resolving = app
          .resolveInputConflicts(review, {'check-in:c': false})
          .then((_) => resolved = true);
      await Future<void>.delayed(Duration.zero);
      expect(resolved, false);
      expect(app.checkIns.single.energy, 3);
      gate.complete();
      await Future.wait([saving, resolving]);
      final outcomes = await repo.outcomesByRange(
        'owner',
        start: _when.subtract(const Duration(days: 1)),
        end: _when.add(const Duration(days: 1)),
      );
      expect(outcomes.single.value, 8);
      expect(app.checkIns.single.energy, 8);
    },
  );

  test(
    'keeping cloud after opting out does not reconstruct learning outcomes',
    () async {
      final repo = _Repository()
        ..seed(
          'owner',
          _state(checkIns: [_checkIn('c')], outcomeConsent: true),
        );
      final app = _controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = true;
      repo.outcomesOffline = true;
      await app.addCheckIn(
        id: 'c',
        energy: 3,
        mood: 5,
        stress: 5,
        timestamp: _when,
      );
      await app.setOutcomeConsent(false);
      repo.seed('owner', _state(checkIns: [_checkIn('c', 8)]));
      final review = await app.reviewInputConflicts();
      repo.offline = false;
      repo.outcomesOffline = false;
      await app.resolveInputConflicts(review, {'check-in:c': false});
      expect(app.checkIns.single.energy, 8);
      expect(app.outcomes, isEmpty);
      expect(app.hasPendingOutcomeChanges, false);
      expect(app.outcomeConsent, false);
    },
  );

  test(
    'every conflict needs a choice and arbitrary extra choices are rejected',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      final review = await app.reviewInputConflicts();
      await expectLater(
        app.resolveInputConflicts(review, {}),
        throwsStateError,
      );
      await expectLater(
        app.resolveInputConflicts(review, {
          review.items.single.key: true,
          'signal:unknown': false,
        }),
        throwsStateError,
      );
      expect(app.profile.name, 'Phone name');
      expect((await repo.readUser('owner'))!.profile.name, 'Cloud name');
    },
  );

  test('local changes after preview are never overwritten', () async {
    final (:repo, :app) = await _profileConflict();
    addTearDown(app.dispose);
    final review = await app.reviewInputConflicts();
    await app.updateProfile(app.profile.copyWith(name: 'New phone edit'));
    await expectLater(
      app.resolveInputConflicts(review, {review.items.single.key: false}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Phone data changed'),
        ),
      ),
    );
    expect(app.profile.name, 'New phone edit');
    expect((await repo.readUser('owner'))!.profile.name, 'Cloud name');
  });

  test(
    'remote changes after preview require a new review, including unrelated rows',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      final review = await app.reviewInputConflicts();
      repo.seed(
        'owner',
        _state(
          profile: const UserProfile(name: 'Newest cloud'),
          signals: [_signal('new')],
        ),
      );
      await expectLater(
        app.resolveInputConflicts(review, {review.items.single.key: true}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Cloud data changed'),
          ),
        ),
      );
      expect(app.profile.name, 'Phone name');
      expect((await repo.readUser('owner'))!.profile.name, 'Newest cloud');
      expect(app.hasPendingCloudChanges, true);
    },
  );

  test(
    'transaction race after confirmation leaves both versions intact and retryable',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      final review = await app.reviewInputConflicts();
      repo.offline = false;
      repo.beforePatch = () => repo.seed(
        'owner',
        _state(profile: const UserProfile(name: 'Third phone')),
      );
      await app.resolveInputConflicts(review, {review.items.single.key: true});
      expect(app.profile.name, 'Phone name');
      expect((await repo.readUser('owner'))!.profile.name, 'Third phone');
      expect(app.cloudSyncConflict, true);
      expect(app.hasPendingCloudChanges, true);
    },
  );

  test(
    'confirmed choices are durable when upload fails and finish after restart',
    () async {
      final (:repo, :app) = await _profileConflict();
      final review = await app.reviewInputConflicts();
      await app.resolveInputConflicts(review, {review.items.single.key: true});
      expect(app.hasPendingCloudChanges, true);
      app.dispose();
      repo.offline = false;
      final restarted = _controller(repo);
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.profile.name, 'Phone name');
      expect(restarted.profile.role, 'Phone role');
      expect(restarted.profile.goal, 'Cloud goal');
      expect(restarted.hasPendingCloudChanges, false);
      expect((await repo.readUser('owner'))!.profile.name, 'Phone name');
    },
  );

  test(
    'device Health status is rebased without offering ineffective permission choices',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      app.lastSync = _when.subtract(const Duration(hours: 1));
      app.healthBackgroundRefreshEnabled = true;
      repo.seed(
        'owner',
        _state(
          profile: const UserProfile(name: 'Cloud name'),
          healthAuthorized: true,
          lastSync: _when.subtract(const Duration(hours: 2)),
        ),
      );
      final review = await app.reviewInputConflicts();
      expect(review.items.map((item) => item.key), ['profile:profile.name']);
      repo.offline = false;
      await app.resolveInputConflicts(review, {review.items.single.key: true});
      expect(app.healthAuthorized, false);
      expect(app.healthBackgroundRefreshEnabled, true);
      expect(app.lastSync, _when.subtract(const Duration(hours: 1)));
      expect(app.hasPendingCloudChanges, false);
    },
  );

  test(
    'privacy revocation after preview blocks resolution without uploading',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      final review = await app.reviewInputConflicts();
      repo.seed(
        'owner',
        _state(
          profile: const UserProfile(name: 'Cloud name'),
        ).copyWith(deletionPending: true),
      );
      await expectLater(
        app.resolveInputConflicts(review, {review.items.single.key: true}),
        throwsStateError,
      );
      expect(app.deletionPending, true);
      expect(app.profile.name, 'Phone name');
      expect((await repo.readUser('owner'))!.profile.name, 'Cloud name');
    },
  );

  for (final duringResolve in [false, true]) {
    test(
      'newer privacy choices supersede a stale ${duringResolve ? 'confirmation' : 'review'} privacy read',
      () async {
        final (:repo, :app) = await _profileConflict();
        addTearDown(app.dispose);
        await app.setOutcomeConsent(true);
        final review = duringResolve ? await app.reviewInputConflicts() : null;
        final gate = Completer<void>();
        final started = Completer<void>();
        repo.privacyGate = gate;
        repo.privacyStarted = started;
        final patchCount = repo.patches;
        final Future<Object?> pending = duringResolve
            ? app.resolveInputConflicts(review!, {
                review.items.single.key: true,
              })
            : app.reviewInputConflicts();
        final rejected = expectLater(pending, throwsStateError);
        await started.future;
        await app.setOutcomeConsent(false);
        expect(app.outcomeConsent, false);
        gate.complete();
        await rejected;
        expect(app.outcomeConsent, false);
        expect(app.profile.name, 'Phone name');
        expect(app.profile.role, 'Phone role');
        expect(app.hasPendingCloudChanges, true);
        expect(app.isCloudSyncing, false);
        expect(repo.patches, patchCount);
        final remote = (await repo.readUser('owner'))!;
        expect(remote.outcomeConsent, false);
        expect(remote.profile.name, 'Cloud name');
      },
    );
  }

  test(
    'account switch during a cloud read cannot apply stale review data',
    () async {
      final (:repo, :app) = await _profileConflict();
      addTearDown(app.dispose);
      final review = await app.reviewInputConflicts();
      final started = Completer<void>();
      final gate = Completer<void>();
      repo.readGate = gate;
      repo.readStarted = started;
      final resolution = app.resolveInputConflicts(review, {
        review.items.single.key: true,
      });
      final rejected = expectLater(resolution, throwsStateError);
      await started.future;
      await app.signOut();
      gate.complete();
      await rejected;
      expect(app.isSignedOut, true);
      expect((await repo.readUser('owner'))!.profile.name, 'Cloud name');
    },
  );

  testWidgets(
    'saving selected conflicts syncs and returns to the previous screen',
    (tester) async {
      final (:repo, :app) = (await tester.runAsync(_profileConflict))!;
      addTearDown(app.dispose);
      repo.offline = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTonyoTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SyncConflictScreen(controller: app),
                  ),
                ),
                child: const Text('Open review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open review'));
      await tester.pumpAndSettle();
      final keep = find.byKey(
        const Key('sync-conflict-phone-profile:profile.name'),
      );
      await tester.scrollUntilVisible(keep, 200);
      await tester.pumpAndSettle();
      await tester.tap(keep);
      await tester.pump();
      final save = find.byKey(const Key('sync-conflict-save'));
      await tester.scrollUntilVisible(save, 200);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Open review'), findsOneWidget);
      expect(find.text('Your choices are saved and synced.'), findsOneWidget);
      expect((await repo.readUser('owner'))!.profile.name, 'Phone name');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conflict choices are explicit and readable at 320px and 2x text',
    (tester) async {
      final (:repo, :app) = (await tester.runAsync(_profileConflict))!;
      addTearDown(app.dispose);
      repo.offline = false;
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTonyoTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SyncConflictScreen(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('sync-conflict-save'));
      await tester.scrollUntilVisible(save, 300);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final keepPhone = find.byKey(
        const Key('sync-conflict-phone-profile:profile.name'),
      );
      await tester.scrollUntilVisible(keepPhone, -300);
      await tester.ensureVisible(keepPhone);
      await tester.pumpAndSettle();
      expect(find.text('Phone name'), findsOneWidget);
      expect(find.text('Cloud name'), findsOneWidget);
      await tester.tap(keepPhone);
      await tester.pump();
      await tester.scrollUntilVisible(save, 300);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sync-conflict-save')))
            .onPressed,
        isNotNull,
      );
      expect(find.text('1 of 1 choices made'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
