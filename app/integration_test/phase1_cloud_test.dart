import 'dart:convert';
import 'dart:math';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/firebase_emulator_options.dart';
import 'package:app/src/firebase_services.dart';
import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'phase2a_measurement_fixtures.dart';
import 'phase2a_measurement_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const verifyRestart = bool.fromEnvironment('TONYO_VERIFY_PROCESS_RESTART');

  testWidgets(
    verifyRestart
        ? 'native restart preserves measurements and research tools'
        : 'native measurement entry, persistence and cloud policy',
    (tester) async {
      if (!TonyoFirebaseEmulatorOptions.enabled) {
        throw StateError(
          'Run only through the local emulator integration script.',
        );
      }
      final runtime = (await FirebaseRuntime.initialize())!;
      final app = Firebase.app(TonyoFirebaseEmulatorOptions.appName);
      final firestore = FirebaseFirestore.instanceFor(app: app);
      expect(app.options.projectId, 'demo-tonyo-privacy');
      expect(firestore.settings.host, '127.0.0.1:8080');
      expect(firestore.settings.sslEnabled, isFalse);
      expect(firestore.settings.persistenceEnabled, isFalse);
      if (verifyRestart) {
        await _verifyProcessRestart(tester, runtime, firestore);
        return;
      }
      // Generated test credentials stay in process memory and are never printed.
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final email = 'phase1-$nonce@example.invalid';
      final password = 'Test-${Random.secure().nextInt(1 << 32)}-only!';
      AppController controller() => AppController(
        accountAuth: runtime.auth,
        cloudRepository: runtime.repository,
        prepDataSource: runtime.prepSource,
        energyModelMetadataWriter: runtime.energyModelMetadataWriter,
      );
      var current = controller();
      await current.load();
      await tester.pumpWidget(TonyoApp(controller: current));
      await tester.pumpAndSettle();
      expect(current.privacyFeaturesAllowed, isFalse);
      await expectLater(
        current.completeOnboarding(
          const UserProfile(name: 'Synthetic adult'),
          email: email,
          password: password,
        ),
        throwsStateError,
      );
      // Exercise the same explicit-consent/account methods as normal onboarding;
      // no initialPrivacyConsent injection, admin write, claim or mock repository.
      await current.acceptPrivacy(
        ageBand: PrivacyAgeBand.adult,
        region: PrivacyRegion.us,
        acknowledged: true,
      );
      await current.completeOnboarding(
        const UserProfile(name: 'Synthetic adult', ageRange: '18+'),
        email: email,
        password: password,
      );
      expect(current.cloudSyncError, isNull);
      expect(current.outcomeConsent, isFalse);
      expect(current.healthAuthorized, isFalse);
      final uid = current.cloudUid!;
      final user = firestore.collection('users').doc(uid);
      const group = 'activity-phase1-explicit-zero';
      await current.saveActivityLog(id: group, exerciseHours: 0);
      await current.updateProfile(
        current.profile.copyWith(wakeHour: 9, bedHour: 22),
      );
      await current.setPreferredLanguage('es');
      expect(current.cloudSyncError, isNull);
      // The next roadmap step adds independent raw custom measurements, not
      // legacy model labels. Exercise native integer/null encoding and rules.
      final definition = CheckInMeasurement.snapshot(
        language: 'en',
        translate: (text) => text,
      );
      await current.saveSelfReportCheckIn(
        id: 'checkin-measurement-complete',
        period: CheckInPeriod.evening,
        energy: 7,
        fatigue: 3,
        sleepiness: 4,
        focus: 8,
        mood: 6,
        stress: 2,
        questionnaireLanguage: 'en',
        questionnaireSnapshot: definition,
      );
      expect(current.cloudSyncError, isNull);
      await current.saveSelfReportCheckIn(
        id: 'checkin-measurement-cleared',
        period: CheckInPeriod.morning,
        energy: 5,
        focus: 6,
        questionnaireLanguage: 'en',
        questionnaireSnapshot: definition,
      );
      expect(current.cloudSyncError, isNull);
      final observedAt = current.checkIns
          .singleWhere((row) => row.id == 'checkin-measurement-cleared')
          .timestamp;
      await current.saveSelfReportCheckIn(
        id: 'checkin-measurement-cleared',
        period: CheckInPeriod.morning,
        focus: 6,
        questionnaireLanguage: 'en',
        questionnaireSnapshot: definition,
      );
      expect(current.cloudSyncError, isNull);
      final rawMeasurement =
          (await user
                  .collection('checkIns')
                  .doc('checkin-measurement-cleared')
                  .get(const GetOptions(source: Source.server)))
              .data()!;
      expect(rawMeasurement['energy'], isNull);
      expect(rawMeasurement['focus'], 6);
      expect(rawMeasurement['answeredItemCount'], 1);
      expect(
        (rawMeasurement['timestamp'] as Timestamp).toDate().toUtc(),
        observedAt.toUtc(),
      );
      expect(current.outcomes, isEmpty);
      await exerciseMeasurementEntryUi(tester, current);
      await seedMeasurementHistory(current);
      expectMeasurementHistory(current.checkIns, current.signals);
      expectUiMeasurementState(current.checkIns);
      verifyMeasurementReadModels(current);
      // A test-only manifest preserves exact pre-restart values in a separate
      // native-preferences key before later cloud hydration. No credentials.
      final preferences = await SharedPreferences.getInstance();
      expect(
        await preferences.setString(
          _measurementManifestKey,
          jsonEncode(_measurementSnapshot(current.checkIns, current.signals)),
        ),
        isTrue,
      );
      final zeroDocument = await user
          .collection('signals')
          .doc('$group-exercise')
          .get(const GetOptions(source: Source.server));
      expect(zeroDocument.data()?['value'], 0);
      expect(
        (await user
                .collection('signals')
                .doc('$group-hydration')
                .get(const GetOptions(source: Source.server)))
            .exists,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
      current = controller();
      await current.load();
      await tester.pumpWidget(TonyoApp(controller: current));
      await tester.pumpAndSettle();
      expect(
        current.activityLogs
            .singleWhere((row) => row.id == group)
            .exerciseHours,
        0,
      );
      expect(current.profile.wakeHour, 9);
      expect(current.profile.bedHour, 22);
      expect(current.profile.preferredLanguage, 'es');
      // Clearing is a separate real cloud delete, while another field is retained.
      await current.saveActivityLog(id: group, studyHours: 1);
      expect(
        (await user
                .collection('signals')
                .doc('$group-exercise')
                .get(const GetOptions(source: Source.server)))
            .exists,
        isFalse,
      );
      expect(
        (await runtime.repository.readUser(
          uid,
        ))!.signals.where((row) => row.groupId == group).map((row) => row.type),
        [SignalType.study],
      );

      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final deterministic = ScoreSnapshot(
        energy: 72,
        cognitive: 68,
        confidence: .4,
        drivers: const [],
        day: day,
        calculatedAt: now,
        inputCount: 1,
        cognitiveInputCount: 1,
        energyModelVersion: FatigueEngine.energyModelVersion,
        cognitiveModelVersion: FatigueEngine.cognitiveModelVersion,
      );
      await runtime.repository.upsertScoreSnapshot(
        uid,
        deterministic.withEnergyCorrection(5, 'obsolete-synthetic-model'),
      );
      await runtime.repository.upsertScoreSnapshot(uid, deterministic);
      final scoreData =
          (await user
                  .collection('scoreSnapshots')
                  .doc(scoreSnapshotId(day))
                  .get(const GetOptions(source: Source.server)))
              .data()!;
      expect(scoreData.containsKey('deterministicEnergy'), isTrue);
      expect(scoreData['deterministicEnergy'], isNull);
      expect(scoreData['personalizedModelVersion'], isNull);
      final loaded = (await runtime.repository.scoreSnapshotForDay(uid, day))!;
      expect(loaded.energy, 72);
      expect(loaded.personalizedModelVersion, isNull);
      expect(loaded.energyModelVersion, FatigueEngine.energyModelVersion);

      final denied = isA<FirebaseException>().having(
        (error) => error.code,
        'code',
        'permission-denied',
      );
      await expectLater(
        user.collection('outcomes').doc('without-opt-in').set({'value': 1}),
        throwsA(denied),
      );
      // Owner export remains available with optional learning switched off.
      expect(await runtime.repository.exportUser(uid), isNotEmpty);
      await current.signOut();
      expect(current.isSignedOut, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();

      final other = await runtime.auth.register(
        email: 'other-$nonce@example.invalid',
        password: password,
      );
      await expectLater(
        user.get(const GetOptions(source: Source.server)),
        throwsA(denied),
      );
      await expectLater(
        runtime.repository.savePrivacyConsent(
          other.uid,
          PrivacyConsent(
            ageBand: PrivacyAgeBand.age16to17,
            region: PrivacyRegion.us,
            acceptedAt: DateTime.now(),
          ),
        ),
        throwsA(denied),
      );
      await runtime.auth.deleteCurrentAccount();
      final beforeRestart = controller();
      await beforeRestart.load();
      await beforeRestart.signIn(email: email, password: password);
      await beforeRestart.saveActivityLog(
        id: 'activity-phase1-restart-zero',
        exerciseHours: 0,
      );
      expect(beforeRestart.cloudSyncError, isNull);
      await _expectPersistentState();
      beforeRestart.dispose();
      // A second native process verifies persisted Auth and state. No test
      // password or token is persisted by the test itself.
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _verifyProcessRestart(
  WidgetTester tester,
  FirebaseRuntime runtime,
  FirebaseFirestore firestore,
) async {
  // Read native preferences before controller load can hydrate from Firestore.
  await _expectPersistentState();
  final session = runtime.auth.currentSession;
  expect(
    session,
    isNotNull,
    reason: 'Native emulator Auth must survive restart.',
  );
  final uid = session!.uid;
  expect(session.email, startsWith('phase1-'));
  expect(session.email, endsWith('@example.invalid'));
  final state = (await runtime.repository.readUser(uid))!;
  expect(state.profile.wakeHour, 9);
  expect(state.profile.bedHour, 22);
  expect(state.profile.preferredLanguage, 'es');
  _expectMeasurements(state.checkIns);
  expectMeasurementHistory(state.checkIns, state.signals);
  expectUiMeasurementState(state.checkIns);
  await _expectMeasurementSnapshot(state.checkIns, state.signals);
  expect(
    state.signals
        .singleWhere((row) => row.id == 'activity-phase1-restart-zero-exercise')
        .value,
    0,
  );
  expect(
    state.signals
        .where((row) => row.groupId == 'activity-phase1-explicit-zero')
        .map((row) => row.type),
    [SignalType.study],
  );
  final saved = (await runtime.repository.scoreSnapshotForDay(
    uid,
    DateTime.now(),
  ))!;
  expect(saved.deterministicEnergy, isNull);
  expect(saved.personalizedModelVersion, isNull);
  expect(saved.energyModelVersion, FatigueEngine.energyModelVersion);
  final current = AppController(
    accountAuth: runtime.auth,
    cloudRepository: runtime.repository,
    prepDataSource: runtime.prepSource,
    energyModelMetadataWriter: runtime.energyModelMetadataWriter,
  );
  await current.load();
  await tester.pumpWidget(TonyoApp(controller: current));
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: find.byType(NavigationBar), matching: find.text('Hoy')),
    findsOneWidget,
  );
  expect(
    Localizations.localeOf(
      tester.element(find.byType(NavigationBar)),
    ).languageCode,
    'es',
  );
  expect(
    current.activityLogs
        .singleWhere((row) => row.id == 'activity-phase1-restart-zero')
        .exerciseHours,
    0,
  );
  expect(current.profile.preferredLanguage, 'es');
  expect(current.profile.wakeHour, 9);
  expect(current.profile.bedHour, 22);
  expect(current.outcomeConsent, isFalse);
  expect(current.healthAuthorized, isFalse);
  _expectMeasurements(current.checkIns);
  expectMeasurementHistory(current.checkIns, current.signals);
  expectUiMeasurementState(current.checkIns);
  await _expectMeasurementSnapshot(current.checkIns, current.signals);
  verifyMeasurementReadModels(current);
  await exerciseMeasurementReviewUi(tester, current);
  await tester.pumpWidget(const SizedBox.shrink());
  current.dispose();
  // Normal owner lifecycle APIs delete only this synthetic account and data.
  await runtime.repository.deleteUserTree(uid);
  expect(
    (await firestore
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server)))
        .exists,
    isFalse,
  );
  await runtime.auth.deleteCurrentAccount();
}

Future<void> _expectPersistentState() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final raw = preferences.getString('tonyo_state_v1');
  expect(raw, isNotNull, reason: 'The native app cache must survive restart.');
  final saved = jsonDecode(raw!) as Map<String, dynamic>;
  final checkIns = (saved['checkIns'] as List)
      .map((value) => DailyCheckIn.fromJson(value as Map<String, dynamic>))
      .toList();
  _expectMeasurements(checkIns);
  expectUiMeasurementState(checkIns);
  final profile = UserProfile.fromJson(
    saved['profile'] as Map<String, dynamic>,
  );
  expect(profile.preferredLanguage, 'es');
  expect(profile.wakeHour, 9);
  expect(profile.bedHour, 22);
  final signals = (saved['signals'] as List)
      .map((value) => SignalReading.fromJson(value as Map<String, dynamic>))
      .toList();
  expectMeasurementHistory(checkIns, signals);
  await _expectMeasurementSnapshot(checkIns, signals);
  expect(
    signals
        .singleWhere((row) => row.id == 'activity-phase1-restart-zero-exercise')
        .value,
    0,
  );
  expect(
    signals
        .where((row) => row.groupId == 'activity-phase1-explicit-zero')
        .map((row) => row.type),
    [SignalType.study],
  );
}

const _measurementManifestKey = 'tonyo_acceptance_measurement_manifest_v1';

Map<String, Object?> _measurementSnapshot(
  List<DailyCheckIn> checkIns,
  List<SignalReading> signals,
) {
  final responses = checkIns.where((row) => row.isResearchCheckIn).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final sleeps =
      signals
          .where((row) => row.groupId?.startsWith('acceptance-sleep-') ?? false)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  return {
    'checkIns': responses.map((row) => row.toJson()).toList(),
    'signals': sleeps.map((row) => row.toJson()).toList(),
  };
}

Future<void> _expectMeasurementSnapshot(
  List<DailyCheckIn> checkIns,
  List<SignalReading> signals,
) async {
  final preferences = await SharedPreferences.getInstance();
  final manifest = preferences.getString(_measurementManifestKey);
  expect(manifest, isNotNull, reason: 'Initial native manifest must exist.');
  expect(
    _measurementSnapshot(checkIns, signals),
    jsonDecode(manifest!),
    reason:
        'Raw values, nulls, notes, exact times and definitions must survive.',
  );
}

void _expectMeasurements(List<DailyCheckIn> rows) {
  final complete = rows.singleWhere(
    (item) => item.id == 'checkin-measurement-complete',
  );
  expect(complete.ratings.values, [7, 3, 4, 8, 6, 2]);
  expect(complete.completionStatus, 'complete');
  expect(complete.period, CheckInPeriod.evening);
  expect(complete.questionnaireVersion, CheckInMeasurement.currentVersion);
  expect(complete.questionnaireLanguage, 'en');
  expect(complete.source, 'selfReport');
  expect(complete.localDate, isNotNull);
  expect(complete.utcOffsetMinutes, isNotNull);
  expect(complete.recordedAt, isNotNull);
  expect(
    complete.questionnaireSnapshot,
    CheckInMeasurement.snapshot(language: 'en', translate: (text) => text),
  );
  final cleared = rows.singleWhere(
    (item) => item.id == 'checkin-measurement-cleared',
  );
  expect(cleared.period, CheckInPeriod.morning);
  expect(cleared.energy, isNull);
  expect(cleared.fatigue, isNull);
  expect(cleared.mood, isNull);
  expect(cleared.focus, 6);
  expect(cleared.completionStatus, 'partial');
}
