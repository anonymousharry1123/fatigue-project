import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/device_backup_service.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/screens/questionnaire_library_screen.dart';
import 'package:app/src/screens/research_export_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _RecordingBackupService extends DeviceBackupService {
  int saves = 0;
  int opens = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> save({required String json, required String filename}) async {
    saves++;
    return true;
  }

  @override
  Future<String?> open() async {
    opens++;
    return null;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Profile opens research export without preparing or saving data',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final service = _RecordingBackupService();
      await _pumpProfile(tester, controller, service);
      final before = controller.exportJson();

      await _openSetting(tester, 'research-export-setting');

      expect(find.byType(ResearchExportScreen), findsOneWidget);
      expect(
        tester
            .widget<ResearchExportScreen>(find.byType(ResearchExportScreen))
            .controller,
        same(controller),
      );
      expect(
        tester
            .widget<ResearchExportScreen>(find.byType(ResearchExportScreen))
            .service,
        same(service),
      );
      expect(find.byKey(const Key('research-prepare')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('research-study-code')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const Key('research-export-summary')), findsNothing);
      expect(find.byKey(const Key('research-save-json')), findsNothing);
      expect(find.byKey(const Key('research-copy-json')), findsNothing);
      expect(find.byKey(const Key('research-copy-csv')), findsNothing);
      expect(service.saves, 0);
      expect(service.opens, 0);
      expect(controller.exportJson(), before);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(ResearchExportScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Profile opens a read-only questionnaire library and returns', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final service = _RecordingBackupService();
    await _pumpProfile(tester, controller, service);
    final before = controller.exportJson();

    await _openSetting(tester, 'questionnaire-library-setting');

    expect(find.byType(QuestionnaireLibraryScreen), findsOneWidget);
    expect(
      find.byKey(const Key('questionnaire-library-status')),
      findsOneWidget,
    );
    expect(find.text('Installed instruments: 0'), findsOneWidget);
    expect(find.text('No periodic questionnaire is available'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('questionnaire-library-daily-check-ins')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Daily check-ins stay separate'), findsOneWidget);
    expect(service.saves, 0);
    expect(service.opens, 0);
    expect(controller.exportJson(), before);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(QuestionnaireLibraryScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

AppController _controller() =>
    AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => DateTime.utc(2026, 10, 10, 12),
      )
      ..isReady = true
      ..onboardingComplete = true;

Future<void> _pumpProfile(
  WidgetTester tester,
  AppController controller,
  DeviceBackupService service,
) async {
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTonyoTheme(),
        home: Scaffold(body: ProfileScreen(backupService: service)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSetting(WidgetTester tester, String key) async {
  final setting = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    setting,
    350,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(setting);
  await tester.pumpAndSettle();
  await tester.tap(setting);
  await tester.pumpAndSettle();
}
