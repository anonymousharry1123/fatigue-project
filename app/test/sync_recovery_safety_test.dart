import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

const _session = AccountSession(uid: 'owner', email: 'owner@example.com');
final _now = DateTime(2026, 9, 20, 12);

class _RecoveryAuth extends MemoryAccountAuth {
  _RecoveryAuth() : super(session: _session);
  bool offline = true;

  @override
  Future<void> refreshPrivacyClaims() async {
    if (offline) throw StateError('offline');
  }
}

class _RecoveryRepository extends MemoryCloudRepository {
  _RecoveryRepository() : super(signedInUid: 'owner');
  Completer<CloudUserState?>? nextRead;
  final readStarted = Completer<void>();

  @override
  Future<CloudUserState?> readUser(String uid) async {
    final held = nextRead;
    nextRead = null;
    if (held != null) {
      if (!readStarted.isCompleted) readStarted.complete();
      return held.future;
    }
    return super.readUser(uid);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'retry cannot claim an ownerless legacy cache as the current account',
    () async {
      final previousReading = SignalReading(
        id: 'previous-account-private-data',
        type: SignalType.study,
        value: 2,
        timestamp: _now,
      );
      SharedPreferences.setMockInitialValues({
        'tonyo_state_v1': jsonEncode({
          'onboardingComplete': true,
          'accountEmail': 'previous@example.com',
          'profile': const UserProfile(name: 'Previous account').toJson(),
          'signals': [previousReading.toJson()],
          'checkIns': [],
          'privacyConsent': testAdultPrivacyConsent.toJson(),
        }),
      });
      final auth = _RecoveryAuth();
      final repository = _RecoveryRepository()..seed('owner', _state());
      final app = AppController(
        accountAuth: auth,
        cloudRepository: repository,
        clock: () => _now,
      );
      addTearDown(app.dispose);
      await app.load();
      expect(app.canExportDeviceBackup, isFalse);

      auth.offline = false;
      await expectLater(app.retryCloudSync(), throwsStateError);

      expect(app.canExportDeviceBackup, isFalse);
      await expectLater(app.exportDeviceBackup(), throwsStateError);
      expect(app.signals.single.id, previousReading.id);
      expect(repository.inputPatchCallCount, 0);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getKeys().where(
          (key) => key.startsWith('tonyo_device_recovery_v1_'),
        ),
        isEmpty,
      );
    },
  );

  test('stale cloud restore cannot undo a newer privacy withdrawal', () async {
    final auth = _RecoveryAuth();
    final repository = _RecoveryRepository()..seed('owner', _state());
    final app = AppController(
      accountAuth: auth,
      cloudRepository: repository,
      clock: () => _now,
    );
    addTearDown(app.dispose);
    await app.load();

    auth.offline = false;
    final oldCloudRead = Completer<CloudUserState?>();
    repository.nextRead = oldCloudRead;
    final retry = app.retryCloudSync();
    await repository.readStarted.future;

    // This newer verification supersedes the pending restore. Its result must
    // remain authoritative even when the older read returns allowed consent.
    repository.seed('owner', _state(consent: false));
    await app.handleAppResumed();
    expect(app.privacyFeaturesAllowed, isFalse);
    oldCloudRead.complete(_state());
    await retry;

    expect(app.privacyFeaturesAllowed, isFalse);
    await expectLater(app.addSignal(SignalType.study, 2), throwsStateError);
    expect(repository.inputPatchCallCount, 0);
  });
}
