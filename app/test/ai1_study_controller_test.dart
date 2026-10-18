import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_capture_store.dart';
import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/device_timezone_service.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _Store implements Ai1CaptureStore {
  _Store(this.now);
  final DateTime Function() now;
  final values = <String, String>{};
  Completer<void>? gate;
  Completer<void>? entered;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String?> read(String owner) async => values[owner];
  @override
  Future<DateTime> write(String owner, String value) async {
    if (gate != null) {
      final current = gate!;
      gate = null;
      entered?.complete();
      await current.future;
    }
    values[owner] = value;
    return now();
  }

  @override
  Future<void> clear(String owner) async {
    values.remove(owner);
  }

  @override
  Future<void> clearAll() async {
    values.clear();
  }
}

class _Health extends HealthService {
  List<SignalReading> samples = [];
  @override
  Future<HealthAuthorizationState> authorizationStatus() async =>
      HealthAuthorizationState.authorized;
  @override
  Future<HealthAuthorizationState> requestAuthorization() async =>
      HealthAuthorizationState.authorized;
  @override
  Future<bool> enableBackgroundUpdates(
    Future<void> Function() callback,
  ) async => true;
  @override
  Future<void> disableBackgroundUpdates() async {}
  @override
  Future<List<SignalReading>> sync({bool recentOnly = false}) async => [];
  @override
  Future<List<SignalReading>> syncActivity() async => [];
  @override
  Future<List<SignalReading>> syncSleep() async => samples;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late String timezone;
  late _Store store;
  late _Health health;
  late AppController app;
  DateTime day(int hour) => DateTime.utc(2026, 10, 17, hour);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 16, 12);
    timezone = 'Etc/UTC';
    store = _Store(() => now);
    health = _Health();
    app = AppController(
      clock: () => now,
      initialPrivacyConsent: testAdultPrivacyConsent,
      captureStore: store,
      healthService: health,
      deviceTimezoneService: DeviceTimezoneService(
        readIdentifier: () async => timezone,
        clock: () => now,
      ),
    );
    await app.load();
  });
  tearDown(() => app.dispose());
  Future<void> start({Ai1SleepSource source = Ai1SleepSource.manual}) async {
    await app.setAi1CaptureEnabled(true);
    await app.startAi1Study(source: source, days: 4);
  }

  Future<void> morning() async {
    await start();
    now = day(8);
    await app.addSleep(
      bedtime: day(7).subtract(const Duration(hours: 8)).toLocal(),
      wakeTime: day(7).toLocal(),
      quality: 4,
    );
    now = day(10);
    await app.refreshAi1Study();
  }

  SignalReading sample() => SignalReading(
    id: 'private-stage',
    type: SignalType.sleepCore,
    value: 8,
    timestamp: day(7),
    source: SignalSource.healthKit,
    quality: 1,
    groupId: 'test.health.producer',
  );
  Map<String, dynamic> exported() =>
      jsonDecode(app.exportAi1Study()) as Map<String, dynamic>;

  test(
    'ordinary saves produce a local dataset and readiness through controller',
    () async {
      await morning();
      now = day(19);
      await app.saveSelfReportCheckIn(
        period: CheckInPeriod.evening,
        energy: 7,
        questionnaireLanguage: 'en',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (s) => s,
        ),
      );
      now = day(23);
      final data = exported();
      expect(
        data['predictionEvents'].single['analysisPair'],
        isTrue,
        reason: jsonEncode(data['predictionEvents']),
      );
      expect(data['readiness']['coverage']['completedOutcomes'], 1);
      expect(data['readiness']['modelingReady'], isFalse);
      final ordinary = jsonDecode(await app.exportDeviceBackup());
      expect(jsonEncode(ordinary), isNot(contains('predictionEvents')));
    },
  );
  test(
    'study remains off by default and start never silently enables history',
    () async {
      expect(app.ai1CaptureEnabled, isFalse);
      await expectLater(
        app.startAi1Study(source: Ai1SleepSource.manual, days: 28),
        throwsStateError,
      );
      expect(store.values, isEmpty);
    },
  );
  test(
    'source changes require explicit clearing, not a second plan revision',
    () async {
      await start();
      await expectLater(
        app.startAi1Study(source: Ai1SleepSource.appleHealth, days: 4),
        throwsStateError,
      );
      expect(app.ai1StudyStatus, contains('manual'));
    },
  );
  test('timezone is refreshed before morning event selection', () async {
    await start();
    timezone = 'Europe/London';
    now = day(10);
    await app.refreshAi1Study();
    now = day(23);
    expect(
      exported()['predictionEvents'].single['snapshotStatus'],
      'not_issued',
    );
    expect(store.values.values.single, contains('timezone-change'));
  });
  test(
    'disconnect erases a Health query pending inside native persistence',
    () async {
      await start(source: Ai1SleepSource.appleHealth);
      now = day(8);
      await app.connectHealth();
      health.samples = [sample()];
      final entered = Completer<void>();
      final release = Completer<void>();
      store.entered = entered;
      store.gate = release;
      final syncing = app.syncHealth();
      await entered.future;
      final disconnect = app.disconnectHealth();
      release.complete();
      await Future.wait([syncing, disconnect]);
      expect(store.values.values.single, isNot(contains('private-stage')));
      expect(app.healthAuthorized, isFalse);
    },
  );
  test('deleting imported sleep removes independent Health evidence', () async {
    await start(source: Ai1SleepSource.appleHealth);
    now = day(8);
    health.samples = [sample()];
    await app.connectHealth();
    final imported = app.signals.firstWhere((s) => s.type == SignalType.sleep);
    now = day(10);
    await app.refreshAi1Study();
    await app.deleteSleepLog(imported.groupId!);
    expect(store.values.values.single, isNot(contains('private-stage')));
    now = day(23);
    expect(exported()['predictionEvents'].single['feature'], isNull);
  });
  test('history disablement erases plan and blocks export', () async {
    await morning();
    await app.setAi1CaptureEnabled(false);
    expect(app.ai1StudyActive, isFalse);
    expect(app.exportAi1Study, throwsStateError);
    expect(store.values, isEmpty);
  });
  test('sign-out prevents export and pending study tick', () async {
    await morning();
    await app.signOut();
    expect(app.exportAi1Study, throwsStateError);
    await app.refreshAi1Study();
    expect(app.ai1StudyActive, isFalse);
  });
}
