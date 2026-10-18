import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/device_backup_service.dart';
import 'package:app/src/screens/study_tools_screen.dart';
import 'package:app/src/screens/research_export_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StudyController extends AppController {
  bool enabled = false;
  bool active = false;
  bool busy = false;
  bool exportAllowed = true;
  int revision = 0;
  String? uid;
  String? captureError;
  bool failExport = false;
  final starts = <({Ai1SleepSource source, int days})>[];
  int exportCalls = 0;

  static final exported = jsonEncode({
    'rawMeasurements': [
      {'sourceId': 'synthetic-private-raw-sentinel'},
    ],
    'readiness': {
      'modelingReady': false,
      'coverage': {
        'opportunities': 4,
        'completedOutcomes': 2,
        'pairedOutcomes': 1,
      },
    },
  });

  @override
  bool get ai1CaptureEnabled => enabled;
  @override
  bool get ai1CaptureBusy => busy;
  @override
  String? get ai1CaptureError => captureError;
  @override
  bool get ai1StudyActive => active && enabled;
  @override
  String get ai1StudyStatus => ai1StudyActive
      ? '2026-10-18 – 2026-11-14 · manual'
      : 'No study plan started.';
  @override
  bool get canExportDeviceBackup => exportAllowed && !isSignedOut;
  @override
  int get sessionRevision => revision;
  @override
  String? get cloudUid => uid;

  @override
  Future<void> startAi1Study({
    required Ai1SleepSource source,
    required int days,
  }) async {
    starts.add((source: source, days: days));
    active = true;
    notifyListeners();
  }

  @override
  String exportAi1Study() {
    exportCalls++;
    if (failExport) throw StateError('sensitive-internal-diagnostic');
    return exported;
  }

  void changed() => notifyListeners();
}

class _StudyFileService extends DeviceBackupService {
  bool supported = true;
  bool saved = true;
  bool fails = false;
  Completer<bool>? pending;
  final files = <({String json, String filename})>[];

  @override
  bool get isSupported => supported;

  @override
  Future<bool> save({required String json, required String filename}) async {
    files.add((json: json, filename: filename));
    if (fails) throw StateError('sensitive-file-diagnostic');
    return pending == null ? saved : await pending!.future;
  }
}

Future<void> _open(
  WidgetTester tester,
  _StudyController controller,
  _StudyFileService service, {
  double scale = 1,
  bool expandLegacy = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTonyoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: StudyToolsScreen(controller: controller, backupService: service),
    ),
  );
  await tester.pumpAndSettle();
  if (expandLegacy && controller.ai1StudyActive && !controller.isSignedOut) {
    await _tap(tester, 'study-legacy');
    await tester.pumpAndSettle();
  }
}

Future<void> _reach(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    350,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('study-tools-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reach(tester, key);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

Future<void> _confirmExport(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const Key('study-export-confirm')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'opening offers untimed collection without starting a fixed plan',
    (tester) async {
      final controller = _StudyController();
      final service = _StudyFileService();
      await _open(tester, controller, service);
      expect(controller.starts, isEmpty);
      expect(controller.exportCalls, 0);
      expect(service.files, isEmpty);
      expect(find.text('Morning: record Energy only.'), findsOneWidget);
      expect(
        find.textContaining(
          'Evening: record your check-in and last main sleep.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('You can save either at any time.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('study-start')), findsNothing);
      expect(find.byKey(const Key('study-days')), findsNothing);
      expect(find.byKey(const Key('study-legacy')), findsNothing);
      expect(find.textContaining('Sleep must be saved by'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('study-measurement-export')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'measurement export opens without reading or writing a study export',
    (tester) async {
      final controller = _StudyController();
      final service = _StudyFileService();
      await _open(tester, controller, service);
      await _tap(tester, 'study-measurement-export');
      await tester.pumpAndSettle();
      expect(find.byType(ResearchExportScreen), findsOneWidget);
      expect(find.byKey(const Key('research-study-code')), findsOneWidget);
      expect(controller.starts, isEmpty);
      expect(controller.exportCalls, 0);
      expect(service.files, isEmpty);
    },
  );

  testWidgets('existing fixed plan is collapsed until explicitly opened', (
    tester,
  ) async {
    final controller = _StudyController()
      ..enabled = true
      ..active = true;
    final service = _StudyFileService();
    await _open(tester, controller, service, expandLegacy: false);
    expect(find.byKey(const Key('study-flexible-collection')), findsOneWidget);
    expect(find.text('Earlier fixed-schedule study'), findsOneWidget);
    expect(find.byKey(const Key('study-assess')), findsNothing);
    expect(find.textContaining('Sleep must be saved by'), findsNothing);
    await _tap(tester, 'study-legacy');
    await tester.pumpAndSettle();
    await _reach(tester, 'study-assess');
    expect(find.byKey(const Key('study-assess')), findsOneWidget);
    expect(find.textContaining('Sleep must be saved by'), findsOneWidget);
    expect(find.byKey(const Key('study-start')), findsNothing);
    expect(controller.starts, isEmpty);
    expect(controller.exportCalls, 0);
    expect(service.files, isEmpty);
  });

  testWidgets('assessment displays aggregates only and never saves a file', (
    tester,
  ) async {
    final controller = _StudyController()
      ..enabled = true
      ..active = true;
    final service = _StudyFileService();
    await _open(tester, controller, service);
    await _tap(tester, 'study-assess');
    await _reach(tester, 'study-readiness-summary');
    expect(controller.exportCalls, 1);
    expect(find.text('Closed opportunities: 4'), findsOneWidget);
    expect(find.text('Completed Energy outcomes: 2'), findsOneWidget);
    expect(find.text('Paired days: 1'), findsOneWidget);
    expect(find.text('Modeling readiness is not established.'), findsOneWidget);
    expect(find.textContaining('synthetic-private-raw-sentinel'), findsNothing);
    expect(service.files, isEmpty);
    controller.enabled = false;
    controller.changed();
    await tester.pump();
    controller.enabled = true;
    controller.changed();
    await tester.pump();
    expect(find.byKey(const Key('study-readiness-summary')), findsNothing);
  });

  testWidgets(
    'private export requires confirmation and does not copy to clipboard',
    (tester) async {
      final controller = _StudyController()
        ..enabled = true
        ..active = true;
      final service = _StudyFileService();
      final clipboardCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _open(tester, controller, service);
      await _tap(tester, 'study-export');
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.exportCalls, 0);
      expect(service.files, isEmpty);
      expect(
        find.textContaining('cannot recall saved or shared files'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('study-export-cancel')));
      await tester.pumpAndSettle();
      expect(controller.exportCalls, 0);
      await _tap(tester, 'study-export');
      await _confirmExport(tester);
      await tester.pumpAndSettle();
      expect(controller.exportCalls, 1);
      expect(service.files.single.json, _StudyController.exported);
      expect(
        service.files.single.filename,
        matches(r'^tonyo-private-study-\d+\.json$'),
      );
      expect(clipboardCalls, isEmpty);
      expect(
        find.textContaining('synthetic-private-raw-sentinel'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'session changes during confirmation prevent reading or saving another account',
    (tester) async {
      final controller = _StudyController()
        ..enabled = true
        ..active = true
        ..uid = 'old-owner';
      final service = _StudyFileService();
      await _open(tester, controller, service);
      await _tap(tester, 'study-export');
      controller.uid = 'new-owner';
      controller.revision++;
      controller.changed();
      await _confirmExport(tester);
      await tester.pumpAndSettle();
      expect(controller.exportCalls, 0);
      expect(service.files, isEmpty);
      expect(find.byKey(const Key('study-action-message')), findsNothing);
    },
  );

  testWidgets(
    'completion after session change cannot display stale export success',
    (tester) async {
      final controller = _StudyController()
        ..enabled = true
        ..active = true;
      final pending = Completer<bool>();
      final service = _StudyFileService()..pending = pending;
      await _open(tester, controller, service);
      await _tap(tester, 'study-export');
      await _confirmExport(tester);
      expect(service.files, hasLength(1));
      controller.revision++;
      controller.changed();
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('study-action-message')), findsNothing);
    },
  );

  testWidgets('busy and signed-out sessions block assessment and export', (
    tester,
  ) async {
    final controller = _StudyController()
      ..enabled = true
      ..active = true
      ..busy = true;
    final service = _StudyFileService();
    await _open(tester, controller, service);
    await _reach(tester, 'study-export');
    for (final key in ['study-assess', 'study-export']) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(Key(key))).onPressed,
        isNull,
      );
    }
    controller.busy = false;
    controller.isSignedOut = true;
    controller.changed();
    await tester.pump();
    expect(find.byKey(const Key('study-legacy')), findsNothing);
    expect(find.byKey(const Key('study-assess')), findsNothing);
    expect(find.byKey(const Key('study-export')), findsNothing);
    await _reach(tester, 'study-measurement-export');
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('study-measurement-export')),
          )
          .onPressed,
      isNull,
    );
    expect(controller.exportCalls, 0);
    expect(service.files, isEmpty);
  });

  testWidgets('unsupported file saving has no clipboard fallback', (
    tester,
  ) async {
    final controller = _StudyController()
      ..enabled = true
      ..active = true;
    final service = _StudyFileService()..supported = false;
    await _open(tester, controller, service);
    await _reach(tester, 'study-export');
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('study-export')))
          .onPressed,
      isNull,
    );
    expect(
      find.text('Saving a private file is unavailable on this device.'),
      findsOneWidget,
    );
    expect(controller.exportCalls, 0);
  });

  testWidgets('canceled file picker never reports a saved export', (
    tester,
  ) async {
    final controller = _StudyController()
      ..enabled = true
      ..active = true;
    final service = _StudyFileService()..saved = false;
    await _open(tester, controller, service);
    await _tap(tester, 'study-export');
    await _confirmExport(tester);
    await tester.pumpAndSettle();
    await _reach(tester, 'study-action-message');
    expect(find.text('Export canceled. No file was saved.'), findsOneWidget);
    expect(find.textContaining('Private study export saved.'), findsNothing);
  });

  testWidgets('failed assessment shows no partial or raw data', (tester) async {
    final controller = _StudyController()
      ..enabled = true
      ..active = true
      ..failExport = true;
    final service = _StudyFileService();
    await _open(tester, controller, service);
    await _tap(tester, 'study-assess');
    await _reach(tester, 'study-action-message');
    expect(
      find.text('Could not assess local history. Please try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('study-readiness-summary')), findsNothing);
    expect(find.textContaining('sensitive-internal-diagnostic'), findsNothing);
    expect(service.files, isEmpty);
  });

  testWidgets('file failures show sanitized messages', (tester) async {
    final controller = _StudyController()
      ..enabled = true
      ..active = true;
    final service = _StudyFileService()..fails = true;
    await _open(tester, controller, service);
    await _tap(tester, 'study-export');
    await _confirmExport(tester);
    await tester.pumpAndSettle();
    await _reach(tester, 'study-action-message');
    expect(
      find.text('Could not save the private study export. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('sensitive-file-diagnostic'), findsNothing);
  });

  testWidgets('large text keeps plan and export dialog usable', (tester) async {
    final controller = _StudyController()
      ..enabled = true
      ..active = true;
    await _open(tester, controller, _StudyFileService(), scale: 2);
    await _tap(tester, 'study-export');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('study-export-cancel')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
