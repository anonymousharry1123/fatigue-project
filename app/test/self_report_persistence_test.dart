import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/device_timezone_service.dart';
import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 5, 1);
  });

  Map<String, dynamic> definition([String language = 'en']) =>
      CheckInMeasurement.snapshot(
        language: language,
        translate: (text) => text,
      );

  AppController local({
    String? zone = 'America/Los_Angeles',
    bool consent = true,
  }) {
    final app = AppController(
      clock: () => now,
      deviceTimezoneService: DeviceTimezoneService(
        clock: () => now,
        readIdentifier: () async => zone,
      ),
      initialPrivacyConsent: consent ? testAdultPrivacyConsent : null,
    );
    addTearDown(app.dispose);
    return app;
  }

  Future<void> save(
    AppController app, {
    double? energy = 7,
    double? fatigue = 3,
  }) => app.saveSelfReportCheckIn(
    id: 'checkin-measurement',
    period: CheckInPeriod.morning,
    energy: energy,
    fatigue: fatigue,
    questionnaireLanguage: 'en',
    questionnaireSnapshot: definition(),
  );

  test(
    'late Morning and partial raw answers survive local reload in another zone',
    () async {
      final app = local();
      await app.load();
      await save(app);
      final before = app.checkIns.single;
      expect(before.localDate, '2026-10-04');
      expect(before.utcOffsetMinutes, -420);
      expect(before.timezone, 'America/Los_Angeles');
      expect(before.period, CheckInPeriod.morning);
      final restarted = local(zone: 'Asia/Shanghai', consent: false);
      await restarted.load();
      final after = restarted.checkIns.single;
      expect(after.toJson(), before.toJson());
      expect(after.sleepiness, isNull);
      expect(after.mood, isNull);
      expect(after.completionStatus, 'partial');
      expect(restarted.outcomes, isEmpty);
    },
  );

  test(
    'edits retain original observation, zone, language and exact questionnaire',
    () async {
      final app = local();
      await app.load();
      await save(app);
      final original = app.checkIns.single;
      now = now.add(const Duration(days: 1));
      final restarted = local(zone: 'Asia/Shanghai');
      await restarted.load();
      await restarted.saveSelfReportCheckIn(
        id: original.id,
        timestamp: now,
        period: CheckInPeriod.morning,
        fatigue: 8,
        questionnaireLanguage: 'zh-Hans',
        questionnaireSnapshot: definition('zh-Hans'),
      );
      final changed = restarted.checkIns.single;
      expect(changed.energy, isNull);
      expect(changed.fatigue, 8);
      expect(changed.timestamp.toUtc(), original.timestamp.toUtc());
      expect(changed.recordedAt!.toUtc(), now);
      expect(changed.localDate, original.localDate);
      expect(changed.timezone, original.timezone);
      expect(changed.questionnaireLanguage, 'en');
      expect(changed.questionnaireSnapshot, original.questionnaireSnapshot);
    },
  );

  test(
    'empty, fractional, zero and invalid metadata are rejected before persistence',
    () async {
      final app = local();
      await app.load();
      for (final value in [null, 0.0, 5.5, 11.0, double.nan, double.infinity]) {
        await expectLater(
          save(app, energy: value, fatigue: null),
          throwsArgumentError,
        );
        expect(app.checkIns, isEmpty);
      }
      await expectLater(
        app.saveSelfReportCheckIn(
          period: CheckInPeriod.evening,
          energy: 5,
          questionnaireLanguage: 'es',
          questionnaireSnapshot: definition(),
        ),
        throwsArgumentError,
      );
      expect(app.checkIns, isEmpty);
    },
  );

  test(
    'privacy and unverified guardian gates still block measurement writes',
    () async {
      final unconsented = local(consent: false);
      await expectLater(save(unconsented), throwsStateError);
      final minor = AppController(
        clock: () => now,
        initialPrivacyConsent: PrivacyConsent(
          ageBand: PrivacyAgeBand.age16to17,
          region: PrivacyRegion.us,
          acceptedAt: now,
        ),
      );
      addTearDown(minor.dispose);
      await expectLater(save(minor), throwsStateError);
      expect(minor.checkIns, isEmpty);
    },
  );

  test(
    'draft answers do not create old learning outcomes even when opted in',
    () async {
      final app = local();
      await app.load();
      await app.setOutcomeConsent(true);
      await save(app);
      expect(app.outcomeConsent, isTrue);
      expect(app.outcomes, isEmpty);
      expect(app.score.canEstimateEnergy, isFalse);
      expect(app.score.canEstimateCognitive, isFalse);
    },
  );

  test(
    'unrelated save preserves original legacy responses without new metadata',
    () async {
      final app = local();
      await app.load();
      final legacy = DailyCheckIn.fromJson({
        'id': 'original-old',
        'timestamp': '2026-07-20T08:00:00Z',
        'energy': 4,
        'mood': 3,
        'stress': 2,
      });
      app.checkIns.add(legacy);
      await save(app);
      final data = jsonDecode(app.exportJson()) as Map;
      final old = (data['checkIns'] as List).cast<Map>().singleWhere(
        (row) => row['id'] == legacy.id,
      );
      expect(old['energy'], 4);
      expect(old.containsKey('period'), isFalse);
      expect(old.containsKey('questionnaireVersion'), isFalse);
      expect(old.containsKey('localDate'), isFalse);
    },
  );

  test(
    'backup restoration preserves partial responses and does not reconstruct legacy outcomes',
    () async {
      final app = local();
      await app.load();
      await app.setOutcomeConsent(true);
      await save(app, energy: null);
      final backup = await app.exportDeviceBackup();
      final original = app.checkIns.single.toJson();
      await app.deleteCheckIn('checkin-measurement');
      final preview = app.previewDeviceBackup(backup);
      await app.restoreDeviceBackup(preview);
      expect(app.checkIns.single.toJson(), original);
      expect(app.outcomes, isEmpty);
    },
  );

  test('malformed backups cannot downgrade versioned responses', () async {
    final app = local();
    await app.load();
    await save(app);
    final backup =
        jsonDecode(await app.exportDeviceBackup()) as Map<String, dynamic>;
    final row = (backup['local']['checkIns'] as List).single as Map;
    row.remove('questionnaireVersion');
    row.addAll(<String, dynamic>{'energy': 7, 'mood': 6, 'stress': 4});
    expect(
      () => app.previewDeviceBackup(jsonEncode(backup)),
      throwsFormatException,
    );
  });

  test(
    'backup does not restore noncanonical outcomes linked to draft answers',
    () async {
      final app = local();
      await app.load();
      await app.setOutcomeConsent(true);
      await save(app);
      final backup =
          jsonDecode(await app.exportDeviceBackup()) as Map<String, dynamic>;
      backup['local']['outcomes'] = [
        OutcomeRecord(
          id: 'noncanonical-linked-outcome',
          type: OutcomeType.observedEnergy,
          value: 7,
          observedAt: now,
          recordedAt: now,
          source: OutcomeSource.checkIn,
          sourceId: 'checkin-measurement',
        ).toJson(),
      ];
      final preview = app.previewDeviceBackup(jsonEncode(backup));
      await app.restoreDeviceBackup(preview);
      expect(app.checkIns.single.energy, 7);
      expect(app.outcomes, isEmpty);
    },
  );

  test(
    'raw cloud sync saves and clears answers without restoring an old answer on reload',
    () async {
      final repo = MemoryCloudRepository(signedInUid: 'owner')
        ..seed(
          'owner',
          CloudUserState(
            profile: const UserProfile(),
            accountEmail: 'owner@example.invalid',
            onboardingComplete: false,
            notificationsEnabled: false,
            outcomeConsent: false,
            healthAuthorized: false,
            privacyConsent: testAdultPrivacyConsent,
            migrationVersion: localMigrationVersion,
            signals: const [],
            checkIns: const [],
          ),
        );
      AppController connected() {
        final app = AppController(
          cloudRepository: repo,
          accountAuth: MemoryAccountAuth(
            session: const AccountSession(
              uid: 'owner',
              email: 'owner@example.invalid',
            ),
          ),
          clock: () => now,
        );
        addTearDown(app.dispose);
        return app;
      }

      final app = connected();
      await app.load();
      await save(app);
      expect(app.cloudSyncError, isNull);
      expect((await repo.readUser('owner'))!.checkIns.single.energy, 7);
      await save(app, energy: null, fatigue: 6);
      expect(app.cloudSyncError, isNull);
      SharedPreferences.setMockInitialValues({});
      final fresh = connected();
      await fresh.load();
      expect(fresh.checkIns.single.energy, isNull);
      expect(fresh.checkIns.single.fatigue, 6);
      expect(fresh.checkIns.single.questionnaireSnapshot, definition());
      expect(repo.replaceUserCallCount, 0);
    },
  );
}
