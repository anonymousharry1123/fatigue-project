import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/energy_model_repository.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/ml_prep_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 9, 7, 18);
const _session = AccountSession(uid: 'owner', email: 'owner@example.test');
final _adult = PrivacyConsent(
  ageBand: PrivacyAgeBand.adult,
  region: PrivacyRegion.us,
  acceptedAt: _now.subtract(const Duration(days: 1)),
);
final _minor = PrivacyConsent(
  ageBand: PrivacyAgeBand.age16to17,
  region: PrivacyRegion.us,
  acceptedAt: _now.subtract(const Duration(days: 1)),
);

CloudUserState _state({
  PrivacyConsent? receipt,
  bool consent = false,
  bool onboarded = false,
}) => CloudUserState(
  profile: const UserProfile(name: 'Private owner'),
  accountEmail: _session.email,
  onboardingComplete: onboarded,
  notificationsEnabled: false,
  outcomeConsent: consent,
  healthAuthorized: false,
  signals: [
    SignalReading(
      id: 'saved',
      type: SignalType.hydration,
      value: 1.5,
      timestamp: _now,
    ),
  ],
  checkIns: [
    DailyCheckIn(
      id: 'saved-checkin',
      energy: 7,
      mood: 6,
      stress: 3,
      timestamp: _now,
    ),
  ],
  migrationVersion: localMigrationVersion,
  privacyConsent: receipt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fresh same-account sign-in reopens owned adult data during Firestore quota',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      await h.controller.signOut();
      final restarted = h.newController();
      await restarted.load();
      expect(restarted.isSignedOut, true);
      expect(restarted.privacyFeaturesAllowed, false);
      h.repository.readError = 'resource-exhausted';
      final writes = h.repository.inputPatchCallCount;
      await restarted.signIn(email: _session.email, password: 'right');
      expect(restarted.isSignedOut, false);
      expect(restarted.isUsingQuotaLocalData, true);
      expect(restarted.cloudBackupLabel, 'Backup pending');
      await restarted.addSignal(SignalType.hydration, 2);
      expect(restarted.signals, hasLength(2));
      h.health.authorized = true;
      h.health.imported = [
        SignalReading(
          id: 'signed-in-health',
          type: SignalType.heartRate,
          value: 70,
          timestamp: h.now,
          source: SignalSource.healthKit,
        ),
      ];
      await restarted.refreshHealthAuthorization();
      await restarted.connectHealth();
      expect(restarted.signals.map((r) => r.id), contains('signed-in-health'));
      expect(h.repository.inputPatchCallCount, writes);
    },
  );

  for (final blocked in [
    'wrong-password',
    'other-account',
    'user-disabled',
    'permission-denied',
    'unavailable',
    'minor',
  ]) {
    test(
      '$blocked cannot reopen a signed-out cache through quota recovery',
      () async {
        final h = _Harness(
          state: _state(
            receipt: blocked == 'minor' ? _minor : _adult,
            onboarded: true,
          ),
        );
        h.auth.grantGuardian = blocked == 'minor';
        await h.controller.load();
        await h.controller.signOut();
        h.repository.readError =
            const {'permission-denied', 'unavailable'}.contains(blocked)
            ? blocked
            : 'resource-exhausted';
        if (blocked == 'user-disabled') h.auth.claimsError = blocked;
        await expectLater(
          h.controller.signIn(
            email: blocked == 'other-account'
                ? 'other@example.test'
                : _session.email,
            password: blocked == 'wrong-password' ? 'wrong' : 'right',
          ),
          throwsA(anything),
        );
        expect(h.controller.isSignedOut, true);
        expect(h.controller.privacyFeaturesAllowed, false);
        expect(h.controller.signals.single.id, 'saved');
      },
    );
  }

  testWidgets(
    'stalled account verification permits local startup, but late account rejection revokes it',
    (tester) async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      final gate = h.auth.claimsGate = Completer<void>();
      final restarted = h.newController();
      var loaded = false;
      final startup = restarted.load().then((_) => loaded = true);
      await tester.pump();
      expect(loaded, false);
      await tester.pump(const Duration(seconds: 8));
      await startup;
      expect(restarted.isReady, true);
      expect(restarted.isUsingOfflineData, true);
      await restarted.addSignal(SignalType.hydration, 2);
      gate.completeError(
        FirebaseException(plugin: 'firebase_auth', code: 'user-disabled'),
      );
      await tester.pump();
      expect(restarted.privacyFeaturesAllowed, false);
      expect(restarted.offlineAccessExpiresAt, isNull);
      final prefs = await SharedPreferences.getInstance();
      final state = jsonDecode(prefs.getString('tonyo_state_v1')!) as Map;
      expect((state['offlineAccess'] as Map)['lease'], isNull);
      expect(state['signals'], hasLength(2));
    },
  );

  test(
    'verified adult can restart, save and import Health offline without cloud calls',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      final expires = h.controller.offlineAccessExpiresAt;
      expect(expires, h.now.add(const Duration(hours: 72)));
      h.auth.claimsError = 'network-request-failed';
      h.now = h.now.add(const Duration(hours: 1));
      final reads = h.repository.userReads + h.repository.privacyReads;
      final writes = h.repository.inputPatchCallCount;
      final restarted = h.newController();
      await restarted.load();
      expect(restarted.isReady, true);
      expect(restarted.isUsingOfflineData, true);
      expect(restarted.cloudBackupLabel, 'Backup pending');
      await restarted.addSignal(SignalType.hydration, 2);
      h.health.authorized = true;
      h.health.imported = [
        SignalReading(
          id: 'offline-heart',
          type: SignalType.heartRate,
          value: 70,
          timestamp: h.now,
          source: SignalSource.healthKit,
        ),
      ];
      await restarted.refreshHealthAuthorization();
      await restarted.connectHealth();
      expect(restarted.signals.map((s) => s.id), contains('offline-heart'));
      expect(h.repository.userReads + h.repository.privacyReads, reads);
      expect(h.repository.inputPatchCallCount, writes);
      expect(restarted.offlineAccessExpiresAt, expires);
      final again = h.newController();
      await again.load();
      expect(
        again.signals.map((s) => s.id).toSet(),
        restarted.signals.map((s) => s.id).toSet(),
      );
      expect(again.offlineAccessExpiresAt, expires);
      h.auth.claimsError = null;
      await again.retryCloudSync();
      expect(again.isUsingDeviceOnlyData, false);
      expect(again.hasPendingCloudChanges, false);
      expect(again.cloudBackupLabel, 'Backed up');
      expect(
        again.offlineAccessExpiresAt,
        h.now.add(const Duration(hours: 72)),
      );
    },
  );

  test(
    'Firestore network failure permits local collection only within verified lease',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      h.repository.readError = 'unavailable';
      await h.controller.handleAppResumed();
      expect(h.controller.isUsingOfflineData, true);
      await h.controller.addSignal(SignalType.hydration, 2);
      h.now = _now.add(const Duration(hours: 72));
      expect(h.controller.privacyFeaturesAllowed, false);
      await expectLater(
        h.controller.addSignal(SignalType.hydration, 3),
        throwsStateError,
      );
      final restarted = h.newController();
      await restarted.load();
      expect(restarted.privacyFeaturesAllowed, false);
      expect(restarted.signals, hasLength(2));
    },
  );

  for (final failure in [
    'user-disabled',
    'invalid-user-token',
    'permission-denied',
  ]) {
    test(
      '$failure permanently clears offline grant before a later network failure',
      () async {
        final h = _Harness(state: _state(receipt: _adult, onboarded: true));
        await h.controller.load();
        h.auth.claimsError = failure;
        await h.controller.handleAppResumed();
        expect(h.controller.privacyFeaturesAllowed, false);
        h.auth.claimsError = 'network-request-failed';
        final restarted = h.newController();
        await restarted.load();
        expect(restarted.privacyFeaturesAllowed, false);
        expect(restarted.offlineAccessExpiresAt, isNull);
      },
    );
  }

  test(
    'clock rollback, owner change and missing consent cannot borrow an offline grant',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      h.auth.claimsError = 'network-request-failed';
      h.now = _now.subtract(const Duration(minutes: 1));
      await h.controller.handleAppResumed();
      expect(h.controller.privacyFeaturesAllowed, false);
      h.now = _now;
      h.auth.session = const AccountSession(
        uid: 'other',
        email: 'other@example.test',
      );
      final other = h.newController();
      await other.load();
      expect(other.privacyFeaturesAllowed, false);
    },
  );

  test(
    'foreground edits save immediately and upload once after the quiet period',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      h.controller.setAppForeground(true);
      final writes = h.repository.inputPatchCallCount;
      await h.controller.saveActivityLog(
        id: 'edited-water',
        hydrationLiters: 2,
      );
      await h.controller.saveActivityLog(
        id: 'edited-water',
        hydrationLiters: 3,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        (jsonDecode(prefs.getString('tonyo_state_v1')!) as Map)['signals'],
        hasLength(2),
      );
      expect(h.repository.inputPatchCallCount, writes);
      expect(h.controller.cloudBackupLabel, 'Backup pending');
      h.now = h.now.add(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(h.repository.inputPatchCallCount, writes + 1);
      expect(h.controller.hasPendingCloudChanges, false);
      expect(h.controller.cloudBackupLabel, 'Backed up');
      final cloud = (await h.repository.readUser('owner'))!;
      expect(
        cloud.signals.singleWhere((r) => r.groupId == 'edited-water').value,
        3,
      );
      h.controller.setAppForeground(false);
    },
  );

  test(
    'closing during the quiet period retains changes and restart uploads them',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      h.controller.setAppForeground(true);
      final writes = h.repository.inputPatchCallCount;
      await h.controller.addSignal(SignalType.hydration, 2);
      h.controller.setAppForeground(false);
      final restarted = h.newController();
      await restarted.load();
      expect(h.repository.inputPatchCallCount, writes + 1);
      expect(restarted.signals, hasLength(2));
      expect(restarted.hasPendingCloudChanges, false);
    },
  );

  test(
    'quota permits owned adult saves and Health imports across restart, then safely uploads',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      h.repository.readError = 'resource-exhausted';
      await h.controller.handleAppResumed();
      expect(h.controller.isUsingQuotaLocalData, true);
      expect(h.controller.privacyFeaturesAllowed, true);
      expect(h.controller.privacyOperationError, isNull);
      final writes = h.repository.inputPatchCallCount;
      final scores = h.repository.scoreUpsertCallCount;
      await h.controller.addSignal(SignalType.hydration, 2);
      await h.controller.addCheckIn(energy: 8, mood: 7, stress: 2);
      h.health.authorized = true;
      h.health.imported = [
        SignalReading(
          id: 'healthkit-quota-heart',
          type: SignalType.heartRate,
          value: 71,
          timestamp: h.now,
          source: SignalSource.healthKit,
        ),
      ];
      await h.controller.refreshHealthAuthorization();
      await h.controller.connectHealth();
      expect(h.health.imports, greaterThan(0));
      expect(
        h.controller.signals.map((r) => r.id),
        contains('healthkit-quota-heart'),
      );
      expect(h.controller.hasPendingCloudChanges, true);
      expect(h.repository.inputPatchCallCount, writes);
      expect(h.repository.scoreUpsertCallCount, scores);
      expect(
        h.controller.cloudSyncStatusMessage,
        contains('Logging and Apple Health continue'),
      );
      final signalIds = h.controller.signals.map((r) => r.id).toSet();
      final checkInIds = h.controller.checkIns.map((r) => r.id).toSet();
      // Restored cooldown must still require a fresh Auth check on restart.
      final restarted = h.newController();
      await restarted.load();
      expect(restarted.isUsingQuotaLocalData, true);
      expect(restarted.signals.map((r) => r.id).toSet(), signalIds);
      expect(restarted.checkIns.map((r) => r.id).toSet(), checkInIds);
      await expectLater(
        restarted.retryCloudSync(),
        throwsA(isA<FirebaseException>()),
      );
      expect(restarted.isUsingQuotaLocalData, true);
      expect(restarted.privacyOperationError, isNull);
      // Timer expiry alone is not permission to upload or query derived data.
      h.now = h.now.add(const Duration(hours: 2));
      h.repository.readError = null;
      await restarted.addSignal(SignalType.hydration, 3);
      expect(h.repository.inputPatchCallCount, writes);
      expect(h.repository.scoreUpsertCallCount, scores);
      await restarted.retryCloudSync();
      expect(restarted.isUsingQuotaLocalData, false);
      expect(restarted.hasPendingCloudChanges, false);
      final cloud = (await h.repository.readUser('owner'))!;
      expect(
        cloud.signals.map((r) => r.id).toSet(),
        restarted.signals.map((r) => r.id).toSet(),
      );
      expect(cloud.checkIns.map((r) => r.id).toSet(), checkInIds);
    },
  );

  test(
    'stale startup hydration quota still allows a durable local save',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      h.now = h.now.add(const Duration(hours: 4));
      h.repository.readError = 'resource-exhausted';
      final reads = h.repository.userReads;
      final restarted = h.newController();
      await restarted.load();
      expect(h.repository.userReads, reads + 1);
      expect(restarted.isUsingQuotaLocalData, true);
      await restarted.addSignal(SignalType.hydration, 2);
      final saved =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'tonyo_state_v1',
                )!,
              )
              as Map;
      expect(saved['signals'], hasLength(2));
      expect(restarted.hasPendingCloudChanges, true);
    },
  );

  for (final failure in ['permission-denied']) {
    test(
      '$failure ends quota local permission rather than reusing it',
      () async {
        final h = _Harness(state: _state(receipt: _adult, onboarded: true));
        await h.controller.load();
        h.repository.readError = 'resource-exhausted';
        await h.controller.handleAppResumed();
        expect(h.controller.isUsingQuotaLocalData, true);
        h.repository.readError = failure;
        await expectLater(
          h.controller.retryCloudSync(),
          throwsA(isA<FirebaseException>()),
        );
        expect(h.controller.privacyFeaturesAllowed, false);
        await expectLater(
          h.controller.addSignal(SignalType.hydration, 2),
          throwsStateError,
        );
      },
    );
  }

  test(
    'quota fallback cannot bypass failed fresh Auth on resume or restart',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      h.repository.readError = 'resource-exhausted';
      await h.controller.handleAppResumed();
      expect(h.controller.isUsingQuotaLocalData, true);
      h.auth.failClaims = true;
      await h.controller.handleAppResumed();
      expect(h.controller.privacyFeaturesAllowed, false);
      final restarted = h.newController();
      await restarted.load();
      expect(restarted.privacyFeaturesAllowed, false);
      await expectLater(
        restarted.addSignal(SignalType.hydration, 2),
        throwsStateError,
      );
    },
  );

  for (final receipt in [null, _minor]) {
    test(
      'quota never grants local collection for missing or guardian consent: ${receipt?.ageBand}',
      () async {
        final h = _Harness(state: _state(receipt: receipt, onboarded: true));
        h.auth.grantGuardian = true;
        await h.controller.load();
        h.repository.readError = 'resource-exhausted';
        await h.controller.handleAppResumed();
        expect(h.controller.privacyFeaturesAllowed, false);
        expect(h.controller.isUsingQuotaLocalData, false);
        await expectLater(
          h.controller.addSignal(SignalType.hydration, 2),
          throwsStateError,
        );
      },
    );
  }

  test(
    'quota does not adopt another account cached consent or inputs',
    () async {
      final h = _Harness(state: _state(receipt: _adult, onboarded: true));
      await h.controller.load();
      h.auth.session = const AccountSession(
        uid: 'other',
        email: 'other@example.test',
      );
      h.repository.readError = 'resource-exhausted';
      final restarted = h.newController();
      await restarted.load();
      expect(restarted.privacyFeaturesAllowed, false);
      expect(restarted.isUsingQuotaLocalData, false);
    },
  );

  for (final deleted in [false, true]) {
    test(
      'recovery observes ${deleted ? 'deletion' : 'revoked consent'} before uploading local edits',
      () async {
        final h = _Harness(state: _state(receipt: _adult, onboarded: true));
        await h.controller.load();
        h.repository.readError = 'resource-exhausted';
        await h.controller.handleAppResumed();
        await h.controller.addSignal(SignalType.hydration, 2);
        final writes = h.repository.inputPatchCallCount;
        h.repository.seed(
          'owner',
          _state(onboarded: true).copyWith(deletionPending: deleted),
        );
        h.repository.readError = null;
        await expectLater(h.controller.retryCloudSync(), throwsStateError);
        expect(h.controller.privacyFeaturesAllowed, false);
        expect(h.controller.isUsingQuotaLocalData, false);
        expect(h.repository.inputPatchCallCount, writes);
        expect(h.controller.signals, hasLength(2));
      },
    );
  }

  test(
    'legacy account with no receipt never imports, uploads or adds personal records',
    () async {
      final h = _Harness(state: _state());
      await h.controller.load();
      expect(h.controller.isReady, true);
      expect(h.controller.privacyReviewRequired, true);
      expect(h.health.reads, 0);
      expect(h.screen.reads, 0);
      expect(h.repository.replaceUserCallCount, 0);
      expect(h.repository.inputPatchCallCount, 0);
      expect(h.repository.scoreUpsertCallCount, 0);
      await expectLater(
        h.controller.addSignal(SignalType.hydration, 2),
        throwsStateError,
      );
      await expectLater(
        h.controller.addCheckIn(energy: 8, mood: 7, stress: 2),
        throwsStateError,
      );
      expect(h.controller.signals, hasLength(1));
      expect(h.controller.checkIns, hasLength(1));
      expect(h.repository.replaceUserCallCount, 0);
      expect(h.repository.inputPatchCallCount, 0);
    },
  );

  test(
    'explicit adult acknowledgement does not opt into learning or rewrite logs',
    () async {
      final h = _Harness(state: _state());
      await h.controller.load();
      await expectLater(
        h.controller.acceptPrivacy(
          ageBand: PrivacyAgeBand.adult,
          region: PrivacyRegion.us,
          acknowledged: false,
        ),
        throwsArgumentError,
      );
      expect(h.repository.privacyWrites, 0);
      await h.controller.acceptPrivacy(
        ageBand: PrivacyAgeBand.adult,
        region: PrivacyRegion.us,
        acknowledged: true,
      );
      expect(h.controller.privacyFeaturesAllowed, true);
      expect(h.controller.privacyConsent?.acceptedAt, _now);
      expect(h.controller.outcomeConsent, false);
      expect(h.repository.privacyWrites, 1);
      expect(h.repository.outcomeWrites, 0);
      expect(h.repository.replaceUserCallCount, 0);
      expect(h.repository.inputPatchCallCount, 0);
      await h.controller.setOutcomeConsent(true);
      expect(h.controller.outcomeConsent, true);
      expect(h.controller.outcomeConsentUpdatedAt, _now);
      expect(h.repository.outcomeWrites, 1);
      await h.controller.setOutcomeConsent(false);
      expect(h.controller.outcomeConsent, false);
      expect(h.repository.outcomeWrites, 2);
      expect(h.repository.replaceUserCallCount, 0);
      expect(h.repository.inputPatchCallCount, 0);
    },
  );

  test(
    'unverified minor is blocked while fresh trusted guardian claims unlock permitted work',
    () async {
      final h = _Harness(state: _state(receipt: _minor));
      await h.controller.load();
      expect(h.controller.guardianConsentBlocker, isNotNull);
      expect(h.controller.privacyFeaturesAllowed, false);
      expect(h.health.reads, 0);
      expect(h.repository.inputPatchCallCount, 0);
      await expectLater(
        h.controller.acceptPrivacy(
          ageBand: PrivacyAgeBand.adult,
          region: PrivacyRegion.us,
          acknowledged: true,
        ),
        throwsStateError,
      );
      await expectLater(h.controller.setOutcomeConsent(true), throwsStateError);
      h.auth.grantGuardian = true;
      await h.controller.handleAppResumed();
      expect(h.auth.claimRefreshes, 2);
      expect(h.repository.privacyReads, 1);
      expect(h.controller.guardianConsentVerified, true);
      expect(h.controller.privacyFeaturesAllowed, true);
      // Foreground recovery now flushes pending preference metadata once
      // fresh guardian verification allows uploads.
      expect(h.repository.inputPatchCallCount, 1);
      await h.controller.addSignal(SignalType.hydration, 1);
      expect(h.repository.inputPatchCallCount, 2);
      expect(h.repository.replaceUserCallCount, 0);
      final saved = (await h.repository.readUser('owner'))!;
      expect(saved.signals, hasLength(2));
      expect(
        saved.signals.singleWhere((signal) => signal.id != 'saved').value,
        1,
      );
      expect(
        saved.signals.singleWhere((signal) => signal.id == 'saved').value,
        1.5,
      );
    },
  );

  test(
    'local underage setup cannot turn a checkbox into guardian approval',
    () async {
      final controller = AppController(
        healthService: _Health([]),
        clock: () => _now,
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.acceptPrivacy(
          ageBand: PrivacyAgeBand.under13,
          region: PrivacyRegion.unknown,
          acknowledged: true,
        ),
        throwsStateError,
      );
      expect(controller.privacyConsent, isNull);
      expect(controller.privacyFeaturesAllowed, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tonyo_state_v1'), isNull);
    },
  );

  test(
    'remote revocation or offline privacy confirmation pauses new collection',
    () async {
      final h = _Harness(state: _state(receipt: _adult, consent: true));
      await h.controller.load();
      expect(h.controller.privacyFeaturesAllowed, true);
      h.repository.seed('owner', _state(receipt: _adult, consent: false));
      await h.controller.handleAppResumed();
      expect(h.controller.outcomeConsent, false);
      expect(h.repository.privacyReads, 1);
      final reads = h.health.reads;
      h.repository.failPrivacyRead = true;
      await h.controller.handleAppResumed();
      expect(h.controller.privacyFeaturesAllowed, false);
      expect(h.health.reads, reads);
      expect(h.health.disables, greaterThan(0));
      await expectLater(
        h.controller.addSignal(SignalType.hydration, 1),
        throwsStateError,
      );
    },
  );

  test(
    'wrong password changes no tracking data, cache, observers or account',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      await h.controller.load();
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString('tonyo_state_v1');
      h.events.clear();
      final clears = h.models.clears;
      await expectLater(
        h.controller.deleteAccountData(password: 'wrong'),
        throwsStateError,
      );
      expect(h.events, ['reauth']);
      expect(h.repository.deletes, 0);
      expect(h.auth.deletes, 0);
      expect(h.models.clears, clears);
      expect(h.controller.deletionPending, false);
      expect(prefs.getString('tonyo_state_v1'), before);
      expect(prefs.getString('tonyo_privacy_deletion_v1'), isNull);
      expect(h.auth.currentSession?.uid, 'owner');
    },
  );

  test(
    'deletion verifies password first then cloud, Auth and device data in order',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      await h.controller.load();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('unrelated-host-setting', 'keep');
      h.events.clear();
      await h.controller.deleteAccountData(password: 'right');
      expect(h.events.first, 'reauth');
      expect(
        h.events.indexOf('cloud-delete'),
        greaterThan(h.events.indexOf('reauth')),
      );
      expect(
        h.events.indexOf('auth-delete'),
        greaterThan(h.events.indexOf('cloud-delete')),
      );
      expect(
        h.events.indexOf('model-clear'),
        greaterThan(h.events.indexOf('auth-delete')),
      );
      expect(h.auth.currentSession, isNull);
      expect(h.controller.signals, isEmpty);
      expect(h.controller.checkIns, isEmpty);
      expect(h.controller.onboardingComplete, false);
      expect(h.controller.deletionPending, false);
      expect(prefs.getString('tonyo_state_v1'), isNull);
      expect(prefs.getString('tonyo_privacy_deletion_v1'), isNull);
      expect(prefs.getString('unrelated-host-setting'), 'keep');
    },
  );

  test(
    'partial deletion persists a pause across restart and retries safely',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      await h.controller.load();
      h.repository.failDelete = true;
      await expectLater(
        h.controller.deleteAccountData(password: 'right'),
        throwsStateError,
      );
      expect(h.controller.deletionPending, true);
      expect(h.controller.privacyFeaturesAllowed, false);
      expect(h.auth.deletes, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('tonyo_privacy_deletion_v1')!)['stage'],
        'requested',
      );
      final restarted = h.newController();
      final reads = h.repository.userReads;
      await restarted.load();
      expect(restarted.deletionPending, true);
      expect(h.repository.userReads, reads);
      await expectLater(
        restarted.addSignal(SignalType.hydration, 1),
        throwsStateError,
      );
      h.repository.failDelete = false;
      await restarted.deleteAccountData(password: 'right');
      expect(h.repository.deletes, 2);
      expect(h.auth.deletes, 1);
      expect(restarted.deletionPending, false);
      expect(prefs.getString('tonyo_privacy_deletion_v1'), isNull);
    },
  );

  test(
    'interrupted deletion without Auth offers device-only cleanup without cloud claims',
    () async {
      SharedPreferences.setMockInitialValues({
        'tonyo_privacy_deletion_v1': jsonEncode({
          'owner': 'owner',
          'stage': 'requested',
        }),
        'tonyo_state_v1': jsonEncode({
          'onboardingComplete': true,
          'signals': [],
          'checkIns': [],
        }),
        'tonyo_ml_prep_v1_owner': '{}',
        'tonyo_energy_model_v1_owner': '{}',
        'unrelated-host-setting': 'keep',
      });
      final h = _Harness(state: _state(receipt: _adult));
      h.auth.session = null;
      await h.controller.load();
      expect(h.controller.deletionPending, true);
      expect(h.repository.userReads, 0);
      await h.controller.clearDeviceAfterInterruptedDeletion();
      expect(h.repository.deletes, 0);
      expect(h.auth.deletes, 0);
      expect(h.auth.reauths, 0);
      expect(h.controller.deletionPending, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'unrelated-host-setting'});
    },
  );

  test(
    'Auth-deleted journal survives local cleanup failure and restart retries only device cleanup',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      await h.controller.load();
      h.models.failClear = true;
      await expectLater(
        h.controller.deleteAccountData(password: 'right'),
        throwsStateError,
      );
      expect(h.auth.currentSession, isNull);
      expect(h.repository.deletes, 1);
      expect(h.auth.deletes, 1);
      expect(h.controller.deletionPending, true);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('tonyo_privacy_deletion_v1')!)['stage'],
        'authDeleted',
      );
      final restarted = h.newController();
      await restarted.load();
      expect(restarted.deletionPending, true);
      h.models.failClear = false;
      await restarted.deleteAccountData();
      expect(h.repository.deletes, 1);
      expect(h.auth.deletes, 1);
      expect(h.auth.reauths, 1);
      expect(restarted.deletionPending, false);
      expect(prefs.getString('tonyo_state_v1'), isNull);
      expect(prefs.getString('tonyo_privacy_deletion_v1'), isNull);
    },
  );

  test(
    'offline Auth privacy refresh finishes startup in a paused state',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      h.auth.failClaims = true;
      await h.controller.load();
      expect(h.controller.isReady, true);
      expect(h.controller.privacyFeaturesAllowed, false);
      expect(h.health.reads, 0);
      expect(h.repository.replaceUserCallCount, 0);
      expect(h.repository.inputPatchCallCount, 0);
      expect(h.controller.privacyOperationError, isNotNull);
    },
  );

  test(
    'remote deletion marker pauses this device without recreating user data',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      await h.controller.load();
      h.repository.seed(
        'owner',
        _state(receipt: _adult).copyWith(deletionPending: true),
      );
      final writes =
          h.repository.replaceUserCallCount + h.repository.inputPatchCallCount;
      await h.controller.handleAppResumed();
      expect(h.controller.deletionPending, true);
      expect(h.controller.privacyFeaturesAllowed, false);
      await expectLater(
        h.controller.addSignal(SignalType.hydration, 1),
        throwsStateError,
      );
      expect(
        h.repository.replaceUserCallCount + h.repository.inputPatchCallCount,
        writes,
      );
      expect(h.auth.deletes, 0);
    },
  );

  test(
    'remaining cloud data and only owner caches can be exported during deletion pause',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      await h.controller.load();
      h.repository.failDelete = true;
      await expectLater(
        h.controller.deleteAccountData(password: 'right'),
        throwsStateError,
      );
      final prefs = await SharedPreferences.getInstance();
      final ownKey =
          'tonyo_energy_model_v1_${base64Url.encode(utf8.encode('owner'))}';
      final otherKey =
          'tonyo_energy_model_v1_${base64Url.encode(utf8.encode('other'))}';
      await prefs.setString(
        ownKey,
        jsonEncode({
          'ownerKey': prepFingerprint({'uid': 'owner'}),
          'model': null,
        }),
      );
      await prefs.setString(
        otherKey,
        jsonEncode({
          'ownerKey': prepFingerprint({'uid': 'other'}),
          'secret': 'exclude',
        }),
      );
      // Generate real envelopes through MlPrepService. Snapshot JSON contains
      // no UID, and identical content can belong to different account owners.
      final ownPrep = await _realPrepCache('owner');
      final otherPrep = await _realPrepCache('other');
      final ownPrepKey = 'tonyo_ml_prep_v1_${ownPrep.$1}';
      final otherPrepKey = 'tonyo_ml_prep_v1_${otherPrep.$1}';
      expect(
        (jsonDecode(ownPrep.$2) as Map)['snapshot'],
        isNot(contains('uid')),
      );
      expect(
        (jsonDecode(ownPrep.$2) as Map)['snapshot'],
        (jsonDecode(otherPrep.$2) as Map)['snapshot'],
      );
      await prefs.setString(ownPrepKey, ownPrep.$2);
      await prefs.setString(otherPrepKey, otherPrep.$2);
      await prefs.setString(
        'tonyo_ml_prep_v1_corrupt',
        jsonEncode({
          'uid': 'owner',
          'snapshot': {'uid': 'owner'},
        }),
      );
      final windowKey =
          'tonyo_ml_prep_window_v1_${prepFingerprint({'uid': 'owner'})}';
      final otherWindowKey =
          'tonyo_ml_prep_window_v1_${prepFingerprint({'uid': 'other'})}';
      final window = PrepWindow.endingOn(_now, timezone: 'UTC').toJson();
      await prefs.setString(windowKey, jsonEncode(window));
      await prefs.setString(otherWindowKey, jsonEncode(window));
      final writes =
          h.repository.replaceUserCallCount + h.repository.inputPatchCallCount;
      final exported = jsonDecode(await h.controller.exportAllData()) as Map;
      expect((exported['cloud'] as Map)['userDocument'], isNotNull);
      expect(
        ((exported['cloud'] as Map)['collections'] as Map)['signals'],
        hasLength(1),
      );
      final local = exported['local'] as Map;
      expect(local['privacyOwnerUid'], 'owner');
      final caches = local['derivedCaches'] as Map;
      expect(caches.keys, containsAll([ownKey, ownPrepKey, windowKey]));
      expect(caches[ownPrepKey], jsonDecode(ownPrep.$2));
      expect(caches.keys, isNot(contains(otherKey)));
      expect(caches.keys, isNot(contains(otherPrepKey)));
      expect(caches.keys, isNot(contains(otherWindowKey)));
      expect(caches.keys, isNot(contains('tonyo_ml_prep_v1_corrupt')));
      expect(
        h.repository.replaceUserCallCount + h.repository.inputPatchCallCount,
        writes,
      );
      expect(h.controller.deletionPending, true);
    },
  );

  test(
    'account switching during export returns no previous-owner result',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      await h.controller.load();
      h.repository.pendingExport = Completer<Map<String, Object?>>();
      final exporting = h.controller.exportAllData();
      h.auth.session = const AccountSession(
        uid: 'other',
        email: 'other@example.test',
      );
      h.repository.pendingExport!.complete({'private': 'old owner'});
      await expectLater(exporting, throwsStateError);
      expect(h.controller.isExportingData, false);
      expect(h.controller.privacyOperationError, contains('No partial export'));
    },
  );

  test(
    'account change immediately after reauthentication prevents all deletion',
    () async {
      final h = _Harness(state: _state(receipt: _adult));
      await h.controller.load();
      h.auth.afterReauth = () => h.auth.session = const AccountSession(
        uid: 'other',
        email: 'other@example.test',
      );
      h.events.clear();
      await expectLater(
        h.controller.deleteAccountData(password: 'right'),
        throwsStateError,
      );
      expect(h.events, ['reauth']);
      expect(h.repository.deletes, 0);
      expect(h.auth.deletes, 0);
      expect(h.controller.deletionPending, false);
    },
  );
}

Future<(String, String)> _realPrepCache(String uid) async {
  final cache = MemoryPrepCache();
  final window = PrepWindow.endingOn(_now, timezone: 'UTC');
  await MlPrepService(source: _CacheOnlySource(uid), cache: cache).prepare(
    window: window,
    loadedSnapshot: PrepSnapshot(
      uid: uid,
      window: window,
      consent: const PrepConsent(
        collection: false,
        trainingUse: false,
        version: 0,
      ),
      fetchedAt: _now,
      schemaVersion: cloudSchemaVersion,
      signals: const [],
      checkIns: const [],
      outcomes: const [],
    ),
  );
  return (cache.values.keys.single, cache.values.values.single);
}

class _CacheOnlySource implements PrepDataSource {
  _CacheOnlySource(this.currentUid);
  @override
  final String currentUid;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Cache fixture must not read source data');
}

class _Harness {
  _Harness({required CloudUserState state}) {
    auth = _Auth(events);
    repository = _Repository(events)..seed('owner', state);
    health = _Health(events);
    screen = _Screen();
    notifications = _Notifications(events);
    models = _Models(events);
    controller = newController();
  }
  final events = <String>[];
  DateTime now = _now;
  late final _Auth auth;
  late final _Repository repository;
  late final _Health health;
  late final _Screen screen;
  late final _Notifications notifications;
  late final _Models models;
  late final AppController controller;

  AppController newController() {
    final controller = AppController(
      accountAuth: auth,
      cloudRepository: repository,
      healthService: health,
      screenTimeService: screen,
      notificationService: notifications,
      energyModelStore: models,
      clock: () => now,
    );
    addTearDown(controller.dispose);
    return controller;
  }
}

class _Auth extends MemoryAccountAuth {
  _Auth(this.events) : super(session: _session, expectedPassword: 'right');
  final List<String> events;
  int claimRefreshes = 0;
  int reauths = 0;
  int deletes = 0;
  bool grantGuardian = false;
  bool failClaims = false;
  String? claimsError;
  Completer<void>? claimsGate;
  void Function()? afterReauth;
  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    if (password != expectedPassword) {
      throw FirebaseException(plugin: 'firebase_auth', code: 'wrong-password');
    }
    session = email == _session.email
        ? _session
        : AccountSession(uid: 'other', email: email);
    return session!;
  }

  @override
  Future<void> refreshPrivacyClaims() async {
    claimRefreshes++;
    await claimsGate?.future;
    if (failClaims) throw StateError('offline token verification');
    if (claimsError != null) {
      throw FirebaseException(plugin: 'firebase_auth', code: claimsError!);
    }
    if (session != null) {
      session = AccountSession(
        uid: session!.uid,
        email: session!.email,
        guardianConsentVerified: grantGuardian,
      );
    }
  }

  @override
  Future<void> reauthenticate({required String password}) async {
    reauths++;
    events.add('reauth');
    await super.reauthenticate(password: password);
    afterReauth?.call();
  }

  @override
  Future<void> deleteCurrentAccount() async {
    deletes++;
    events.add('auth-delete');
    await super.deleteCurrentAccount();
  }
}

class _Repository extends MemoryCloudRepository {
  _Repository(this.events) : super(signedInUid: 'owner', now: () => _now);
  final List<String> events;
  int userReads = 0;
  int privacyReads = 0;
  int privacyWrites = 0;
  int outcomeWrites = 0;
  int deletes = 0;
  bool failPrivacyRead = false;
  String? readError;
  void checkRead() {
    if (readError != null) {
      throw FirebaseException(plugin: 'cloud_firestore', code: readError!);
    }
  }

  bool failDelete = false;
  Completer<Map<String, Object?>>? pendingExport;
  @override
  Future<CloudUserState?> readUser(String uid) {
    userReads++;
    checkRead();
    return super.readUser(uid);
  }

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) {
    privacyReads++;
    checkRead();
    if (failPrivacyRead) throw StateError('offline');
    return super.readAccountPrivacy(uid);
  }

  @override
  Future<PrivacyConsent> savePrivacyConsent(
    String uid,
    PrivacyConsent receipt,
  ) {
    privacyWrites++;
    return super.savePrivacyConsent(uid, receipt);
  }

  @override
  Future<DateTime> saveOutcomeConsent(String uid, bool enabled) {
    outcomeWrites++;
    return super.saveOutcomeConsent(uid, enabled);
  }

  @override
  Future<void> deleteUserTree(String uid) async {
    deletes++;
    events.add('cloud-delete');
    if (failDelete) {
      await super.clearScoreSnapshots(uid);
      throw StateError('interrupted cloud deletion');
    }
    await super.deleteUserTree(uid);
  }

  @override
  Future<Map<String, Object?>> exportUser(String uid) =>
      pendingExport?.future ?? super.exportUser(uid);
}

class _Health extends HealthService {
  _Health(this.events);
  final List<String> events;
  int reads = 0;
  int disables = 0;
  bool authorized = false;
  int imports = 0;
  List<SignalReading> imported = [];
  @override
  Future<HealthAuthorizationState> requestAuthorization() =>
      authorizationStatus();
  @override
  Future<bool> enableBackgroundUpdates(Future<void> Function() changed) async =>
      true;
  @override
  Future<List<SignalReading>> sync({bool recentOnly = false}) async {
    imports++;
    return imported;
  }

  @override
  Future<List<SignalReading>> syncSleep() async => [];
  @override
  Future<List<SignalReading>> syncActivity() async => [];

  @override
  Future<HealthAuthorizationState> authorizationStatus() async {
    reads++;
    return authorized
        ? HealthAuthorizationState.authorized
        : HealthAuthorizationState.unavailable;
  }

  @override
  Future<void> disableBackgroundUpdates() async {
    disables++;
    events.add('health-disable');
  }
}

class _Screen extends ScreenTimeService {
  int reads = 0;
  @override
  Future<ScreenTimeAuthorizationState> authorizationStatus() async {
    reads++;
    return ScreenTimeAuthorizationState.unavailable;
  }
}

class _Notifications implements NotificationService {
  _Notifications(this.events);
  final List<String> events;
  @override
  bool get supportsScheduling => false;
  @override
  Future<void> cancelGuidance() async {
    events.add('notification-cancel');
  }

  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.unavailable;
  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.unavailable;
  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {}
}

class _Models extends MemoryEnergyModelStore {
  _Models(this.events);
  final List<String> events;
  int clears = 0;
  bool failClear = false;
  @override
  Future<void> clear() async {
    clears++;
    events.add('model-clear');
    if (failClear) throw StateError('Device cache clear failed');
    await super.clear();
  }
}
