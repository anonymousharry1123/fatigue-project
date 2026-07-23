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
      );

      final restored = AppController();
      await restored.load();

      expect(restored.onboardingComplete, isTrue);
      expect(restored.profile.name, 'Jordan');
      expect(restored.profile.role, 'Athlete');
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
    expect(restored.signals, isEmpty);
  });

  test('Version 0.8 stores morning/evening check-ins on a 1–10 scale', () async {
    final controller = AppController();
    await controller.load();

    await controller.addCheckIn(
      energy: 8,
      mood: 7,
      stress: 3,
      period: CheckInPeriod.morning,
      note: 'Ready to study',
    );
    await controller.addCheckIn(
      energy: 5,
      mood: 4,
      stress: 8,
      period: CheckInPeriod.evening,
    );

    expect(controller.checkIns, hasLength(2));
    expect(controller.checkIns.first.period, CheckInPeriod.evening);
    expect(controller.checkIns.first.stress, 8);
    expect(controller.checkIns.last.mood, 7);

    final restored = AppController();
    await restored.load();
    expect(restored.checkIns, hasLength(2));
    expect(restored.checkIns.first.period, CheckInPeriod.evening);
    expect(restored.recentCheckIns().first.energy, 5);
  });

  test('Version 0.8 rejects ratings outside 1–10', () async {
    final controller = AppController();
    await controller.load();

    expect(
      () => controller.addCheckIn(energy: 0, mood: 5, stress: 5),
      throwsArgumentError,
    );
    expect(
      () => controller.addCheckIn(energy: 5, mood: 11, stress: 5),
      throwsArgumentError,
    );
  });

  test('Version 0.9 saves reaction benchmarks and exposes a baseline', () async {
    final controller = AppController();
    await controller.load();

    await controller.addReactionResult(290);
    await controller.addReactionResult(270);
    await controller.addReactionResult(250);

    expect(controller.reactionBaseline, closeTo(270, 0.01));

    final restored = AppController();
    await restored.load();
    expect(
      restored.signals.where((item) => item.type == SignalType.reactionTime),
      hasLength(3),
    );
    expect(restored.reactionBaseline, closeTo(270, 0.01));
  });

  test('Version 0.9 rejects invalid reaction averages', () async {
    final controller = AppController();
    await controller.load();

    expect(() => controller.addReactionResult(50), throwsArgumentError);
    expect(() => controller.addReactionResult(2000), throwsArgumentError);
  });
}
