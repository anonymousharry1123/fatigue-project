import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:app/src/screens/onboarding_screen.dart';
import 'package:app/src/screens/privacy_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

const _coachPayload = 'tonyo-guidance:coach:plan-2026-09-20-focus';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  int selectedTab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  Future<(_NavigationController, _TapNotifications)> showApp(
    WidgetTester tester, {
    String? launchPayload,
    bool ready = true,
    bool onboarded = true,
    bool consented = true,
    Completer<void>? loadGate,
    bool failInitialization = false,
    MemoryAccountAuth? auth,
  }) async {
    final service = _TapNotifications(
      launchPayload: launchPayload,
      failInitialization: failInitialization,
    );
    final controller =
        _NavigationController(
            service: service,
            consented: consented,
            loadGate: loadGate,
            auth: auth,
          )
          ..isReady = ready
          ..onboardingComplete = onboarded;
    addTearDown(controller.dispose);
    await tester.pumpWidget(TonyoApp(controller: controller));
    await tester.pump();
    return (controller, service);
  }

  testWidgets('warm Coach and forecast taps select Coach only once', (
    tester,
  ) async {
    final (controller, service) = await showApp(tester);
    expect(selectedTab(tester), 0);
    service.tap(_coachPayload);
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 3);

    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(0);
    await tester.pump();
    controller.announce();
    await tester.pump();
    expect(selectedTab(tester), 0);

    service.tap('tonyo-guidance:2026-09-20-recovery');
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 3);
  });

  testWidgets(
    'a tap returns from an open detail route to the existing Coach tab',
    (tester) async {
      final (_, service) = await showApp(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Private detail')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private detail'), findsOneWidget);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Nested detail')),
        ),
      );
      await tester.pumpAndSettle();
      service.tap(_coachPayload);
      await tester.pumpAndSettle();
      expect(find.text('Private detail'), findsNothing);
      expect(find.text('Nested detail'), findsNothing);
      expect(selectedTab(tester), 3);
      expect(navigator.canPop(), isFalse);
    },
  );

  testWidgets('a notification leaves a save protected by PopScope intact', (
    tester,
  ) async {
    final (_, service) = await showApp(tester);
    final saving = ValueNotifier(true);
    addTearDown(saving.dispose);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<bool>(
          valueListenable: saving,
          builder: (_, busy, _) => PopScope(
            canPop: !busy,
            child: const Scaffold(body: Text('Saving important changes')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    service.tap(_coachPayload);
    await tester.pumpAndSettle();
    expect(find.text('Saving important changes'), findsOneWidget);
    expect(navigator.canPop(), isTrue);
    saving.value = false;
    await tester.pump();
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 3);
  });

  testWidgets('cold-launch tap waits for loading before opening Coach', (
    tester,
  ) async {
    final gate = Completer<void>();
    await showApp(
      tester,
      launchPayload: _coachPayload,
      ready: false,
      loadGate: gate,
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 3);
  });

  testWidgets('a tap waits behind onboarding without bypassing it', (
    tester,
  ) async {
    final (controller, service) = await showApp(tester, onboarded: false);
    service.tap(_coachPayload);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    controller.onboardingComplete = true;
    controller.announce();
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 3);
  });

  testWidgets(
    'a tap waits behind privacy review until the same session consents',
    (tester) async {
      final (controller, service) = await showApp(tester, consented: false);
      service.tap(_coachPayload);
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyCenterScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await controller.acceptPrivacy(
        ageBand: PrivacyAgeBand.adult,
        region: PrivacyRegion.us,
        acknowledged: true,
      );
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 3);
    },
  );

  testWidgets('sign-out discards a pending tap before a later local resume', (
    tester,
  ) async {
    final (controller, service) = await showApp(tester, onboarded: false);
    service.tap(_coachPayload);
    await controller.signOut();
    controller.onboardingComplete = true;
    controller.announce();
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await controller.resumeLocalProfile();
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 0);
  });

  testWidgets('a changed account discards a tap waiting for onboarding', (
    tester,
  ) async {
    final auth = MemoryAccountAuth(
      session: const AccountSession(uid: 'owner', email: 'owner@example.com'),
    );
    final (controller, service) = await showApp(
      tester,
      onboarded: false,
      auth: auth,
    );
    service.tap(_coachPayload);
    auth.session = const AccountSession(
      uid: 'other',
      email: 'other@example.com',
    );
    controller.onboardingComplete = true;
    controller.announce();
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyCenterScreen), findsOneWidget);
    await controller.acceptPrivacy(
      ageBand: PrivacyAgeBand.adult,
      region: PrivacyRegion.us,
      acknowledged: true,
    );
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 0);
  });

  testWidgets('unrelated or malformed payloads leave navigation alone', (
    tester,
  ) async {
    final (_, service) = await showApp(tester);
    for (final payload in [
      '',
      'other-app:coach:plan',
      'tonyo-guidance:',
      'tonyo-guidance:unknown',
      'tonyo-guidance:coach:',
      'tonyo-guidance:coach:%XX',
      'tonyo-guidance:coach:%0A',
    ]) {
      service.tap(payload);
      await tester.pump();
      expect(selectedTab(tester), 0, reason: payload);
    }
  });

  testWidgets('response initialization failure does not block normal launch', (
    tester,
  ) async {
    await showApp(tester, failInitialization: true);
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late notification callback cannot navigate a disposed app', (
    tester,
  ) async {
    final (_, service) = await showApp(tester);
    await tester.pumpWidget(const SizedBox());
    service.tap(_coachPayload);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _NavigationController extends AppController {
  _NavigationController({
    required NotificationService service,
    required bool consented,
    this.loadGate,
    MemoryAccountAuth? auth,
  }) : super(
         notificationService: service,
         initialPrivacyConsent: consented ? testAdultPrivacyConsent : null,
         accountAuth: auth,
         healthService: _NoHealth(),
         screenTimeService: _NoScreenTime(),
       );

  final Completer<void>? loadGate;

  @override
  Future<void> load() async {
    await loadGate?.future;
    isReady = true;
    notifyListeners();
  }

  void announce() => notifyListeners();
}

class _TapNotifications
    implements NotificationService, NotificationResponseSource {
  _TapNotifications({this.launchPayload, this.failInitialization = false});

  final String? launchPayload;
  final bool failInitialization;
  void Function(String)? _onTap;
  bool _launchConsumed = false;

  void tap(String payload) => _onTap?.call(payload);

  @override
  Future<void> initializeResponses(void Function(String payload) onTap) async {
    if (failInitialization) throw StateError('Platform unavailable');
    _onTap = onTap;
    if (!_launchConsumed && launchPayload != null) {
      _launchConsumed = true;
      onTap(launchPayload!);
    }
  }

  @override
  bool get supportsScheduling => false;
  @override
  Future<void> cancelGuidance() async {}
  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.unavailable;
  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.unavailable;
  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {}
}

class _NoHealth extends HealthService {
  @override
  Future<HealthAuthorizationState> authorizationStatus() async =>
      HealthAuthorizationState.unavailable;
  @override
  Future<void> disableBackgroundUpdates() async {}
}

class _NoScreenTime extends ScreenTimeService {
  @override
  Future<ScreenTimeAuthorizationState> authorizationStatus() async =>
      ScreenTimeAuthorizationState.unavailable;
}
