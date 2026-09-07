import 'privacy_test_support.dart';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/energy_model_repository.dart';
import 'package:app/src/energy_residual_model.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/benchmark_energy_model.dart' show benchmarkSnapshot;

class _PrepSource implements PrepDataSource {
  _PrepSource(this.auth, this.snapshot);
  final MemoryAccountAuth auth;
  final PrepSnapshot snapshot;
  int accountReads = 0;
  int collectionReads = 0;

  @override
  String? get currentUid => auth.currentSession?.uid;

  @override
  Future<PrepAccountMetadata> readAccount(String uid) async {
    accountReads++;
    expect(uid, snapshot.uid);
    return PrepAccountMetadata(
      consent: snapshot.consent,
      schemaVersion: snapshot.schemaVersion,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> readCollection(
    String uid,
    PrepCollection collection,
    PrepWindow window, {
    required int limit,
  }) async {
    collectionReads++;
    expect(uid, snapshot.uid);
    expect(window.toJson(), snapshot.window.toJson());
    expect(limit, collection.maximumDocuments);
    return switch (collection) {
      PrepCollection.signals => snapshot.signals,
      PrepCollection.checkIns => snapshot.checkIns,
      PrepCollection.outcomes => snapshot.outcomes,
    };
  }
}

class _Health extends HealthService {
  int imports = 0;

  @override
  Future<HealthAuthorizationState> authorizationStatus() async =>
      HealthAuthorizationState.unavailable;
  @override
  Future<void> disableBackgroundUpdates() async {}
  @override
  Future<List<SignalReading>> sync() async {
    imports++;
    return [];
  }

  @override
  Future<List<SignalReading>> syncSleep() => sync();
  @override
  Future<List<SignalReading>> syncActivity() => sync();
}

class _ScreenTime extends ScreenTimeService {
  @override
  Future<ScreenTimeAuthorizationState> authorizationStatus() async =>
      ScreenTimeAuthorizationState.unavailable;
}

class _Harness {
  _Harness() {
    snapshot = benchmarkSnapshot();
    auth = MemoryAccountAuth(
      session: AccountSession(uid: snapshot.uid, email: 'isolated@example.com'),
    );
    source = _PrepSource(auth, snapshot);
    writer = MemoryEnergyModelMetadataWriter(auth: auth);
    repository = MemoryCloudRepository(signedInUid: snapshot.uid)
      ..seed(
        snapshot.uid,
        CloudUserState(
          privacyConsent: testAdultPrivacyConsent,
          profile: const UserProfile(name: 'Isolated integration test'),
          accountEmail: 'isolated@example.com',
          onboardingComplete: true,
          notificationsEnabled: false,
          outcomeConsent: true,
          healthAuthorized: false,
          migrationVersion: localMigrationVersion,
          signals: liveSignals,
          checkIns: const [],
        ),
      );
    controller = createController();
  }

  // A small future clock ensures an actual prep fetch's system timestamp is
  // never later than the injected model clock. No dates reach a real account.
  final now = DateTime.now().add(const Duration(days: 1));
  late final PrepSnapshot snapshot;
  late final MemoryAccountAuth auth;
  late final _PrepSource source;
  late final MemoryEnergyModelMetadataWriter writer;
  late final MemoryCloudRepository repository;
  final store = MemoryEnergyModelStore();
  final health = _Health();
  late final AppController controller;

  List<SignalReading> get liveSignals {
    final at = DateTime(now.year, now.month, now.day, 0).toUtc();
    return [
      for (final entry in {
        SignalType.exercise: 1.0,
        SignalType.hydration: 2.0,
        SignalType.study: 2.0,
        SignalType.screenTime: 2.0,
        SignalType.caffeine: 1.0,
      }.entries)
        SignalReading(
          id: 'manual-${at.microsecondsSinceEpoch}-${entry.key.name}',
          groupId: 'activity-${at.microsecondsSinceEpoch}',
          type: entry.key,
          value: entry.value,
          timestamp: at,
          syncedAt: at,
        ),
    ];
  }

  AppController createController() => AppController(
    initialPrivacyConsent: testAdultPrivacyConsent,
    accountAuth: auth,
    cloudRepository: repository,
    prepDataSource: source,
    energyModelStore: store,
    energyModelMetadataWriter: writer,
    healthService: health,
    screenTimeService: _ScreenTime(),
    clock: () => now,
  );

  Future<void> seedAcceptedModel() async {
    final fit = EnergyResidualTrainer.train(
      snapshot: snapshot,
      report: MlPrepBuilder.build(snapshot),
      trainedAt: snapshot.fetchedAt,
    );
    expect(fit.reason, 'accepted');
    await store.write(
      snapshot.uid,
      jsonEncode({
        'schemaVersion': 1,
        'ownerKey': prepFingerprint({'uid': snapshot.uid}),
        'model': fit.model!.toJson(),
        'lastAttemptAt': snapshot.fetchedAt.toIso8601String(),
        'eligibleOutcomeKeys': [
          for (final row in snapshot.outcomes)
            prepFingerprint({'outcomeId': row['id']}),
        ],
      }),
    );
  }

  Map<String, dynamic> get saved =>
      jsonDecode(store.values[snapshot.uid]!) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'load, scoring, new outcomes and Health never train or sync model metadata',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      expect(h.store.values, isEmpty);
      expect(h.writer.writes, 0);
      expect(h.source.collectionReads, 0);

      await h.controller.load();
      await h.controller.refreshScores(forceRecalculate: true);
      await h.controller.addCheckIn(
        energy: 7,
        mood: 6,
        stress: 4,
        timestamp: h.now,
      );
      h.controller.healthAuthorized = true;
      await h.controller.syncHealth();
      await h.controller.handleAppResumed();

      expect(h.health.imports, 3);
      expect(h.store.values, isEmpty);
      expect(h.writer.writes, 0);
      expect(h.source.accountReads, 0);
      expect(h.source.collectionReads, 0);
      expect(h.controller.isRefreshingPersonalizedModel, isFalse);
    },
  );

  test(
    'explicit refresh without a prepared snapshot rejects without database work',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.controller.outcomeConsent = true;
      await expectLater(
        h.controller.refreshPersonalizedModel(window: h.snapshot.window),
        throwsStateError,
      );
      expect(h.source.accountReads, 0);
      expect(h.source.collectionReads, 0);
      expect(h.repository.replaceUserCallCount, 0);
      expect(h.writer.writes, 0);
      expect(h.store.values, isEmpty);
    },
  );

  test(
    'explicit training consumes cached prep only and writes small metadata once',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.controller.outcomeConsent = true;
      h.controller.signals = h.liveSignals;
      final run = await h.controller.prepareModelSnapshot(
        window: h.snapshot.window,
      );
      expect(run.report.energyReady, isTrue);
      expect(h.source.accountReads, 1);
      expect(h.source.collectionReads, 3);
      expect(h.writer.writes, 0);

      await h.controller.refreshPersonalizedModel(window: h.snapshot.window);
      expect(h.controller.personalizedModelStatus, contains('accepted'));
      expect(h.saved['model'], isNotNull);
      expect(h.writer.writes, 1);
      expect(h.source.accountReads, 1);
      expect(h.source.collectionReads, 3);
      expect(h.repository.replaceUserCallCount, 0);
      expect(h.repository.scoreUpsertCallCount, 0);
      expect(h.repository.forecastReplaceCallCount, 0);
      expect(
        h.writer.values[h.snapshot.uid]!.keys.toSet(),
        EnergyModelMetadata.fields,
      );
      expect(h.writer.values[h.snapshot.uid], isNot(contains('weights')));

      await h.controller.refreshPersonalizedModel(window: h.snapshot.window);
      expect(h.writer.writes, 1);
      expect(h.source.collectionReads, 3);
      expect(h.repository.replaceUserCallCount, 0);
    },
  );

  test(
    'a mismatched window or edited account cannot reuse the old prepared run',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      h.controller.outcomeConsent = true;
      await h.controller.prepareModelSnapshot(window: h.snapshot.window);
      await expectLater(
        h.controller.refreshPersonalizedModel(
          window: PrepWindow.endingOn(
            DateTime(2026, 7, 30),
            timezone: h.snapshot.window.timezone,
          ),
        ),
        throwsStateError,
      );
      await h.controller.updateProfile(
        const UserProfile(name: 'Edited locally'),
      );
      final priorWrites = h.repository.replaceUserCallCount;
      await expectLater(
        h.controller.refreshPersonalizedModel(window: h.snapshot.window),
        throwsStateError,
      );
      expect(h.writer.writes, 0);
      expect(h.source.collectionReads, 3);
      expect(h.repository.replaceUserCallCount, priorWrites);
    },
  );

  test(
    'accepted owner model restores locally without fitting or metadata sync',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      await h.seedAcceptedModel();
      final before = h.store.values[h.snapshot.uid];
      await h.controller.load();
      expect(h.controller.personalizedModelStatus, contains('restored'));
      expect(h.controller.score.deterministicEnergy, isNotNull);
      expect(
        h.controller.score.energy - h.controller.score.deterministicEnergy!,
        inInclusiveRange(-10, 10),
      );
      expect(h.store.values[h.snapshot.uid], before);
      expect(h.writer.writes, 0);
      expect(h.source.collectionReads, 0);
    },
  );

  test(
    'revoking consent immediately removes correction and persisted weights',
    () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      await h.seedAcceptedModel();
      await h.controller.load();
      final personalized = h.controller.score;
      expect(personalized.deterministicEnergy, isNotNull);
      final attempt = h.saved['lastAttemptAt'];
      final revoke = h.controller.setOutcomeConsent(false);
      expect(h.controller.score.deterministicEnergy, isNull);
      expect(h.controller.score.energy, personalized.deterministicEnergy);
      expect(h.controller.score.cognitive, personalized.cognitive);
      expect(h.controller.score.confidence, personalized.confidence);
      await revoke;
      expect(h.saved['model'], isNull);
      expect(h.saved['lastAttemptAt'], attempt);
      expect(h.writer.writes, 0);
    },
  );

  for (final operation in [
    'deleteSignal',
    'editActivity',
    'editCheckIn',
    'deleteCheckIn',
  ]) {
    test(
      '$operation clears accepted weights without training or metadata writes',
      () async {
        final h = _Harness();
        addTearDown(h.controller.dispose);
        await h.seedAcceptedModel();
        await h.controller.load();
        expect(h.controller.score.deterministicEnergy, isNotNull);
        final attempt = h.saved['lastAttemptAt'];
        switch (operation) {
          case 'deleteSignal':
            await h.controller.deleteSignal(h.controller.signals.first.id);
          case 'editActivity':
            await h.controller.saveActivityLog(
              id: h.controller.signals.first.groupId,
              hydrationLiters: 3,
              timestamp: h.now,
            );
          case 'editCheckIn':
          case 'deleteCheckIn':
            const id = 'checkin-1783000000000000';
            h.controller.checkIns.add(
              DailyCheckIn(
                id: id,
                timestamp: h.now,
                energy: 7,
                mood: 6,
                stress: 4,
              ),
            );
            if (operation == 'editCheckIn') {
              await h.controller.addCheckIn(
                id: id,
                energy: 8,
                mood: 6,
                stress: 4,
                timestamp: h.now,
              );
            } else {
              await h.controller.deleteCheckIn(id);
            }
        }
        expect(h.saved['model'], isNull);
        expect(h.saved['lastAttemptAt'], attempt);
        expect(h.controller.score.deterministicEnergy, isNull);
        expect(h.writer.writes, 0);
        expect(h.source.collectionReads, 0);
      },
    );
  }
}
