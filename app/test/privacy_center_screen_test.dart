import 'dart:async';
import 'dart:convert';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:app/src/screens/privacy_center_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _PrivacyScreenController extends AppController {
  PrivacyConsent? savedConsent;
  bool review = true;
  bool cloud = false;
  bool cloudConfigured = false;
  bool pendingDeletion = false;
  bool exportBusy = false;
  bool deleteBusy = false;
  String? blocker;
  String? operationError;
  String? owner;
  int acceptCalls = 0;
  int exportCalls = 0;
  int deleteCalls = 0;
  int outcomeCalls = 0;
  int deviceClearCalls = 0;
  int statusCheckCalls = 0;
  String? deletionPassword;
  bool failExport = false;
  bool failDelete = false;
  Completer<void>? deletionCompleter;
  Completer<void>? exportCompleter;

  @override
  PrivacyConsent? get privacyConsent => savedConsent;
  @override
  bool get privacyReviewRequired => review;
  @override
  bool get privacyFeaturesAllowed => !review && blocker == null;
  @override
  bool get isPrivacyBusy => exportBusy || deleteBusy;
  @override
  bool get isDeletingAccount => deleteBusy;
  @override
  bool get isExportingData => exportBusy;
  @override
  bool get deletionPending => pendingDeletion;
  @override
  String? get privacyOperationError => operationError;
  @override
  String? get guardianConsentBlocker => blocker;
  @override
  bool get guardianConsentVerified => false;
  @override
  bool get isCloudAuthenticated => cloud;
  @override
  bool get cloudEnabled => cloud || cloudConfigured;
  @override
  String? get cloudUid => owner;

  @override
  Future<void> acceptPrivacy({
    required PrivacyAgeBand ageBand,
    required PrivacyRegion region,
    required bool acknowledged,
  }) async {
    if (!acknowledged) throw StateError('Explicit acknowledgement required');
    acceptCalls++;
    savedConsent = PrivacyConsent(
      ageBand: ageBand,
      region: region,
      acceptedAt: DateTime.utc(2026, 9, 7, 9),
    );
    review = false;
    notifyListeners();
  }

  @override
  Future<String> exportAllData() async {
    exportCalls++;
    exportBusy = true;
    notifyListeners();
    try {
      await exportCompleter?.future;
      if (failExport) throw StateError('private internal failure');
      return jsonEncode({
        'exportVersion': 2,
        'cloud': cloud
            ? {
                'collections': {
                  'signals': {
                    'signal-1': {'value': 2},
                  },
                  'outcomes': {
                    'outcome-1': {'energy': 5},
                  },
                },
              }
            : null,
        'local': {
          'signals': [1, 2],
          'checkIns': [1],
          'outcomes': [],
        },
      });
    } finally {
      exportBusy = false;
      notifyListeners();
    }
  }

  @override
  Future<void> deleteAccountData({String? password}) async {
    deleteCalls++;
    deletionPassword = password;
    deleteBusy = true;
    notifyListeners();
    try {
      await deletionCompleter?.future;
      if (failDelete) {
        pendingDeletion = true;
        operationError =
            'Deletion is unfinished. Retry to remove the remaining data.';
        throw StateError('private internal failure');
      }
    } finally {
      deleteBusy = false;
      notifyListeners();
    }
  }

  @override
  Future<void> setOutcomeConsent(bool value) async {
    outcomeCalls++;
    outcomeConsent = value;
    notifyListeners();
  }

  @override
  Future<void> clearDeviceAfterInterruptedDeletion() async {
    deviceClearCalls++;
  }

  @override
  Future<void> handleAppResumed() async {
    statusCheckCalls++;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(
    WidgetTester tester,
    _PrivacyScreenController controller, {
    bool requireReview = false,
    double scale = 1,
    Size size = const Size(900, 1600),
  }) async {
    tester.view.physicalSize = size;
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
        home: PrivacyCenterScreen(
          controller: controller,
          requireReview: requireReview,
        ),
      ),
    );
  }

  Future<void> reach(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      450,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('privacy-center-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'opening requires an explicit age, region and acknowledgement; no side effects',
    (tester) async {
      final controller = _PrivacyScreenController();
      await open(tester, controller, requireReview: true);
      await reach(tester, const Key('privacy-accept-button'));
      expect(
        tester
            .widget<DropdownButtonFormField<PrivacyAgeBand>>(
              find.byKey(const Key('privacy-age-band')),
            )
            .initialValue,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<PrivacyRegion>>(
              find.byKey(const Key('privacy-region')),
            )
            .initialValue,
        isNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('privacy-acknowledgement')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('privacy-accept-button')),
            )
            .onPressed,
        isNull,
      );
      expect(controller.acceptCalls, 0);
      expect(controller.exportCalls, 0);
      expect(controller.deleteCalls, 0);
      expect(controller.outcomeCalls, 0);
      expect(find.byType(BackButton), findsNothing);
    },
  );

  testWidgets('saving adult privacy choices does not enable outcome learning', (
    tester,
  ) async {
    final controller = _PrivacyScreenController();
    await open(tester, controller);
    await reach(tester, const Key('privacy-age-band'));
    await acknowledgeAdultPrivacy(tester);
    await reach(tester, const Key('privacy-accept-button'));
    await tester.tap(find.byKey(const Key('privacy-accept-button')));
    await tester.pumpAndSettle();
    expect(controller.acceptCalls, 1);
    expect(controller.savedConsent?.ageBand, PrivacyAgeBand.adult);
    expect(controller.outcomeConsent, isFalse);
    expect(controller.outcomeCalls, 0);
    expect(find.byKey(const Key('privacy-consent-receipt')), findsOneWidget);
    expect(find.byKey(const Key('privacy-age-band')), findsNothing);
  });

  testWidgets(
    'saved youth identity stays immutable and verification is not self-attested',
    (tester) async {
      final controller = _PrivacyScreenController()
        ..savedConsent = PrivacyConsent(
          ageBand: PrivacyAgeBand.age16to17,
          region: PrivacyRegion.us,
          acceptedAt: DateTime.utc(2026, 9, 1),
        )
        ..review = false
        ..blocker =
            'Verified guardian authorization is required. Setup is not available in this build.';
      await open(tester, controller, requireReview: true);
      await reach(tester, const Key('privacy-guardian-required'));
      expect(find.byKey(const Key('privacy-age-band')), findsNothing);
      expect(find.byKey(const Key('privacy-region')), findsNothing);
      expect(find.textContaining('Setup is not available'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await reach(tester, const Key('privacy-outcome-switch'));
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('privacy-outcome-switch')),
            )
            .onChanged,
        isNull,
      );
    },
  );

  testWidgets(
    'export counts are shown before a separately confirmed clipboard copy',
    (tester) async {
      final controller = _PrivacyScreenController()
        ..savedConsent = testAdultPrivacyConsent
        ..review = false
        ..cloud = true
        ..owner = 'owner';
      final clipboardWrites = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add((call.arguments as Map)['text'] as String);
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
      await open(tester, controller);
      await reach(tester, const Key('privacy-generate-export'));
      await tester.tap(find.byKey(const Key('privacy-generate-export')));
      await tester.pumpAndSettle();
      expect(controller.exportCalls, 1);
      expect(clipboardWrites, isEmpty);
      await reach(tester, const Key('privacy-copy-export'));
      expect(find.text('cloud · signals: 1'), findsOneWidget);
      expect(find.text('local · signals: 2'), findsOneWidget);
      expect(find.textContaining('not as one atomic'), findsOneWidget);
      await tester.tap(find.byKey(const Key('privacy-copy-export')));
      await tester.pumpAndSettle();
      expect(find.text('Copy sensitive data?'), findsOneWidget);
      expect(clipboardWrites, isEmpty);
      await tester.tap(find.byKey(const Key('privacy-confirm-copy')));
      await tester.pumpAndSettle();
      expect(clipboardWrites, hasLength(1));
    },
  );

  testWidgets(
    'checking account status does not reacknowledge or enable learning',
    (tester) async {
      final controller = _PrivacyScreenController()
        ..savedConsent = testAdultPrivacyConsent
        ..review = true
        ..cloud = true;
      await open(tester, controller, requireReview: true);
      await reach(tester, const Key('privacy-check-account-status'));
      await tester.tap(find.byKey(const Key('privacy-check-account-status')));
      await tester.pumpAndSettle();
      expect(controller.statusCheckCalls, 1);
      expect(controller.acceptCalls, 0);
      expect(controller.outcomeCalls, 0);
      expect(controller.outcomeConsent, isFalse);
      expect(controller.savedConsent, same(testAdultPrivacyConsent));
    },
  );

  testWidgets('failed export does not present a partial file as ready', (
    tester,
  ) async {
    final controller = _PrivacyScreenController()
      ..review = false
      ..failExport = true;
    await open(tester, controller);
    await reach(tester, const Key('privacy-generate-export'));
    await tester.tap(find.byKey(const Key('privacy-generate-export')));
    await tester.pumpAndSettle();
    await reach(tester, const Key('privacy-operation-error'));
    expect(find.byKey(const Key('privacy-export-summary')), findsNothing);
    expect(find.byKey(const Key('privacy-copy-export')), findsNothing);
    expect(find.textContaining('private internal failure'), findsNothing);
  });

  testWidgets('in-flight export is not disclosed after the owner changes', (
    tester,
  ) async {
    final controller = _PrivacyScreenController()
      ..review = false
      ..cloud = true
      ..owner = 'first'
      ..exportCompleter = Completer<void>();
    await open(tester, controller);
    await reach(tester, const Key('privacy-generate-export'));
    await tester.tap(find.byKey(const Key('privacy-generate-export')));
    await tester.pump();
    controller.owner = 'second';
    controller.changed();
    controller.exportCompleter!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy-export-summary')), findsNothing);
  });

  for (final cloud in [false, true]) {
    testWidgets(
      'deletion requires typed confirmation${cloud ? ' and a cloud password' : ''}',
      (tester) async {
        final controller = _PrivacyScreenController()
          ..review = false
          ..cloud = cloud;
        await open(tester, controller);
        await reach(tester, const Key('privacy-delete-data'));
        await tester.tap(find.byKey(const Key('privacy-delete-data')));
        await tester.pumpAndSettle();
        final confirm = find.byKey(const Key('privacy-confirm-deletion'));
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        await tester.enterText(
          find.byKey(const Key('privacy-delete-confirmation')),
          'delete',
        );
        await tester.pump();
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        await tester.enterText(
          find.byKey(const Key('privacy-delete-confirmation')),
          'DELETE',
        );
        await tester.pump();
        if (cloud) {
          expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
          await tester.enterText(
            find.byKey(const Key('privacy-delete-password')),
            'test-only-password',
          );
          await tester.pump();
        }
        expect(controller.deleteCalls, 0);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(controller.deleteCalls, 1);
        expect(
          controller.deletionPassword,
          cloud ? 'test-only-password' : null,
        );
      },
    );
  }

  testWidgets(
    'incomplete deletion remains visible and may be retried without false success',
    (tester) async {
      final controller = _PrivacyScreenController()
        ..review = false
        ..failDelete = true;
      await open(tester, controller);
      await reach(tester, const Key('privacy-delete-data'));
      await tester.tap(find.byKey(const Key('privacy-delete-data')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('privacy-delete-confirmation')),
        'DELETE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('privacy-confirm-deletion')));
      await tester.pumpAndSettle();
      expect(controller.deleteCalls, 1);
      await reach(tester, const Key('privacy-delete-data'));
      expect(find.text('Retry unfinished deletion'), findsOneWidget);
      expect(find.textContaining('deleted successfully'), findsNothing);
      await reach(tester, const Key('privacy-operation-error'));
      expect(
        find.descendant(
          of: find.byKey(const Key('privacy-operation-error')),
          matching: find.textContaining('Deletion is unfinished'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Deletion is unfinished'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'while deletion is active, repeated actions and route back are disabled',
    (tester) async {
      final controller = _PrivacyScreenController()
        ..review = false
        ..deletionCompleter = Completer<void>();
      await open(tester, controller);
      await reach(tester, const Key('privacy-delete-data'));
      await tester.tap(find.byKey(const Key('privacy-delete-data')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('privacy-delete-confirmation')),
        'DELETE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('privacy-confirm-deletion')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.deleteCalls, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('privacy-delete-data')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<PopScope>(find.byType(PopScope).first).canPop,
        isFalse,
      );
      controller.deletionCompleter!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'interrupted cloud deletion without auth never becomes a local account deletion',
    (tester) async {
      final controller = _PrivacyScreenController()
        ..cloudConfigured = true
        ..pendingDeletion = true;
      await open(tester, controller, requireReview: true);
      expect(
        find.textContaining('Cloud account deletion could not be confirmed'),
        findsOneWidget,
      );
      await reach(tester, const Key('privacy-delete-data'));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('privacy-delete-data')),
            )
            .onPressed,
        isNull,
      );
      await reach(tester, const Key('privacy-clear-device-only'));
      await tester.tap(find.byKey(const Key('privacy-clear-device-only')));
      await tester.pumpAndSettle();
      expect(find.text('Erase only this device?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('does not confirm deletion'),
        ),
        findsOneWidget,
      );
      expect(controller.deviceClearCalls, 0);
      await tester.enterText(
        find.byKey(const Key('privacy-delete-confirmation')),
        'DELETE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('privacy-confirm-deletion')));
      await tester.pumpAndSettle();
      expect(controller.deviceClearCalls, 1);
      expect(controller.deleteCalls, 0);
    },
  );

  testWidgets('320 px layout at 2x text remains scrollable without overflow', (
    tester,
  ) async {
    final controller = _PrivacyScreenController();
    await open(tester, controller, size: const Size(320, 740), scale: 2);
    expect(tester.takeException(), isNull);
    await reach(tester, const Key('privacy-age-band'));
    await acknowledgeAdultPrivacy(tester);
    expect(tester.takeException(), isNull);
    await reach(tester, const Key('privacy-accept-button'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('privacy-accept-button')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.byKey(const Key('privacy-accept-button')).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(controller.acceptCalls, 1);
    expect(controller.savedConsent?.ageBand, PrivacyAgeBand.adult);
    expect(controller.savedConsent?.region, PrivacyRegion.us);
    expect(controller.savedConsent?.wellnessAcknowledged, isTrue);
    await reach(tester, const Key('privacy-delete-data'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('privacy-delete-data')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new account asks privacy before any identifiers with neutral defaults',
    (tester) async {
      final controller = _PrivacyScreenController()..isReady = true;
      addTearDown(controller.dispose);
      await tester.pumpWidget(TonyoApp(controller: controller));
      await tester.tap(find.text('Create my account'));
      await tester.pumpAndSettle();
      expect(find.text('Before you begin'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);
      expect(find.widgetWithText(TextField, 'First name'), findsNothing);
      expect(find.byKey(const Key('password-field')), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<PrivacyAgeBand>>(
              find.byKey(const Key('privacy-age-band')),
            )
            .initialValue,
        isNull,
      );
      expect(controller.acceptCalls, 0);
    },
  );

  testWidgets(
    'a minor cannot navigate forward or change the selected band to bypass protection',
    (tester) async {
      final controller = _PrivacyScreenController()..isReady = true;
      addTearDown(controller.dispose);
      await tester.pumpWidget(TonyoApp(controller: controller));
      await tester.tap(find.text('Create my account'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('privacy-age-band')));
      await tester.tap(find.byKey(const Key('privacy-age-band')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(PrivacyAgeBand.age16to17.label).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy-age-band')), findsNothing);
      expect(find.byKey(const Key('privacy-age-protection')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardian setup unavailable'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(const Key('onboarding-privacy-scroll')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('password-field')), findsNothing);
      expect(controller.acceptCalls, 0);
    },
  );
}
