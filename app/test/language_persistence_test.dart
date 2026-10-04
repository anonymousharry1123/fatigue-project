import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/energy_model_repository.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Exercise the preferences plugin's durable-write result and reload behavior.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'privacy_test_support.dart';

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.empty();
  bool failStateWrites = false;
  Completer<bool>? nextStateWrite;
  Completer<void>? writeStarted;
  final completedLanguages = <String>[];

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.tonyo_state_v1') {
      final gate = nextStateWrite;
      nextStateWrite = null;
      writeStarted?.complete();
      writeStarted = null;
      if (gate != null && !await gate.future) return false;
      if (failStateWrites) return false;
      final result = await super.setValue(type, key, value);
      if (result) {
        completedLanguages.add(
          (jsonDecode(value as String)['profile'] as Map)['preferredLanguage']
              as String,
        );
      }
      return result;
    }
    return super.setValue(type, key, value);
  }
}

class _Notifications implements NotificationService {
  int mutations = 0;
  @override
  bool get supportsScheduling => true;
  @override
  Future<NotificationPermissionState> permissionStatus() async =>
      NotificationPermissionState.granted;
  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.granted;
  @override
  Future<void> cancelGuidance() async {
    mutations++;
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {
    mutations++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 4, 10);
  late _Store store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
  });

  AppController local({
    PrivacyConsent? consent,
    bool acknowledged = true,
    NotificationService? notifications,
    EnergyModelStore? modelStore,
  }) {
    final app = AppController(
      clock: () => now,
      initialPrivacyConsent: acknowledged
          ? consent ?? testAdultPrivacyConsent
          : null,
      notificationService: notifications,
      energyModelStore: modelStore,
    )..onboardingComplete = acknowledged;
    addTearDown(app.dispose);
    return app;
  }

  Future<Map<String, dynamic>?> storedState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final value = preferences.getString('tonyo_state_v1');
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  test(
    'language survives save, preference reload and a newly loaded controller',
    () async {
      final app = local();
      await app.setPreferredLanguage('zh_TW');
      expect(app.effectiveLanguage, 'zh-Hant');
      expect((await storedState())!['profile']['preferredLanguage'], 'zh-Hant');
      final restored = local(acknowledged: false);
      await restored.load();
      expect(restored.onboardingComplete, isTrue);
      expect(restored.profile.preferredLanguage, 'zh-Hant');
      expect(restored.effectiveLanguage, 'zh-Hant');
      expect(restored.privacyFeaturesAllowed, isTrue);
      expect(restored.outcomeConsent, isFalse);
    },
  );

  test(
    'device export and backup contain language while retaining raw zero and missing fields',
    () async {
      final app = local();
      await app.saveActivityLog(exerciseHours: 0);
      await app.setPreferredLanguage('es');
      final exported = jsonDecode(app.exportJson()) as Map;
      final backup = jsonDecode(await app.exportDeviceBackup()) as Map;
      expect(exported['profile']['preferredLanguage'], 'es');
      expect(backup['local']['profile']['preferredLanguage'], 'es');
      expect(backup['local']['signals'], exported['signals']);
      expect(
        (exported['signals'] as List)
            .where((row) => row['type'] == 'exercise')
            .single['value'],
        0,
      );
      expect(
        (exported['signals'] as List).where(
          (row) => row['type'] == 'hydration',
        ),
        isEmpty,
      );
      expect(backup['scope']['cloudFetched'], isFalse);
    },
  );

  test(
    'signup preview changes presentation without persisting or granting consent',
    () async {
      final app = local(acknowledged: false);
      app.previewOnboardingLanguage('es-MX');
      expect(app.effectiveLanguage, 'es');
      expect(app.profile.preferredLanguage, 'en');
      expect(app.privacyConsent, isNull);
      expect(app.privacyFeaturesAllowed, isFalse);
      expect(app.onboardingComplete, isFalse);
      expect(await storedState(), isNull);
      expect(store.completedLanguages, isEmpty);
      await expectLater(app.setPreferredLanguage('zh-Hans'), throwsStateError);
      expect(app.effectiveLanguage, 'es');
      expect(app.profile.preferredLanguage, 'en');
      expect(await storedState(), isNull);
      final restarted = local(acknowledged: false);
      await restarted.load();
      expect(restarted.effectiveLanguage, 'en');
      expect(restarted.privacyConsent, isNull);
    },
  );

  test('signed-in presentation ignores a stray onboarding preview', () async {
    final app = local();
    await app.setPreferredLanguage('es');
    app.previewOnboardingLanguage('zh-Hans');
    expect(app.effectiveLanguage, 'es');
    expect((await storedState())!['profile']['preferredLanguage'], 'es');
  });

  test(
    'missing guardian eligibility denies a saved language mutation',
    () async {
      final app = local(
        consent: PrivacyConsent(
          ageBand: PrivacyAgeBand.age16to17,
          region: PrivacyRegion.us,
          acceptedAt: now,
        ),
      );
      final before = app.exportJson();
      await expectLater(app.setPreferredLanguage('es'), throwsStateError);
      expect(app.profile.preferredLanguage, 'en');
      expect(app.exportJson(), before);
      expect(await storedState(), isNull);
    },
  );

  test(
    'signed-out preference edits cannot change the retained profile',
    () async {
      final app = local();
      await app.setPreferredLanguage('es');
      await app.signOut();
      await expectLater(app.setPreferredLanguage('zh-Hans'), throwsStateError);
      expect(app.profile.preferredLanguage, 'es');
      expect((await storedState())!['profile']['preferredLanguage'], 'es');
      expect(app.isSignedOut, isTrue);
    },
  );

  test(
    'failed local language save rolls back durable and in-memory preference',
    () async {
      final app = local();
      await app.setPreferredLanguage('es');
      store.failStateWrites = true;
      await expectLater(app.setPreferredLanguage('zh-Hans'), throwsStateError);
      expect(app.profile.preferredLanguage, 'es');
      expect(app.effectiveLanguage, 'es');
      expect((await storedState())!['profile']['preferredLanguage'], 'es');
      store.failStateWrites = false;
      final restarted = local(acknowledged: false);
      await restarted.load();
      expect(restarted.effectiveLanguage, 'es');
    },
  );

  test(
    'overlapping language saves keep the newest choice after durable reload',
    () async {
      final app = local();
      final gate = store.nextStateWrite = Completer<bool>();
      final started = store.writeStarted = Completer<void>();
      final older = app.setPreferredLanguage('es');
      await started.future;
      final newer = app.setPreferredLanguage('zh-Hant');
      // Drain the second request's microtasks before releasing the older write.
      // A serialized implementation keeps it queued; an unsafe one writes it first.
      await Future<void>.delayed(Duration.zero);
      gate.complete(true);
      await Future.wait([older, newer]);
      expect(app.profile.preferredLanguage, 'zh-Hant');
      expect(
        (await storedState())!['profile']['preferredLanguage'],
        'zh-Hant',
        reason: 'The older delayed write must never become the restart value.',
      );
      final restarted = local(acknowledged: false);
      await restarted.load();
      expect(restarted.effectiveLanguage, 'zh-Hant');
    },
  );

  test(
    'a failed older save does not poison a queued newer language choice',
    () async {
      final app = local();
      final gate = store.nextStateWrite = Completer<bool>();
      final started = store.writeStarted = Completer<void>();
      final older = app.setPreferredLanguage('es');
      final failure = expectLater(older, throwsStateError);
      await started.future;
      final newer = app.setPreferredLanguage('zh-Hant');
      await Future<void>.delayed(Duration.zero);
      gate.complete(false);
      await failure;
      await newer;
      expect(app.profile.preferredLanguage, 'zh-Hant');
      expect((await storedState())!['profile']['preferredLanguage'], 'zh-Hant');
    },
  );

  test(
    'language-only edits preserve cached scores, forecasts, raw observations and training safeguards',
    () async {
      final notifications = _Notifications();
      final models = MemoryEnergyModelStore();
      final ledger = jsonEncode({
        'owner': 'synthetic-owner',
        'model': null,
        'lastAttemptAt': now.toUtc().toIso8601String(),
        'eligibleOutcomeKeys': ['synthetic-outcome'],
      });
      models.values['synthetic-owner'] = ledger;
      final app = local(notifications: notifications, modelStore: models)
        ..signals = [
          SignalReading(
            id: 'manual-exercise-zero',
            type: SignalType.exercise,
            value: 0,
            timestamp: now,
            recordedAt: now,
          ),
        ]
        ..checkIns = [
          DailyCheckIn(
            id: 'manual-check',
            timestamp: now,
            energy: 6,
            mood: 7,
            stress: 4,
          ),
        ];
      await app.refreshScores();
      await app.refreshForecasts();
      await app.refreshGuidance();
      final beforeScore = app.score;
      final beforeForecast = app.forecastFor(now);
      expect(beforeForecast, isNotEmpty);
      final beforeScoreValues = scoreSnapshotToCloud(
        snapshot: beforeScore,
        day: now,
      );
      final beforeRaw = jsonDecode(app.exportJson()) as Map;
      final beforeRevision = app.modelPreparationRevision;
      final beforeNotifications = notifications.mutations;
      final beforePlan = app.recommendations
          .map((row) => (row.id, row.scheduledAt))
          .toList();
      await app.setPreferredLanguage('zh-Hans');
      expect(app.score, same(beforeScore));
      expect(app.forecastFor(now), same(beforeForecast));
      expect(
        scoreSnapshotToCloud(snapshot: app.score, day: now),
        beforeScoreValues,
      );
      final afterRaw = jsonDecode(app.exportJson()) as Map;
      for (final key in [
        'signals',
        'checkIns',
        'outcomes',
        'privacyConsent',
        'outcomeConsentUpdatedAt',
        'derivedRulesVersion',
      ]) {
        expect(afterRaw[key], beforeRaw[key], reason: key);
      }
      expect(app.profile.wakeHour, 7);
      expect(app.profile.bedHour, 23);
      expect(app.modelPreparationRevision, beforeRevision);
      expect(models.values['synthetic-owner'], ledger);
      expect(app.outcomeConsent, isFalse);
      expect(notifications.mutations, beforeNotifications);
      expect(
        app.recommendations.map((row) => (row.id, row.scheduledAt)).toList(),
        beforePlan,
      );
    },
  );

  test(
    'a late language write cannot recreate observations after deletion',
    () async {
      final app = local()
        ..signals = [
          SignalReading(
            id: 'synthetic-deletion-record',
            type: SignalType.exercise,
            value: 0,
            timestamp: now,
          ),
        ];
      final gate = store.nextStateWrite = Completer<bool>();
      final started = store.writeStarted = Completer<void>();
      final save = app.setPreferredLanguage('es');
      final failure = expectLater(save, throwsStateError);
      await started.future;
      final queued = app.setPreferredLanguage('zh-Hant');
      final queuedFailure = expectLater(queued, throwsStateError);
      var deletionFinished = false;
      final deletion = app.deleteAccountData().then((_) {
        deletionFinished = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(app.isDeletingAccount, isTrue);
      expect(
        deletionFinished,
        isFalse,
        reason:
            'Deletion must drain in-flight profile writes before reporting success.',
      );
      gate.complete(true);
      await failure;
      await queuedFailure;
      await deletion;
      expect(app.signals, isEmpty);
      expect(await storedState(), isNull);
      final restarted = local(acknowledged: false);
      await restarted.load();
      expect(restarted.signals, isEmpty);
      expect(restarted.privacyConsent, isNull);
      expect(restarted.onboardingComplete, isFalse);
    },
  );

  test(
    'a delayed language save cannot erase a newer raw observation on restart',
    () async {
      final app = local();
      final gate = store.nextStateWrite = Completer<bool>();
      final started = store.writeStarted = Completer<void>();
      final save = app.setPreferredLanguage('es');
      await started.future;
      final observation = app.addSignal(SignalType.exercise, 0);
      await Future<void>.delayed(Duration.zero);
      gate.complete(true);
      await Future.wait([save, observation]);
      expect(app.signals.single.value, 0);
      final persisted = (await storedState())!;
      expect(persisted['signals'], hasLength(1));
      final restarted = local(acknowledged: false);
      await restarted.load();
      expect(restarted.profile.preferredLanguage, 'es');
      expect(restarted.signals.single.type, SignalType.exercise);
      expect(restarted.signals.single.value, 0);
    },
  );
}
