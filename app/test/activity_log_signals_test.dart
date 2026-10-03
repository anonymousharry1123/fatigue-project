import 'dart:convert';

import 'privacy_test_support.dart';
import 'package:app/src/activity_sync_logic.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const uid = 'activity-user';
  final day = DateTime(2026, 9, 7);

  MemoryCloudRepository repositoryFor({
    List<SignalReading> signals = const [],
  }) => MemoryCloudRepository(signedInUid: uid)
    ..seed(
      uid,
      CloudUserState(
        profile: const UserProfile(),
        accountEmail: 'activity@example.com',
        onboardingComplete: false,
        notificationsEnabled: false,
        outcomeConsent: false,
        healthAuthorized: false,
        signals: signals,
        checkIns: const [],
        migrationVersion: localMigrationVersion,
        privacyConsent: testAdultPrivacyConsent,
      ),
    );

  AppController controllerFor(MemoryCloudRepository repository) =>
      AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        accountAuth: MemoryAccountAuth(
          session: const AccountSession(
            uid: uid,
            email: 'activity@example.com',
          ),
        ),
        cloudRepository: repository,
      );

  for (final type in ActivityLogEntry.allowedTypes) {
    test(
      'explicit ${type.name} is saved while omitted fields remain absent',
      () async {
        final repository = repositoryFor();
        final controller = controllerFor(repository);
        addTearDown(controller.dispose);

        await controller.saveActivityLog(
          id: 'activity-single',
          hydrationLiters: type == SignalType.hydration ? .25 : null,
          studyHours: type == SignalType.study ? .25 : null,
          exerciseHours: type == SignalType.exercise ? .25 : null,
          screenTimeHours: type == SignalType.screenTime ? .25 : null,
          timestamp: day,
        );

        final cloud = (await repository.readUser(uid))!;
        for (final signals in [controller.signals, cloud.signals]) {
          expect(signals, hasLength(1));
          expect(signals.single.type, type);
          expect(signals.single.value, .25);
          expect(signals.single.groupId, 'activity-single');
        }
        expect(repository.inputPatchCallCount, 1);
        expect(repository.replaceUserCallCount, 0);
        expect(controller.cloudSyncError, isNull);
        expect(controller.activityLogs, hasLength(1));
      },
    );
  }

  test(
    'positive and zero values survive sync and local restore while blanks stay absent',
    () async {
      final repository = repositoryFor();
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);

      await controller.saveActivityLog(
        id: 'activity-mixed',
        hydrationLiters: 1.25,
        studyHours: 0,
        screenTimeHours: .5,
        timestamp: day,
      );

      final cloud = (await repository.readUser(uid))!;
      for (final signals in [controller.signals, cloud.signals]) {
        expect(
          signals.map((signal) => signal.type),
          unorderedEquals([
            SignalType.hydration,
            SignalType.study,
            SignalType.screenTime,
          ]),
        );
        expect(
          signals
              .singleWhere((signal) => signal.type == SignalType.study)
              .value,
          0,
        );
        expect(
          signals.where((signal) => signal.type == SignalType.exercise),
          isEmpty,
        );
      }
      final restored = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
      );
      addTearDown(restored.dispose);
      await restored.load();
      expect(
        restored.signals.map((signal) => signal.toJson()),
        controller.signals.map((signal) => signal.toJson()),
      );
      expect(restored.activityLogs.single.studyHours, 0);
      expect(restored.activityLogs.single.exerciseHours, isNull);
      final exported =
          (jsonDecode(controller.exportJson())
                  as Map<String, dynamic>)['signals']
              as List;
      final exportedSignals = exported
          .map(
            (item) =>
                SignalReading.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList();
      expect(
        exportedSignals
            .singleWhere((signal) => signal.type == SignalType.study)
            .value,
        0,
      );
      expect(
        exportedSignals.where((signal) => signal.type == SignalType.exercise),
        isEmpty,
      );
    },
  );

  test(
    'zero preserves a manual override while blank restores imported fallback',
    () async {
      final preserved = [
        SignalReading(
          id: 'health-workout',
          type: SignalType.exercise,
          value: 1.5,
          source: SignalSource.healthKit,
          timestamp: day.add(const Duration(hours: 10)),
        ),
        SignalReading(
          id: 'health-water',
          type: SignalType.hydration,
          value: .4,
          source: SignalSource.healthKit,
          timestamp: day.add(const Duration(hours: 11)),
        ),
        SignalReading(
          id: 'activity-older-study',
          groupId: 'activity-older',
          type: SignalType.study,
          value: 2,
          timestamp: day.subtract(const Duration(days: 1)),
        ),
        SignalReading(
          id: 'activity-older-exercise',
          groupId: 'activity-older',
          type: SignalType.exercise,
          value: 0,
          timestamp: day.subtract(const Duration(days: 1)),
        ),
      ];
      final repository = repositoryFor(signals: preserved);
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);
      controller.signals = [...preserved];

      await controller.saveActivityLog(
        id: 'activity-edited',
        hydrationLiters: 1.25,
        exerciseHours: .75,
        screenTimeHours: 1,
        timestamp: day.add(const Duration(hours: 12)),
      );

      for (final entry in {
        SignalType.hydration: 1.25,
        SignalType.exercise: .75,
      }.entries) {
        final total = ActivitySyncLogic.aggregateForDay(
          controller.signals,
          type: entry.key,
          day: day,
        )!;
        expect(total.total, entry.value);
        expect(total.usesManualCorrection, isTrue);
      }

      await controller.saveActivityLog(
        id: 'activity-edited',
        studyHours: 2,
        exerciseHours: 0,
        screenTimeHours: 0,
        timestamp: day.add(const Duration(hours: 13)),
      );

      final cloud = (await repository.readUser(uid))!;
      for (final signals in [controller.signals, cloud.signals]) {
        final edited = signals.where(
          (signal) => signal.groupId == 'activity-edited',
        );
        expect(edited, hasLength(3));
        expect(
          edited.singleWhere((signal) => signal.type == SignalType.study).value,
          2,
        );
        expect(
          edited
              .singleWhere((signal) => signal.type == SignalType.exercise)
              .value,
          0,
        );
        expect(
          edited
              .singleWhere((signal) => signal.type == SignalType.screenTime)
              .value,
          0,
        );
        expect(
          signals
              .where((signal) => signal.groupId != 'activity-edited')
              .map((signal) => signal.toJson()),
          preserved.map((signal) => signal.toJson()),
        );
        for (final entry in {
          SignalType.hydration: .4,
          SignalType.exercise: 0.0,
        }.entries) {
          final total = ActivitySyncLogic.aggregateForDay(
            signals,
            type: entry.key,
            day: day,
          )!;
          expect(total.total, entry.value);
          expect(total.usesManualCorrection, entry.key == SignalType.exercise);
        }
      }
      expect(repository.inputPatchCallCount, 2);
      expect(repository.replaceUserCallCount, 0);
      expect(controller.cloudSyncError, isNull);
    },
  );

  test(
    'blank submission is rejected but explicit all-zero replacement is saved',
    () async {
      final repository = repositoryFor();
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);
      await controller.saveActivityLog(
        id: 'activity-existing',
        studyHours: 1,
        timestamp: day,
      );
      final before = controller.exportJson();
      final preferences = await SharedPreferences.getInstance();
      final persistedBefore = preferences.getString('tonyo_state_v1');
      final cloudBefore = (await repository.readUser(uid))!;
      final writesBefore = repository.inputPatchCallCount;

      await expectLater(controller.saveActivityLog(), throwsArgumentError);
      expect(controller.exportJson(), before);
      expect(preferences.getString('tonyo_state_v1'), persistedBefore);
      expect(await repository.readUser(uid), same(cloudBefore));
      expect(repository.inputPatchCallCount, writesBefore);
      await controller.saveActivityLog(
        id: 'activity-existing',
        hydrationLiters: 0,
        studyHours: 0,
        exerciseHours: 0,
        screenTimeHours: 0,
        timestamp: day,
      );
      final cloud = (await repository.readUser(uid))!;
      for (final signals in [controller.signals, cloud.signals]) {
        expect(signals, hasLength(4));
        expect(signals.every((signal) => signal.value == 0), isTrue);
      }
      expect(controller.activityLogs.single.exerciseHours, 0);
      expect(repository.inputPatchCallCount, writesBefore + 1);
      expect(repository.replaceUserCallCount, 0);
    },
  );

  test(
    'device backup round trip preserves explicit zero and missing categories',
    () async {
      final original = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => day.add(const Duration(hours: 12)),
      );
      addTearDown(original.dispose);
      await original.saveActivityLog(
        id: 'activity-zero-backup',
        studyHours: 0,
        exerciseHours: 0,
        timestamp: day,
      );
      final raw = await original.exportDeviceBackup();
      final restored = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => day.add(const Duration(hours: 12)),
      );
      addTearDown(restored.dispose);
      await restored.restoreDeviceBackup(restored.previewDeviceBackup(raw));
      final log = restored.activityLogs.single;
      expect(log.studyHours, 0);
      expect(log.exerciseHours, 0);
      expect(log.hydrationLiters, isNull);
      expect(log.screenTimeHours, isNull);
      expect(restored.signals, hasLength(2));
      expect(restored.signals.every((signal) => signal.value == 0), isTrue);
    },
  );

  test(
    'invalid supplied values are rejected before filtering or replacing a log',
    () async {
      final repository = repositoryFor();
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);
      await controller.saveActivityLog(
        id: 'activity-existing',
        studyHours: 1,
        timestamp: day,
      );
      final before = controller.exportJson();
      final cloudBefore = (await repository.readUser(uid))!;
      final writesBefore = repository.inputPatchCallCount;

      for (final invalid in [
        -.1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        await expectLater(
          controller.saveActivityLog(
            id: 'activity-existing',
            studyHours: 1,
            exerciseHours: invalid,
          ),
          throwsArgumentError,
        );
      }
      for (final invalid
          in <
            ({double? water, double? study, double? exercise, double? screen})
          >[
            (water: 10.1, study: null, exercise: null, screen: null),
            (water: null, study: 18.1, exercise: null, screen: null),
            (water: null, study: null, exercise: 12.1, screen: null),
            (water: null, study: null, exercise: null, screen: 24.1),
          ]) {
        await expectLater(
          controller.saveActivityLog(
            id: 'activity-existing',
            hydrationLiters: invalid.water,
            studyHours: invalid.study,
            exerciseHours: invalid.exercise,
            screenTimeHours: invalid.screen,
          ),
          throwsArgumentError,
        );
      }

      expect(controller.exportJson(), before);
      expect(await repository.readUser(uid), same(cloudBefore));
      expect(repository.inputPatchCallCount, writesBefore);
      expect(repository.replaceUserCallCount, 0);
    },
  );
}
