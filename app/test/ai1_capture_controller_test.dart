import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_capture.dart';
import 'package:app/src/ai1_capture_store.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/device_timezone_service.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The preferences test platform provides deterministic durable-save races.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'privacy_test_support.dart';

class _CaptureStore implements Ai1CaptureStore {
  _CaptureStore(this.now);
  final DateTime Function() now;
  final values = <String, String>{};
  bool available = true;
  bool failWrites = false;
  String? blockedReadOwner;
  Completer<void>? readStarted;
  Completer<void>? releaseRead;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<String?> read(String owner) async {
    if (blockedReadOwner == owner) {
      blockedReadOwner = null;
      readStarted?.complete();
      await releaseRead?.future;
    }
    return values[owner];
  }

  @override
  Future<DateTime> write(String owner, String value) async {
    if (failWrites) throw StateError('capture storage failed');
    values[owner] = value;
    return now();
  }

  @override
  Future<void> clear(String owner) async => values.remove(owner);
  @override
  Future<void> clearAll() async => values.clear();
}

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences() : super.empty();
  Completer<bool>? gate;
  Completer<void>? started;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.tonyo_state_v1' && gate != null) {
      final blocked = gate!;
      gate = null;
      started?.complete();
      if (!await blocked.future) return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late _CaptureStore capture;
  late _Preferences preferences;

  setUp(() {
    now = DateTime.utc(2026, 10, 11, 19);
    SharedPreferences.setMockInitialValues({});
    preferences = _Preferences();
    SharedPreferencesStorePlatform.instance = preferences;
    capture = _CaptureStore(() => now);
  });

  Future<AppController> controller() async {
    final app = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
      captureStore: capture,
      clock: () => now,
      deviceTimezoneService: DeviceTimezoneService(
        readIdentifier: () async => 'Etc/UTC',
        clock: () => now,
      ),
    );
    addTearDown(app.dispose);
    await app.load();
    return app;
  }

  Future<void> report(
    AppController app, {
    String id = 'response',
    double? energy = 7,
    String note = '',
    String language = 'en',
  }) => app.saveSelfReportCheckIn(
    id: id,
    period: CheckInPeriod.evening,
    energy: energy,
    fatigue: 3,
    note: note,
    questionnaireLanguage: language,
    questionnaireSnapshot: CheckInMeasurement.snapshot(
      language: language,
      translate: AppLocalizations(language).text,
    ),
  );

  Future<List<Ai1CaptureEntry>> entries() async {
    final journal = Ai1CaptureJournal(store: capture, clock: () => now);
    await journal.load('local');
    return journal.entries;
  }

  test(
    'first privacy acknowledgement discovers capture without enrolling',
    () async {
      final app = AppController(captureStore: capture, clock: () => now);
      addTearDown(app.dispose);
      await app.load();
      expect(app.privacyReviewRequired, isTrue);
      expect(app.ai1CaptureAvailable, isFalse);
      await app.acceptPrivacy(
        ageBand: PrivacyAgeBand.adult,
        region: PrivacyRegion.us,
        acknowledged: true,
      );
      expect(app.ai1CaptureAvailable, isTrue);
      expect(app.ai1CaptureEnabled, isFalse);
      expect(app.ai1CapturedRevisionCount, 0);
      expect(capture.values, isEmpty);
    },
  );

  test(
    'a stale load cannot unload the newer signed-in owner history',
    () async {
      final seed = Ai1CaptureJournal(store: capture, clock: () => now);
      await seed.start('cloud:old-owner');
      await seed.start('cloud:test-uid');
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'old-owner',
          email: 'old@example.test',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'old-owner');
      for (final owner in ['old-owner', 'test-uid']) {
        repository.seed(
          owner,
          CloudUserState(
            privacyConsent: testAdultPrivacyConsent,
            profile: const UserProfile(),
            accountEmail: owner == 'old-owner'
                ? 'old@example.test'
                : 'new@example.test',
            onboardingComplete: false,
            notificationsEnabled: false,
            outcomeConsent: false,
            healthAuthorized: false,
            migrationVersion: localMigrationVersion,
            signals: [],
            checkIns: [],
          ),
        );
      }
      final app = AppController(
        accountAuth: auth,
        cloudRepository: repository,
        captureStore: capture,
        clock: () => now,
      );
      addTearDown(app.dispose);
      capture.blockedReadOwner = 'cloud:old-owner';
      capture.readStarted = Completer<void>();
      capture.releaseRead = Completer<void>();
      final oldLoad = app.load();
      await capture.readStarted!.future;
      repository.signedInUid = 'test-uid';
      final signIn = app.signIn(
        email: 'new@example.test',
        password: 'synthetic',
      );
      // Drain immediate cloud/preferences futures until the new journal load is
      // queued behind the deliberately blocked old-owner read.
      await Future<void>.delayed(Duration.zero);
      expect(app.cloudUid, 'test-uid');
      capture.releaseRead!.complete();
      await Future.wait([oldLoad, signIn]);
      expect(app.ai1CaptureEnabled, isTrue);
      expect(app.ai1CaptureError, isNull);
    },
  );

  test(
    'a cloud owner never inherits local profile capture or enrollment',
    () async {
      final local = await controller();
      await local.setAi1CaptureEnabled(true);
      await report(local);
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'cloud-owner',
          email: 'owner@example.test',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'cloud-owner')
        ..seed(
          'cloud-owner',
          CloudUserState(
            privacyConsent: testAdultPrivacyConsent,
            profile: const UserProfile(),
            accountEmail: 'owner@example.test',
            onboardingComplete: false,
            notificationsEnabled: false,
            outcomeConsent: false,
            healthAuthorized: false,
            migrationVersion: localMigrationVersion,
            signals: [],
            checkIns: [],
          ),
        );
      final cloud = AppController(
        accountAuth: auth,
        cloudRepository: repository,
        captureStore: capture,
        clock: () => now,
        deviceTimezoneService: DeviceTimezoneService(
          readIdentifier: () async => 'Etc/UTC',
          clock: () => now,
        ),
      );
      addTearDown(cloud.dispose);
      await cloud.load();
      expect(cloud.ai1CaptureEnabled, isFalse);
      expect(cloud.ai1CapturedRevisionCount, 0);
      await cloud.setAi1CaptureEnabled(true);
      await report(cloud, id: 'cloud-response');
      expect(cloud.ai1CapturedRevisionCount, 1);
      expect(capture.values.keys.toSet(), {'local', 'cloud:cloud-owner'});
      final exported = jsonDecode(await cloud.exportAllData()) as Map;
      expect(
        exported['scope']['excludes'],
        contains('Device experiment history'),
      );
      await cloud.signOut();
      expect(cloud.ai1CapturedRevisionCount, 0);
      expect(cloud.ai1CaptureEnabled, isFalse);
    },
  );

  test(
    'clearing optional history remains available during privacy review',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      await report(app);
      now = DateTime.utc(2019);
      expect(app.privacyReviewRequired, isTrue);
      await expectLater(app.setAi1CaptureEnabled(true), throwsStateError);
      await app.setAi1CaptureEnabled(false);
      expect(capture.values, isEmpty);
      expect(app.checkIns, hasLength(1));
    },
  );

  test('unsupported history identity does not break ordinary saves', () async {
    final app = await controller();
    final longId = List.filled(201, 'x').join();
    await report(app, id: longId);
    expect(app.checkIns, hasLength(1));
    await app.setAi1CaptureEnabled(true);
    await report(app, id: '${longId}y');
    expect(app.checkIns, hasLength(2));
    expect(app.ai1CaptureEnabled, isFalse);
    expect(app.ai1CaptureError, isNotNull);
  });

  test(
    'backup replacement purges old evidence and never imports history',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      await report(app);
      final backup = jsonDecode(await app.exportDeviceBackup()) as Map;
      expect(
        backup['scope']['excludes'],
        contains('Device experiment history'),
      );
      backup['local']['checkIns'][0]['energy'] = 9;
      final preview = app.previewDeviceBackup(jsonEncode(backup));
      await app.restoreDeviceBackup(preview, replaceExisting: true);
      expect(app.checkIns.single.energy, 9);
      expect(app.ai1CapturedRevisionCount, 0);
      expect(await entries(), isEmpty);
    },
  );

  test(
    'malformed external sleep replacement invalidates history without blocking save',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      await app.addSleep(
        id: 'sleep-example',
        bedtime: DateTime(2026, 10, 10, 23),
        wakeTime: DateTime(2026, 10, 11, 7),
        quality: 4,
      );
      app.signals = app.signals.map((signal) {
        if (signal.id != 'sleep-example-duration') return signal;
        return SignalReading.fromJson({...signal.toJson(), 'value': 14.0});
      }).toList();
      await app.addCheckIn(energy: 6, mood: 5, stress: 3);
      expect(app.ai1CapturedRevisionCount, 0);
      expect(app.checkIns, hasLength(1));
    },
  );

  test(
    'a failed history purge cannot report a successful response deletion',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      await report(app);
      capture.failWrites = true;
      await expectLater(app.deleteCheckIn('response'), throwsStateError);
      expect(app.checkIns, hasLength(1));
      expect(app.ai1CaptureError, isNotNull);
      capture.failWrites = false;
      await app.deleteCheckIn('response');
      expect(app.checkIns, isEmpty);
      expect(await entries(), isEmpty);
    },
  );

  test(
    'reset drains a waiting local save before erasing capture storage',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      final gate = Completer<bool>();
      preferences.gate = gate;
      preferences.started = Completer<void>();
      final pending = report(app);
      final failed = expectLater(pending, throwsStateError);
      await preferences.started!.future;
      final reset = app.reset();
      gate.complete(true);
      await reset;
      await failed;
      expect(capture.values, isEmpty);
      expect(app.checkIns, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString('tonyo_state_v1'),
        isNull,
      );
    },
  );

  test(
    'capture is off by default and enabling never backfills old answers',
    () async {
      final app = await controller();
      expect(app.ai1CaptureAvailable, isTrue);
      expect(app.ai1CaptureEnabled, isFalse);
      await report(app);
      expect(app.ai1CapturedRevisionCount, 0);
      await app.setAi1CaptureEnabled(true);
      expect(app.ai1CapturedRevisionCount, 0);
      await report(app, id: 'new-response');
      expect(app.ai1CapturedRevisionCount, 1);
      final saved = await entries();
      expect(saved.single.sourceId, 'new-response');
      expect(saved.single.originalLocal, isTrue);
      expect(saved.single.lineageComplete, isTrue);
      expect(app.outcomes, isEmpty);
      expect(app.outcomeConsent, isFalse);
    },
  );

  test(
    'first capture of an old answer edit does not invent original lineage',
    () async {
      final app = await controller();
      await report(app);
      await app.setAi1CaptureEnabled(true);
      now = now.add(const Duration(minutes: 1));
      await report(app, energy: 8);
      final saved = await entries();
      expect(saved.single.originalLocal, isFalse);
      expect(saved.single.lineageComplete, isFalse);
    },
  );

  test(
    'captures ratings revisions but excludes notes and note-only edits',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      await report(app, note: 'private note');
      now = now.add(const Duration(minutes: 1));
      await report(app, note: 'another private note');
      expect(app.ai1CapturedRevisionCount, 1);
      now = now.add(const Duration(minutes: 1));
      await report(app, energy: 8);
      final saved = await entries();
      expect(saved, hasLength(2));
      expect(saved.first.data['ratings'], containsPair('energy', 7.0));
      expect(saved.last.data['ratings'], containsPair('energy', 8.0));
      expect(capture.values.values.join(), isNot(contains('private note')));
      expect(saved.first.data['sharedHeading'], 'How do you feel right now?');
    },
  );

  test(
    'captures authored heading in the supplied questionnaire language',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      await report(app, language: 'es');
      final saved = (await entries()).single;
      expect(saved.data['questionnaireLanguage'], 'es');
      expect(
        saved.data['sharedHeading'],
        const AppLocalizations('es').text('How do you feel right now?'),
      );
    },
  );

  test(
    'receipt follows local persistence, including a save past the window',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      now = DateTime.utc(2026, 10, 11, 21, 59);
      final gate = Completer<bool>();
      preferences.gate = gate;
      preferences.started = Completer<void>();
      final pending = report(app);
      await preferences.started!.future;
      expect(app.ai1CapturedRevisionCount, 0);
      now = DateTime.utc(2026, 10, 11, 22, 1);
      gate.complete(true);
      await pending;
      final saved = (await entries()).single;
      expect(saved.acknowledgedAt, now);
      expect(saved.data['observedAt'], '2026-10-11T21:59:00.000Z');
    },
  );

  test('failed ordinary save cannot create capture evidence', () async {
    final app = await controller();
    await app.setAi1CaptureEnabled(true);
    preferences.gate = Completer<bool>()..complete(false);
    await expectLater(report(app), throwsStateError);
    expect(app.ai1CapturedRevisionCount, 0);
    expect(await entries(), isEmpty);
  });

  test(
    'enabling while a response save waits does not capture it retroactively',
    () async {
      final app = await controller();
      final gate = Completer<bool>();
      preferences.gate = gate;
      preferences.started = Completer<void>();
      final pending = report(app);
      await preferences.started!.future;
      await app.setAi1CaptureEnabled(true);
      gate.complete(true);
      await pending;
      expect(app.ai1CapturedRevisionCount, 0);
    },
  );

  test(
    'stop and restart while a response save waits invalidates the old intent',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      final gate = Completer<bool>();
      preferences.gate = gate;
      preferences.started = Completer<void>();
      final pending = report(app);
      await preferences.started!.future;
      await app.setAi1CaptureEnabled(false);
      await app.setAi1CaptureEnabled(true);
      gate.complete(true);
      await pending;
      expect(app.ai1CapturedRevisionCount, 0);
    },
  );

  test(
    'manual sleep keeps actual endpoints and deleting one signal purges it',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      final start = DateTime(2026, 10, 10, 23, 20);
      final end = DateTime(2026, 10, 11, 7, 40);
      await app.addSleep(
        id: 'sleep-example',
        bedtime: start,
        wakeTime: end,
        quality: 4,
      );
      final saved = (await entries()).single;
      expect(saved.data['startedAt'], start.toUtc().toIso8601String());
      expect(saved.data['endedAt'], end.toUtc().toIso8601String());
      expect(saved.data['durationHours'], closeTo(8 + 1 / 3, 0.00001));
      await app.deleteSignal('sleep-example-bedtime');
      expect(app.ai1CapturedRevisionCount, 0);
      expect(await entries(), isEmpty);
    },
  );

  test(
    'nap comparison retains its captured actual start without inferring one',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      await app.addSleep(
        id: 'sleep-nap',
        bedtime: DateTime.utc(2026, 10, 11, 14),
        wakeTime: DateTime.utc(2026, 10, 11, 14, 30),
        quality: 3,
        kind: SleepKind.nap,
      );
      expect(app.ai1CapturedRevisionCount, 1);
      await app.deleteSleepLog('sleep-nap');
      expect(await entries(), isEmpty);
    },
  );

  test('deleting a response purges every prior rating revision', () async {
    final app = await controller();
    await app.setAi1CaptureEnabled(true);
    await report(app);
    now = now.add(const Duration(minutes: 1));
    await report(app, energy: 9);
    await app.deleteCheckIn('response');
    expect(app.ai1CapturedRevisionCount, 0);
    expect(await entries(), isEmpty);
    await report(app, energy: 6);
    expect(app.ai1CapturedRevisionCount, 0);
  });

  test('stop clears history while keeping ordinary user logs', () async {
    final app = await controller();
    await app.setAi1CaptureEnabled(true);
    await report(app);
    await app.setAi1CaptureEnabled(false);
    expect(app.ai1CaptureEnabled, isFalse);
    expect(app.ai1CapturedRevisionCount, 0);
    expect(app.checkIns, hasLength(1));
    expect(await entries(), isEmpty);
  });

  test(
    'clear tracking stops capture and reset erases its private store',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      await report(app);
      await app.clearTrackingData();
      expect(app.ai1CaptureEnabled, isFalse);
      expect(app.checkIns, isEmpty);
      expect(await entries(), isEmpty);
      await app.setAi1CaptureEnabled(true);
      await report(app, id: 'after-clear');
      await app.reset();
      expect(capture.values, isEmpty);
      expect(app.ai1CapturedRevisionCount, 0);
    },
  );

  test('restart restores only existing owned capture evidence', () async {
    final first = await controller();
    await first.setAi1CaptureEnabled(true);
    await report(first);
    final restored = await controller();
    expect(restored.ai1CaptureEnabled, isTrue);
    expect(restored.ai1CapturedRevisionCount, 1);
    expect((await entries()).single.originalLocal, isTrue);
  });

  test(
    'signout invalidates a waiting capture before local storage completes',
    () async {
      final app = await controller();
      await app.setAi1CaptureEnabled(true);
      final gate = Completer<bool>();
      preferences.gate = gate;
      preferences.started = Completer<void>();
      final pending = report(app);
      final stopped = expectLater(pending, throwsStateError);
      await preferences.started!.future;
      await app.signOut();
      gate.complete(true);
      await stopped;
      expect(app.ai1CapturedRevisionCount, 0);
      expect(await entries(), isEmpty);
    },
  );
}
