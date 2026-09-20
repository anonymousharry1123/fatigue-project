import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

CloudUserState _state({
  UserProfile profile = const UserProfile(name: 'Owner'),
  bool notificationsEnabled = false,
  bool healthAuthorized = false,
  List<SignalReading> signals = const [],
}) => CloudUserState(
  profile: profile,
  accountEmail: 'owner@example.com',
  onboardingComplete: false,
  notificationsEnabled: notificationsEnabled,
  outcomeConsent: false,
  healthAuthorized: healthAuthorized,
  signals: signals,
  checkIns: const [],
  migrationVersion: localMigrationVersion,
  notificationPrefsVersion: notificationPreferencesVersion,
);

InputSyncSnapshot _snapshot(Map<String, dynamic> root) =>
    InputSyncSnapshot(root: root, signals: {}, checkIns: {});

void main() {
  test(
    'independent profile edits merge while new phone records upload',
    () async {
      final baseline = InputSyncSnapshot.fromState(_state());
      final restoredJournal = InputSyncSnapshot.fromJson(baseline.toJson());
      final reading = SignalReading(
        id: 'phone-only',
        type: SignalType.hydration,
        value: 2,
        timestamp: DateTime.utc(2026, 9, 20, 12),
      );
      final patch = InputSyncPatch(
        restoredJournal,
        InputSyncSnapshot.fromState(
          _state(
            profile: const UserProfile(name: 'Updated name'),
            signals: [reading],
          ),
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'owner')
        ..seed(
          'owner',
          _state(profile: const UserProfile(name: 'Owner', bedHour: 22)),
        );

      await repository.applyInputPatch('owner', patch);
      // Retrying after a lost acknowledgement remains safe.
      await repository.applyInputPatch('owner', patch);

      final saved = (await repository.readUser('owner'))!;
      expect(saved.profile.name, 'Updated name');
      expect(saved.profile.bedHour, 22);
      expect(saved.signals.single.id, reading.id);
      expect(patch.root.keys, ['profile.name']);
    },
  );

  test(
    'independent preference edits preserve the other device choice',
    () async {
      final patch = InputSyncPatch(
        InputSyncSnapshot.fromState(_state()),
        InputSyncSnapshot.fromState(_state(notificationsEnabled: true)),
      );
      final repository = MemoryCloudRepository(signedInUid: 'owner')
        ..seed('owner', _state(healthAuthorized: true));

      await repository.applyInputPatch('owner', patch);

      final saved = (await repository.readUser('owner'))!;
      expect(saved.notificationsEnabled, true);
      expect(saved.healthAuthorized, true);
    },
  );

  test('a conflicting change to the same profile field still fails closed', () {
    final patch = InputSyncPatch(
      InputSyncSnapshot.fromState(_state()),
      InputSyncSnapshot.fromState(
        _state(profile: const UserProfile(name: 'Phone name')),
      ),
    );
    final remote = InputSyncSnapshot.fromState(
      _state(profile: const UserProfile(name: 'Other phone name')),
    );

    expect(() => patch.checkAgainst(remote), throwsA(isA<InputSyncConflict>()));
  });

  test(
    'cleared nested fields preserve unknown and concurrently changed fields',
    () {
      final before = _snapshot({
        'healthSync': {'reason': 'manual', 'status': 'idle'},
      });
      final after = _snapshot({
        'healthSync': {'status': 'idle'},
      });
      final remote = _snapshot({
        'healthSync': {
          'reason': 'manual',
          'status': 'success',
          'serverMetadata': {'source': 'verified'},
        },
      });
      final patch = InputSyncPatch(before, after);

      patch.checkAgainst(remote);
      final merged = remote.overlay(patch);
      final health = merged.root['healthSync'] as Map;
      expect(health['reason'], isNull);
      expect(health['status'], 'success');
      expect(health['serverMetadata'], {'source': 'verified'});
      expect((remote.root['healthSync'] as Map)['reason'], 'manual');
      expect(
        syncMergedData(patch.rootData(useBefore: true), patch.rootData()),
        {
          'healthSync': {'reason': null},
        },
      );
      // Restoring the retry baseline only restores the changed field.
      expect(
        sameSyncValue(merged.overlay(patch, useBefore: true).root, remote.root),
        true,
      );
      patch.checkAgainst(merged);
    },
  );

  test(
    'removing a known map leaves unknown children out of the cloud write',
    () {
      final patch = InputSyncPatch(
        _snapshot({
          'healthSync': {'reason': 'manual'},
        }),
        _snapshot({}),
      );
      final remote = _snapshot({
        'healthSync': {'reason': 'manual', 'unknown': 'preserve'},
      });

      patch.checkAgainst(remote);
      expect(remote.overlay(patch).root['healthSync'], {
        'reason': null,
        'unknown': 'preserve',
      });
      expect(patch.rootData(), {
        'healthSync': {'reason': null},
      });
    },
  );

  test(
    'nested time edits remain Firestore timestamps after journal replay',
    () {
      final instant = DateTime.utc(2026, 9, 20, 12);
      final patch = InputSyncPatch(
        _snapshot({'healthSync': <String, dynamic>{}}),
        _snapshot({
          'healthSync': {'lastAttemptAt': instant.toIso8601String()},
        }),
      );

      expect(
        syncMergedData(patch.rootData(useBefore: true), patch.rootData()),
        {
          'healthSync': {'lastAttemptAt': instant},
        },
      );
    },
  );
}
