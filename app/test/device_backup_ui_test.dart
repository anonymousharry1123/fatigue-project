import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/device_backup_service.dart';
import 'package:app/src/screens/privacy_center_screen.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _BackupController extends AppController {
  _BackupController() : super(initialPrivacyConsent: testAdultPrivacyConsent) {
    isReady = true;
    onboardingComplete = true;
  }

  bool cloud = true;
  bool review = false;
  int revision = 0;
  int backupCalls = 0;
  int accountExportCalls = 0;
  int retryCalls = 0;
  int signOutCalls = 0;
  Completer<String>? snapshot;
  Completer<void>? retry;
  Completer<void>? signOutRequest;
  static const backup = '{"local":{"unsynced":"phone-data"}}';

  @override
  bool get isCloudAuthenticated => cloud;
  @override
  bool get hasPendingCloudChanges => cloud;
  @override
  bool get privacyReviewRequired => review;
  @override
  bool get canExportDeviceBackup =>
      !isSignedOut && !isDeletingAccount && !deletionPending;
  @override
  int get sessionRevision => revision;

  @override
  Future<String> exportDeviceBackup() async {
    backupCalls++;
    return snapshot == null ? backup : await snapshot!.future;
  }

  @override
  Future<String> exportAllData() async {
    accountExportCalls++;
    throw StateError('Cloud is offline');
  }

  @override
  Future<void> retryCloudSync() async {
    retryCalls++;
    await retry?.future;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await signOutRequest?.future;
    isSignedOut = true;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

class _BackupService extends DeviceBackupService {
  _BackupService({this.supported = true});
  final bool supported;
  final requests = <Completer<bool>>[];
  final exports = <String>[];
  final filenames = <String>[];

  @override
  bool get isSupported => supported;

  @override
  Future<bool> save({required String json, required String filename}) async {
    exports.add(json);
    filenames.add(filename);
    final request = Completer<bool>();
    requests.add(request);
    return request.future;
  }
}

Future<void> _open(
  WidgetTester tester,
  _BackupController controller,
  _BackupService service, {
  bool privacy = false,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: buildTonyoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: privacy
            ? PrivacyCenterScreen(
                controller: controller,
                requireReview: true,
                backupService: service,
              )
            : Scaffold(body: ProfileScreen(backupService: service)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Backup stays available during sync and preserves pending changes',
    (tester) async {
      final controller = _BackupController()..isCloudSyncing = true;
      final service = _BackupService();
      addTearDown(controller.dispose);
      await _open(tester, controller, service);
      await _reveal(tester, 'cloud-sync-save-backup');
      final submit = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('cloud-sync-save-backup')),
          )
          .onPressed!;
      submit();
      submit();
      await tester.pumpAndSettle();
      expect(service.exports, [_BackupController.backup]);
      expect(service.filenames.single, startsWith('tonyo-device-backup-'));
      expect(service.filenames.single, endsWith('.json'));
      expect(controller.backupCalls, 1);
      expect(controller.accountExportCalls, 0);
      expect(controller.retryCalls, 0);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('cloud-sync-save-backup')),
            )
            .onPressed,
        isNull,
      );
      service.requests.single.complete(true);
      await tester.pumpAndSettle();
      expect(
        find.text('Device backup saved. Your pending changes can still sync.'),
        findsOneWidget,
      );
      expect(controller.hasPendingCloudChanges, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final cancel in [true, false]) {
    testWidgets('Backup ${cancel ? 'cancellation' : 'failure'} allows retry', (
      tester,
    ) async {
      final controller = _BackupController();
      final service = _BackupService();
      addTearDown(controller.dispose);
      await _open(tester, controller, service);
      await _reveal(tester, 'cloud-sync-save-backup');
      await tester.tap(find.byKey(const Key('cloud-sync-save-backup')));
      await tester.pumpAndSettle();
      if (cancel) {
        service.requests.single.complete(false);
      } else {
        service.requests.single.completeError(StateError('File unavailable'));
      }
      await tester.pumpAndSettle();
      expect(
        find.text(
          cancel
              ? 'Backup canceled. No file was saved.'
              : 'Could not save device backup. Please try again.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('cloud-sync-save-backup')),
            )
            .onPressed,
        isNotNull,
      );
      expect(controller.hasPendingCloudChanges, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Local-only profile can save without a cloud recovery card', (
    tester,
  ) async {
    final controller = _BackupController()..cloud = false;
    final service = _BackupService();
    addTearDown(controller.dispose);
    await _open(tester, controller, service);
    expect(find.byKey(const Key('cloud-sync-recovery-card')), findsNothing);
    await _reveal(tester, 'device-backup-setting');
    await tester.tap(find.byKey(const Key('device-backup-setting')));
    await tester.pumpAndSettle();
    service.requests.single.complete(true);
    await tester.pumpAndSettle();
    expect(controller.backupCalls, 1);
    expect(controller.accountExportCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Snapshot cannot open a file picker after an account change', (
    tester,
  ) async {
    final controller = _BackupController()..snapshot = Completer<String>();
    final service = _BackupService();
    addTearDown(controller.dispose);
    await _open(tester, controller, service);
    await _reveal(tester, 'cloud-sync-save-backup');
    await tester.tap(find.byKey(const Key('cloud-sync-save-backup')));
    await tester.pumpAndSettle();
    controller.revision++;
    controller.snapshot!.complete(_BackupController.backup);
    await tester.pumpAndSettle();
    expect(service.requests, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Unsupported platform copies JSON only after explicit action', (
    tester,
  ) async {
    final controller = _BackupController();
    final service = _BackupService(supported: false);
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
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      controller.dispose();
    });
    await _open(tester, controller, service);
    await _reveal(tester, 'cloud-sync-save-backup');
    await tester.tap(find.byKey(const Key('cloud-sync-save-backup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device-backup-copy-dialog')), findsOneWidget);
    expect(controller.backupCalls, 0);
    expect(copied, isNull);
    await tester.tap(find.byKey(const Key('device-backup-copy-confirm')));
    await tester.pumpAndSettle();
    expect(copied, _BackupController.backup);
    expect(service.requests, isEmpty);
    expect(
      find.text('Backup JSON copied. Paste it into a file to save it.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Backup copy confirmation does not cross a session change', (
    tester,
  ) async {
    final controller = _BackupController();
    final service = _BackupService(supported: false);
    addTearDown(controller.dispose);
    await _open(tester, controller, service);
    await _reveal(tester, 'cloud-sync-save-backup');
    await tester.tap(find.byKey(const Key('cloud-sync-save-backup')));
    await tester.pumpAndSettle();
    controller.revision++;
    await tester.tap(find.byKey(const Key('device-backup-copy-confirm')));
    await tester.pumpAndSettle();
    expect(controller.backupCalls, 0);
    expect(service.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Backup disables during deletion and sign-out', (tester) async {
    final controller = _BackupController()..isDeletingAccount = true;
    final service = _BackupService();
    addTearDown(controller.dispose);
    await _open(tester, controller, service);
    final signOut = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('profile-sign-out-button')),
        )
        .onPressed!;
    await _reveal(tester, 'cloud-sync-save-backup');
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('cloud-sync-save-backup')),
          )
          .onPressed,
      isNull,
    );
    controller.isDeletingAccount = false;
    controller.signOutRequest = Completer<void>();
    controller.changed();
    await tester.pumpAndSettle();
    signOut();
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('cloud-sync-save-backup')),
          )
          .onPressed,
      isNull,
    );
    controller.signOutRequest!.complete();
    await tester.pumpAndSettle();
    expect(service.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Privacy review permits offline backup during connection retry', (
    tester,
  ) async {
    final controller = _BackupController()
      ..review = true
      ..retry = Completer<void>();
    final service = _BackupService();
    addTearDown(controller.dispose);
    await _open(tester, controller, service, privacy: true);
    await _reveal(tester, 'privacy-retry-connection');
    await tester.tap(find.byKey(const Key('privacy-retry-connection')));
    await tester.pumpAndSettle();
    expect(controller.retryCalls, 1);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('privacy-retry-connection')),
          )
          .onPressed,
      isNull,
    );
    final save = tester
        .widget<OutlinedButton>(find.byKey(const Key('privacy-save-backup')))
        .onPressed!;
    save();
    await tester.pumpAndSettle();
    expect(service.exports, [_BackupController.backup]);
    service.requests.single.complete(true);
    controller.retry!.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(find.text('Could not connect. Please try again.'), findsOneWidget);
    expect(controller.accountExportCalls, 0);
    expect(controller.hasPendingCloudChanges, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Navigating away during backup consumes an eventual failure', (
    tester,
  ) async {
    final controller = _BackupController();
    final service = _BackupService();
    addTearDown(controller.dispose);
    await _open(tester, controller, service);
    await _reveal(tester, 'cloud-sync-save-backup');
    await tester.tap(find.byKey(const Key('cloud-sync-save-backup')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    service.requests.single.completeError(StateError('File unavailable'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
