import 'privacy_test_support.dart';
import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:app/src/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'sign-out removes pushed routes and back cannot reopen the profile',
    (tester) async {
      final controller =
          AppController(
              initialPrivacyConsent: testAdultPrivacyConsent,
              healthService: _NoHealth(),
              screenTimeService: _NoScreenTime(),
              notificationService: _NoNotifications(),
            )
            ..isReady = true
            ..onboardingComplete = true;
      addTearDown(controller.dispose);
      await tester.pumpWidget(TonyoApp(controller: controller));
      final privateNavigator = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      privateNavigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Private detail route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private detail route'), findsOneWidget);
      expect(privateNavigator.canPop(), isTrue);

      await controller.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Private detail route'), findsNothing);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      final welcomeNavigator = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      expect(welcomeNavigator.canPop(), isFalse);
      expect(await welcomeNavigator.maybePop(), isFalse);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await controller.resumeLocalProfile();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Private detail route'), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    },
  );
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

class _NoNotifications implements NotificationService {
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
