import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:app/src/screens/onboarding_screen.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

Widget _app(AppController controller, Widget home) => AppScope(
  controller: controller,
  child: ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      locale: localeForLanguage(controller.effectiveLanguage),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTonyoTheme(),
      home: Scaffold(body: home),
    ),
  ),
);

void _largeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pickLanguage(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('onboarding-language-picker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'signup switches to Spanish before consent and retains youth protections',
    (tester) async {
      _largeView(tester);
      final controller = AppController()..isReady = true;
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller, const OnboardingScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Create my account'), findsOneWidget);
      expect(controller.effectiveLanguage, 'en');

      await _pickLanguage(tester, 'Español');
      expect(find.text('Crear mi cuenta'), findsOneWidget);
      expect(controller.effectiveLanguage, 'es');
      expect(controller.profile.preferredLanguage, 'en');
      expect(controller.privacyConsent, isNull);
      await tester.tap(find.text('Crear mi cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Antes de empezar'), findsOneWidget);
      expect(
        find.textContaining('No necesitamos tu fecha de nacimiento'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('privacy-age-band')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16–17').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Se necesita la autorización de un tutor'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Configuración de tutor no disponible',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(controller.privacyConsent, isNull);
      expect(controller.onboardingComplete, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Spanish signup fits a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController()..isReady = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        controller,
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.4),
          ),
          child: OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _pickLanguage(tester, 'Español');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Crear mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Antes de empezar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Chinese signup carries the selected language through ordinary consent',
    (tester) async {
      _largeView(tester);
      final controller = _SignupController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller, const OnboardingScreen()));
      await tester.pumpAndSettle();
      await _pickLanguage(tester, '简体中文');
      await tester.tap(find.text('创建我的账户'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-age-band')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('18 岁及以上').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-region')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('美国').last);
      await tester.pumpAndSettle();
      final checkbox = find.descendant(
        of: find.byKey(const Key('privacy-acknowledgement')),
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
      await tester.tap(find.text('按这些选择继续'));
      await tester.pumpAndSettle();
      expect(controller.privacyConsent?.ageBand, PrivacyAgeBand.adult);
      await tester.enterText(
        find.widgetWithText(TextFormField, '电子邮箱'),
        'synthetic@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('password-field')),
        'synthetic-password',
      );
      await tester.enterText(
        find.byKey(const Key('confirm-password-field')),
        'synthetic-password',
      );
      await tester.tap(find.text('继续设置个人资料'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '名字'), 'Synthetic');
      await tester.tap(find.text('设置我的作息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用演示数据开始'));
      await tester.pumpAndSettle();
      expect(controller.submitted?.preferredLanguage, 'zh-Hans');
      expect(controller.submitted?.role, 'Student athlete');
      expect(controller.submitted?.goal, 'Balance focus and training');
      expect(controller.submitted?.name, 'Synthetic');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings changes immediately to Traditional Chinese and persists on reload',
    (tester) async {
      _largeView(tester);
      final controller =
          AppController(initialPrivacyConsent: testAdultPrivacyConsent)
            ..isReady = true
            ..onboardingComplete = true
            ..profile = const UserProfile(name: 'Synthetic');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller, const ProfileScreen()));
      await tester.pumpAndSettle();
      final setting = find.byKey(const Key('language-preference-setting'));
      await tester.scrollUntilVisible(
        setting,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(setting);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-choice-zh-Hant')));
      await tester.pumpAndSettle();
      expect(controller.profile.preferredLanguage, 'zh-Hant');
      expect(find.text('語言'), findsWidgets);
      expect(find.text('關閉'), findsOneWidget);
      await tester.tap(find.byKey(const Key('language-close')));
      await tester.pumpAndSettle();
      expect(find.text('設置'), findsOneWidget);
      expect(controller.profile.name, 'Synthetic');

      final restarted = AppController();
      addTearDown(restarted.dispose);
      await tester.runAsync(restarted.load);
      expect(restarted.profile.preferredLanguage, 'zh-Hant');
      expect(restarted.profile.name, 'Synthetic');
      expect(restarted.privacyConsent?.ageBand, PrivacyAgeBand.adult);
      expect(tester.takeException(), isNull);
    },
  );
}

class _SignupController extends AppController {
  _SignupController() {
    isReady = true;
  }
  UserProfile? submitted;

  @override
  Future<void> completeOnboarding(
    UserProfile newProfile, {
    String? email,
    String? password,
    bool signInToExistingAccount = false,
  }) async {
    submitted = newProfile;
  }
}
