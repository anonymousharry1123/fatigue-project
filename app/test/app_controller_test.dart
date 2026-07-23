import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Version 0.5 restores onboarding and profile from local storage',
    () async {
      final first = AppController();
      await first.load();
      await first.completeOnboarding(
        const UserProfile(name: 'Jordan', role: 'Athlete'),
        email: 'Jordan@Example.com',
      );

      final restored = AppController();
      await restored.load();

      expect(restored.onboardingComplete, isTrue);
      expect(restored.profile.name, 'Jordan');
      expect(restored.profile.role, 'Athlete');
      expect(restored.accountEmail, 'jordan@example.com');
      expect(restored.exportJson(), isNot(contains('password')));
      expect(restored.signals, isNotEmpty);
    },
  );

  test('reset removes the persisted Version 0.5 state', () async {
    final controller = AppController();
    await controller.load();
    await controller.completeOnboarding(const UserProfile());
    await controller.reset();

    final restored = AppController();
    await restored.load();
    expect(restored.onboardingComplete, isFalse);
    expect(restored.accountEmail, isNull);
    expect(restored.signals, isEmpty);
  });

  test(
    'Version 0.6 saves, validates, edits, and restores activity logs',
    () async {
      final controller = AppController();
      await controller.load();

      await controller.saveActivityLog(
        hydrationLiters: 2.4,
        studyHours: 3,
        exerciseHours: 1.25,
        screenTimeHours: 4.5,
        timestamp: DateTime(2026, 7, 22, 18),
      );

      expect(controller.activityLogs, hasLength(1));
      expect(controller.activityLogs.single.hydrationLiters, 2.4);
      expect(
        controller.signals.where(
          (item) => item.groupId == controller.activityLogs.single.id,
        ),
        hasLength(4),
      );

      final id = controller.activityLogs.single.id;
      await controller.saveActivityLog(
        id: id,
        hydrationLiters: 3,
        studyHours: 2,
        exerciseHours: .5,
        screenTimeHours: 5,
        timestamp: DateTime(2026, 7, 22, 19),
      );
      expect(controller.activityLogs, hasLength(1));
      expect(controller.activityLogs.single.id, id);
      expect(controller.activityLogs.single.hydrationLiters, 3);

      expect(
        () => controller.saveActivityLog(
          hydrationLiters: 12,
          studyHours: 2,
          exerciseHours: 1,
          screenTimeHours: 4,
        ),
        throwsArgumentError,
      );
      expect(controller.activityLogs, hasLength(1));

      final restored = AppController();
      await restored.load();
      expect(restored.activityLogs, hasLength(1));
      expect(restored.activityLogs.single.screenTimeHours, 5);
    },
  );

  test(
    'Version 0.7 calculates sleep duration and bedtime consistency',
    () async {
      final controller = AppController();
      await controller.load();

      await controller.addSleep(
        bedtime: DateTime(2026, 7, 20, 23),
        wakeTime: DateTime(2026, 7, 20, 7),
        quality: 4,
      );
      await controller.addSleep(
        bedtime: DateTime(2026, 7, 21, 23, 30),
        wakeTime: DateTime(2026, 7, 21, 7, 30),
        quality: 3,
      );

      expect(controller.sleepLogs, hasLength(2));
      expect(controller.sleepLogs.first.durationHours, 8);
      expect(controller.sleepLogs.first.quality, 3);
      expect(controller.bedtimeConsistencyMinutes, 15);

      final edited = controller.sleepLogs.first;
      await controller.addSleep(
        id: edited.id,
        bedtime: DateTime(2026, 7, 21, 23, 15),
        wakeTime: DateTime(2026, 7, 22, 7, 45),
        quality: 5,
      );
      expect(controller.sleepLogs, hasLength(2));
      expect(
        controller.sleepLogs
            .singleWhere((item) => item.id == edited.id)
            .quality,
        5,
      );

      expect(
        () => controller.addSleep(
          bedtime: DateTime(2026, 7, 22),
          wakeTime: DateTime(2026, 7, 22, 20),
          quality: 4,
        ),
        throwsArgumentError,
      );

      final restored = AppController();
      await restored.load();
      expect(restored.sleepLogs, hasLength(2));
      expect(restored.sleepLogs.first.durationHours, 8.5);
    },
  );

  test('manual log validation covers every Version 0.6 and 0.7 input', () {
    expect(
      ActivityLogEntry.validationMessage(SignalType.hydration, -0.1),
      isNotNull,
    );
    expect(ActivityLogEntry.validationMessage(SignalType.study, 19), isNotNull);
    expect(
      ActivityLogEntry.validationMessage(SignalType.exercise, 13),
      isNotNull,
    );
    expect(
      ActivityLogEntry.validationMessage(SignalType.screenTime, 25),
      isNotNull,
    );
    expect(
      ActivityLogEntry.validationMessage(SignalType.hydration, 2.5),
      isNull,
    );
    expect(
      SleepLogEntry.validationMessage(
        bedtime: DateTime(2026, 7, 22, 23),
        wakeTime: DateTime(2026, 7, 23, 7),
        quality: 0,
      ),
      isNotNull,
    );
    expect(
      SleepLogEntry.validationMessage(
        bedtime: DateTime(2026, 7, 22, 23),
        wakeTime: DateTime(2026, 7, 22, 23, 15),
        quality: 4,
      ),
      isNotNull,
    );
  });
}
