import 'package:app/src/activity_sync_logic.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const uid = 'activity-user';
  final day = DateTime(2026, 9, 7);

  AppController controllerFor(MemoryCloudRepository repository) =>
      AppController(
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
      'only positive ${type.name} is saved locally and in the cloud',
      () async {
        final repository = MemoryCloudRepository(signedInUid: uid);
        final controller = controllerFor(repository);
        addTearDown(controller.dispose);

        await controller.saveActivityLog(
          id: 'activity-single',
          hydrationLiters: type == SignalType.hydration ? .25 : 0,
          studyHours: type == SignalType.study ? .25 : 0,
          exerciseHours: type == SignalType.exercise ? .25 : 0,
          screenTimeHours: type == SignalType.screenTime ? .25 : 0,
          timestamp: day,
        );

        final cloud = (await repository.readUser(uid))!;
        for (final signals in [controller.signals, cloud.signals]) {
          expect(signals, hasLength(1));
          expect(signals.single.type, type);
          expect(signals.single.value, .25);
          expect(signals.single.groupId, 'activity-single');
        }
        expect(repository.replaceUserCallCount, 1);
        expect(controller.activityLogs, hasLength(1));
      },
    );
  }

  test(
    'mixed positive, zero, and omitted fields create only positive signals',
    () async {
      final repository = MemoryCloudRepository(signedInUid: uid);
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
          unorderedEquals([SignalType.hydration, SignalType.screenTime]),
        );
        expect(signals.every((signal) => signal.value > 0), isTrue);
      }
      final restored = AppController();
      addTearDown(restored.dispose);
      await restored.load();
      expect(
        restored.signals.map((signal) => signal.toJson()),
        controller.signals.map((signal) => signal.toJson()),
      );
      expect(restored.activityLogs.single.studyHours, 0);
      expect(restored.activityLogs.single.exerciseHours, 0);
    },
  );

  test(
    'editing to zero or blank removes only that log category and restores Health fallback',
    () async {
      final repository = MemoryCloudRepository(signedInUid: uid);
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);
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
        expect(edited, hasLength(1));
        expect(edited.single.type, SignalType.study);
        expect(edited.single.value, 2);
        expect(
          signals
              .where((signal) => signal.groupId != 'activity-edited')
              .map((signal) => signal.toJson()),
          preserved.map((signal) => signal.toJson()),
        );
        for (final entry in {
          SignalType.hydration: .4,
          SignalType.exercise: 1.5,
        }.entries) {
          final total = ActivitySyncLogic.aggregateForDay(
            signals,
            type: entry.key,
            day: day,
          )!;
          expect(total.total, entry.value);
          expect(total.usesManualCorrection, isFalse);
        }
      }
      expect(repository.replaceUserCallCount, 2);
    },
  );

  test(
    'all-zero or blank submissions leave existing data and cloud writes unchanged',
    () async {
      final repository = MemoryCloudRepository(signedInUid: uid);
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
      final writesBefore = repository.replaceUserCallCount;

      await expectLater(controller.saveActivityLog(), throwsArgumentError);
      await expectLater(
        controller.saveActivityLog(
          id: 'activity-existing',
          hydrationLiters: 0,
          studyHours: 0,
          exerciseHours: 0,
          screenTimeHours: 0,
        ),
        throwsArgumentError,
      );

      expect(controller.exportJson(), before);
      expect(preferences.getString('tonyo_state_v1'), persistedBefore);
      expect(await repository.readUser(uid), same(cloudBefore));
      expect(repository.replaceUserCallCount, writesBefore);
    },
  );

  test(
    'invalid supplied values are rejected before filtering or replacing a log',
    () async {
      final repository = MemoryCloudRepository(signedInUid: uid);
      final controller = controllerFor(repository);
      addTearDown(controller.dispose);
      await controller.saveActivityLog(
        id: 'activity-existing',
        studyHours: 1,
        timestamp: day,
      );
      final before = controller.exportJson();
      final cloudBefore = (await repository.readUser(uid))!;
      final writesBefore = repository.replaceUserCallCount;

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
      expect(repository.replaceUserCallCount, writesBefore);
    },
  );
}
