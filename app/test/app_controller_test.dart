import 'package:app/src/app_controller.dart';
import 'package:app/src/activity_sync_logic.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/health_service.dart';
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

  test(
    'Profile createCloudAccount registers and uploads local data',
    () async {
      final local = AppController();
      await local.load();
      await local.completeOnboarding(const UserProfile(name: 'Device Maya'));

      final repository = MemoryCloudRepository(signedInUid: 'test-uid');
      final controller = AppController(
        accountAuth: MemoryAccountAuth(),
        cloudRepository: repository,
      );
      await controller.load();

      await controller.createCloudAccount(
        email: 'maya@example.com',
        password: 'secure-pass',
      );

      expect(controller.isCloudAuthenticated, isTrue);
      expect(controller.accountEmail, 'maya@example.com');
      final cloud = await repository.readUser('test-uid');
      expect(cloud, isNotNull);
      expect(cloud!.profile.name, 'Device Maya');
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
    'clearTrackingData wipes logs but keeps the signed-in account',
    () async {
      final auth = MemoryAccountAuth();
      final repository = MemoryCloudRepository(signedInUid: 'test-uid');
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );
      await controller.load();
      await controller.completeOnboarding(
        const UserProfile(name: 'Fresh start'),
        email: 'fresh@example.com',
        password: 'secure-pass',
      );
      await controller.addCheckIn(energy: 6, mood: 6, stress: 4);
      await controller.addSignal(SignalType.hydration, 2.0);
      expect(controller.checkIns, isNotEmpty);
      expect(controller.signals, isNotEmpty);

      await controller.clearTrackingData();

      expect(controller.onboardingComplete, isTrue);
      expect(controller.accountEmail, 'fresh@example.com');
      expect(controller.profile.name, 'Fresh start');
      expect(controller.checkIns, isEmpty);
      expect(controller.signals, isEmpty);
      expect(auth.currentSession, isNotNull);
      final cloud = await repository.readUser('test-uid');
      expect(cloud?.checkIns, isEmpty);
      expect(cloud?.signals, isEmpty);
    },
  );

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
      expect(controller.score.cognitiveInputCount, 6);
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
      expect(persisted?.cognitiveDrivers, hasLength(6));
      expect(persisted?.previousCognitive, 62);
      expect(persisted?.drivers, hasLength(7));
    },
  );

  test(
    'Version 0.13 loads today snapshot and day-scoped signal summaries',
    () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'dashboard-uid',
          email: 'dashboard@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'dashboard-uid')
        ..seed(
          'dashboard-uid',
          CloudUserState(
            profile: const UserProfile(name: 'Dashboard Maya'),
            accountEmail: 'dashboard@example.com',
            onboardingComplete: true,
            notificationsEnabled: true,
            outcomeConsent: false,
            healthAuthorized: false,
            migrationVersion: localMigrationVersion,
            signals: [
              SignalReading(
                id: 'water-morning',
                type: SignalType.hydration,
                value: .7,
                timestamp: day,
              ),
              SignalReading(
                id: 'water-lunch',
                type: SignalType.hydration,
                value: 1.2,
                timestamp: day,
              ),
              SignalReading(
                id: 'old-water',
                type: SignalType.hydration,
                value: 4,
                timestamp: day.subtract(const Duration(hours: 2)),
              ),
            ],
            checkIns: const [],
          ),
        );
      await repository.upsertScoreSnapshot(
        'dashboard-uid',
        ScoreSnapshot(
          energy: 91,
          cognitive: 87,
          confidence: .88,
          drivers: const [ScoreDriver('Sleep', 7, 'Saved driver')],
          cognitiveConfidence: .82,
          cognitiveDrivers: const [
            ScoreDriver('Reaction time', 5, 'Saved driver'),
          ],
          inputCount: 6,
          cognitiveInputCount: 4,
          freshness: .86,
          cognitiveFreshness: .81,
          day: day,
          calculatedAt: day.add(const Duration(hours: 6)),
        ),
      );
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );

      await controller.load();

      expect(controller.score.energy, 91);
      expect(controller.score.cognitive, 87);
      expect(controller.scoreLoadedFromSnapshot, isTrue);
      final hydration = controller.todaySignalSummaries.singleWhere(
        (item) => item.type == SignalType.hydration,
      );
      expect(hydration.displayValue, '1.9 L');
      expect(hydration.readingCount, 2);
    },
  );

  test('Version 0.14 upgrades snapshots without freshness metadata', () async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final auth = MemoryAccountAuth(
      session: const AccountSession(
        uid: 'upgrade-uid',
        email: 'upgrade@example.com',
      ),
    );
    final repository = MemoryCloudRepository(signedInUid: 'upgrade-uid')
      ..seed(
        'upgrade-uid',
        CloudUserState(
          profile: const UserProfile(name: 'Upgrade Maya'),
          accountEmail: 'upgrade@example.com',
          onboardingComplete: true,
          notificationsEnabled: true,
          outcomeConsent: false,
          healthAuthorized: false,
          migrationVersion: localMigrationVersion,
          signals: [
            SignalReading(
              id: 'sleep',
              type: SignalType.sleep,
              value: 8,
              timestamp: now,
            ),
          ],
          checkIns: const [],
        ),
      );
    await repository.upsertScoreSnapshot(
      'upgrade-uid',
      ScoreSnapshot(
        energy: 99,
        cognitive: 99,
        confidence: .95,
        drivers: const [],
        day: day,
      ),
    );
    final controller = AppController(
      accountAuth: auth,
      cloudRepository: repository,
    );

    await controller.load();

    final upgraded = await repository.scoreSnapshotForDay('upgrade-uid', day);
    expect(controller.score.energy, isNot(99));
    expect(controller.scoreLoadedFromSnapshot, isFalse);
    expect(controller.score.freshness, isNotNull);
    expect(upgraded?.freshness, isNotNull);
    expect(upgraded?.drivers.single.explanation, isNotEmpty);
  });

  test(
    'Version 0.16 persists and reloads a seven-day forecast range',
    () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'forecast-uid',
          email: 'forecast@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'forecast-uid')
        ..seed(
          'forecast-uid',
          CloudUserState(
            profile: const UserProfile(name: 'Forecast Maya'),
            accountEmail: 'forecast@example.com',
            onboardingComplete: true,
            notificationsEnabled: true,
            outcomeConsent: false,
            healthAuthorized: false,
            migrationVersion: localMigrationVersion,
            signals: [
              SignalReading(
                id: 'sleep',
                type: SignalType.sleep,
                value: 8,
                timestamp: now,
              ),
              SignalReading(
                id: 'bedtime',
                type: SignalType.bedtime,
                value: 23,
                timestamp: now,
              ),
              SignalReading(
                id: 'study',
                type: SignalType.study,
                value: 3,
                timestamp: now,
              ),
            ],
            checkIns: [
              DailyCheckIn(
                id: 'check-in',
                timestamp: now,
                energy: 7,
                mood: 7,
                stress: 3,
              ),
            ],
          ),
        );
      final first = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );
      await first.load();

      final persisted = await repository.forecastPointsByRange(
        'forecast-uid',
        start: day,
        end: day.add(const Duration(days: 7)),
      );
      expect(persisted, hasLength(119));
      expect(first.forecastFor(day), hasLength(17));
      expect(first.forecastSummariesFor(day), hasLength(7));
      expect(persisted.every((point) => point.updatedAt != null), isTrue);
      expect(
        persisted.every(
          (point) =>
              point.signalEvidenceIds.contains('sleep') &&
              point.checkInEvidenceIds.contains('check-in'),
        ),
        isTrue,
      );
      expect(first.forecastLoadedFromCloud, isFalse);
      expect(first.forecastError, isNull);

      final restored = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );
      await restored.load();

      expect(restored.forecastLoadedFromCloud, isTrue);
      expect(restored.forecastFor(day), hasLength(17));
      expect(restored.forecastSummariesFor(day), hasLength(7));
      expect(
        restored
            .windowsFor(day)
            .expand((window) => window.evidence)
            .map((evidence) => evidence.id),
        containsAll(['sleep', 'check-in']),
      );
      expect(
        restored.forecastFor(day).first.energy,
        first.forecastFor(day).first.energy,
      );

      final staleAt = now.subtract(const Duration(hours: 13));
      for (var index = 0; index < AppController.forecastDayCount; index++) {
        final targetDay = day.add(Duration(days: index));
        final targetPoints = persisted
            .where(
              (point) =>
                  point.time.year == targetDay.year &&
                  point.time.month == targetDay.month &&
                  point.time.day == targetDay.day,
            )
            .map(
              (point) => ForecastPoint(
                point.time,
                99,
                point.uncertainty,
                updatedAt: staleAt,
              ),
            )
            .toList();
        await repository.replaceForecastPoints(
          'forecast-uid',
          day: targetDay,
          points: targetPoints,
        );
      }
      final refreshed = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );
      await refreshed.load();

      expect(refreshed.forecastLoadedFromCloud, isFalse);
      expect(refreshed.forecastFor(day).first.energy, isNot(99));
      expect(
        refreshed
            .forecastSummariesFor(day)
            .every((summary) => !summary.isStaleAt(DateTime.now())),
        isTrue,
      );
    },
  );

  test(
    'Versions 0.18–0.19 persist grounded guidance and alert dismissal',
    () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'guidance-uid',
          email: 'guidance@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'guidance-uid')
        ..seed(
          'guidance-uid',
          CloudUserState(
            profile: const UserProfile(name: 'Guidance Maya'),
            accountEmail: 'guidance@example.com',
            onboardingComplete: true,
            notificationsEnabled: true,
            outcomeConsent: false,
            healthAuthorized: false,
            migrationVersion: localMigrationVersion,
            signals: [
              for (var index = 0; index < 4; index++)
                SignalReading(
                  id: 'short-sleep-$index',
                  type: SignalType.sleep,
                  value: 5.4,
                  timestamp: now.subtract(Duration(days: index)),
                ),
              SignalReading(
                id: 'bedtime',
                type: SignalType.bedtime,
                value: 1,
                timestamp: now.subtract(const Duration(hours: 6)),
              ),
              for (var index = 0; index < 3; index++)
                SignalReading(
                  id: 'exercise-$index',
                  type: SignalType.exercise,
                  value: 2.5,
                  timestamp: now.subtract(Duration(days: index)),
                ),
              SignalReading(
                id: 'study',
                type: SignalType.study,
                value: 6,
                timestamp: now.subtract(const Duration(hours: 2)),
              ),
              SignalReading(
                id: 'hydration',
                type: SignalType.hydration,
                value: .7,
                timestamp: now.subtract(const Duration(hours: 1)),
              ),
            ],
            checkIns: [
              for (var index = 0; index < 3; index++)
                DailyCheckIn(
                  id: 'strained-$index',
                  timestamp: now.subtract(Duration(days: index)),
                  energy: 3,
                  mood: 4,
                  stress: 9,
                ),
            ],
          ),
        );
      final first = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );

      await first.load();

      final persistedRecommendations = await repository.recommendationsForDay(
        'guidance-uid',
        day,
      );
      final persistedAlerts = await repository.riskAlertsForDay(
        'guidance-uid',
        day,
      );
      expect(first.recommendations, hasLength(5));
      expect(first.recommendations.every((item) => item.isGrounded), isTrue);
      expect(persistedRecommendations, hasLength(5));
      expect(persistedAlerts.map((item) => item.category).toSet(), {
        RiskAlertCategory.sleepDebt,
        RiskAlertCategory.trainingLoad,
        RiskAlertCategory.fatigueStress,
      });
      expect(first.guidanceSavedToCloud, isTrue);
      expect(first.guidanceError, isNull);

      final dismissedId = persistedAlerts.first.id;
      await first.dismissRiskAlert(dismissedId);
      expect(first.alerts.map((item) => item.id), isNot(contains(dismissedId)));

      final restored = AppController(
        accountAuth: auth,
        cloudRepository: repository,
      );
      await restored.load();

      expect(
        restored.allAlerts
            .singleWhere((item) => item.id == dismissedId)
            .dismissed,
        isTrue,
      );
      expect(
        restored.alerts.map((item) => item.id),
        isNot(contains(dismissedId)),
      );
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
    expect(
      controller.signals
          .singleWhere((signal) => signal.type == SignalType.hydration)
          .note,
      ActivitySyncLogic.manualCorrectionNote,
    );
    expect(
      controller.signals
          .singleWhere((signal) => signal.type == SignalType.exercise)
          .note,
      ActivitySyncLogic.blankManualValueNote,
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

  test(
    'Version 0.22 handles approval, denial, and revocation without changing manual data',
    () async {
      final health = _FakeHealthService(
        status: HealthAuthorizationState.notDetermined,
        requestResult: HealthAuthorizationState.denied,
      );
      final controller = AppController(healthService: health);
      await controller.load();
      final manual = SignalReading(
        id: 'manual-hydration',
        type: SignalType.hydration,
        value: 2.2,
        timestamp: DateTime(2026, 8, 17, 12),
      );
      controller.signals = [manual];

      expect(controller.healthAvailable, isTrue);
      expect(await controller.connectHealth(), isFalse);
      expect(controller.healthAuthorization, HealthAuthorizationState.denied);
      expect(controller.signals, [manual]);

      health.requestResult = HealthAuthorizationState.authorized;
      expect(await controller.connectHealth(), isTrue);
      expect(controller.healthAuthorized, isTrue);
      expect(controller.signals, [manual]);

      await controller.disconnectHealth();
      expect(controller.healthAuthorized, isFalse);
      expect(controller.healthAuthorization, HealthAuthorizationState.revoked);
      expect(controller.signals, [manual]);

      health.status = HealthAuthorizationState.authorized;
      await controller.refreshHealthAuthorization();
      expect(controller.healthAuthorization, HealthAuthorizationState.revoked);
      expect(controller.signals, [manual]);
    },
  );

  test(
    'Version 0.23 imports normalized heart signals and persists them to Firestore',
    () async {
      final hrvTimestamp = DateTime.utc(2026, 8, 17, 10);
      final health = _FakeHealthService(
        status: HealthAuthorizationState.notDetermined,
        requestResult: HealthAuthorizationState.authorized,
        syncReadings: [
          SignalReading(
            id: 'healthkit-hrv',
            type: SignalType.hrv,
            value: 55.2,
            timestamp: hrvTimestamp,
            source: SignalSource.healthKit,
          ),
          SignalReading(
            id: 'healthkit-rhr',
            type: SignalType.restingHeartRate,
            value: 61,
            timestamp: DateTime.utc(2026, 8, 17, 9),
            source: SignalSource.healthKit,
          ),
          SignalReading(
            id: 'healthkit-manual-duplicate',
            type: SignalType.hrv,
            value: 55.25,
            timestamp: hrvTimestamp.add(const Duration(minutes: 1)),
            source: SignalSource.healthKit,
          ),
        ],
      );
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'health-user',
          email: 'health@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'health-user');
      final controller = AppController(
        healthService: health,
        accountAuth: auth,
        cloudRepository: repository,
      );
      await controller.load();
      controller.signals = [
        SignalReading(
          id: 'manual-hrv',
          type: SignalType.hrv,
          value: 55.2,
          timestamp: hrvTimestamp.toLocal(),
        ),
      ];

      expect(await controller.connectHealth(), isTrue);

      expect(health.syncCalls, 1);
      expect(controller.lastHealthImportCount, 1);
      expect(controller.lastHealthDuplicateCount, 2);
      expect(controller.lastHealthRejectedCount, 0);
      expect(controller.healthKitHeartSignalCount, 1);
      expect(controller.lastSync, isNotNull);
      expect(
        controller.signals
            .singleWhere((item) => item.id == 'manual-hrv')
            .source,
        SignalSource.manual,
      );
      final imported = controller.signals.singleWhere(
        (item) => item.id == 'healthkit-rhr',
      );
      expect(imported.source, SignalSource.healthKit);
      expect(imported.timestamp.isUtc, isFalse);

      final cloud = await repository.readUser('health-user');
      expect(cloud, isNotNull);
      expect(
        cloud!.signals.singleWhere((item) => item.id == 'healthkit-rhr').source,
        SignalSource.healthKit,
      );
    },
  );

  test(
    'Version 0.23 surfaces sync failures without losing existing data',
    () async {
      final health = _FakeHealthService(
        status: HealthAuthorizationState.notDetermined,
        requestResult: HealthAuthorizationState.authorized,
        syncError: const HealthSyncException('Health query failed.'),
        sleepSyncError: const HealthSyncException('Sleep query failed.'),
        activitySyncError: const HealthSyncException('Activity query failed.'),
      );
      final controller = AppController(healthService: health);
      await controller.load();
      final manual = SignalReading(
        id: 'manual-heart',
        type: SignalType.hrv,
        value: 52,
        timestamp: DateTime(2026, 8, 17, 10),
      );
      controller.signals = [manual];

      expect(await controller.connectHealth(), isTrue);

      expect(controller.healthAuthorized, isTrue);
      expect(controller.isSyncing, isFalse);
      expect(controller.healthSyncError, 'Health query failed.');
      expect(controller.sleepSyncError, 'Sleep query failed.');
      expect(controller.activitySyncError, 'Activity query failed.');
      expect(controller.lastSync, isNull);
      expect(controller.signals, [manual]);
    },
  );

  test(
    'Version 0.24 reconciles typed sleep stages and persists the night to Firestore',
    () async {
      final wake = DateTime(2026, 8, 17, 7);
      final health = _FakeHealthService(
        status: HealthAuthorizationState.notDetermined,
        requestResult: HealthAuthorizationState.authorized,
        sleepReadings: [
          SignalReading(
            id: 'healthkit-sleep-core',
            type: SignalType.sleepCore,
            value: 5,
            timestamp: wake.subtract(const Duration(hours: 3)),
            source: SignalSource.healthKit,
            groupId: 'com.apple.health.watch',
          ),
          SignalReading(
            id: 'healthkit-sleep-deep',
            type: SignalType.sleepDeep,
            value: 1.5,
            timestamp: wake.subtract(const Duration(hours: 1, minutes: 30)),
            source: SignalSource.healthKit,
            groupId: 'com.apple.health.watch',
          ),
          SignalReading(
            id: 'healthkit-sleep-rem',
            type: SignalType.sleepRem,
            value: 1.5,
            timestamp: wake,
            source: SignalSource.healthKit,
            groupId: 'com.apple.health.watch',
          ),
        ],
      );
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'sleep-user',
          email: 'sleep@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'sleep-user');
      final controller = AppController(
        healthService: health,
        accountAuth: auth,
        cloudRepository: repository,
      );
      await controller.load();

      expect(await controller.connectHealth(), isTrue);

      expect(health.sleepSyncCalls, 1);
      expect(controller.lastSleepNightCount, 1);
      expect(controller.healthKitSleepNightCount, 1);
      expect(controller.healthKitSleepSignalCount, 3);
      expect(
        controller.signals
            .singleWhere((item) => item.type == SignalType.sleep)
            .value,
        8,
      );
      expect(
        controller.signals.map((item) => item.type),
        containsAll([
          SignalType.sleepCore,
          SignalType.sleepDeep,
          SignalType.sleepRem,
        ]),
      );

      final cloud = await repository.readUser('sleep-user');
      expect(cloud, isNotNull);
      expect(
        cloud!.signals.where((item) => item.type == SignalType.sleepDeep),
        hasLength(1),
      );
    },
  );

  test(
    'Version 0.25 persists activity imports and retains manual fallback controls',
    () async {
      final day = DateTime(2026, 8, 17);
      final health = _FakeHealthService(
        status: HealthAuthorizationState.notDetermined,
        requestResult: HealthAuthorizationState.authorized,
        activityReadings: [
          SignalReading(
            id: 'healthkit-workout',
            type: SignalType.exercise,
            value: 1.5,
            timestamp: day.add(const Duration(hours: 10)),
            source: SignalSource.healthKit,
          ),
          SignalReading(
            id: 'healthkit-water',
            type: SignalType.hydration,
            value: .4,
            timestamp: day.add(const Duration(hours: 11)),
            source: SignalSource.healthKit,
          ),
        ],
      );
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'activity-user',
          email: 'activity@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'activity-user');
      final controller = AppController(
        healthService: health,
        accountAuth: auth,
        cloudRepository: repository,
      );
      await controller.load();

      expect(await controller.connectHealth(), isTrue);

      expect(health.activitySyncCalls, 1);
      expect(controller.lastActivityImportCount, 2);
      expect(controller.healthKitWorkoutSignalCount, 1);
      expect(controller.healthKitHydrationSignalCount, 1);
      var cloud = await repository.readUser('activity-user');
      expect(cloud, isNotNull);
      expect(
        cloud!.signals.map((item) => item.id),
        containsAll(['healthkit-workout', 'healthkit-water']),
      );

      await controller.saveActivityLog(
        id: 'activity-correction',
        exerciseHours: .75,
        hydrationLiters: 1.8,
        timestamp: day.add(const Duration(hours: 12)),
      );
      expect(
        ActivitySyncLogic.aggregateForDay(
          controller.signals,
          type: SignalType.exercise,
          day: day,
        )!.total,
        .75,
      );
      expect(
        ActivitySyncLogic.aggregateForDay(
          controller.signals,
          type: SignalType.hydration,
          day: day,
        )!.total,
        1.8,
      );

      await controller.deleteActivityLog('activity-correction');
      expect(
        ActivitySyncLogic.aggregateForDay(
          controller.signals,
          type: SignalType.exercise,
          day: day,
        )!.total,
        1.5,
      );
      expect(
        ActivitySyncLogic.aggregateForDay(
          controller.signals,
          type: SignalType.hydration,
          day: day,
        )!.total,
        .4,
      );
      cloud = await repository.readUser('activity-user');
      expect(
        cloud!.signals.map((item) => item.id),
        contains('healthkit-workout'),
      );
      expect(
        cloud.signals.where((item) => item.groupId == 'activity-correction'),
        isEmpty,
      );
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

class _FakeHealthService extends HealthService {
  _FakeHealthService({
    required this.status,
    required this.requestResult,
    this.syncReadings = const [],
    this.sleepReadings = const [],
    this.activityReadings = const [],
    this.syncError,
    this.sleepSyncError,
    this.activitySyncError,
  });

  HealthAuthorizationState status;
  HealthAuthorizationState requestResult;
  List<SignalReading> syncReadings;
  List<SignalReading> sleepReadings;
  List<SignalReading> activityReadings;
  Object? syncError;
  Object? sleepSyncError;
  Object? activitySyncError;
  int syncCalls = 0;
  int sleepSyncCalls = 0;
  int activitySyncCalls = 0;

  @override
  Future<HealthAuthorizationState> authorizationStatus() async => status;

  @override
  Future<HealthAuthorizationState> requestAuthorization() async =>
      requestResult;

  @override
  Future<List<SignalReading>> sync() async {
    syncCalls += 1;
    final error = syncError;
    if (error != null) throw error;
    return syncReadings;
  }

  @override
  Future<List<SignalReading>> syncSleep() async {
    sleepSyncCalls += 1;
    final error = sleepSyncError;
    if (error != null) throw error;
    return sleepReadings;
  }

  @override
  Future<List<SignalReading>> syncActivity() async {
    activitySyncCalls += 1;
    final error = activitySyncError;
    if (error != null) throw error;
    return activityReadings;
  }
}
