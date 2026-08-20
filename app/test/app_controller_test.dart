import 'package:app/src/app_controller.dart';
import 'package:app/src/activity_sync_logic.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screen_time_service.dart';
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

  test(
    'Version 0.31 links only future consented energy and reaction outcomes',
    () async {
      final now = DateTime(2026, 8, 20, 12);
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'outcome-uid',
          email: 'outcomes@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'outcome-uid')
        ..seed(
          'outcome-uid',
          const CloudUserState(
            profile: UserProfile(name: 'Outcome Maya'),
            accountEmail: 'outcomes@example.com',
            onboardingComplete: false,
            notificationsEnabled: false,
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
        clock: () => now,
      );

      await controller.load();
      await controller.addCheckIn(
        id: 'before-consent',
        energy: 4,
        mood: 5,
        stress: 6,
        timestamp: now.subtract(const Duration(hours: 2)),
      );
      await controller.addReactionResult(270);
      expect(controller.outcomes, isEmpty);

      await controller.setOutcomeConsent(true);
      expect(
        (await repository.readUser('outcome-uid'))!.outcomeConsent,
        isTrue,
      );
      await controller.addCheckIn(
        id: 'after-consent',
        energy: 8,
        mood: 7,
        stress: 3,
        timestamp: now,
      );
      await controller.addReactionResult(245);

      expect(controller.observedEnergyOutcomeCount, 1);
      expect(controller.cognitiveOutcomeCount, 1);
      final stored = await repository.outcomesByRange(
        'outcome-uid',
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(days: 1)),
      );
      expect(stored, hasLength(2));
      expect(stored.map((item) => item.type).toSet(), {
        OutcomeType.observedEnergy,
        OutcomeType.cognitiveReaction,
      });

      await controller.setOutcomeConsent(false);
      expect(controller.outcomes, isEmpty);
      expect(
        (await repository.readUser('outcome-uid'))!.outcomeConsent,
        isFalse,
      );
      expect(
        repository.outcomesByRange(
          'outcome-uid',
          start: now.subtract(const Duration(days: 1)),
          end: now.add(const Duration(days: 1)),
        ),
        throwsStateError,
      );

      await controller.setOutcomeConsent(true);
      expect(controller.outcomes, hasLength(2));
      await controller.deleteCheckIn('after-consent');
      expect(controller.observedEnergyOutcomeCount, 0);
      final reactionSignal = controller.signals.firstWhere(
        (item) => item.type == SignalType.reactionTime && item.value == 245,
      );
      await controller.deleteSignal(reactionSignal.id);
      expect(controller.outcomes, isEmpty);
    },
  );

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
          personalBaselines: PersonalBaselines(
            generatedAt: day,
            windowDays: 42,
            metrics: const [],
          ),
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
    'Versions 0.18–0.31 persist plans, feedback, outcomes, and alert dismissal',
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
            profile: const UserProfile(
              name: 'Guidance Maya',
              coachPriority: CoachPriority.training,
            ),
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
      for (var index = 1; index <= 2; index++) {
        final historyDay = day.subtract(Duration(days: index));
        await repository.replaceRecommendationsForDay(
          'guidance-uid',
          day: historyDay,
          recommendations: [
            Recommendation(
              id: 'history-focus-$index',
              title: 'Past focus',
              detail: 'Past grounded focus block',
              timeLabel: '9:00 AM',
              category: 'Deep work',
              status: RecommendationStatus.completed,
              scheduledAt: historyDay.add(const Duration(hours: 9)),
              day: historyDay,
              generatedAt: historyDay,
              planPhase: CoachPlanPhase.deepWork,
              helpful: true,
            ),
            Recommendation(
              id: 'history-training-$index',
              title: 'Past training',
              detail: 'Past grounded training block',
              timeLabel: '5:00 PM',
              category: 'Training',
              status: RecommendationStatus.dismissed,
              scheduledAt: historyDay.add(const Duration(hours: 17)),
              day: historyDay,
              generatedAt: historyDay,
              planPhase: CoachPlanPhase.training,
              helpful: false,
            ),
          ],
        );
      }
      final first = AppController(
        accountAuth: auth,
        cloudRepository: repository,
        clock: () => now,
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
      expect(first.recommendations, hasLength(8));
      expect(first.recommendations.every((item) => item.isGrounded), isTrue);
      expect(
        first.recommendations.every(
          (item) =>
              item.planPhase != null &&
              item.durationMinutes != null &&
              item.decisionReason != null,
        ),
        isTrue,
      );
      expect(persistedRecommendations, hasLength(8));
      final focus = first.recommendations.singleWhere(
        (item) => item.planPhase == CoachPlanPhase.deepWork,
      );
      final training = first.recommendations.singleWhere(
        (item) => item.planPhase == CoachPlanPhase.training,
      );
      expect(focus.feedbackSampleCount, 2);
      expect(focus.feedbackScore, .75);
      expect(focus.feedbackRank, 1);
      expect(focus.priority, RecommendationPriority.important);
      expect(training.feedbackSampleCount, 2);
      expect(training.feedbackScore, .25);
      expect(training.priority, RecommendationPriority.routine);
      expect(
        (await repository.readUser('guidance-uid'))!.profile.coachPriority,
        CoachPriority.training,
      );
      expect(persistedAlerts.map((item) => item.category).toSet(), {
        RiskAlertCategory.sleepDebt,
        RiskAlertCategory.trainingLoad,
        RiskAlertCategory.fatigueStress,
      });
      expect(first.guidanceSavedToCloud, isTrue);
      expect(first.guidanceError, isNull);

      await first.setOutcomeConsent(true);

      final completedId = first.recommendations.first.id;
      await first.setRecommendationStatus(
        completedId,
        RecommendationStatus.accepted,
      );
      expect(
        (await repository.recommendationsForDay(
          'guidance-uid',
          day,
        )).singleWhere((item) => item.id == completedId).status,
        RecommendationStatus.accepted,
      );
      await first.setRecommendationStatus(
        completedId,
        RecommendationStatus.completed,
      );
      await first.setRecommendationFeedback(completedId, true);
      await first.recordObservedEnergy(7, recommendationId: completedId);
      expect(first.outcomeForRecommendation(completedId)?.value, 7);
      final dismissedRecommendationId = first.recommendations.last.id;
      await first.setRecommendationStatus(
        dismissedRecommendationId,
        RecommendationStatus.dismissed,
      );
      await first.setRecommendationFeedback(dismissedRecommendationId, false);

      final dismissedId = persistedAlerts.first.id;
      await first.dismissRiskAlert(dismissedId);
      expect(first.alerts.map((item) => item.id), isNot(contains(dismissedId)));

      final restored = AppController(
        accountAuth: auth,
        cloudRepository: repository,
        clock: () => now,
      );
      await restored.load();

      final restoredCompleted = restored.recommendations.singleWhere(
        (item) => item.id == completedId,
      );
      final restoredDismissed = restored.recommendations.singleWhere(
        (item) => item.id == dismissedRecommendationId,
      );
      expect(restoredCompleted.status, RecommendationStatus.completed);
      expect(restoredCompleted.helpful, isTrue);
      expect(restored.outcomeForRecommendation(completedId)?.value, 7);
      expect(restoredDismissed.status, RecommendationStatus.dismissed);
      expect(restoredDismissed.helpful, isFalse);

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

  test(
    'Version 0.26 background refresh persists status and skips unchanged model work',
    () async {
      var now = DateTime(2026, 8, 20, 12);
      final health = _FakeHealthService(
        status: HealthAuthorizationState.notDetermined,
        requestResult: HealthAuthorizationState.authorized,
        syncReadings: [
          SignalReading(
            id: 'healthkit-hrv-v26',
            type: SignalType.hrv,
            value: 56,
            timestamp: now.subtract(const Duration(hours: 1)),
            source: SignalSource.healthKit,
          ),
        ],
      );
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'refresh-user',
          email: 'refresh@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'refresh-user');
      final controller = AppController(
        healthService: health,
        accountAuth: auth,
        cloudRepository: repository,
        clock: () => now,
      );
      await controller.load();
      controller.onboardingComplete = true;

      expect(await controller.connectHealth(), isTrue);

      expect(health.backgroundEnableCalls, 1);
      expect(controller.healthBackgroundRefreshEnabled, isTrue);
      expect(controller.healthSyncStatus, HealthSyncStatus.updated);
      expect(controller.lastHealthRefreshReason, HealthRefreshReason.initial);
      expect(controller.lastHealthChangeAt, now);
      expect(controller.signals.single.syncedAt, now.toUtc());
      final scoreWrites = repository.scoreUpsertCallCount;
      final forecastWrites = repository.forecastReplaceCallCount;

      now = now.add(const Duration(minutes: 16));
      await health.triggerBackgroundUpdate();

      expect(controller.healthSyncStatus, HealthSyncStatus.upToDate);
      expect(
        controller.lastHealthRefreshReason,
        HealthRefreshReason.background,
      );
      expect(repository.scoreUpsertCallCount, scoreWrites);
      expect(repository.forecastReplaceCallCount, forecastWrites);
      final cloud = await repository.readUser('refresh-user');
      expect(cloud?.healthSyncStatus, HealthSyncStatus.upToDate);
      expect(cloud?.lastHealthRefreshReason, HealthRefreshReason.background);
    },
  );

  test(
    'Version 0.27 queries private history and persists mature personal baselines',
    () async {
      final today = DateTime(2026, 8, 20);
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'baseline-user',
          email: 'baseline@example.com',
        ),
      );
      final repository = MemoryCloudRepository(signedInUid: 'baseline-user')
        ..seed(
          'baseline-user',
          CloudUserState(
            profile: const UserProfile(name: 'Baseline Maya'),
            accountEmail: 'baseline@example.com',
            onboardingComplete: true,
            notificationsEnabled: false,
            outcomeConsent: false,
            healthAuthorized: false,
            signals: [
              for (var daysAgo = 1; daysAgo <= 7; daysAgo++) ...[
                for (final entry in const {
                  SignalType.hrv: 52.0,
                  SignalType.restingHeartRate: 61.0,
                  SignalType.sleep: 8.0,
                  SignalType.reactionTime: 275.0,
                }.entries)
                  SignalReading(
                    id: '${entry.key.name}-$daysAgo',
                    type: entry.key,
                    value: entry.value,
                    timestamp: today
                        .subtract(Duration(days: daysAgo))
                        .add(const Duration(hours: 7)),
                  ),
              ],
              for (final entry in const {
                SignalType.hrv: 58.0,
                SignalType.restingHeartRate: 64.0,
                SignalType.sleep: 7.5,
                SignalType.reactionTime: 260.0,
              }.entries)
                SignalReading(
                  id: '${entry.key.name}-today',
                  type: entry.key,
                  value: entry.value,
                  timestamp: today.add(const Duration(hours: 8)),
                ),
            ],
            checkIns: const [],
          ),
        );
      final controller = AppController(
        accountAuth: auth,
        cloudRepository: repository,
        clock: () => today.add(const Duration(hours: 12)),
      );

      await controller.load();

      expect(controller.personalBaselines.readyCount, 4);
      expect(controller.score.baselineConfidence, 1);
      expect(
        controller.personalBaselines
            .metric(PersonalBaselineType.hrv)
            ?.sampleCount,
        7,
      );
      final saved = await repository.scoreSnapshotForDay(
        'baseline-user',
        today,
      );
      expect(saved?.personalBaselines?.readyCount, 4);
      expect(saved?.baselineConfidence, 1);
    },
  );

  test(
    'Version 0.28 gates the private report without replacing manual signals',
    () async {
      final screenTime = _FakeScreenTimeService(
        status: ScreenTimeAuthorizationState.entitlementRequired,
        requestResult: ScreenTimeAuthorizationState.authorized,
      );
      final controller = AppController(screenTimeService: screenTime);

      await controller.load();
      expect(
        controller.screenTimeAuthorization,
        ScreenTimeAuthorizationState.entitlementRequired,
      );
      expect(controller.screenTimeReportAvailable, isFalse);

      screenTime.status = ScreenTimeAuthorizationState.notDetermined;
      await controller.refreshScreenTimeAuthorization();
      await controller.saveActivityLog(screenTimeHours: 3.25);
      expect(controller.manualScreenTimeSignalCount, 1);

      final authorization = await controller.authorizeScreenTimeReport();
      final shown = await controller.showScreenTimeReport();

      expect(authorization, ScreenTimeAuthorizationState.authorized);
      expect(shown, isTrue);
      expect(screenTime.authorizationRequests, 1);
      expect(screenTime.reportRequests, 1);
      expect(
        controller.signals
            .singleWhere((item) => item.type == SignalType.screenTime)
            .value,
        3.25,
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
  int backgroundEnableCalls = 0;
  int backgroundDisableCalls = 0;
  Future<void> Function()? backgroundCallback;

  @override
  Future<bool> enableBackgroundUpdates(
    Future<void> Function() onHealthDataChanged,
  ) async {
    backgroundEnableCalls += 1;
    backgroundCallback = onHealthDataChanged;
    return true;
  }

  @override
  Future<void> disableBackgroundUpdates() async {
    backgroundDisableCalls += 1;
    backgroundCallback = null;
  }

  Future<void> triggerBackgroundUpdate() async {
    await backgroundCallback?.call();
  }

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

class _FakeScreenTimeService extends ScreenTimeService {
  _FakeScreenTimeService({required this.status, required this.requestResult});

  ScreenTimeAuthorizationState status;
  ScreenTimeAuthorizationState requestResult;
  int authorizationRequests = 0;
  int reportRequests = 0;

  @override
  Future<ScreenTimeAuthorizationState> authorizationStatus() async => status;

  @override
  Future<ScreenTimeAuthorizationState> requestAuthorization() async {
    authorizationRequests += 1;
    status = requestResult;
    return requestResult;
  }

  @override
  Future<bool> showReport() async {
    reportRequests += 1;
    return true;
  }
}
