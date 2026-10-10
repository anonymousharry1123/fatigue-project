import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/device_backup_service.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/research_export_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _SaveService extends DeviceBackupService {
  final payloads = <String>[];
  final filenames = <String>[];
  bool supported = true;
  bool saved = true;
  bool fail = false;
  Completer<bool>? pending;
  @override
  bool get isSupported => supported;
  @override
  Future<bool> save({required String json, required String filename}) async {
    payloads.add(json);
    filenames.add(filename);
    if (fail) throw StateError('save failed');
    return pending?.future ?? saved;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 10, 20);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  AppController controller() {
    final app = AppController(
      initialPrivacyConsent: testAdultPrivacyConsent,
      clock: () => now,
    );
    app.checkIns = [
      DailyCheckIn(
        id: 'private-id',
        timestamp: now,
        recordedAt: now,
        energy: 6,
        mood: null,
        stress: null,
        localDate: '2026-10-10',
        utcOffsetMinutes: 0,
        questionnaireLanguage: 'en',
        questionnaireVersion: CheckInMeasurement.currentVersion,
        source: 'selfReport',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (text) => text,
        ),
      ),
    ];
    addTearDown(app.dispose);
    return app;
  }

  testWidgets(
    'opening does not export; explicit prepare and save use reviewable snapshot',
    (tester) async {
      final app = controller();
      final service = _SaveService();
      await _pump(tester, app, service);
      expect(service.payloads, isEmpty);
      expect(find.byKey(const Key('research-export-summary')), findsNothing);
      await _prepare(tester);
      expect(
        find.text('1 responses · 1 partial · 0 sleep pairs · 0 excluded'),
        findsOneWidget,
      );
      app.checkIns.clear();
      await _tap(tester, 'research-save-json');
      expect(
        (jsonDecode(service.payloads.single)['responses'] as List).length,
        1,
      );
      expect(service.filenames.single, startsWith('tonyo-research-'));
      expect(service.payloads.single, isNot(contains('private-id')));
      expect(find.text('Research JSON saved.'), findsOneWidget);
    },
  );

  testWidgets('cancel and save error do not claim success; retry is possible', (
    tester,
  ) async {
    final service = _SaveService()..saved = false;
    await _pump(tester, controller(), service);
    await _prepare(tester);
    await _tap(tester, 'research-save-json');
    expect(find.text('Export canceled. No file was saved.'), findsOneWidget);
    service.fail = true;
    await _tap(tester, 'research-save-json');
    expect(
      find.text('Could not save the research export. Retry or use Copy JSON.'),
      findsOneWidget,
    );
    service.fail = false;
    service.saved = true;
    await _tap(tester, 'research-save-json');
    expect(find.text('Research JSON saved.'), findsOneWidget);
  });

  testWidgets(
    'clipboard copy requires explicit confirmation and cancels on session change',
    (tester) async {
      final app = controller();
      final copies = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, app, _SaveService()..supported = false);
      await _prepare(tester);
      expect(find.byKey(const Key('research-save-json')), findsNothing);
      await _tap(tester, 'research-copy-csv');
      expect(copies, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(copies, isEmpty);
      await _tap(tester, 'research-copy-csv');
      await tester.runAsync(app.signOut);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('research-copy-confirm')));
      await tester.pumpAndSettle();
      expect(copies, isEmpty);
      expect(find.byKey(const Key('research-export-summary')), findsNothing);
    },
  );

  testWidgets('CSV confirmation copies only the prepared response table', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, controller(), _SaveService()..supported = false);
    await _prepare(tester);
    await _tap(tester, 'research-copy-csv');
    await tester.tap(find.byKey(const Key('research-copy-confirm')));
    await tester.pumpAndSettle();
    expect(copied, startsWith('"study_code","response_ref"'));
    expect(copied, contains('"P001"'));
    expect(copied, isNot(contains('private-id')));
  });

  testWidgets('invalid study code does not prepare data or open native saver', (
    tester,
  ) async {
    final service = _SaveService();
    await _pump(tester, controller(), service);
    await tester.enterText(
      find.byKey(const Key('research-study-code')),
      'email@example.com',
    );
    await _tap(tester, 'research-prepare');
    expect(find.byKey(const Key('research-export-summary')), findsNothing);
    expect(service.payloads, isEmpty);
    expect(find.textContaining('Use a study code of 1–32'), findsOneWidget);
  });

  for (final language in ['en', 'es', 'zh-Hans', 'zh-Hant']) {
    testWidgets('$language research export fits at 320px and 2x text', (
      tester,
    ) async {
      await _pump(
        tester,
        controller(),
        _SaveService(),
        language: language,
        large: true,
      );
      await _prepare(tester);
      await tester.ensureVisible(find.byKey(const Key('research-copy-json')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _prepare(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('research-study-code')), 'P001');
  await _tap(tester, 'research-prepare');
}

Future<void> _pump(
  WidgetTester tester,
  AppController app,
  DeviceBackupService service, {
  String language = 'en',
  bool large = false,
}) async {
  tester.view.physicalSize = Size(large ? 320 : 390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: localeForLanguage(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTonyoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
        child: child!,
      ),
      home: ResearchExportScreen(controller: app, service: service),
    ),
  );
  await tester.pumpAndSettle();
}
