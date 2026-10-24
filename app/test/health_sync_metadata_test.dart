import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'polling metadata is absent from input patches while profile edits remain',
    () {
      final before = InputSyncSnapshot.fromState(_state());
      final attempted = InputSyncSnapshot.fromState(
        _state(
          lastSync: DateTime.utc(2026, 10, 24, 12),
          status: HealthSyncStatus.upToDate,
          reason: HealthRefreshReason.foreground,
          background: true,
        ),
      );
      expect(InputSyncPatch(before, attempted).isEmpty, isTrue);
      expect(attempted.root.containsKey('healthSync'), isFalse);
      expect(attempted.root.containsKey('lastHealthSync'), isFalse);
      final edited = InputSyncSnapshot.fromState(
        _state(
          name: 'Edited profile',
          lastSync: DateTime.utc(2026, 10, 24, 13),
          status: HealthSyncStatus.failed,
          reason: HealthRefreshReason.manual,
        ),
      );
      final patch = InputSyncPatch(before, edited);
      expect(patch.root.keys, ['profile.name']);
    },
  );

  test(
    'legacy journal diagnostics do not create deletes or conflict on upgrade',
    () {
      final current = InputSyncSnapshot.fromState(_state());
      final legacy = InputSyncSnapshot.fromJson({
        ...current.toJson(),
        'root': {
          ...current.root,
          'lastHealthSync': '2026-10-23T12:00:00.000Z',
          'healthSync': {
            'status': 'updated',
            'reason': 'background',
            'lastAttemptAt': '2026-10-23T12:00:00.000Z',
            'lastSuccessAt': '2026-10-23T12:00:00.000Z',
            'lastMeaningfulChangeAt': '2026-10-23T12:00:00.000Z',
            'backgroundRefreshEnabled': true,
          },
        },
      });
      expect(InputSyncPatch(legacy, current).isEmpty, isTrue);
      final edited = InputSyncSnapshot.fromState(_state(name: 'New name'));
      final patch = InputSyncPatch(legacy, edited);
      expect(patch.root.keys, ['profile.name']);
      expect(patch.rootData(), {
        'profile': {'name': 'New name'},
      });
      patch.checkAgainst(current);
      expect(legacy.toJson(), current.toJson());
    },
  );

  test(
    'snapshot overlay retains authoritative diagnostics outside the input root',
    () {
      final local = _state(
        lastSync: DateTime.utc(2026, 10, 24, 12),
        status: HealthSyncStatus.partialFailure,
        reason: HealthRefreshReason.background,
        background: true,
      );
      final before = InputSyncSnapshot.fromState(local);
      final patch = InputSyncPatch(
        before,
        InputSyncSnapshot.fromState(_state(name: 'New name')),
      );
      final result = before.overlay(patch).toState(local);
      expect(result.profile.name, 'New name');
      expect(result.lastSync, local.lastSync);
      expect(result.lastHealthSyncAttempt, local.lastHealthSyncAttempt);
      expect(result.lastHealthChangeAt, local.lastHealthChangeAt);
      expect(result.healthSyncStatus, local.healthSyncStatus);
      expect(result.lastHealthRefreshReason, local.lastHealthRefreshReason);
      expect(result.healthBackgroundRefreshEnabled, isTrue);
      expect(result.privacyConsent, local.privacyConsent);
    },
  );

  test(
    'repeated unchanged Health imports keep diagnostics local and write no cloud patch',
    () async {
      var now = DateTime.utc(2026, 10, 24, 12);
      final health = _HealthService(now);
      final repository = _Repository()..seed('owner', _state());
      final app = AppController(
        cloudRepository: repository,
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: 'owner',
            email: 'owner@example.com',
          ),
        ),
        healthService: health,
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => now,
      );
      addTearDown(app.dispose);
      await app.load();
      expect(await app.connectHealth(), isTrue);
      final firstPatches = repository.patches;
      expect(
        firstPatches,
        greaterThan(0),
      ); // Initial HRV input is still uploaded.
      expect(
        (await repository.readUser('owner'))!.signals.single.type,
        SignalType.hrv,
      );
      for (var attempt = 0; attempt < 3; attempt++) {
        now = now.add(const Duration(minutes: 15));
        await app.syncHealth();
        expect(app.lastSync, now);
        expect(app.lastHealthSyncAttempt, now);
        expect(app.healthSyncStatus, HealthSyncStatus.upToDate);
      }
      expect(repository.patches, firstPatches);
      expect(app.hasPendingCloudChanges, isFalse);
      expect(health.reads, 4);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('tonyo_state_v1')!) as Map;
      expect(saved['lastHealthSyncAttempt'], now.toIso8601String());
      expect(saved['lastSync'], now.toIso8601String());
      expect(saved['healthSyncStatus'], 'upToDate');
    },
  );

  test(
    'cloud hydration preserves current device attempts and active observer',
    () async {
      final now = DateTime.utc(2026, 10, 24, 12);
      final health = _HealthService(now);
      final repository = _Repository()..seed('owner', _state());
      final app = AppController(
        cloudRepository: repository,
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: 'owner',
            email: 'owner@example.com',
          ),
        ),
        healthService: health,
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => now,
      );
      addTearDown(app.dispose);
      await app.load();
      await app.connectHealth();
      final status = app.healthSyncStatus;
      final reason = app.lastHealthRefreshReason;
      final changedAt = app.lastHealthChangeAt;
      expect(app.healthBackgroundRefreshEnabled, isTrue);
      repository.seed(
        'owner',
        _state(
          name: 'Updated on another device',
          lastSync: DateTime.utc(2020),
          status: HealthSyncStatus.failed,
          reason: HealthRefreshReason.foreground,
          background: false,
        ),
      );
      await app.useCloudInputs();
      expect(app.profile.name, 'Updated on another device');
      expect(app.lastSync, now);
      expect(app.lastHealthSyncAttempt, now);
      expect(app.lastHealthChangeAt, changedAt);
      expect(app.healthSyncStatus, status);
      expect(app.lastHealthRefreshReason, reason);
      expect(app.healthBackgroundRefreshEnabled, isTrue);
      expect(app.healthAuthorized, isTrue);
    },
  );
}

CloudUserState _state({
  String name = 'Owner',
  DateTime? lastSync,
  HealthSyncStatus status = HealthSyncStatus.idle,
  HealthRefreshReason? reason,
  bool background = false,
}) => CloudUserState(
  profile: UserProfile(name: name),
  accountEmail: 'owner@example.com',
  onboardingComplete: false,
  notificationsEnabled: false,
  notificationPrefsVersion: notificationPreferencesVersion,
  outcomeConsent: false,
  healthAuthorized: true,
  lastSync: lastSync,
  lastHealthSyncAttempt: lastSync,
  lastHealthChangeAt: lastSync,
  healthSyncStatus: status,
  lastHealthRefreshReason: reason,
  healthBackgroundRefreshEnabled: background,
  migrationVersion: localMigrationVersion,
  privacyConsent: testAdultPrivacyConsent,
  signals: const [],
  checkIns: const [],
);

class _Repository extends MemoryCloudRepository {
  _Repository() : super(signedInUid: 'owner');
  int patches = 0;
  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    patches++;
    await super.applyInputPatch(uid, patch);
  }
}

class _HealthService extends HealthService {
  _HealthService(this.at);
  final DateTime at;
  int reads = 0;
  @override
  Future<HealthAuthorizationState> authorizationStatus() async =>
      HealthAuthorizationState.authorized;
  @override
  Future<HealthAuthorizationState> requestAuthorization() async =>
      HealthAuthorizationState.authorized;
  @override
  Future<bool> enableBackgroundUpdates(
    Future<void> Function() onHealthDataChanged,
  ) async => true;
  @override
  Future<void> disableBackgroundUpdates() async {}
  @override
  Future<List<SignalReading>> sync({bool recentOnly = false}) async {
    reads++;
    return [
      SignalReading(
        id: 'healthkit-hrv',
        type: SignalType.hrv,
        value: 52,
        timestamp: at,
        source: SignalSource.healthKit,
      ),
    ];
  }

  @override
  Future<List<SignalReading>> syncSleep() async => [];
  @override
  Future<List<SignalReading>> syncActivity() async => [];
}
