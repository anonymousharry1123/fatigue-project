import 'privacy_test_support.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'new app logs preserve availability without inventing training eligibility',
    () async {
      // Isolated generated test data, never inserted into a real account.
      final zone = DateTime(2026, 7, 15).timeZoneOffset.inHours == -7
          ? 'America/Los_Angeles'
          : 'Etc/UTC';
      final window = PrepWindow.endingOn(DateTime(2026, 7, 31), timezone: zone);
      var at = window.start;
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        clock: () => at,
      )..outcomeConsent = true;
      addTearDown(controller.dispose);
      for (var day = 0; day < 14; day++) {
        at = window.start.add(Duration(days: day, hours: 9));
        await controller.saveActivityLog(
          hydrationLiters: 2,
          studyHours: 2,
          exerciseHours: 1,
          screenTimeHours: 1,
        );
        await controller.addSignal(SignalType.caffeine, 1);
        at = window.start.add(Duration(days: day, hours: 20));
        await controller.addCheckIn(energy: 7, mood: 6, stress: 4);
      }
      expect(controller.signals.every((row) => row.recordedAt != null), isTrue);
      expect(
        controller.checkIns.every((row) => row.recordedAt != null),
        isTrue,
      );
      final snapshot = PrepSnapshot(
        uid: 'isolated-test',
        window: window,
        consent: const PrepConsent(
          collection: true,
          trainingUse: true,
          version: 1,
        ),
        fetchedAt: at,
        schemaVersion: 12,
        signals: controller.signals.map((row) => row.toJson()).toList(),
        checkIns: controller.checkIns.map((row) => row.toJson()).toList(),
        outcomes: controller.outcomes.map((row) => row.toJson()).toList(),
      );
      final report = MlPrepBuilder.build(snapshot);
      expect(
        report.energyReady,
        isFalse,
        reason: '${report.toJson()['readiness']}',
      );
      // Each Energy outcome excludes its own check-in; these rows have no
      // earlier same-day mood/stress or mature heart baseline. Retired fluid,
      // exercise and caffeine slots cannot substitute for eligible inputs.
      expect(
        ((report.toJson()['readiness'] as Map)['energy'] as Map)['reasons'],
        contains('insufficient_feature_coverage'),
      );
      expect(
        report.examples.every((row) => row.features['mood'] == null),
        isTrue,
      );
      expect(
        report.examples.every((row) => row.features['hydration'] == null),
        isTrue,
      );
      expect(
        report.examples.where((row) => row.head == 'energy'),
        hasLength(14),
      );
      expect(report.cognitiveReady, isFalse);

      // A later correction keeps the observation day, but must not pretend the
      // edited value was available when those historical labels were collected.
      final firstLog = controller.activityLogs.last;
      at = window.end;
      await controller.saveActivityLog(
        id: firstLog.id,
        timestamp: firstLog.timestamp,
        hydrationLiters: 3,
      );
      final edited = controller.signals.singleWhere(
        (row) => row.groupId == firstLog.id,
      );
      expect(edited.timestamp, firstLog.timestamp);
      expect(edited.recordedAt, at);
    },
  );
}
