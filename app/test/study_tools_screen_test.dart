import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/device_backup_service.dart';
import 'package:app/src/screens/study_tools_screen.dart';
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
  bool failStart = false;
  bool failExport = false;
  Completer<void>? startPending;
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
    await startPending?.future;
    if (failStart) throw StateError('sensitive-internal-diagnostic');
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

  testWidgets('opening is inert; history and plan stay off', (tester) async {
    final controller = _StudyController();
    final service = _StudyFileService();
    await _open(tester, controller, service);
    expect(controller.starts, isEmpty);
    expect(controller.exportCalls, 0);
    expect(service.files, isEmpty);
    expect(find.text('No study plan started.'), findsOneWidget);
    expect(
      find.textContaining('Enable “Keep local study history”'),
      findsOneWidget,
    );
    await _reach(tester, 'study-start');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('study-start')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('study-days')))
          .controller!
          .text,
      '28',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<Ai1SleepSource>>(
            find.byKey(const Key('study-source')),
          )
          .initialValue,
      Ai1SleepSource.manual,
    );
  });

  testWidgets(
    'explicit start freezes chosen source and days; pending work disables controls',
    (tester) async {
      final pending = Completer<void>();
      final controller = _StudyController()
        ..enabled = true
        ..startPending = pending;
      final service = _StudyFileService();
      await _open(tester, controller, service);
      await _tap(tester, 'study-source');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apple Health').last);
      await tester.pumpAndSettle();
      await _reach(tester, 'study-days');
      await tester.enterText(find.byKey(const Key('study-days')), '14');
      await _tap(tester, 'study-start');
      expect(controller.starts, [
        (source: Ai1SleepSource.appleHealth, days: 14),
      ]);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('study-start')))
            .onPressed,
        isNull,
      );
      expect(controller.exportCalls, 0);
      pending.complete();
      await tester.pumpAndSettle();
      expect(controller.ai1StudyActive, isTrue);
      expect(find.byKey(const Key('study-days')), findsNothing);
      expect(find.byKey(const Key('study-source')), findsNothing);
      expect(service.files, isEmpty);
    },
  );

  testWidgets('invalid calendar counts cannot start and 366 is permitted', (
    tester,
  ) async {
    final controller = _StudyController()..enabled = true;
    await _open(tester, controller, _StudyFileService());
    await _reach(tester, 'study-days');
    for (final value in ['', '0', '367']) {
      await tester.enterText(find.byKey(const Key('study-days')), value);
      await tester.pump();
      await _reach(tester, 'study-start');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('study-start')))
            .onPressed,
        isNull,
      );
    }
    await _reach(tester, 'study-days');
    await tester.enterText(find.byKey(const Key('study-days')), '366');
    await tester.pump();
    await _tap(tester, 'study-start');
    await tester.pumpAndSettle();
    expect(controller.starts.single.days, 366);
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
    for (final key in ['study-assess', 'study-export']) {
      expect(
        tester.widget<OutlinedButton>(find.byKey(Key(key))).onPressed,
        isNull,
      );
    }
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

  testWidgets('start and file failures show sanitized messages', (
    tester,
  ) async {
    final controller = _StudyController()
      ..enabled = true
      ..failStart = true;
    final service = _StudyFileService()..fails = true;
    await _open(tester, controller, service);
    await _tap(tester, 'study-start');
    await tester.pumpAndSettle();
    await _reach(tester, 'study-action-message');
    expect(
      find.textContaining('Could not start the study plan.'),
      findsOneWidget,
    );
    expect(find.textContaining('sensitive-internal-diagnostic'), findsNothing);
    controller.active = true;
    controller.changed();
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
