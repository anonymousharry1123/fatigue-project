import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/device_backup_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/backup_restore_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

final _at = DateTime.utc(2026, 9, 19, 12);

SignalReading _signal(String id, [double value = 1]) => SignalReading(
  id: id,
  type: SignalType.hydration,
  value: value,
  timestamp: _at,
);

Map<String, Object?> _local(
  List<SignalReading> signals, {
  String name = 'Backup name',
}) => {
  'profile': UserProfile(name: name).toJson(),
  'signals': signals.map((item) => item.toJson()).toList(),
  'checkIns': [],
  'outcomes': [],
  'outcomeConsent': false,
};

String _backup(List<SignalReading> signals, {List<SignalReading>? recovery}) =>
    jsonEncode({
      'backupVersion': 1,
      'backupType': 'tonyoDeviceData',
      'ownerUid': null,
      'local': _local(signals),
      if (recovery != null)
        'beforeCloudRestore': {
          'ownerUid': null,
          'local': _local(recovery, name: 'Recovery name'),
        },
    });

class _BackupService extends DeviceBackupService {
  _BackupService(this.response);
  String? response;
  Completer<String?>? picker;
  PlatformException? error;
  int opens = 0;

  @override
  bool get isSupported => true;

  @override
  Future<String?> open() async {
    opens++;
    if (error != null) throw error!;
    return picker == null ? response : await picker!.future;
  }
}

AppController _controller({List<SignalReading> signals = const []}) =>
    AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => _at,
      )
      ..signals = [...signals]
      ..profile = const UserProfile(name: 'Phone name')
      ..isReady = true;

Future<void> _pump(
  WidgetTester tester,
  AppController controller,
  _BackupService service, {
  bool narrow = false,
}) async {
  if (narrow) {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTonyoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
        child: child!,
      ),
      home: BackupRestoreScreen(controller: controller, service: service),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  await tester.scrollUntilVisible(finder, delta);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await _reveal(tester, find.byKey(const Key('backup-import-open')));
  await tester.tap(find.byKey(const Key('backup-import-open')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('canceling the file picker leaves phone data unchanged', (
    tester,
  ) async {
    final controller = _controller(signals: [_signal('phone', 2)]);
    addTearDown(controller.dispose);
    final service = _BackupService(null);
    await _pump(tester, controller, service);
    await _open(tester);
    expect(service.opens, 1);
    expect(find.text('Backup preview'), findsNothing);
    expect(find.byKey(const Key('backup-import-confirm')), findsNothing);
    expect(controller.signals.single.id, 'phone');
    expect(controller.signals.single.value, 2);
    expect(controller.profile.name, 'Phone name');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid JSON shows an error and a valid second file can be previewed',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final service = _BackupService('{');
      await _pump(tester, controller, service);
      await _open(tester);
      expect(find.textContaining('Unexpected'), findsOneWidget);
      expect(find.text('Backup preview'), findsNothing);
      expect(controller.signals, isEmpty);
      service.response = _backup([_signal('valid')]);
      await _open(tester);
      expect(find.text('Backup preview'), findsOneWidget);
      expect(find.textContaining('Unexpected'), findsNothing);
      expect(controller.signals, isEmpty);
    },
  );

  testWidgets(
    'an invalid replacement file clears the previous restorable preview',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final service = _BackupService(_backup([_signal('previous-file')]));
      await _pump(tester, controller, service);
      await _open(tester);
      expect(find.text('Backup preview'), findsOneWidget);
      service.response = '{';
      await _open(tester);
      expect(find.textContaining('Unexpected'), findsOneWidget);
      expect(find.text('Backup preview'), findsNothing);
      expect(find.byKey(const Key('backup-import-confirm')), findsNothing);
      expect(controller.signals, isEmpty);
    },
  );

  testWidgets('a native read failure clears the previous restorable preview', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    final service = _BackupService(_backup([_signal('previous-file')]));
    await _pump(tester, controller, service);
    await _open(tester);
    expect(find.text('Backup preview'), findsOneWidget);
    service.error = PlatformException(
      code: 'backup_read_failed',
      message: 'The selected file could not be read.',
    );
    await _open(tester);
    expect(find.text('The selected file could not be read.'), findsOneWidget);
    expect(find.text('Backup preview'), findsNothing);
    expect(find.byKey(const Key('backup-import-confirm')), findsNothing);
    expect(controller.signals, isEmpty);
    expect(controller.profile.name, 'Phone name');
  });

  testWidgets(
    'preview never mutates data and default confirmation keeps differing phone values',
    (tester) async {
      final controller = _controller(signals: [_signal('existing', 2)]);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        controller,
        _BackupService(_backup([_signal('existing', 3), _signal('new', 4)])),
      );
      await _open(tester);
      expect(controller.signals, hasLength(1));
      expect(controller.signals.single.value, 2);
      expect(controller.profile.name, 'Phone name');
      final replace = find.byKey(const Key('backup-import-replace'));
      await _reveal(tester, replace);
      expect(tester.widget<CheckboxListTile>(replace).value, false);
      final profile = find.byKey(const Key('backup-import-profile'));
      expect(tester.widget<CheckboxListTile>(profile).value, false);
      final confirm = find.byKey(const Key('backup-import-confirm'));
      await _reveal(tester, confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(controller.signals, hasLength(2));
      expect(
        controller.signals.firstWhere((item) => item.id == 'existing').value,
        2,
      );
      expect(
        controller.signals.firstWhere((item) => item.id == 'new').value,
        4,
      );
      expect(controller.profile.name, 'Phone name');
      expect(find.text('Backup restored to this device.'), findsOneWidget);
    },
  );

  testWidgets('differing records require explicit replacement selection', (
    tester,
  ) async {
    final controller = _controller(signals: [_signal('existing', 2)]);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      _BackupService(_backup([_signal('existing', 3)])),
    );
    await _open(tester);
    final confirm = find.byKey(const Key('backup-import-confirm'));
    await _reveal(tester, confirm);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    final replace = find.byKey(const Key('backup-import-replace'));
    await _reveal(tester, replace, delta: -250);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(replace).value, true);
    expect(controller.signals.single.value, 2);
    await _reveal(tester, confirm);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(controller.signals.single.value, 3);
    expect(controller.profile.name, 'Phone name');
  });

  testWidgets(
    'profile restore is opt in and enables a preview containing only duplicates',
    (tester) async {
      final controller = _controller(signals: [_signal('existing', 2)]);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        controller,
        _BackupService(_backup([_signal('existing', 2)])),
      );
      await _open(tester);
      final confirm = find.byKey(const Key('backup-import-confirm'));
      await _reveal(tester, confirm);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      final profile = find.byKey(const Key('backup-import-profile'));
      await _reveal(tester, profile, delta: -250);
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(controller.profile.name, 'Phone name');
      await _reveal(tester, confirm);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(controller.profile.name, 'Backup name');
      expect(controller.signals.single.value, 2);
    },
  );

  testWidgets(
    'recovery selector previews and restores only the chosen saved copy',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        controller,
        _BackupService(
          _backup(
            [_signal('main')],
            recovery: [_signal('recovery-a'), _signal('recovery-b')],
          ),
        ),
      );
      await _open(tester);
      expect(find.textContaining('1 new records'), findsOneWidget);
      final recovery = find.text('Recovery copy before cloud restore');
      await _reveal(tester, recovery);
      await tester.tap(recovery);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 new records'), findsOneWidget);
      expect(find.text('Restore profile for Recovery name'), findsOneWidget);
      expect(controller.signals, isEmpty);
      final confirm = find.byKey(const Key('backup-import-confirm'));
      await _reveal(tester, confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(controller.signals.map((item) => item.id).toSet(), {
        'recovery-a',
        'recovery-b',
      });
      expect(controller.profile.name, 'Phone name');
    },
  );

  testWidgets(
    'a native file returned after session ends cannot create a preview',
    (tester) async {
      final controller = _controller(signals: [_signal('phone')]);
      addTearDown(controller.dispose);
      final picker = Completer<String?>();
      final service = _BackupService(null)..picker = picker;
      await _pump(tester, controller, service);
      await tester.tap(find.byKey(const Key('backup-import-open')));
      await tester.pump();
      expect(service.opens, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('backup-import-open')))
            .onPressed,
        isNull,
      );
      await tester.runAsync(controller.signOut);
      picker.complete(_backup([_signal('unwanted')]));
      await tester.pumpAndSettle();
      expect(find.text('Backup preview'), findsNothing);
      expect(controller.signals.single.id, 'phone');
      expect(controller.isSignedOut, true);
    },
  );

  testWidgets('restore preview and controls fit 320px at 2x text', (
    tester,
  ) async {
    final controller = _controller(signals: [_signal('existing', 2)]);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      _BackupService(
        _backup(
          [_signal('existing', 3), _signal('new')],
          recovery: [_signal('recovery')],
        ),
      ),
      narrow: true,
    );
    await _open(tester);
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    for (
      var index = 0;
      index < 60 && position.pixels < position.maxScrollExtent;
      index++
    ) {
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(position.pixels, position.maxScrollExtent);
    expect(find.byKey(const Key('backup-import-confirm')), findsOneWidget);
    expect(controller.signals.single.value, 2);
  });
}
