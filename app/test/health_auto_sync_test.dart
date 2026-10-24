import 'dart:async';

import 'package:app/src/app_controller.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'new Health data imports within the foreground refresh interval',
    () async {
      var now = DateTime.utc(2026, 10, 11, 12);
      final health = _ControlledHealthService();
      final controller = _controller(health, () => now);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.connectHealth();

      now = now.add(const Duration(seconds: 10));
      health.heartReadings = [_heart('new-heart', now)];
      await health.notifyChanged();

      expect(health.heartCalls, 2);
      expect(controller.signals.map((row) => row.id), contains('new-heart'));
      expect(
        controller.lastHealthRefreshReason,
        HealthRefreshReason.background,
      );
      expect(controller.healthSyncStatus, HealthSyncStatus.updated);
    },
  );

  testWidgets(
    'foreground polls every fifteen minutes and stops when app is hidden',
    (tester) async {
      var now = DateTime.utc(2026, 10, 11, 12);
      final health = _ControlledHealthService();
      final controller = _controller(health, () => now);
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await controller.load();
        await controller.connectHealth();
      });
      controller.setAppForeground(true);
      health.heartReadings = [
        SignalReading(
          id: 'ordinary-heart-rate',
          type: SignalType.heartRate,
          value: 73,
          timestamp: now,
          source: SignalSource.healthKit,
        ),
      ];
      now = now.add(const Duration(minutes: 14, seconds: 59));
      await tester.pump(const Duration(minutes: 14, seconds: 59));
      expect(health.heartCalls, 1);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(health.heartCalls, 2);
      expect(controller.latestHealthKitHeartRate?.value, 73);
      expect(
        controller.lastHealthRefreshReason,
        HealthRefreshReason.foreground,
      );
      expect(health.recentOnlyRequests, [false, true]);
      controller.setAppForeground(false);
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      expect(health.heartCalls, 2);
      controller.setAppForeground(true);
      now = now.add(const Duration(minutes: 15));
      await tester.pump(const Duration(minutes: 15));
      await tester.pumpAndSettle();
      expect(health.heartCalls, 3);
      await controller.disconnectHealth();
      now = now.add(const Duration(minutes: 15));
      await tester.pump(const Duration(minutes: 15));
      expect(health.heartCalls, 3);
      controller.setAppForeground(false);
    },
  );

  test(
    'automatic recent reads retain initial, daily and manual backfills',
    () async {
      var now = DateTime.utc(2026, 10, 11, 12);
      final health = _ControlledHealthService();
      final controller = _controller(health, () => now);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.connectHealth();
      now = now.add(const Duration(seconds: 10));
      await health.notifyChanged();
      now = now.add(const Duration(days: 1));
      await health.notifyChanged();
      await controller.syncHealth();
      expect(health.recentOnlyRequests, [false, true, false, false]);
      await controller.disconnectHealth();
      await controller.connectHealth();
      expect(health.recentOnlyRequests.last, isFalse);
    },
  );

  for (final phase in _ReadPhase.values) {
    test(
      'Health events during ${phase.name} read coalesce into one refresh',
      () async {
        final now = DateTime.utc(2026, 10, 11, 12);
        final health = _ControlledHealthService();
        final controller = _controller(health, () => now);
        addTearDown(controller.dispose);
        await controller.load();
        await controller.connectHealth();

        final pause = _Pause<List<SignalReading>>();
        health.readPauses[phase] = pause;
        final firstEvent = health.notifyChanged();
        await pause.started.future;
        health.heartReadings = [_heart('arrived-during-read', now)];
        final nextEvents = List.generate(3, (_) => health.notifyChanged());
        pause.release.complete(const []);
        await Future.wait([firstEvent, ...nextEvents]);

        // Initial import, the interrupted import, and one shared trailing import.
        expect(health.heartCalls, 3);
        expect(health.sleepCalls, 3);
        expect(health.activityCalls, 3);
        expect(
          controller.signals.map((row) => row.id),
          contains('arrived-during-read'),
        );
        expect(controller.isSyncing, isFalse);
      },
    );
  }

  test('disconnect blocks a pending read and its queued refresh', () async {
    final now = DateTime.utc(2026, 10, 11, 12);
    final health = _ControlledHealthService();
    final controller = _controller(health, () => now);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.connectHealth();

    final pause = _Pause<List<SignalReading>>();
    health.readPauses[_ReadPhase.heart] = pause;
    final event = health.notifyChanged();
    await pause.started.future;
    final queuedEvent = health.notifyChanged();
    await controller.disconnectHealth();
    pause.release.complete([_heart('late-disconnected-read', now)]);
    await Future.wait([event, queuedEvent]);

    expect(controller.signals, isEmpty);
    expect(health.heartCalls, 2);
    expect(health.sleepCalls, 1);
    expect(health.activityCalls, 1);
    expect(controller.healthAuthorized, isFalse);
    expect(controller.healthBackgroundRefreshEnabled, isFalse);
    expect(controller.healthSyncStatus, HealthSyncStatus.disabled);
    expect(controller.isSyncing, isFalse);
  });

  test(
    'disconnect takes effect before native observer removal finishes',
    () async {
      final now = DateTime.utc(2026, 10, 11, 12);
      final health = _ControlledHealthService();
      final controller = _controller(health, () => now);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.connectHealth();
      final oldCallback = health.callback!;
      final pause = _Pause<void>();
      health.disablePause = pause;

      final disconnect = controller.disconnectHealth();
      await pause.started.future;
      health.heartReadings = [_heart('after-disconnect', now)];
      await oldCallback();

      expect(controller.healthAuthorized, isFalse);
      expect(health.heartCalls, 1);
      expect(controller.signals, isEmpty);
      pause.release.complete();
      await disconnect;
    },
  );

  test(
    'late permission completion cannot reconnect after disconnect',
    () async {
      final health = _ControlledHealthService();
      final controller = _controller(health);
      addTearDown(controller.dispose);
      await controller.load();
      final pause = _Pause<HealthAuthorizationState>();
      health.requestPause = pause;

      final connect = controller.connectHealth();
      await pause.started.future;
      await controller.disconnectHealth();
      pause.release.complete(HealthAuthorizationState.authorized);

      expect(await connect, isFalse);
      expect(controller.healthAuthorized, isFalse);
      expect(controller.healthAuthorization, HealthAuthorizationState.revoked);
      expect(health.enableCalls, 0);
      expect(health.heartCalls, 0);
    },
  );

  test(
    'late observer registration cannot restart a disconnected import',
    () async {
      final health = _ControlledHealthService();
      final controller = _controller(health);
      addTearDown(controller.dispose);
      await controller.load();
      final pause = _Pause<bool>();
      health.enablePause = pause;

      final connect = controller.connectHealth();
      await pause.started.future;
      final oldCallback = health.callback!;
      final disconnect = controller.disconnectHealth();
      pause.release.complete(true);
      await disconnect;
      expect(await connect, isFalse);
      await oldCallback();

      expect(controller.healthAuthorized, isFalse);
      expect(controller.healthBackgroundRefreshEnabled, isFalse);
      expect(controller.healthAuthorization, HealthAuthorizationState.revoked);
      expect(health.heartCalls, 0);
    },
  );

  test('late status check preserves a newer explicit disconnect', () async {
    final health = _ControlledHealthService();
    final controller = _controller(health);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.connectHealth();
    final pause = _Pause<HealthAuthorizationState>();
    health.statusPause = pause;

    final status = controller.refreshHealthAuthorization();
    await pause.started.future;
    await controller.disconnectHealth();
    pause.release.complete(HealthAuthorizationState.authorized);
    await status;

    expect(controller.healthAuthorized, isFalse);
    expect(controller.healthAuthorization, HealthAuthorizationState.revoked);
    expect(controller.healthSyncStatus, HealthSyncStatus.disabled);
  });

  test(
    'a previous connection callback cannot import after reconnecting',
    () async {
      final health = _ControlledHealthService();
      final controller = _controller(health);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.connectHealth();
      final previousCallback = health.callback!;
      await controller.disconnectHealth();
      await controller.connectHealth();

      await previousCallback();
      expect(health.heartCalls, 2);
      await health.notifyChanged();
      expect(health.heartCalls, 3);
      expect(controller.healthAuthorized, isTrue);
      expect(controller.healthBackgroundRefreshEnabled, isTrue);
    },
  );

  test(
    'a stale read cannot clear a new connection import in progress',
    () async {
      final now = DateTime.utc(2026, 10, 11, 12);
      final health = _ControlledHealthService();
      final controller = _controller(health, () => now);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.connectHealth();

      final previousRead = _Pause<List<SignalReading>>();
      health.readPauses[_ReadPhase.heart] = previousRead;
      final previousEvent = health.notifyChanged();
      await previousRead.started.future;
      await controller.disconnectHealth();

      final currentRead = _Pause<List<SignalReading>>();
      health.readPauses[_ReadPhase.heart] = currentRead;
      final reconnect = controller.connectHealth();
      await currentRead.started.future;
      previousRead.release.complete([_heart('previous-connection-read', now)]);
      await previousEvent;

      expect(controller.healthAuthorized, isTrue);
      expect(controller.isSyncing, isTrue);
      expect(controller.signals, isEmpty);
      currentRead.release.complete([_heart('current-connection-read', now)]);
      expect(await reconnect, isTrue);
      expect(controller.signals.map((row) => row.id), [
        'current-connection-read',
      ]);
      expect(controller.isSyncing, isFalse);
    },
  );

  test(
    'late native setup cleanup preserves a newer connection observer',
    () async {
      final now = DateTime.utc(2026, 10, 11, 12);
      final health = _ControlledHealthService();
      final controller = _controller(health, () => now);
      addTearDown(controller.dispose);
      await controller.load();
      final previousSetup = _Pause<bool>();
      health.enablePause = previousSetup;

      final firstConnect = controller.connectHealth();
      await previousSetup.started.future;
      final disconnect = controller.disconnectHealth();
      final reconnect = controller.connectHealth();
      previousSetup.release.complete(true);
      await disconnect;
      expect(await firstConnect, isFalse);
      expect(await reconnect, isTrue);

      health.heartReadings = [_heart('new-observer-read', now)];
      await health.notifyChanged();
      expect(health.enableCalls, 2);
      expect(controller.healthBackgroundRefreshEnabled, isTrue);
      expect(
        controller.signals.map((row) => row.id),
        contains('new-observer-read'),
      );
    },
  );

  test(
    'resume never prompts or imports without an active Tonyo connection',
    () async {
      final health = _ControlledHealthService()
        ..status = HealthAuthorizationState.authorized;
      final controller = _controller(health);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.handleAppResumed();

      expect(health.requestCalls, 0);
      expect(health.enableCalls, 0);
      expect(health.heartCalls, 0);

      await controller.connectHealth();
      await controller.disconnectHealth();
      await controller.handleAppResumed();

      expect(health.requestCalls, 1);
      expect(health.enableCalls, 1);
      expect(health.heartCalls, 1);
      expect(controller.healthAuthorization, HealthAuthorizationState.revoked);
    },
  );

  test(
    'a saved connection imports on launch and later foreground resume',
    () async {
      var now = DateTime.utc(2026, 10, 11, 12);
      final firstHealth = _ControlledHealthService();
      final first = _controller(firstHealth, () => now);
      await first.load();
      await first.connectHealth();
      first.dispose();

      now = now.add(const Duration(minutes: 16));
      final nextHealth = _ControlledHealthService()
        ..status = HealthAuthorizationState.authorized
        ..heartReadings = [_heart('launch-read', now)];
      final restored = _controller(nextHealth, () => now);
      addTearDown(restored.dispose);
      await restored.load();

      expect(nextHealth.requestCalls, 0);
      expect(nextHealth.enableCalls, 1);
      expect(nextHealth.heartCalls, 1);
      expect(restored.signals.map((row) => row.id), contains('launch-read'));

      now = now.add(const Duration(minutes: 16));
      nextHealth.heartReadings = [_heart('foreground-read', now)];
      await restored.handleAppResumed();

      expect(nextHealth.requestCalls, 0);
      expect(nextHealth.enableCalls, 1);
      expect(nextHealth.heartCalls, 2);
      expect(
        restored.signals.map((row) => row.id),
        contains('foreground-read'),
      );
      expect(restored.lastHealthRefreshReason, HealthRefreshReason.foreground);
    },
  );

  test(
    'disconnect while signed out stays disconnected after resuming',
    () async {
      final firstHealth = _ControlledHealthService();
      final first = _controller(firstHealth);
      await first.load();
      first.onboardingComplete = true;
      await first.connectHealth();
      await first.signOut();
      await first.disconnectHealth();
      first.dispose();

      final nextHealth = _ControlledHealthService()
        ..status = HealthAuthorizationState.authorized;
      final restored = _controller(nextHealth);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.canResumeLocalProfile, isTrue);
      await restored.resumeLocalProfile();

      expect(restored.healthAuthorized, isFalse);
      expect(restored.healthAuthorization, HealthAuthorizationState.revoked);
      expect(nextHealth.requestCalls, 0);
      expect(nextHealth.enableCalls, 0);
      expect(nextHealth.heartCalls, 0);
    },
  );
}

AppController _controller(
  _ControlledHealthService health, [
  DateTime Function()? clock,
]) => AppController(
  initialPrivacyConsent: testAdultPrivacyConsent,
  healthService: health,
  clock: clock ?? () => DateTime.utc(2026, 10, 11, 12),
);

SignalReading _heart(String id, DateTime at) => SignalReading(
  id: id,
  type: SignalType.hrv,
  value: 55,
  timestamp: at.subtract(const Duration(minutes: 1)),
  source: SignalSource.healthKit,
);

enum _ReadPhase { heart, sleep, activity }

class _Pause<T> {
  final started = Completer<void>();
  final release = Completer<T>();

  Future<T> wait() {
    started.complete();
    return release.future;
  }
}

class _ControlledHealthService extends HealthService {
  HealthAuthorizationState status = HealthAuthorizationState.notDetermined;
  List<SignalReading> heartReadings = const [];
  int requestCalls = 0;
  int enableCalls = 0;
  int heartCalls = 0;
  int sleepCalls = 0;
  int activityCalls = 0;
  final recentOnlyRequests = <bool>[];
  Future<void> Function()? callback;
  _Pause<HealthAuthorizationState>? statusPause;
  _Pause<HealthAuthorizationState>? requestPause;
  _Pause<bool>? enablePause;
  _Pause<void>? disablePause;
  final readPauses = <_ReadPhase, _Pause<List<SignalReading>>>{};

  Future<void> notifyChanged() async => await callback?.call();

  @override
  Future<HealthAuthorizationState> authorizationStatus() async {
    final pause = statusPause;
    statusPause = null;
    return pause == null ? status : await pause.wait();
  }

  @override
  Future<HealthAuthorizationState> requestAuthorization() async {
    requestCalls++;
    final pause = requestPause;
    requestPause = null;
    status = pause == null
        ? HealthAuthorizationState.authorized
        : await pause.wait();
    return status;
  }

  @override
  Future<bool> enableBackgroundUpdates(
    Future<void> Function() onHealthDataChanged,
  ) async {
    enableCalls++;
    callback = onHealthDataChanged;
    final pause = enablePause;
    enablePause = null;
    return pause == null ? true : await pause.wait();
  }

  @override
  Future<void> disableBackgroundUpdates() async {
    final pause = disablePause;
    disablePause = null;
    if (pause != null) await pause.wait();
    callback = null;
  }

  @override
  Future<List<SignalReading>> sync({bool recentOnly = false}) async {
    heartCalls++;
    recentOnlyRequests.add(recentOnly);
    final pause = readPauses.remove(_ReadPhase.heart);
    return pause == null ? heartReadings : await pause.wait();
  }

  @override
  Future<List<SignalReading>> syncSleep() async {
    sleepCalls++;
    final pause = readPauses.remove(_ReadPhase.sleep);
    return pause == null ? const [] : await pause.wait();
  }

  @override
  Future<List<SignalReading>> syncActivity() async {
    activityCalls++;
    final pause = readPauses.remove(_ReadPhase.activity);
    return pause == null ? const [] : await pause.wait();
  }
}
