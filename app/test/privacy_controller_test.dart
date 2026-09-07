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

CloudUserState _state({PrivacyConsent? receipt, bool consent = false}) =>
    CloudUserState(
      profile: const UserProfile(name: 'Private owner'),
      accountEmail: _session.email,
      onboardingComplete: false,
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
    'legacy account with no receipt never imports, uploads or adds personal records',
    () async {
      final h = _Harness(state: _state());
      await h.controller.load();
      expect(h.controller.isReady, true);
      expect(h.controller.privacyReviewRequired, true);
      expect(h.health.reads, 0);
      expect(h.screen.reads, 0);
      expect(h.repository.replaceUserCallCount, 0);
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
      await h.controller.setOutcomeConsent(true);
      expect(h.controller.outcomeConsent, true);
      expect(h.controller.outcomeConsentUpdatedAt, _now);
      expect(h.repository.outcomeWrites, 1);
      await h.controller.setOutcomeConsent(false);
      expect(h.controller.outcomeConsent, false);
      expect(h.repository.outcomeWrites, 2);
      expect(h.repository.replaceUserCallCount, 0);
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
      await h.controller.addSignal(SignalType.hydration, 1);
      expect(h.repository.replaceUserCallCount, 1);
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
      final writes = h.repository.replaceUserCallCount;
      await h.controller.handleAppResumed();
      expect(h.controller.deletionPending, true);
      expect(h.controller.privacyFeaturesAllowed, false);
      await expectLater(
        h.controller.addSignal(SignalType.hydration, 1),
        throwsStateError,
      );
      expect(h.repository.replaceUserCallCount, writes);
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
      final writes = h.repository.replaceUserCallCount;
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
      expect(h.repository.replaceUserCallCount, writes);
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
      clock: () => _now,
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
  void Function()? afterReauth;
  @override
  Future<void> refreshPrivacyClaims() async {
    claimRefreshes++;
    if (failClaims) throw StateError('offline token verification');
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
  bool failDelete = false;
  Completer<Map<String, Object?>>? pendingExport;
  @override
  Future<CloudUserState?> readUser(String uid) {
    userReads++;
    return super.readUser(uid);
  }

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) {
    privacyReads++;
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
  @override
  Future<HealthAuthorizationState> authorizationStatus() async {
    reads++;
    return HealthAuthorizationState.unavailable;
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
