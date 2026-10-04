import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/activity_log_screen.dart';
import 'package:app/src/screens/daily_checkin_screen.dart';
import 'package:app/src/screens/daily_history_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 10, 4, 12);
  AppController controller() => AppController(
    initialPrivacyConsent: testAdultPrivacyConsent,
    clock: () => now,
  );
  Future<void> pump(
    WidgetTester tester,
    AppController controller,
    Widget screen,
    String language,
  ) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          locale: localeForLanguage(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTonyoTheme(),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Spanish activity form preserves decimal comma, zero and blanks',
    (tester) async {
      final current = controller();
      addTearDown(current.dispose);
      await pump(tester, current, const ActivityLogScreen(), 'es');
      expect(find.text('Registro de actividad'), findsOneWidget);
      Finder field(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field('hydration-field'), '1,5');
      await tester.enterText(field('exercise-field'), '0');
      await tester.ensureVisible(find.text('Guardar actividad'));
      await tester.tap(find.text('Guardar actividad'));
      await tester.pumpAndSettle();
      final log = current.activityLogs.single;
      expect(log.hydrationLiters, 1.5);
      expect(log.exerciseHours, 0);
      expect(log.studyHours, isNull);
      expect(log.screenTimeHours, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Chinese check-in labels leave an authored-looking user note intact',
    (tester) async {
      final current = controller();
      addTearDown(current.dispose);
      current.checkIns = [
        DailyCheckIn(
          id: 'synthetic-note',
          timestamp: now,
          energy: 6,
          mood: 6,
          stress: 4,
          note: 'Save activity',
        ),
      ];
      await pump(tester, current, const DailyCheckInScreen(), 'zh-Hans');
      expect(find.text('每日状态记录'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Save activity'),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Save activity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history distinguishes an explicit zero from absent categories', (
    tester,
  ) async {
    final current = controller();
    addTearDown(current.dispose);
    await current.saveActivityLog(
      id: 'activity-zero-history',
      exerciseHours: 0,
      timestamp: now,
    );
    await pump(tester, current, const DailyHistoryScreen(), 'es');
    expect(find.text('0 h de ejercicio'), findsOneWidget);
    expect(find.textContaining('de estudio'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent activity card does not invent zero for blank fields', (
    tester,
  ) async {
    final current = controller();
    addTearDown(current.dispose);
    await current.saveActivityLog(
      id: 'activity-zero-card',
      exerciseHours: 0,
      timestamp: now,
    );
    await pump(tester, current, const ActivityLogScreen(), 'es');
    await tester.scrollUntilVisible(
      find.text('0 h de ejercicio'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0 h de ejercicio'), findsOneWidget);
    expect(find.text('0 h de estudio'), findsNothing);
    expect(find.text('0 h de pantalla'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
