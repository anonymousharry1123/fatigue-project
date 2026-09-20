import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The preferences plugin's test platform is used to simulate storage failures.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'privacy_test_support.dart';

final _now = DateTime(2026, 9, 20, 12);
SignalReading _signal(String id, [double value = 2]) => SignalReading(
  id: id,
  type: SignalType.study,
  value: value,
  timestamp: _now,
  recordedAt: _now,
);

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.empty();
  Completer<bool>? gate;
  final started = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.tonyo_state_v1' && gate != null) {
      final pending = gate!;
      gate = null;
      if (!started.isCompleted) started.complete();
      if (!await pending.future) return false;
    }
    return super.setValue(type, key, value);
  }
}

class _Repository extends MemoryCloudRepository {
  _Repository() : super(signedInUid: 'owner');
  bool offline = false;
  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    if (offline) throw StateError('offline');
    return super.applyInputPatch(uid, patch);
  }
}

AppController _local() => AppController(
  initialPrivacyConsent: testAdultPrivacyConsent,
  clock: () => _now,
);

Future<String> _file(List<SignalReading> signals, {String? owner}) async {
  final source = _local()..signals = signals;
  final file =
      jsonDecode(await source.exportDeviceBackup()) as Map<String, dynamic>;
  source.dispose();
  file['ownerUid'] = owner;
  file['local']['privacyOwnerUid'] = owner;
  return jsonEncode(file);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
  });

  test(
    'preview does not mutate, restore merges IDs and is idempotent',
    () async {
      final app = _local()
        ..signals = [_signal('already'), _signal('phone-only')];
      addTearDown(app.dispose);
      final raw = await _file([_signal('already'), _signal('backup-only')]);
      final preview = app.previewDeviceBackup(raw);
      expect(preview.newRecords, 1);
      expect(preview.duplicates, 1);
      expect(app.signals, hasLength(2));
      await app.restoreDeviceBackup(preview);
      expect(app.signals.map((item) => item.id).toSet(), {
        'already',
        'phone-only',
        'backup-only',
      });
      final replay = app.previewDeviceBackup(raw);
      expect(replay.newRecords, 0);
      expect(replay.duplicates, 2);
      await app.restoreDeviceBackup(replay);
      expect(app.signals, hasLength(3));
      final persisted = jsonDecode(
        (await SharedPreferences.getInstance()).getString('tonyo_state_v1')!,
      );
      expect(persisted['signals'], hasLength(3));
    },
  );

  test('differing rows and profile require explicit replacement', () async {
    final app = _local()
      ..signals = [_signal('same', 4)]
      ..profile = const UserProfile(name: 'Current owner');
    addTearDown(app.dispose);
    final raw = await _file([_signal('same', 2), _signal('new')]);
    final preview = app.previewDeviceBackup(raw);
    expect(preview.differingRecords, 1);
    expect(preview.profileDiffers, true);
    await app.restoreDeviceBackup(preview);
    expect(app.signals.singleWhere((item) => item.id == 'same').value, 4);
    expect(app.profile.name, 'Current owner');
    await app.restoreDeviceBackup(
      app.previewDeviceBackup(raw),
      replaceExisting: true,
      restoreProfile: true,
    );
    expect(app.signals.singleWhere((item) => item.id == 'same').value, 2);
    expect(app.profile.name, const UserProfile().name);
    expect(app.privacyConsent, testAdultPrivacyConsent);
    expect(app.notificationsEnabled, false);
    expect(app.healthAuthorized, false);
  });

  test('new local edits invalidate an old preview', () async {
    final app = _local();
    addTearDown(app.dispose);
    final preview = app.previewDeviceBackup(await _file([_signal('backup')]));
    await app.addSignal(SignalType.hydration, 1);
    await expectLater(app.restoreDeviceBackup(preview), throwsStateError);
    expect(app.signals.single.type, SignalType.hydration);
  });

  test(
    'imported learning outcomes follow retained phone source values',
    () async {
      final source = _local()
        ..outcomeConsent = true
        ..outcomeConsentUpdatedAt = _now;
      addTearDown(source.dispose);
      await source.addCheckIn(id: 'check', energy: 3, mood: 5, stress: 5);
      await source.addReactionResult(350, resultId: 'reaction');
      final raw = await source.exportDeviceBackup();
      final app = _local()
        ..outcomeConsent = true
        ..outcomeConsentUpdatedAt = _now
        ..checkIns = [
          DailyCheckIn(
            id: 'check',
            timestamp: _now,
            recordedAt: _now,
            energy: 8,
            mood: 5,
            stress: 5,
            period: CheckInPeriod.morning,
          ),
        ]
        ..signals = [
          SignalReading(
            id: 'reaction',
            type: SignalType.reactionTime,
            value: 500,
            timestamp: _now,
            recordedAt: _now,
          ),
        ];
      addTearDown(app.dispose);
      await app.restoreDeviceBackup(app.previewDeviceBackup(raw));
      expect(app.checkIns.single.energy, 8);
      expect(app.signals.single.value, 500);
      expect(
        {for (final item in app.outcomes) item.id: item.value},
        {'energy-checkin-check': 8, 'reaction-reaction': 500},
      );
      final replay = app.previewDeviceBackup(raw);
      expect(replay.newRecords, 0);
      final before = app.outcomes.map((item) => item.toJson()).toList();
      await app.restoreDeviceBackup(replay);
      expect(app.outcomes.map((item) => item.toJson()).toList(), before);
      final restarted = _local();
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.outcomes.map((item) => item.toJson()).toList(), before);
    },
  );

  for (final replace in [false, true]) {
    test(
      'source replacement $replace keeps existing learning results consistent without backup outcomes',
      () async {
        final source = _local();
        addTearDown(source.dispose);
        await source.addCheckIn(id: 'check', energy: 3, mood: 5, stress: 5);
        await source.addReactionResult(350, resultId: 'reaction');
        await source.addSignal(SignalType.hydration, 1);
        final raw = await source.exportDeviceBackup();
        final app = _local()
          ..outcomeConsent = true
          ..outcomeConsentUpdatedAt = _now;
        addTearDown(app.dispose);
        await app.addCheckIn(id: 'check', energy: 8, mood: 5, stress: 5);
        await app.addReactionResult(500, resultId: 'reaction');
        await app.restoreDeviceBackup(
          app.previewDeviceBackup(raw),
          replaceExisting: replace,
        );
        expect(app.checkIns.single.energy, replace ? 3 : 8);
        expect(
          app.signals.singleWhere((item) => item.id == 'reaction').value,
          replace ? 350 : 500,
        );
        expect(
          {for (final item in app.outcomes) item.id: item.value},
          {
            'energy-checkin-check': replace ? 3 : 8,
            'reaction-reaction': replace ? 350 : 500,
          },
        );
      },
    );
  }

  test(
    'restored cloud inputs remain queued offline and survive restart',
    () async {
      final repo = _Repository()
        ..seed(
          'owner',
          CloudUserState(
            profile: const UserProfile(),
            accountEmail: 'owner@example.com',
            onboardingComplete: false,
            notificationsEnabled: false,
            outcomeConsent: false,
            healthAuthorized: false,
            signals: [_signal('remote')],
            checkIns: const [],
            notificationPrefsVersion: notificationPreferencesVersion,
            migrationVersion: localMigrationVersion,
            privacyConsent: testAdultPrivacyConsent,
          ),
        );
      AppController make() => AppController(
        cloudRepository: repo,
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: 'owner',
            email: 'owner@example.com',
          ),
        ),
        clock: () => _now,
      );
      final app = make();
      await app.load();
      repo.offline = true;
      await app.restoreDeviceBackup(
        app.previewDeviceBackup(
          await _file([_signal('backup')], owner: 'owner'),
        ),
      );
      expect(app.hasPendingCloudChanges, true);
      expect((await repo.readUser('owner'))!.signals.single.id, 'remote');
      app.dispose();
      final restarted = make();
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(
        restarted.signals.map((item) => item.id),
        containsAll(['remote', 'backup']),
      );
      expect(restarted.hasPendingCloudChanges, true);
      repo.offline = false;
      await restarted.retryCloudSync();
      expect(
        (await repo.readUser('owner'))!.signals.map((item) => item.id),
        containsAll(['remote', 'backup']),
      );
      expect(restarted.hasPendingCloudChanges, false);
    },
  );

  for (final persist in [false, true]) {
    test(
      'concurrent device edit survives ${persist ? 'stale successful' : 'failed'} restore write',
      () async {
        final app = _local()..signals = [_signal('original')];
        addTearDown(app.dispose);
        final preview = app.previewDeviceBackup(
          await _file([_signal('backup')]),
        );
        final gate = Completer<bool>();
        store.gate = gate;
        final restore = app.restoreDeviceBackup(preview);
        final failure = expectLater(restore, throwsStateError);
        await store.started.future;
        expect(app.signals.single.id, 'original');
        app.signals.add(_signal('concurrent-edit'));
        gate.complete(persist);
        await failure;
        expect(app.signals.map((item) => item.id).toSet(), {
          'original',
          'concurrent-edit',
        });
        final prefs = await SharedPreferences.getInstance();
        expect(
          (jsonDecode(prefs.getString('tonyo_state_v1')!)['signals'] as List)
              .map((item) => item['id'])
              .toSet(),
          {'original', 'concurrent-edit'},
        );
        final restarted = _local();
        addTearDown(restarted.dispose);
        await restarted.load();
        expect(restarted.signals.map((item) => item.id).toSet(), {
          'original',
          'concurrent-edit',
        });
      },
    );
  }

  test(
    'late staged write cannot recreate data after account deletion',
    () async {
      final app = _local()..signals = [_signal('original')];
      addTearDown(app.dispose);
      final preview = app.previewDeviceBackup(await _file([_signal('backup')]));
      final gate = Completer<bool>();
      store.gate = gate;
      final restore = app.restoreDeviceBackup(preview);
      final failure = expectLater(restore, throwsStateError);
      await store.started.future;
      await app.deleteAccountData();
      gate.complete(true);
      await failure;
      expect(app.signals, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString('tonyo_state_v1'),
        isNull,
      );
    },
  );
}
