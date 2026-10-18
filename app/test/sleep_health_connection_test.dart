import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/sleep_log_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppController controller(
    _SleepHealthService health, {
    bool available = true,
  }) =>
      AppController(
          initialPrivacyConsent: testAdultPrivacyConsent,
          healthService: health,
        )
        ..isReady = true
        ..healthAvailable = available;

  Widget screen(AppController controller, {double textScale = 1}) => AppScope(
    controller: controller,
    child: MaterialApp(
      theme: buildTonyoTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const SleepLogScreen(),
        ),
      ),
    ),
  );

  testWidgets('unsupported devices keep manual sleep without a Health prompt', (
    tester,
  ) async {
    final health = _SleepHealthService();
    final model = controller(health, available: false);
    addTearDown(model.dispose);
    await tester.pumpWidget(screen(model));

    expect(find.byKey(const Key('sleep-health-connection')), findsNothing);
    expect(find.byKey(const Key('bedtime-button')), findsOneWidget);
    expect(health.permissionRequests, 0);
    expect(health.sleepSyncs, 0);
  });

  testWidgets(
    'one connection imports sleep and optional retry skips permission',
    (tester) async {
      final health = _SleepHealthService();
      final model = controller(health);
      addTearDown(model.dispose);
      await tester.pumpWidget(screen(model));

      // Opening the manual form alone never requests access.
      expect(health.permissionRequests, 0);
      expect(health.sleepSyncs, 0);
      expect(find.text('Connect Apple Health'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sleep-health-action')));
      await tester.pumpAndSettle();

      expect(health.permissionRequests, 1);
      expect(health.sleepSyncs, 1);
      expect(model.healthAuthorized, isTrue);
      expect(find.text('Connect Apple Health'), findsNothing);
      expect(find.text('Sync now'), findsOneWidget);
      expect(
        find.textContaining('Health data syncs automatically'),
        findsOneWidget,
      );
      expect(
        find.text(
          'No readable sleep samples found. Check Sleep access in Apple Health.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(health.permissionRequests, 1);
      expect(health.sleepSyncs, 2);
      await tester.ensureVisible(find.byKey(const Key('bedtime-button')));
      expect(find.byKey(const Key('bedtime-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending access disables repeat taps and cancellation keeps manual logging',
    (tester) async {
      final response = Completer<HealthAuthorizationState>();
      final health = _SleepHealthService(authorization: response.future);
      final model = controller(health);
      addTearDown(model.dispose);
      await tester.pumpWidget(screen(model));
      final action = find.byKey(const Key('sleep-health-action'));
      await tester.tap(action);
      await tester.pump();

      expect(tester.widget<TextButton>(action).onPressed, isNull);
      expect(health.permissionRequests, 1);
      expect(health.sleepSyncs, 0);
      response.complete(HealthAuthorizationState.denied);
      await tester.pumpAndSettle();

      expect(model.healthAuthorized, isFalse);
      expect(health.sleepSyncs, 0);
      expect(
        find.text('The Apple Health permission sheet was not completed.'),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(action).onPressed, isNotNull);
      await tester.ensureVisible(find.text('Save sleep'));
      await tester.pumpAndSettle();
      expect(find.text('Save sleep').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Save sleep'));
      await tester.pumpAndSettle();
      expect(model.sleepLogs, hasLength(1));
    },
  );

  testWidgets('Health connection fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = controller(_SleepHealthService());
    addTearDown(model.dispose);
    await tester.pumpWidget(screen(model, textScale: 2));
    await tester.ensureVisible(find.byKey(const Key('sleep-health-action')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('sleep-health-action')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _SleepHealthService extends HealthService {
  _SleepHealthService({this.authorization});

  final Future<HealthAuthorizationState>? authorization;
  int permissionRequests = 0;
  int sleepSyncs = 0;

  @override
  Future<HealthAuthorizationState> requestAuthorization() {
    permissionRequests += 1;
    return authorization ?? Future.value(HealthAuthorizationState.authorized);
  }

  @override
  Future<bool> enableBackgroundUpdates(
    Future<void> Function() onHealthDataChanged,
  ) async => true;

  @override
  Future<void> disableBackgroundUpdates() async {}

  @override
  Future<List<SignalReading>> sync({bool recentOnly = false}) async => [];

  @override
  Future<List<SignalReading>> syncSleep() async {
    sleepSyncs += 1;
    return [];
  }

  @override
  Future<List<SignalReading>> syncActivity() async => [];
}
