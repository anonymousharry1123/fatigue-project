import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/schedule_logic.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _ScheduleController extends AppController {
  _ScheduleController()
    : super(initialPrivacyConsent: testAdultPrivacyConsent) {
    isReady = true;
    onboardingComplete = true;
    profile = const UserProfile(name: 'Test', wakeHour: 7, bedHour: 23);
  }
  int updates = 0;
  @override
  Future<void> updateProfile(UserProfile value) async {
    updates++;
    profile = value;
    notifyListeners();
  }
}

Future<void> _open(WidgetTester tester, _ScheduleController controller) async {
  await tester.pumpWidget(
    AppScope(
      controller: controller,
      child: MaterialApp(
        theme: buildTonyoTheme(),
        home: const Scaffold(body: ProfileScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final setting = find.byKey(const Key('sleep-schedule-setting'));
  await tester.scrollUntilVisible(
    setting,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(setting);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('wake and bed settings remain editable after onboarding', (
    tester,
  ) async {
    final controller = _ScheduleController();
    addTearDown(controller.dispose);
    await _open(tester, controller);
    await tester.enterText(
      find.byKey(const Key('schedule-wake-field')),
      '09:30',
    );
    await tester.enterText(
      find.byKey(const Key('schedule-bed-field')),
      '01:30',
    );
    await tester.tap(find.byKey(const Key('schedule-save')));
    await tester.pumpAndSettle();
    expect(controller.updates, 1);
    expect(controller.profile.wakeHour, 9.5);
    expect(controller.profile.bedHour, 1.5);
    expect(controller.profile.name, 'Test');
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule editor rejects malformed or identical clock times', (
    tester,
  ) async {
    final controller = _ScheduleController();
    addTearDown(controller.dispose);
    await _open(tester, controller);
    for (final invalid in ['24:00', '07:60', 'not a time']) {
      await tester.enterText(
        find.byKey(const Key('schedule-wake-field')),
        invalid,
      );
      await tester.tap(find.byKey(const Key('schedule-save')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('schedule-validation-error')),
        findsOneWidget,
      );
      expect(controller.updates, 0);
    }
    await tester.enterText(
      find.byKey(const Key('schedule-wake-field')),
      '23:00',
    );
    await tester.tap(find.byKey(const Key('schedule-save')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Choose different wake and bed times'),
      findsOneWidget,
    );
    expect(controller.updates, 0);
  });

  test(
    'clock validation does not invent an individual minimum sleep requirement',
    () {
      const previous = UserProfile(wakeHour: 7, bedHour: 23);
      expect(
        ScheduleLogic.validationError(previous, previous.copyWith(wakeHour: 6)),
        isNull,
      );
      expect(
        ScheduleLogic.validationError(
          previous,
          previous.copyWith(wakeHour: double.infinity),
        ),
        isNotNull,
      );
      expect(
        ScheduleLogic.validationError(previous, previous.copyWith(bedHour: -1)),
        isNotNull,
      );
    },
  );
}
