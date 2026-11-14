import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_capture_store.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/device_timezone_service.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _Store implements Ai1CaptureStore {
  _Store(this.now);
  final DateTime Function() now;
  final values = <String, String>{};
  Completer<void>? entered, gate;
  bool failClear = false;
  bool failWriteBeforeReplacement = false;
  bool get hasPrediction => values.values.any(
    (raw) => (jsonDecode(raw)['predictions'] as List?)?.isNotEmpty == true,
  );
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String?> read(String owner) async => values[owner];
  @override
  Future<DateTime> write(String owner, String value) async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      entered?.complete();
      await pending.future;
    }
    if (failWriteBeforeReplacement) {
      throw StateError('Native replacement failed before changing storage');
    }
    values[owner] = value;
    return now();
  }

  @override
  Future<void> clear(String owner) async {
    if (failClear) throw StateError('Storage unavailable during erasure');
    values.remove(owner);
  }

  @override
  Future<void> clearAll() async {
    values.clear();
  }
}

class _AuthorizedHealth extends HealthService {
  @override
  Future<HealthAuthorizationState> authorizationStatus() async =>
      HealthAuthorizationState.authorized;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController app;
  late DateTime now;
  late _Store store;
  DateTime at(int day, [int hour = 12]) => DateTime.utc(2026, 10, day, hour);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = at(4);
    store = _Store(() => now);
    app = AppController(
      clock: () => now,
      initialPrivacyConsent: testAdultPrivacyConsent,
      captureStore: _Store(() => now),
      sleepEnergyStore: store,
      deviceTimezoneService: DeviceTimezoneService(
        readIdentifier: () async => 'Etc/UTC',
        clock: () => now,
      ),
    );
    await app.load();
  });
  tearDown(() => app.dispose());
  Future<void> sources({bool today = true}) async {
    for (var d = 1; d <= 3; d++) {
      now = at(d, 8);
      await app.addSleep(
        bedtime: at(d, 8).subtract(Duration(hours: d + 4)).toLocal(),
        wakeTime: at(d, 8).toLocal(),
        quality: 4,
      );
      now = at(d, 20);
      await app.saveSelfReportCheckIn(
        period: CheckInPeriod.evening,
        energy: (d + 4).toDouble(),
        questionnaireLanguage: 'en',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (s) => s,
        ),
      );
    }
    now = at(4, 8);
    if (today) {
      await app.addSleep(
        bedtime: at(4, 1).toLocal(),
        wakeTime: at(4, 8).toLocal(),
        quality: 4,
      );
    }
    now = at(4);
    await app.refreshSleepEnergyExperiment();
  }

  Future<void> enableAndTrain({bool today = true}) async {
    await app.setOutcomeConsent(true);
    await sources(today: today);
    await app.trainSleepEnergyModel();
  }

  test(
    'collection stays off without consent; ordinary saves never implicitly fit or enable',
    () async {
      await sources();
      expect(app.sleepEnergyCanInspect, isFalse);
      expect(app.sleepEnergyRun, isNull);
      expect(app.sleepEnergyLoggingEnabled, isFalse);
      expect(store.hasPrediction, isFalse);
      await app.setOutcomeConsent(true);
      await app.refreshSleepEnergyExperiment();
      expect(app.sleepEnergyReadiness.pairCount, 3);
      expect(app.sleepEnergyRun, isNull);
      expect(app.sleepEnergyLoggingEnabled, isFalse);
      await expectLater(
        app.setSleepEnergyLoggingEnabled(true),
        throwsStateError,
      );
    },
  );

  test(
    'explicit fit and logging preserve normal Energy model and use durable saved inputs',
    () async {
      await enableAndTrain();
      final before = jsonDecode(await app.exportDeviceBackup()) as Map;
      expect(app.sleepEnergyRun!.fits.single.fitted, isTrue);
      expect(app.sleepEnergyLoggingEnabled, isFalse);
      await app.setSleepEnergyLoggingEnabled(true);
      expect(app.sleepEnergyProspectiveResults, hasLength(1));
      expect(
        app.sleepEnergyProspectiveResults.single.status,
        'awaiting_evening',
      );
      expect(
        app.sleepEnergyProspectiveResults.single.modelAbsoluteError,
        isNull,
      );
      expect(store.hasPrediction, isTrue);
      final ordinary = jsonDecode(await app.exportDeviceBackup()) as Map;
      expect(jsonEncode(ordinary), isNot(contains('modelPrediction')));
      // Ordinary raw evidence and legacy observed-energy outcomes stay untouched.
      expect(ordinary['checkIns'], before['checkIns']);
      expect(ordinary['outcomes'], before['outcomes']);
    },
  );

  test(
    'opening a check-in editor blocks both explicit logging and in-flight commit',
    () async {
      await enableAndTrain();
      app.beginSleepEnergyCheckInEditing();
      await app.setSleepEnergyLoggingEnabled(true);
      expect(app.sleepEnergyProspectiveResults, isEmpty);
      expect(app.sleepEnergyPredictionStatus, contains('form is open'));
      app.endSleepEnergyCheckInEditing();
      final release = Completer<void>(), entered = Completer<void>();
      store.gate = release;
      store.entered = entered;
      final recording = app.recordSleepEnergyPrediction();
      await entered.future;
      app.beginSleepEnergyCheckInEditing();
      release.complete();
      await recording;
      expect(
        app.sleepEnergyProspectiveResults.any(
          (r) => r.prediction.receiptAt != null,
        ),
        isFalse,
      );
      app.endSleepEnergyCheckInEditing();
    },
  );

  test(
    'a saved Evening target is evaluated once; later deletion cannot score another target',
    () async {
      await enableAndTrain();
      await app.setSleepEnergyLoggingEnabled(true);
      now = at(4, 20);
      app.beginSleepEnergyCheckInEditing();
      await app.saveSelfReportCheckIn(
        period: CheckInPeriod.evening,
        energy: 8,
        questionnaireLanguage: 'en',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (s) => s,
        ),
      );
      app.endSleepEnergyCheckInEditing();
      await app.refreshSleepEnergyExperiment();
      expect(app.sleepEnergyProspectiveResults.single.scored, isTrue);
      final target = app.checkIns.firstWhere(
        (r) => r.localDate == '2026-10-04',
      );
      await app.deleteCheckIn(target.id);
      await app.refreshSleepEnergyExperiment();
      expect(app.sleepEnergyProspectiveResults.single.status, 'invalidated');
      now = at(4, 21);
      await app.saveSelfReportCheckIn(
        period: CheckInPeriod.evening,
        energy: 7,
        questionnaireLanguage: 'en',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (s) => s,
        ),
      );
      await app.refreshSleepEnergyExperiment();
      expect(app.sleepEnergyProspectiveResults.single.status, 'invalidated');
    },
  );

  test(
    'revoking outcome consent erases model and predictions and does not re-enable',
    () async {
      await enableAndTrain();
      await app.setSleepEnergyLoggingEnabled(true);
      await app.setOutcomeConsent(false);
      expect(store.values, isEmpty);
      expect(app.sleepEnergyRun, isNull);
      expect(app.sleepEnergyProspectiveResults, isEmpty);
      await app.setOutcomeConsent(true);
      await app.refreshSleepEnergyExperiment();
      expect(app.sleepEnergyRun, isNull);
      expect(app.sleepEnergyLoggingEnabled, isFalse);
      expect(app.sleepEnergyReadiness.pairCount, 3);
    },
  );

  test(
    'sign-out immediately hides account experiment and blocks capture',
    () async {
      await enableAndTrain();
      await app.setSleepEnergyLoggingEnabled(true);
      await app.signOut();
      expect(app.sleepEnergyCanInspect, isFalse);
      expect(app.sleepEnergyRun, isNull);
      expect(app.sleepEnergyProspectiveResults, isEmpty);
      expect(app.sleepEnergyLoggingEnabled, isFalse);
      await expectLater(app.recordSleepEnergyPrediction(), throwsStateError);
    },
  );

  test(
    'tracking reset clears experiment and ordinary data in the same controller',
    () async {
      await enableAndTrain();
      await app.setSleepEnergyLoggingEnabled(true);
      await app.clearTrackingData();
      await app.refreshSleepEnergyExperiment();
      expect(app.sleepEnergyRun, isNull);
      expect(app.sleepEnergyProspectiveResults, isEmpty);
      expect(app.sleepEnergyReadiness.pairCount, 0);
      expect(app.sleepEnergyLoggingEnabled, isFalse);
      expect(store.values, isEmpty);
    },
  );

  test(
    'full reset clears the separate experiment store and prevents in-place resurrection',
    () async {
      await enableAndTrain();
      await app.setSleepEnergyLoggingEnabled(true);
      await app.reset();
      expect(store.values, isEmpty);
      expect(app.sleepEnergyRun, isNull);
      expect(app.sleepEnergyProspectiveResults, isEmpty);
    },
  );

  test(
    'HealthKit predictions stay blocked after Health access is disconnected',
    () async {
      await app.setOutcomeConsent(true);
      await sources();
      app.signals = [
        for (final s in app.signals) s.copyWith(source: SignalSource.healthKit),
      ];
      await app.trainSleepEnergyModel();
      expect(app.sleepEnergyRun!.fits.single.sleepSource, 'healthKit');
      expect(app.healthAuthorized, isFalse);
      await app.setSleepEnergyLoggingEnabled(true);
      expect(app.sleepEnergyProspectiveResults, isEmpty);
      expect(app.sleepEnergyPredictionStatus, contains('Health'));
    },
  );

  test(
    'failed consent erasure still durably pauses access and issuance',
    () async {
      await enableAndTrain();
      await app.setSleepEnergyLoggingEnabled(true);
      store.failClear = true;
      await expectLater(app.setOutcomeConsent(false), throwsStateError);
      expect(app.outcomeConsent, isFalse);
      expect(app.sleepEnergyCanInspect, isFalse);
      expect(app.sleepEnergyProspectiveResults, isEmpty);
      final saved = (await SharedPreferences.getInstance()).getString(
        'tonyo_state_v1',
      )!;
      expect((jsonDecode(saved) as Map)['outcomeConsent'], isFalse);
      store.failClear = false;
      await app.setOutcomeConsent(false);
      expect(store.values, isEmpty);
    },
  );

  test(
    'full reset drains an in-flight experiment write before erasing storage',
    () async {
      await enableAndTrain();
      app.beginSleepEnergyCheckInEditing();
      await app.setSleepEnergyLoggingEnabled(true);
      app.endSleepEnergyCheckInEditing();
      final release = Completer<void>(), entered = Completer<void>();
      store.gate = release;
      store.entered = entered;
      final recording = app.recordSleepEnergyPrediction();
      await entered.future;
      final resetting = app.reset();
      expect(app.sleepEnergyCanInspect, isFalse);
      release.complete();
      await Future.wait([recording, resetting]);
      expect(store.values, isEmpty);
      expect(app.sleepEnergyProspectiveResults, isEmpty);
    },
  );

  test(
    'persisted Health disconnect retires old native results after failed invalidation and restart',
    () async {
      await enableAndTrain();
      app.signals = [
        for (final s in app.signals) s.copyWith(source: SignalSource.healthKit),
      ];
      app.healthAvailable = true;
      app.healthAuthorized = true;
      app.healthAuthorization = HealthAuthorizationState.authorized;
      await app.trainSleepEnergyModel();
      await app.setSleepEnergyLoggingEnabled(true);
      now = at(4, 20);
      await app.saveSelfReportCheckIn(
        period: CheckInPeriod.evening,
        energy: 8,
        questionnaireLanguage: 'en',
        questionnaireSnapshot: CheckInMeasurement.snapshot(
          language: 'en',
          translate: (s) => s,
        ),
      );
      await app.refreshSleepEnergyExperiment();
      expect(app.sleepEnergyProspectiveResults.single.scored, isTrue);
      final beforeFailure = Map<String, String>.of(store.values);

      store.failWriteBeforeReplacement = true;
      await expectLater(app.disconnectHealth(), throwsStateError);
      expect(app.healthAuthorized, isFalse);
      expect(app.healthAuthorization, HealthAuthorizationState.revoked);
      expect(app.sleepEnergyProspectiveResults.single.scored, isFalse);
      expect(
        app.sleepEnergyProspectiveResults.single.modelAbsoluteError,
        isNull,
      );
      expect(
        store.values,
        beforeFailure,
        reason: 'The old native file survived the failed replacement.',
      );
      final ordinary =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'tonyo_state_v1',
                )!,
              )
              as Map;
      expect(ordinary['healthAuthorized'], isFalse);
      expect(ordinary['healthAuthorizationState'], 'revoked');

      app.dispose();
      store.failWriteBeforeReplacement = false;
      app = AppController(
        clock: () => now,
        initialPrivacyConsent: testAdultPrivacyConsent,
        captureStore: _Store(() => now),
        sleepEnergyStore: store,
        healthService: _AuthorizedHealth(),
        deviceTimezoneService: DeviceTimezoneService(
          readIdentifier: () async => 'Etc/UTC',
          clock: () => now,
        ),
      );
      await app.load();
      await app.refreshSleepEnergyExperiment();
      expect(app.healthAuthorization, HealthAuthorizationState.revoked);
      expect(app.sleepEnergyRun, isNull);
      expect(app.sleepEnergyLoggingEnabled, isFalse);
      expect(app.sleepEnergyProspectiveResults.single.status, 'invalidated');
      expect(
        app.sleepEnergyProspectiveResults.single.reason,
        'health_source_disconnected',
      );
      expect(
        app.sleepEnergyProspectiveResults.single.modelAbsoluteError,
        isNull,
      );
      final restored = jsonDecode(store.values.values.single) as Map;
      expect(restored['run'], isNull);
      expect(
        (restored['predictions'] as List).single['invalidationReason'],
        'health_source_disconnected',
      );
      await expectLater(app.trainSleepEnergyModel(), throwsStateError);
    },
  );

  for (final operation in ['train', 'logging', 'record']) {
    test(
      'session change during initial $operation await stops the previous action',
      () async {
        await enableAndTrain();
        app.beginSleepEnergyCheckInEditing();
        await app.setSleepEnergyLoggingEnabled(true);
        app.endSleepEnergyCheckInEditing();
        final saved = Map<String, String>.of(store.values);
        final action = switch (operation) {
          'train' => app.trainSleepEnergyModel(),
          'logging' => app.setSleepEnergyLoggingEnabled(true),
          _ => app.recordSleepEnergyPrediction(),
        };
        // Attach error handling before sign-out's first asynchronous boundary.
        final completed = action.then<Object?>(
          (_) => null,
          onError: (Object error) => error,
        );
        await app.signOut();
        final error = await completed;
        if (operation != 'record') expect(error, isA<StateError>());
        expect(store.values, saved);
        expect(app.sleepEnergyProspectiveResults, isEmpty);
        expect(app.sleepEnergyLoggingEnabled, isFalse);
      },
    );
  }
}
