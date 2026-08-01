import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
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
    'Version 0.10-a migrates local JSON on first signed-in launch',
    () async {
      final local = AppController();
      await local.load();
      await local.completeOnboarding(
        const UserProfile(name: 'Legacy Maya'),
        email: 'maya@example.com',
      );
      await local.addCheckIn(
        energy: 8,
        mood: 7,
        stress: 3,
        timestamp: DateTime(2026, 7, 28, 9),
      );

      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'maya-uid',
          email: 'maya@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'maya-uid');
      final migrated = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );

      await migrated.load();

      final cloud = await repository.readUser('maya-uid');
      expect(cloud, isNotNull);
      expect(cloud!.migrationVersion, localMigrationVersion);
      expect(cloud.profile.name, 'Legacy Maya');
      expect(
        cloud.checkIns.any(
          (value) => value.timestamp == DateTime(2026, 7, 28, 9),
        ),
        isTrue,
      );
      expect(migrated.isCloudAuthenticated, isTrue);
      expect(migrated.cloudSyncError, isNull);
    },
  );

  test('Version 0.10-a uses existing cloud state over local cache', () async {
    final local = AppController();
    await local.load();
    await local.completeOnboarding(
      const UserProfile(name: 'Local name'),
      email: 'maya@example.com',
    );

    final auth = MemoryAccountAuth(
      session: const AccountSession(uid: 'maya-uid', email: 'maya@example.com'),
    );
    final repository = MemoryCloudRepository(signedInUid: 'maya-uid')
      ..seed(
        'maya-uid',
        const CloudUserState(
          profile: UserProfile(name: 'Cloud name'),
          accountEmail: 'maya@example.com',
          onboardingComplete: true,
          notificationsEnabled: false,
          outcomeConsent: true,
          healthAuthorized: false,
          migrationVersion: localMigrationVersion,
          signals: [],
          checkIns: [],
        ),
      );
    final restored = AppController(
      accountAuth: auth,
      cloudRepository: repository,
    );

    await restored.load();

    expect(restored.profile.name, 'Cloud name');
    expect(restored.notificationsEnabled, isFalse);
    expect(restored.outcomeConsent, isTrue);
  });

  test('Version 0.10-a returning account restores cloud onboarding', () async {
    final auth = MemoryAccountAuth();
    final repository = MemoryCloudRepository(signedInUid: 'test-uid')
      ..seed(
        'test-uid',
        const CloudUserState(
          profile: UserProfile(name: 'Returning Maya'),
          accountEmail: 'maya@example.com',
          onboardingComplete: true,
          notificationsEnabled: true,
          outcomeConsent: false,
          healthAuthorized: false,
          migrationVersion: localMigrationVersion,
          signals: [],
          checkIns: [],
        ),
      );
    final controller = AppController(
      accountAuth: auth,
      cloudRepository: repository,
    );
    await controller.load();

    await controller.completeOnboarding(
      const UserProfile(name: 'Should not replace cloud'),
      email: 'maya@example.com',
      password: 'secure-pass',
      signInToExistingAccount: true,
    );

    expect(controller.onboardingComplete, isTrue);
    expect(controller.profile.name, 'Returning Maya');
  });

  test('Version 0.10-a syncs writes and deletes cloud account data', () async {
    final auth = MemoryAccountAuth();
    final repository = MemoryCloudRepository(signedInUid: 'test-uid');
    final controller = AppController(
      accountAuth: auth,
      cloudRepository: repository,
    );
    await controller.load();
    await controller.completeOnboarding(
      const UserProfile(name: 'Cloud Maya'),
      email: 'Maya@Example.com',
      password: 'secure-pass',
    );
    await controller.addSignal(SignalType.hydration, 2.5);

    final cloud = await repository.readUser('test-uid');
    expect(cloud?.accountEmail, 'maya@example.com');
    expect(
      cloud?.signals.any((value) => value.type == SignalType.hydration),
      isTrue,
    );
    expect(await controller.exportAllData(), contains('"uid": "test-uid"'));

    await controller.deleteAccountData();
    expect(await repository.readUser('test-uid'), isNull);
    expect(controller.onboardingComplete, isFalse);
    expect(auth.currentSession, isNull);
  });

  test(
    'Versions 0.11–0.12 query cloud inputs and update one daily snapshot',
    () async {
      final now = DateTime.now();
      final recordedAt = now;
      final previousDay = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'score-uid',
          email: 'score@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'score-uid')
        ..seed(
          'score-uid',
          CloudUserState(
            profile: const UserProfile(name: 'Score Maya'),
            accountEmail: 'score@example.com',
            onboardingComplete: true,
            notificationsEnabled: true,
            outcomeConsent: false,
            healthAuthorized: false,
            migrationVersion: localMigrationVersion,
            signals: [
              for (final entry in const {
                SignalType.sleep: 8.1,
                SignalType.hydration: 2.3,
                SignalType.study: 3.0,
                SignalType.exercise: .8,
                SignalType.screenTime: 2.5,
              }.entries)
                SignalReading(
                  id: entry.key.name,
                  type: entry.key,
                  value: entry.value,
                  timestamp: recordedAt,
                ),
              SignalReading(
                id: 'reaction-today',
                type: SignalType.reactionTime,
                value: 260,
                timestamp: recordedAt,
              ),
              SignalReading(
                id: 'reaction-prior',
                type: SignalType.reactionTime,
                value: 280,
                timestamp: recordedAt.subtract(const Duration(days: 8)),
              ),
            ],
            checkIns: [
              DailyCheckIn(
                id: 'today-check-in',
                timestamp: recordedAt,
                energy: 8,
                mood: 8,
                stress: 3,
              ),
            ],
          ),
        );
      await repository.upsertScoreSnapshot(
        'score-uid',
        ScoreSnapshot(
          energy: 68,
          cognitive: 62,
          confidence: .8,
          drivers: const [],
          cognitiveConfidence: .7,
          cognitiveDrivers: const [],
          day: previousDay,
        ),
      );
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );

      await controller.load();

      final persisted = await repository.scoreSnapshotForDay('score-uid', now);
      expect(controller.score.inputCount, 7);
      expect(controller.score.cognitiveInputCount, 5);
      expect(controller.score.previousCognitive, 62);
      expect(
        controller.score.cognitiveDrivers
            .singleWhere((driver) => driver.label == 'Reaction time')
            .detail,
        contains('baseline'),
      );
      expect(controller.score.isEstimate, isTrue);
      expect(controller.scoreError, isNull);
      expect(persisted, isNotNull);
      expect(persisted?.energy, controller.score.energy);
      expect(persisted?.cognitive, controller.score.cognitive);
      expect(persisted?.cognitiveDrivers, hasLength(5));
      expect(persisted?.previousCognitive, 62);
      expect(persisted?.drivers, hasLength(7));
    },
  );

  test(
    'Version 0.8 stores morning/evening check-ins on a 1–10 scale',
    () async {
      final controller = AppController();
      await controller.load();

      await controller.addCheckIn(
        energy: 8,
        mood: 7,
        stress: 3,
        note: 'Ready to study',
        timestamp: DateTime(2026, 7, 23, 9),
      );
      await controller.addCheckIn(
        energy: 5,
        mood: 4,
        stress: 8,
        timestamp: DateTime(2026, 7, 23, 20),
      );

      expect(controller.checkIns, hasLength(2));
      expect(controller.checkIns.first.period, CheckInPeriod.evening);
      expect(controller.checkIns.first.stress, 8);
      expect(controller.checkIns.last.period, CheckInPeriod.morning);
      expect(controller.checkIns.last.mood, 7);

      final restored = AppController();
      await restored.load();
      expect(restored.checkIns, hasLength(2));
      expect(restored.checkIns.first.period, CheckInPeriod.evening);
      expect(restored.recentCheckIns().first.energy, 5);
    },
  );

  test(
    'Version 0.8 period follows the check-in timestamp, not a manual choice',
    () async {
      final controller = AppController();
      await controller.load();

      await controller.addCheckIn(
        energy: 6,
        mood: 6,
        stress: 4,
        timestamp: DateTime(2026, 7, 23, 21),
      );

      expect(controller.checkIns.single.period, CheckInPeriod.evening);

      await controller.addCheckIn(
        energy: 7,
        mood: 7,
        stress: 3,
        timestamp: DateTime(2026, 7, 23, 10),
      );

      expect(controller.checkIns.first.period, CheckInPeriod.morning);
    },
  );

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

  test(
    'Version 0.9 saves reaction benchmarks and exposes a baseline',
    () async {
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
    },
  );

  test('Version 0.9 rejects invalid reaction averages', () async {
    final controller = AppController();
    await controller.load();

    expect(() => controller.addReactionResult(50), throwsArgumentError);
    expect(() => controller.addReactionResult(2000), throwsArgumentError);
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

  test('Version 0.6 activity logs treat omitted fields as zero', () async {
    final controller = AppController();
    await controller.load();
    await controller.saveActivityLog(
      hydrationLiters: 2.2,
      timestamp: DateTime(2026, 7, 23, 12),
    );

    expect(controller.activityLogs, hasLength(1));
    expect(controller.activityLogs.single.hydrationLiters, 2.2);
    expect(controller.activityLogs.single.studyHours, 0);
    expect(controller.activityLogs.single.exerciseHours, 0);
    expect(controller.activityLogs.single.screenTimeHours, 0);
    expect(
      controller.signals.where(
        (signal) => signal.groupId == controller.activityLogs.single.id,
      ),
      hasLength(4),
    );

    final restored = AppController();
    await restored.load();
    expect(restored.activityLogs.single.hydrationLiters, 2.2);
    expect(restored.activityLogs.single.studyHours, 0);

    expect(() => controller.saveActivityLog(), throwsArgumentError);
  });

  test(
    'Version 0.10 history persists, edits, and deletes manual entries',
    () async {
      final controller = AppController();
      await controller.load();
      final day = DateTime(2026, 7, 23);
      await controller.saveActivityLog(
        hydrationLiters: 2.5,
        timestamp: day.add(const Duration(hours: 18)),
      );
      await controller.addSleep(
        bedtime: day.subtract(const Duration(hours: 1)),
        wakeTime: day.add(const Duration(hours: 7)),
        quality: 4,
      );
      await controller.addCheckIn(
        energy: 8,
        mood: 7,
        stress: 3,
        timestamp: day.add(const Duration(hours: 9)),
      );

      expect(controller.dailyHistory, hasLength(1));
      expect(controller.dailyHistory.single.completionCount, 3);
      expect(controller.dailyHistory.single.items, hasLength(3));

      final checkIn = controller.checkIns.single;
      await controller.addCheckIn(
        id: checkIn.id,
        energy: 6,
        mood: 5,
        stress: 4,
        note: 'Updated',
        timestamp: checkIn.timestamp,
      );
      expect(controller.checkIns, hasLength(1));
      expect(controller.checkIns.single.energy, 6);
      expect(controller.checkIns.single.note, 'Updated');

      final restored = AppController();
      await restored.load();
      expect(restored.dailyHistory.single.completionCount, 3);
      expect(restored.checkIns.single.energy, 6);

      await restored.deleteActivityLog(restored.activityLogs.single.id);
      await restored.deleteSleepLog(restored.sleepLogs.single.id);
      await restored.deleteCheckIn(restored.checkIns.single.id);
      expect(restored.dailyHistory, isEmpty);
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
