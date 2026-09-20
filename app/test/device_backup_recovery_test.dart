import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

const _session = AccountSession(uid: 'owner', email: 'owner@example.com');
final _now = DateTime(2026, 9, 20, 12);

class _Auth extends MemoryAccountAuth {
  _Auth() : super(session: _session);
  bool offline = false;
  @override
  Future<void> refreshPrivacyClaims() async {
    if (offline) throw StateError('offline');
  }
}

class _Repository extends MemoryCloudRepository {
  _Repository() : super(signedInUid: 'owner');
  bool offline = false;
  int reads = 0;
  int patches = 0;
  Completer<void>? privacyGate;
  @override
  Future<CloudUserState?> readUser(String uid) async {
    reads++;
    if (offline) throw StateError('offline');
    return super.readUser(uid);
  }

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) async {
    reads++;
    if (privacyGate != null) await privacyGate!.future;
    if (offline) throw StateError('offline');
    return super.readAccountPrivacy(uid);
  }

  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    patches++;
    if (offline) throw StateError('offline');
    await super.applyInputPatch(uid, patch);
  }
}

CloudUserState _state({bool consent = true}) => CloudUserState(
  profile: const UserProfile(name: 'Owner'),
  accountEmail: _session.email,
  onboardingComplete: false,
  notificationsEnabled: false,
  outcomeConsent: false,
  healthAuthorized: false,
  signals: const [],
  checkIns: const [],
  migrationVersion: localMigrationVersion,
  notificationPrefsVersion: notificationPreferencesVersion,
  privacyConsent: consent ? testAdultPrivacyConsent : null,
);

AppController _controller(_Repository repo, [_Auth? auth]) => AppController(
  accountAuth: auth ?? _Auth(),
  cloudRepository: repo,
  clock: () => _now,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<String> saveOfflineEdit(_Repository repo) async {
    final app = _controller(repo);
    await app.load();
    repo.offline = true;
    await app.addSignal(SignalType.study, 2);
    final id = app.signals.single.id;
    expect(app.hasPendingCloudChanges, isTrue);
    app.dispose();
    return id;
  }

  test(
    'offline restart can back up pending data and retry after reconnect',
    () async {
      final repo = _Repository()..seed('owner', _state());
      final id = await saveOfflineEdit(repo);
      final auth = _Auth()..offline = true;
      final app = _controller(repo, auth);
      addTearDown(app.dispose);
      await app.load();
      expect(app.privacyReviewRequired, isTrue);
      final reads = repo.reads;
      final backup = jsonDecode(await app.exportDeviceBackup()) as Map;
      expect(repo.reads, reads);
      expect(backup['local']['signals'].single['id'], id);
      expect(backup['local']['inputSync']['uid'], 'owner');
      expect(backup['sync']['pendingInputs'], isTrue);
      expect(backup['scope']['cloudFetched'], isFalse);
      expect(app.hasPendingCloudChanges, isTrue);
      auth.offline = false;
      repo.offline = false;
      await app.retryCloudSync();
      expect(app.privacyFeaturesAllowed, isTrue);
      expect(app.hasPendingCloudChanges, isFalse);
      expect(app.cloudSyncError, isNull);
      expect((await repo.readUser('owner'))!.signals.single.id, id);
    },
  );

  test('foreground reconnect flushes pending phone inputs', () async {
    final repo = _Repository()..seed('owner', _state());
    final id = await saveOfflineEdit(repo);
    final app = _controller(repo);
    addTearDown(app.dispose);
    await app.load();
    expect(app.hasPendingCloudChanges, isTrue);
    repo.offline = false;
    await app.handleAppResumed();
    expect(app.hasPendingCloudChanges, isFalse);
    expect((await repo.readUser('owner'))!.signals.single.id, id);
  });

  test('retry still blocks uploads after consent withdrawal', () async {
    final repo = _Repository()..seed('owner', _state());
    await saveOfflineEdit(repo);
    final app = _controller(repo);
    addTearDown(app.dispose);
    await app.load();
    repo.offline = false;
    repo.seed('owner', _state(consent: false));
    final writes = repo.patches;
    await expectLater(app.retryCloudSync(), throwsStateError);
    expect(repo.patches, writes);
    expect(app.hasPendingCloudChanges, isTrue);
    expect(
      jsonDecode(await app.exportDeviceBackup())['local']['signals'],
      hasLength(1),
    );
  });

  test(
    'retry cannot upload after sign-out during privacy verification',
    () async {
      final repo = _Repository()..seed('owner', _state());
      await saveOfflineEdit(repo);
      final app = _controller(repo);
      addTearDown(app.dispose);
      await app.load();
      repo.offline = false;
      repo.privacyGate = Completer<void>();
      final writes = repo.patches;
      final retry = app.retryCloudSync();
      await Future<void>.delayed(Duration.zero);
      await app.signOut();
      repo.privacyGate!.complete();
      await retry;
      expect(repo.patches, writes);
      expect(app.canExportDeviceBackup, isFalse);
      await expectLater(app.exportDeviceBackup(), throwsStateError);
    },
  );

  test(
    'legacy phone data is archived before cloud restore and survives restart',
    () async {
      final repo = _Repository()..seed('owner', _state());
      final id = await saveOfflineEdit(repo);
      final preferences = await SharedPreferences.getInstance();
      final legacy =
          jsonDecode(preferences.getString('tonyo_state_v1')!)
              as Map<String, dynamic>;
      legacy.remove('inputSync');
      await preferences.setString('tonyo_state_v1', jsonEncode(legacy));
      repo.offline = false;
      final app = _controller(repo);
      await app.load();
      expect(app.signals, isEmpty);
      final backup = jsonDecode(await app.exportDeviceBackup()) as Map;
      expect(backup['beforeCloudRestore']['local']['signals'].single['id'], id);
      expect((await repo.readUser('owner'))!.signals, isEmpty);
      app.dispose();
      final restarted = _controller(repo);
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(
        jsonDecode(
          await restarted.exportDeviceBackup(),
        )['beforeCloudRestore']['local']['signals'].single['id'],
        id,
      );
      await restarted.clearTrackingData();
      expect(
        jsonDecode(
          await restarted.exportDeviceBackup(),
        ).containsKey('beforeCloudRestore'),
        isFalse,
      );
    },
  );

  test('backup rejects cached data belonging to a different account', () async {
    final repo = _Repository()..seed('owner', _state());
    await saveOfflineEdit(repo);
    final auth = _Auth()
      ..session = const AccountSession(uid: 'other', email: 'other@example.com')
      ..offline = true;
    final app = _controller(repo, auth);
    addTearDown(app.dispose);
    await app.load();
    expect(app.canExportDeviceBackup, isFalse);
    await expectLater(app.exportDeviceBackup(), throwsStateError);
  });

  test('local-only backup works without renewed privacy consent', () async {
    final app = AppController();
    addTearDown(app.dispose);
    app.signals = [
      SignalReading(
        id: 'local',
        type: SignalType.study,
        value: 2,
        timestamp: _now,
      ),
    ];
    final backup = jsonDecode(await app.exportDeviceBackup()) as Map;
    expect(backup['local']['signals'].single['id'], 'local');
    expect(backup['ownerUid'], isNull);
  });

  test('backup retains the journal for an unsynced deletion', () async {
    final repo = _Repository()..seed('owner', _state());
    final app = _controller(repo);
    addTearDown(app.dispose);
    await app.load();
    await app.addSignal(SignalType.study, 2);
    final id = app.signals.single.id;
    repo.offline = true;
    await app.deleteSignal(id);
    final backup = jsonDecode(await app.exportDeviceBackup()) as Map;
    expect(backup['local']['signals'], isEmpty);
    expect(backup['local']['inputSync']['baseline']['signals'], contains(id));
    expect(backup['sync']['pendingInputs'], isTrue);
  });

  test(
    'later legacy restores retain earlier device recovery snapshots',
    () async {
      final repo = _Repository()..seed('owner', _state());
      final originalId = await saveOfflineEdit(repo);
      final preferences = await SharedPreferences.getInstance();
      final legacy =
          jsonDecode(preferences.getString('tonyo_state_v1')!)
              as Map<String, dynamic>;
      legacy.remove('inputSync');
      await preferences.setString('tonyo_state_v1', jsonEncode(legacy));
      repo.offline = false;
      final firstRestore = _controller(repo);
      await firstRestore.load();
      firstRestore.dispose();
      legacy['signals'] = [
        SignalReading(
          id: 'new-phone-data',
          type: SignalType.study,
          value: 3,
          timestamp: _now,
        ).toJson(),
      ];
      await preferences.setString('tonyo_state_v1', jsonEncode(legacy));
      final secondRestore = _controller(repo);
      addTearDown(secondRestore.dispose);
      await secondRestore.load();
      final backup =
          jsonDecode(await secondRestore.exportDeviceBackup()) as Map;
      expect(
        backup['beforeCloudRestore']['local']['signals'].single['id'],
        'new-phone-data',
      );
      expect(
        backup['beforeCloudRestore']['earlierSnapshots']
            .single['local']['signals']
            .single['id'],
        originalId,
      );
    },
  );
}
