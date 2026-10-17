import 'dart:async';

import 'package:app/src/app_controller.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/screens/privacy_center_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CaptureScreenController extends AppController {
  bool available = true;
  bool enabled = false;
  bool busy = false;
  bool privacyAllowed = true;
  int count = 0;
  int revision = 0;
  String? captureError;
  bool failChange = false;
  Completer<void>? changeCompleter;
  final changes = <bool>[];

  @override
  bool get privacyReviewRequired => false;
  @override
  bool get privacyFeaturesAllowed => privacyAllowed;
  @override
  bool get ai1CaptureAvailable => available;
  @override
  bool get ai1CaptureEnabled => enabled;
  @override
  bool get ai1CaptureBusy => busy;
  @override
  int get ai1CapturedRevisionCount => count;
  @override
  String? get ai1CaptureError => captureError;
  @override
  int get sessionRevision => revision;

  void changed() => notifyListeners();

  @override
  Future<void> setAi1CaptureEnabled(bool value) async {
    changes.add(value);
    await changeCompleter?.future;
    if (failChange) throw StateError('private store diagnostic');
    enabled = value;
    if (!value) count = 0;
    captureError = null;
    notifyListeners();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(
    WidgetTester tester,
    _CaptureScreenController controller, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
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
        home: PrivacyCenterScreen(controller: controller),
      ),
    );
    await reach(tester, const Key('privacy-study-history-switch'));
  }

  testWidgets('opening keeps history off and explains retained revisions', (
    tester,
  ) async {
    final controller = _CaptureScreenController();
    await open(tester, controller);
    expect(studySwitch(tester).value, isFalse);
    expect(controller.changes, isEmpty);
    expect(controller.outcomeConsent, isFalse);
    expect(find.text('Off · no study history is being saved.'), findsOneWidget);
    expect(find.text('Saved revisions: 0'), findsOneWidget);
    expect(
      find.textContaining('including earlier answers after edits.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Apple Health imports are not included'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Study history is excluded from backups and exports.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('explicit switch enables history without outcome enrollment', (
    tester,
  ) async {
    final controller = _CaptureScreenController();
    await open(tester, controller);
    await tester.tap(find.byKey(const Key('privacy-study-history-switch')));
    await tester.pumpAndSettle();
    expect(controller.changes, [true]);
    expect(controller.outcomeConsent, isFalse);
    expect(studySwitch(tester).value, isTrue);
    expect(find.text('On · starts with new records only.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('turning history off clears the displayed revision count', (
    tester,
  ) async {
    final controller = _CaptureScreenController()
      ..enabled = true
      ..count = 3;
    await open(tester, controller);
    expect(find.text('Saved revisions: 3'), findsOneWidget);
    expect(
      find.textContaining('Turning this off clears this study history.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('privacy-study-history-switch')));
    await tester.pumpAndSettle();
    expect(controller.changes, [false]);
    expect(find.text('Saved revisions: 0'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('unavailable platforms cannot enable local capture', (
    tester,
  ) async {
    final controller = _CaptureScreenController()..available = false;
    await open(tester, controller);
    expect(studySwitch(tester).onChanged, isNull);
    expect(find.text('Available in the iPhone app.'), findsOneWidget);
    expect(find.byKey(const Key('privacy-study-history-count')), findsNothing);
    expect(controller.changes, isEmpty);
  });

  testWidgets('privacy review blocks enabling but permits disabling', (
    tester,
  ) async {
    final controller = _CaptureScreenController()..privacyAllowed = false;
    await open(tester, controller);
    expect(studySwitch(tester).onChanged, isNull);
    controller.enabled = true;
    controller.changed();
    await tester.pumpAndSettle();
    expect(studySwitch(tester).onChanged, isNotNull);
    await tester.tap(find.byKey(const Key('privacy-study-history-switch')));
    await tester.pumpAndSettle();
    expect(controller.changes, [false]);
  });

  testWidgets('pending update disables the switch before store completion', (
    tester,
  ) async {
    final completer = Completer<void>();
    final controller = _CaptureScreenController()..changeCompleter = completer;
    await open(tester, controller);
    await tester.tap(find.byKey(const Key('privacy-study-history-switch')));
    await tester.pump();
    expect(studySwitch(tester).onChanged, isNull);
    expect(find.text('Updating study history…'), findsOneWidget);
    expect(controller.changes, [true]);
    completer.complete();
    await tester.pumpAndSettle();
    expect(studySwitch(tester).onChanged, isNotNull);
    expect(studySwitch(tester).value, isTrue);
  });

  testWidgets('privacy review offers clear even when capture appears off', (
    tester,
  ) async {
    final controller = _CaptureScreenController()..privacyAllowed = false;
    await open(tester, controller);
    await reach(tester, const Key('privacy-clear-study-history'));
    expect(studySwitch(tester).value, isFalse);
    expect(studySwitch(tester).onChanged, isNull);
    expect(find.byKey(const Key('privacy-study-history-error')), findsNothing);
    await tester.tap(find.byKey(const Key('privacy-clear-study-history')));
    await tester.pumpAndSettle();
    expect(controller.changes, [false]);
  });

  testWidgets('failed update is sanitized and offers explicit clear recovery', (
    tester,
  ) async {
    final controller = _CaptureScreenController()..failChange = true;
    await open(tester, controller);
    await tester.tap(find.byKey(const Key('privacy-study-history-switch')));
    await tester.pumpAndSettle();
    await reach(tester, const Key('privacy-clear-study-history'));
    expect(
      find.text('Could not update local study history. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private store diagnostic'), findsNothing);
    expect(studySwitch(tester).value, isFalse);
    controller.failChange = false;
    await tester.tap(find.byKey(const Key('privacy-clear-study-history')));
    await tester.pumpAndSettle();
    expect(controller.changes, [true, false]);
    expect(find.byKey(const Key('privacy-study-history-error')), findsNothing);
  });

  testWidgets('stored capture error offers clear even with history off', (
    tester,
  ) async {
    final controller = _CaptureScreenController()
      ..captureError =
          'Could not update local study history. Please try again.';
    await open(tester, controller, scale: 2);
    await reach(tester, const Key('privacy-clear-study-history'));
    expect(studySwitch(tester).value, isFalse);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('privacy-clear-study-history')));
    await tester.pumpAndSettle();
    expect(controller.changes, [false]);
    expect(find.byKey(const Key('privacy-study-history-error')), findsNothing);
  });

  test('study history copy has every supported translation', () {
    const keys = [
      'Local study history',
      'Save new manual sleep logs and check-in revisions on this device, '
          'including earlier answers after edits. This history is not used '
          'for model training or uploaded to the cloud.',
      'Keep local study history',
      'Available in the iPhone app.',
      'Updating study history…',
      'On · starts with new records only.',
      'Off · no study history is being saved.',
      'Saved revisions: {count}',
      'Turning this off clears this study history. Your ordinary sleep logs '
          'and check-ins stay. Apple Health imports are not included in this '
          'history yet. Study history is excluded from backups and exports.',
      'Could not update local study history. Please try again.',
      'Clear local history',
      'Local history could not be read. Clear it before starting again.',
      'Local history could not be cleared. Retry clearing it.',
      'Local history was interrupted. Clear it before starting again.',
      'Local history is full. Clear it to start a new capture.',
    ];
    for (final key in keys) {
      for (final language in ['es', 'zh-Hans', 'zh-Hant']) {
        expect(
          AppLocalizations.translations[key]?[language],
          isNotEmpty,
          reason: '$language: $key',
        );
      }
    }
  });
}

SwitchListTile studySwitch(WidgetTester tester) =>
    tester.widget<SwitchListTile>(
      find.byKey(const Key('privacy-study-history-switch')),
    );

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
