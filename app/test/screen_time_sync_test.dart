import 'dart:async';

import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screen_time_logic.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:app/src/today_dashboard_logic.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final morning = DateTime(2026, 10, 25, 10);
  ScreenTimeDailyTotal total(double hours, [DateTime? time]) =>
      ScreenTimeDailyTotal(
        day: DateTime(2026, 10, 25),
        seconds: hours * 3600,
        updatedAt: time ?? morning,
      );
  AppController controller(_ScreenTime service, DateTime Function() clock) {
    final value = AppController(
      screenTimeService: service,
      clock: clock,
      initialPrivacyConsent: testAdultPrivacyConsent,
    );
    addTearDown(value.dispose);
    return value;
  }

  test(
    'manual is the default, and report access alone never imports',
    () async {
      final service = _ScreenTime();
      final app = controller(service, () => morning);
      await app.load();
      expect(
        app.screenTimeAuthorization,
        ScreenTimeAuthorizationState.authorized,
      );
      await app.syncScreenTimeIfDue(force: true);
      expect(app.screenTimeAutoSyncEnabled, isFalse);
      expect(service.requests, 0);
      expect(service.reads, 0);
    },
  );

  test(
    'opt-in imports, throttles, and replaces a daily total without duplicates',
    () async {
      var now = morning;
      final service = _ScreenTime()..totals = [total(2)];
      final app = controller(service, () => now);
      await app.setScreenTimeAutoSync(true);
      expect(app.screenTimeAutoSyncEnabled, isTrue);
      expect(service.requests, 1);
      expect(service.reads, 1);
      expect(app.signals.single.value, 2);
      expect(app.signals.single.source, SignalSource.appleScreenTime);
      expect(
        SignalReading.fromJson(app.signals.single.toJson()).source,
        SignalSource.appleScreenTime,
      );

      final original = app.signals.single;
      await app.syncScreenTimeIfDue();
      expect(service.reads, 1);
      now = morning.add(const Duration(minutes: 15));
      await app.syncScreenTimeIfDue();
      expect(service.reads, 2);
      expect(identical(original, app.signals.single), isTrue);
      service.totals = [total(3, now)];
      await app.syncScreenTimeIfDue(force: true);
      expect(app.signals.single.value, 3);
      expect(app.signals.single.id, original.id);
    },
  );

  test('denial and unavailable builds do not enable or read data', () async {
    for (final state in [
      ScreenTimeSyncAvailability.denied,
      ScreenTimeSyncAvailability.entitlementRequired,
      ScreenTimeSyncAvailability.regionUnavailable,
    ]) {
      final service = _ScreenTime()..availability = state;
      final app = controller(service, () => morning);
      await app.setScreenTimeAutoSync(true);
      expect(app.screenTimeAutoSyncEnabled, isFalse);
      expect(service.reads, 0);
      expect(app.screenTimeSyncError, isNotNull);
    }
  });

  test('empty or failing Apple responses preserve existing totals', () async {
    final service = _ScreenTime()..totals = [total(2)];
    final app = controller(service, () => morning);
    await app.setScreenTimeAutoSync(true);
    service.totals = [];
    await app.syncScreenTimeIfDue(force: true);
    expect(app.signals.single.value, 2);
    expect(app.screenTimeSyncError, contains('no Screen Time totals'));
    service.failure = PlatformException(code: 'regionUnavailable');
    await app.syncScreenTimeIfDue(force: true);
    expect(app.signals.single.value, 2);
    expect(
      app.screenTimeSyncAvailability,
      ScreenTimeSyncAvailability.regionUnavailable,
    );
  });

  test(
    'switching off discards an in-flight import and prevents future reads',
    () async {
      final service = _ScreenTime()..totals = [total(2)];
      final app = controller(service, () => morning);
      await app.setScreenTimeAutoSync(true);
      final pending = Completer<List<ScreenTimeDailyTotal>>();
      service.pending = pending;
      final sync = app.syncScreenTimeIfDue(force: true);
      await Future<void>.delayed(Duration.zero);
      await app.setScreenTimeAutoSync(false);
      pending.complete([total(9)]);
      await sync;
      expect(app.signals.single.value, 2);
      expect(app.isScreenTimeSyncing, isFalse);
      final reads = service.reads;
      await app.syncScreenTimeIfDue(force: true);
      expect(service.reads, reads);
    },
  );

  test('sign-out discards an in-flight import', () async {
    final service = _ScreenTime()..totals = [total(2)];
    final app = controller(service, () => morning);
    await app.setScreenTimeAutoSync(true);
    final pending = Completer<List<ScreenTimeDailyTotal>>();
    service.pending = pending;
    final sync = app.syncScreenTimeIfDue(force: true);
    await Future<void>.delayed(Duration.zero);
    await app.signOut();
    pending.complete([total(9)]);
    await sync;
    expect(app.signals.any((row) => row.value == 9), isFalse);
    final reads = service.reads;
    await app.syncScreenTimeIfDue(force: true);
    expect(service.reads, reads);
  });

  test(
    'saved opt-in syncs on launch and when returning after the interval',
    () async {
      var now = morning;
      final service = _ScreenTime()..totals = [total(2)];
      await controller(service, () => now).setScreenTimeAutoSync(true);
      final restored = controller(service, () => now);
      await restored.load();
      expect(restored.screenTimeAutoSyncEnabled, isTrue);
      expect(service.requests, 1);
      expect(service.reads, 2);
      await restored.handleAppResumed();
      expect(
        service.reads,
        2,
        reason:
            'Health being unavailable must not reset the Screen Time throttle.',
      );
      now = now.add(const Duration(minutes: 16));
      service.totals = [total(4, now)];
      await restored.handleAppResumed();
      expect(service.reads, 3);
      expect(restored.signals.single.value, 4);
    },
  );

  test(
    'manual corrections apply per day without dropping other Apple days',
    () {
      final automatic = ScreenTimeLogic.merge(
        existing: [],
        totals: [total(2)],
        now: morning,
      );
      final previousManual = SignalReading(
        id: 'yesterday',
        type: SignalType.screenTime,
        value: 5,
        timestamp: DateTime(2026, 10, 24, 20),
      );
      expect(
        ScreenTimeLogic.modelReadings([...automatic, previousManual]),
        hasLength(2),
      );
      final todayManual = SignalReading(
        id: 'today',
        type: SignalType.screenTime,
        value: 0,
        timestamp: morning,
      );
      expect(
        ScreenTimeLogic.modelReadings([
          ...automatic,
          previousManual,
          todayManual,
        ]).map((row) => row.id),
        ['yesterday', 'today'],
      );
    },
  );

  test('invalid and future totals cannot become model readings', () {
    final merged = ScreenTimeLogic.merge(
      existing: [],
      totals: [
        total(-1),
        total(double.nan),
        total(25),
        total(1, morning.add(const Duration(hours: 1))),
      ],
      now: morning,
    );
    expect(merged, isEmpty);
  });

  test(
    'Today displays the manual correction without adding the Apple total',
    () {
      final readings = ScreenTimeLogic.merge(
        existing: [],
        totals: [total(2)],
        now: morning,
      );
      readings.add(
        SignalReading(
          id: 'manual-zero',
          type: SignalType.screenTime,
          value: 0,
          timestamp: morning,
        ),
      );
      final summary = TodayDashboardLogic.summariesForDay(
        readings,
        day: morning,
        now: morning,
      ).singleWhere((row) => row.type == SignalType.screenTime);
      expect(summary.displayValue, '0.0 hr');
      expect(summary.readingCount, 1);
    },
  );

  testWidgets('automatic polling runs only while Tonyo is open', (
    tester,
  ) async {
    var now = morning;
    final service = _ScreenTime()..totals = [total(2)];
    final app = controller(service, () => now);
    await tester.runAsync(() async {
      await app.load();
      await app.setScreenTimeAutoSync(true);
    });
    app.setAppForeground(true);
    now = now.add(const Duration(minutes: 15));
    service.totals = [total(3, now)];
    await tester.pump(const Duration(minutes: 15));
    await tester.pumpAndSettle();
    expect(service.reads, 2);
    expect(app.signals.single.value, 3);
    app.setAppForeground(false);
    now = now.add(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));
    expect(service.reads, 2);
  });

  test(
    'native payload parser rejects malformed totals and supports explicit zero',
    () async {
      const channel = MethodChannel('tonyo/screen_time');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      var seconds = 0.0;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'syncAvailability') return 'authorized';
        return [
          {
            'day': '2026-10-25',
            'seconds': seconds,
            'updatedAt': morning.toUtc().toIso8601String(),
          },
        ];
      });
      const service = ScreenTimeService();
      expect(
        await service.syncAvailability(),
        ScreenTimeSyncAvailability.authorized,
      );
      expect((await service.readDailyTotals()).single.seconds, 0);
      seconds = -1;
      await expectLater(service.readDailyTotals(), throwsFormatException);
      expect(calls, ['syncAvailability', 'readDailyTotals', 'readDailyTotals']);
    },
  );
}

class _ScreenTime extends ScreenTimeService {
  ScreenTimeSyncAvailability availability =
      ScreenTimeSyncAvailability.authorized;
  List<ScreenTimeDailyTotal> totals = [];
  Completer<List<ScreenTimeDailyTotal>>? pending;
  PlatformException? failure;
  int requests = 0;
  int reads = 0;
  @override
  Future<ScreenTimeAuthorizationState> authorizationStatus() async =>
      ScreenTimeAuthorizationState.authorized;
  @override
  Future<ScreenTimeSyncAvailability> syncAvailability() async => availability;
  @override
  Future<ScreenTimeSyncAvailability> requestSyncAuthorization() async {
    requests++;
    return availability;
  }

  @override
  Future<List<ScreenTimeDailyTotal>> readDailyTotals() async {
    reads++;
    if (failure != null) throw failure!;
    return pending?.future ?? totals;
  }
}
