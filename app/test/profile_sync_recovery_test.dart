import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _SyncController extends AppController {
  _SyncController() : super(initialPrivacyConsent: testAdultPrivacyConsent) {
    isReady = true;
    onboardingComplete = true;
  }

  bool pending = true;
  bool pendingOutcome = false;
  int retries = 0;
  int cloudReads = 0;
  int revision = 0;
  Completer<void> request = Completer<void>();

  @override
  bool get isCloudAuthenticated => true;

  @override
  bool get hasPendingCloudChanges => pending;

  @override
  bool get hasPendingOutcomeChanges => pendingOutcome;

  @override
  int get sessionRevision => revision;

  @override
  Future<void> retryCloudSync() async {
    retries++;
    await request.future;
    _resolved();
  }

  @override
  Future<void> useCloudInputs() async {
    cloudReads++;
    await request.future;
    _resolved();
  }

  void _resolved() {
    pending = false;
    pendingOutcome = false;
    cloudSyncConflict = false;
    cloudSyncError = null;
    outcomeError = null;
    notifyListeners();
  }
}

Future<void> _pump(WidgetTester tester, AppController controller) async {
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
        home: const Scaffold(body: ProfileScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Outcome-only sync failure exposes retry without input replacement',
    (tester) async {
      final controller = _SyncController()
        ..pending = false
        ..pendingOutcome = true
        ..outcomeError = 'Outcome saved on this device · cloud update pending';
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _reveal(tester, 'cloud-sync-retry');
      expect(
        find.text('Outcome saved on this device · cloud update pending'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('cloud-sync-use-cloud')), findsNothing);
      await tester.tap(find.byKey(const Key('cloud-sync-retry')));
      await tester.pump();
      controller.request.complete();
      await tester.pumpAndSettle();
      expect(controller.retries, 1);
      expect(controller.pendingOutcome, isFalse);
      expect(find.byKey(const Key('cloud-sync-recovery-card')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Profile and pending sync recovery fit 320px at 2x text', (
    tester,
  ) async {
    final controller = _SyncController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    expect(tester.takeException(), isNull);
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    for (
      var i = 0;
      i < 100 && position.pixels < position.maxScrollExtent;
      i++
    ) {
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('Retry disables duplicate sync and recovers from a failure', (
    tester,
  ) async {
    final controller = _SyncController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _reveal(tester, 'cloud-sync-retry');
    await tester.tap(find.byKey(const Key('cloud-sync-retry')));
    await tester.pump();
    expect(controller.retries, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cloud-sync-retry')))
          .onPressed,
      isNull,
    );
    controller.request.completeError(StateError('connection unavailable'));
    await tester.pumpAndSettle();
    expect(controller.pending, isTrue);
    expect(
      find.text('Could not finish syncing. Please try again.'),
      findsOneWidget,
    );
    controller.request = Completer<void>();
    await _reveal(tester, 'cloud-sync-retry');
    await tester.tap(find.byKey(const Key('cloud-sync-retry')));
    await tester.pump();
    controller.request.complete();
    await tester.pumpAndSettle();
    expect(controller.retries, 2);
    expect(controller.pending, isFalse);
    expect(find.byKey(const Key('cloud-sync-recovery-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Cloud replacement needs confirmation and remains retryable on failure',
    (tester) async {
      final controller = _SyncController()..cloudSyncConflict = true;
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _reveal(tester, 'cloud-sync-use-cloud');
      await tester.tap(find.byKey(const Key('cloud-sync-use-cloud')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'unsynced profile, activity, sleep, and check-in edits',
        ),
        findsOneWidget,
      );
      expect(controller.cloudReads, 0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('cloud-sync-replace-cancel')));
      await tester.pumpAndSettle();
      expect(controller.pending, isTrue);
      expect(controller.cloudReads, 0);

      await _reveal(tester, 'cloud-sync-use-cloud');
      await tester.tap(find.byKey(const Key('cloud-sync-use-cloud')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-sync-replace-confirm')));
      await tester.pumpAndSettle();
      expect(controller.cloudReads, 1);
      controller.request.completeError(StateError('cloud read unavailable'));
      await tester.pumpAndSettle();
      expect(controller.pending, isTrue);
      expect(
        find.text('Could not load the cloud version. Please try again.'),
        findsOneWidget,
      );

      controller.request = Completer<void>();
      await _reveal(tester, 'cloud-sync-use-cloud');
      await tester.tap(find.byKey(const Key('cloud-sync-use-cloud')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-sync-replace-confirm')));
      await tester.pumpAndSettle();
      controller.request.complete();
      await tester.pumpAndSettle();
      expect(controller.cloudReads, 2);
      expect(controller.pending, isFalse);
      expect(find.byKey(const Key('cloud-sync-recovery-card')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cloud confirmation does not cross an account session change', (
    tester,
  ) async {
    final controller = _SyncController()..cloudSyncConflict = true;
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _reveal(tester, 'cloud-sync-use-cloud');
    await tester.tap(find.byKey(const Key('cloud-sync-use-cloud')));
    await tester.pumpAndSettle();
    controller.revision++;
    await tester.tap(find.byKey(const Key('cloud-sync-replace-confirm')));
    await tester.pumpAndSettle();
    expect(controller.cloudReads, 0);
    expect(controller.pending, isTrue);
    expect(find.byKey(const Key('cloud-sync-replace-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Navigating away during retry handles the eventual failure', (
    tester,
  ) async {
    final controller = _SyncController();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await _reveal(tester, 'cloud-sync-retry');
    await tester.tap(find.byKey(const Key('cloud-sync-retry')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.request.completeError(StateError('connection unavailable'));
    await tester.pumpAndSettle();
    expect(controller.pending, isTrue);
    expect(tester.takeException(), isNull);
  });
}
