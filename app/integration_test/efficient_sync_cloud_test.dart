import 'dart:convert';
import 'dart:math';

import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/firebase_emulator_options.dart';
import 'package:app/src/firebase_services.dart';
import 'package:app/src/heart_rate_cloud.dart';
import 'package:app/src/heart_rate_summary.dart';
import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:app/src/raw_heart_rate_store.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _manifestKey = 'tonyo_native_efficient_sync_manifest_v1';
const _writerId = 'native-integration-writer';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const restart = bool.fromEnvironment('TONYO_VERIFY_PROCESS_RESTART');
  testWidgets(
    restart
        ? 'native restart replays tracked edits and retains acknowledged heart summaries'
        : 'native input transactions and heart summaries obey the deployed emulator rules',
    (tester) async {
      if (!TonyoFirebaseEmulatorOptions.enabled) {
        throw StateError('Use the guarded local emulator integration runner.');
      }
      final runtime = (await FirebaseRuntime.initialize())!;
      final app = Firebase.app(TonyoFirebaseEmulatorOptions.appName);
      final firestore = FirebaseFirestore.instanceFor(app: app);
      expect(app.options.projectId, 'demo-tonyo-privacy');
      expect(firestore.settings.host, '127.0.0.1:8080');
      expect(firestore.settings.sslEnabled, isFalse);
      expect(firestore.settings.persistenceEnabled, isFalse);
      final repository = runtime.repository as FirestoreCloudRepository;
      final heartStore = FirestoreHeartRateCloudStore(
        firestore: firestore,
        auth: runtime.auth,
      );
      final preferences = await SharedPreferences.getInstance();
      if (restart) {
        final manifest =
            jsonDecode(preferences.getString(_manifestKey)!)
                as Map<String, dynamic>;
        final uid = manifest['uid'] as String;
        expect(runtime.auth.currentSession?.uid, uid);
        final rawStore = SqliteRawHeartRateStore();
        expect(await rawStore.hasSnapshot(uid), isTrue);
        expect(
          (await rawStore.load(uid)).map((row) => row.toJson()),
          unorderedEquals(manifest['raw'] as List),
        );
        expect(await rawStore.hasSnapshot('$uid-empty'), isTrue);
        expect(await rawStore.load('$uid-empty'), isEmpty);
        expect(await rawStore.hasSnapshot('$uid-other'), isFalse);
        final provenance = await rawStore.loadProvenance(uid);
        expect(provenance, hasLength(2));
        expect(
          provenance.values.every((value) => value.offsetMinutes == 0),
          isTrue,
        );
        expect(
          provenance.values.every((value) => value.timezoneName == 'Etc/UTC'),
          isTrue,
        );
        final state = await repository.readUserSince(
          uid,
          baseline: InputSyncSnapshot.fromJson(
            Map<String, dynamic>.from(manifest['baseline'] as Map),
          ),
          revision: manifest['revision'] as int,
        );
        expect(state, isNotNull);
        expect(state!.heartRateStorageVersion, 1);
        expect(
          syncCanonical(InputSyncSnapshot.fromState(state).toJson()),
          manifest['expected'],
        );
        final days = await heartStore.readDays(uid);
        expect(days, hasLength(1));
        expect(days.single.summary.toJson(), manifest['summary']);
        final duplicate = await heartStore.saveDay(
          uid,
          writerId: _writerId,
          summary: days.single.summary,
          expectedDigest: days.single.summary.contentDigest,
        );
        expect(duplicate.changed, isFalse);
        await repository.deleteUserTree(uid);
        await runtime.auth.deleteCurrentAccount();
        await rawStore.clear(uid);
        await rawStore.clear('$uid-empty');
        expect(await rawStore.hasSnapshot(uid), isFalse);
        await rawStore.close();
        await preferences.remove(_manifestKey);
        return;
      }

      final nonce = DateTime.now().microsecondsSinceEpoch;
      final session = await runtime.auth.register(
        email: 'sync-$nonce@example.invalid',
        password: 'Test-${Random.secure().nextInt(1 << 32)}-only!',
      );
      final uid = session.uid;
      await repository.savePrivacyConsent(
        uid,
        PrivacyConsent(
          ageBand: PrivacyAgeBand.adult,
          region: PrivacyRegion.us,
          acceptedAt: DateTime.now().toUtc(),
        ),
      );
      await repository.activateInputSync(uid);
      final empty = (await repository.readUser(uid))!;
      expect(empty.inputSyncVersion, 1);
      expect(empty.inputRevision, 0);
      final now = DateTime.now().toUtc();
      final sampleAt = DateTime.utc(
        now.year,
        now.month,
        now.day,
        9,
        0,
        0,
        12,
        345,
      );
      final raw = [
        for (var i = 0; i < 2; i++)
          SignalReading(
            id: 'healthkit-native-heart-$i',
            type: SignalType.heartRate,
            value: 60 + i.toDouble(),
            timestamp: sampleAt.add(Duration(minutes: i)),
            source: SignalSource.healthKit,
            syncedAt: now,
          ),
      ];
      final initialSignals = [
        ...raw,
        SignalReading(
          id: 'healthkit-native-hrv',
          type: SignalType.hrv,
          value: 55,
          timestamp: sampleAt,
          source: SignalSource.healthKit,
          syncedAt: now,
        ),
        for (var i = 0; i < 13; i++)
          SignalReading(
            id: 'manual-native-study-$i',
            type: SignalType.study,
            value: 1,
            timestamp: now.subtract(Duration(minutes: i + 1)),
            recordedAt: now,
          ),
      ];
      final definition = CheckInMeasurement.snapshot(
        language: 'en',
        translate: (text) => text,
      );
      final checkIn = DailyCheckIn(
        id: 'checkin-native-six-answers',
        timestamp: now.subtract(const Duration(hours: 1)),
        recordedAt: now,
        energy: 7,
        fatigue: 3,
        sleepiness: 4,
        focus: 8,
        mood: 6,
        stress: 2,
        period: CheckInPeriod.evening,
        note: 'Synthetic local integration only',
        localDate: now
            .subtract(const Duration(hours: 1))
            .toIso8601String()
            .substring(0, 10),
        timezone: 'Etc/UTC',
        utcOffsetMinutes: 0,
        questionnaireVersion: CheckInMeasurement.currentVersion,
        questionnaireLanguage: 'en',
        source: 'selfReport',
        questionnaireSnapshot: definition,
      );
      final seeded = _withInputs(
        empty,
        signals: initialSignals,
        checkIns: [checkIn],
      );
      await repository.applyInputPatch(
        uid,
        InputSyncPatch(
          InputSyncSnapshot.fromState(empty),
          InputSyncSnapshot.fromState(seeded),
        ),
      );
      final baseline = (await repository.readUser(uid))!;
      expect(baseline.signals, hasLength(16));
      expect(baseline.checkIns.single.energy, 7);
      expect(
        baseline.inputRevision,
        2,
        reason: '16 signals and one check-in use two atomic chunks',
      );

      final legacySummary = HeartRateSummary.build(raw).single;
      final summary = HeartRateSummary.build(initialSignals).single;
      expect(summary.toJson()['schemaVersion'], 2);
      expect(summary.cardiacContext!.hrv!.mean, 55);
      expect(summary.rawContentDigest, legacySummary.contentDigest);
      // Exercise the actual registered sqflite platform channel and default
      // device path before allowing the acknowledged cloud cleanup below.
      final rawStore = SqliteRawHeartRateStore();
      expect(await rawStore.hasSnapshot(uid), isFalse);
      await rawStore.replace(
        uid,
        raw,
        provenance: {
          for (final row in raw)
            row.id: const HeartRateSampleProvenance(
              offsetMinutes: 0,
              timezoneName: 'Etc/UTC',
            ),
        },
      );
      await rawStore.replace('$uid-empty', []);
      expect(
        (await rawStore.load(uid)).map((row) => row.toJson()),
        unorderedEquals(raw.map((row) => row.toJson())),
      );
      await rawStore.close();
      await heartStore.saveDay(
        uid,
        writerId: _writerId,
        summary: legacySummary,
      );
      final ack = await heartStore.saveDay(
        uid,
        writerId: _writerId,
        summary: summary,
        expectedDigest: legacySummary.contentDigest,
      );
      expect(ack.changed, isTrue);
      expect(ack.summary.sampleCount, 2);
      expect(ack.summary.latestValue, 61);
      expect(
        (await heartStore.readDays(uid)).single.summary.toJson(),
        summary.toJson(),
      );
      final cleared = DailyCheckIn.fromJson({
        ...checkIn.toJson(),
        'energy': null,
        'answeredItemCount': 5,
        'completionStatus': 'partial',
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      });
      final revised = _withInputs(
        baseline,
        signals: [
          for (final row in baseline.signals.where(
            (row) => !isRawHeartRate(row),
          ))
            row.id == 'manual-native-study-0'
                ? row.copyWith(
                    value: 3,
                    timestamp: now.subtract(const Duration(days: 60)),
                  )
                : row,
        ],
        checkIns: [cleared],
      );
      await repository.applyInputPatch(
        uid,
        InputSyncPatch(
          InputSyncSnapshot.fromState(baseline),
          InputSyncSnapshot.fromState(revised),
        ),
      );
      final freshRepository = FirestoreCloudRepository(
        firestore: firestore,
        auth: runtime.auth,
      );
      final incremental = (await freshRepository.readUserSince(
        uid,
        baseline: InputSyncSnapshot.fromState(baseline),
        revision: baseline.inputRevision!,
      ))!;
      expect(incremental.signals.where(isRawHeartRate), isEmpty);
      expect(
        incremental.signals
            .singleWhere((row) => row.id == 'manual-native-study-0')
            .value,
        3,
      );
      expect(incremental.checkIns.single.energy, isNull);
      expect(incremental.checkIns.single.focus, 8);
      expect(incremental.checkIns.single.questionnaireSnapshot, definition);
      final sourceCheck =
          (await firestore
                  .collection('users')
                  .doc(uid)
                  .collection('checkIns')
                  .doc(checkIn.id)
                  .get(const GetOptions(source: Source.server)))
              .data()!;
      expect(sourceCheck['energy'], isNull);
      expect(sourceCheck['answeredItemCount'], 5);
      final feedCheck =
          (await firestore
                  .collection('users')
                  .doc(uid)
                  .collection('inputChanges')
                  .doc('checkIns__${checkIn.id}')
                  .get(const GetOptions(source: Source.server)))
              .data()!;
      expect((feedCheck['after'] as Map)['energy'], isNull);
      await freshRepository.finishHeartRateMigration(uid);
      final finalState = (await freshRepository.readUser(uid))!;
      expect(finalState.heartRateStorageVersion, 1);
      await expectLater(
        freshRepository.applyInputPatch(
          uid,
          InputSyncPatch(
            InputSyncSnapshot.fromState(finalState),
            InputSyncSnapshot.fromState(
              finalState.copyWith(signals: [...finalState.signals, raw.first]),
            ),
          ),
        ),
        throwsA(
          isA<FirebaseException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      expect(
        await preferences.setString(
          _manifestKey,
          jsonEncode({
            'uid': uid,
            'baseline': InputSyncSnapshot.fromState(baseline).toJson(),
            'revision': baseline.inputRevision,
            'expected': syncCanonical(
              InputSyncSnapshot.fromState(finalState).toJson(),
            ),
            'summary': summary.toJson(),
            'raw': raw.map((row) => row.toJson()).toList(),
          }),
        ),
        isTrue,
      );
    },
  );
}

CloudUserState _withInputs(
  CloudUserState state, {
  required List<SignalReading> signals,
  required List<DailyCheckIn> checkIns,
}) => InputSyncSnapshot(
  root: InputSyncSnapshot.fromState(state).root,
  signals: {
    for (final row in signals)
      row.id: Map<String, dynamic>.from(signalToCloud(row)),
  },
  checkIns: {
    for (final row in checkIns)
      row.id: Map<String, dynamic>.from(checkInToCloud(row)),
  },
).toState(state);
