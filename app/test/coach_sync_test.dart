import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/models.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _CoachRepository extends MemoryCloudRepository {
  _CoachRepository() : super(signedInUid: 'owner');
  Object? actionFailure;
  bool failDerived = false;
  bool failInputs = false;
  Object? inputFailure;
  bool failOutcomes = false;
  int actionAttempts = 0;
  int derivedAttempts = 0;
  Completer<void>? actionGate;
  Completer<void>? actionStarted;
  Completer<void>? readGate;
  Completer<void>? readStarted;
  Completer<void>? derivedGate;
  Completer<void>? derivedStarted;
  Completer<void>? privacyGate;
  Completer<void>? privacyStarted;

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) async {
    final result = await super.readAccountPrivacy(uid);
    final gate = privacyGate;
    privacyGate = null;
    privacyStarted?.complete();
    privacyStarted = null;
    if (gate != null) await gate.future;
    return result;
  }

  @override
  Future<void> applyRecommendationAction(
    String uid,
    Recommendation record, {
    RecommendationStatus? status,
    bool? helpful,
  }) async {
    actionAttempts++;
    final gate = actionGate;
    actionGate = null;
    actionStarted?.complete();
    actionStarted = null;
    if (gate != null) await gate.future;
    if (actionFailure != null) throw actionFailure!;
    await super.applyRecommendationAction(
      uid,
      record,
      status: status,
      helpful: helpful,
    );
  }

  @override
  Future<void> applyRiskAlertDismissal(String uid, RiskAlert record) async {
    actionAttempts++;
    if (actionFailure != null) throw actionFailure!;
    await super.applyRiskAlertDismissal(uid, record);
  }

  @override
  Future<void> replaceRecommendationsForDay(
    String uid, {
    required DateTime day,
    required List<Recommendation> recommendations,
  }) async {
    derivedAttempts++;
    final gate = derivedGate;
    derivedGate = null;
    derivedStarted?.complete();
    derivedStarted = null;
    if (gate != null) await gate.future;
    if (failDerived) throw StateError('Offline');
    await super.replaceRecommendationsForDay(
      uid,
      day: day,
      recommendations: recommendations,
    );
  }

  @override
  Future<List<Recommendation>> recommendationsForDay(
    String uid,
    DateTime day,
  ) async {
    final result = await super.recommendationsForDay(uid, day);
    final gate = readGate;
    readGate = null;
    readStarted?.complete();
    readStarted = null;
    if (gate != null) await gate.future;
    return result;
  }

  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    if (inputFailure != null) throw inputFailure!;
    if (failInputs) throw StateError('Offline');
    await super.applyInputPatch(uid, patch);
  }

  @override
  Future<void> upsertOutcome(String uid, OutcomeRecord outcome) async {
    if (failOutcomes) throw StateError('Offline');
    await super.upsertOutcome(uid, outcome);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 19, 12);
  late _CoachRepository repository;
  late MemoryAccountAuth auth;

  CloudUserState state({
    String email = 'owner@example.com',
    bool onboarding = true,
  }) => CloudUserState(
    privacyConsent: testAdultPrivacyConsent,
    profile: const UserProfile(),
    accountEmail: email,
    onboardingComplete: onboarding,
    notificationsEnabled: false,
    notificationPrefsVersion: notificationPreferencesVersion,
    outcomeConsent: true,
    outcomeConsentUpdatedAt: DateTime.utc(2026, 9, 1),
    healthAuthorized: false,
    migrationVersion: localMigrationVersion,
    signals: const [],
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
  );

  Future<AppController> load() async {
    final controller = AppController(
      accountAuth: auth,
      cloudRepository: repository,
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  Future<Recommendation> remote(String id, {String uid = 'owner'}) async =>
      (await repository.recommendationsForDay(
        uid,
        now,
      )).singleWhere((item) => item.id == id);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = _CoachRepository()..seed('owner', state());
    auth = MemoryAccountAuth(
      session: const AccountSession(uid: 'owner', email: 'owner@example.com'),
    );
  });

  test(
    'status, feedback and dismissal survive cloud refresh, restart, and one retry',
    () async {
      final first = await load();
      final id = first.recommendations.first.id;
      final alertId = first.alerts.first.id;
      repository.actionFailure = StateError('Offline');
      await first.setRecommendationStatus(id, RecommendationStatus.completed);
      await first.setRecommendationFeedback(id, false);
      await first.dismissRiskAlert(alertId);
      expect(first.hasPendingCoachChanges, isTrue);
      expect(first.pendingCloudRecordCount, 2);
      await first.refreshGuidance();
      expect(
        first.recommendations.singleWhere((item) => item.id == id).status,
        RecommendationStatus.completed,
      );
      expect(
        first.recommendations.singleWhere((item) => item.id == id).helpful,
        isFalse,
      );
      expect(first.alerts.any((item) => item.id == alertId), isFalse);
      expect((await remote(id)).status, RecommendationStatus.suggested);

      final cache =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'tonyo_state_v1',
                )!,
              )
              as Map;
      expect((cache['coachSync'] as Map)['uid'], 'owner');
      final restarted = await load();
      expect(restarted.hasPendingCoachChanges, isTrue);
      expect(
        restarted.recommendations.singleWhere((item) => item.id == id).status,
        RecommendationStatus.completed,
      );
      expect(
        restarted.recommendations.singleWhere((item) => item.id == id).helpful,
        isFalse,
      );
      repository.actionFailure = null;
      await restarted.retryCloudSync();
      expect((await remote(id)).status, RecommendationStatus.completed);
      expect((await remote(id)).helpful, isFalse);
      expect(
        (await repository.riskAlertsForDay(
          'owner',
          now,
        )).singleWhere((item) => item.id == alertId).dismissed,
        isTrue,
      );
      expect(restarted.hasAnyPendingCloudChanges, isFalse);
      expect(restarted.pendingCloudRecordCount, 0);
      expect(restarted.lastCloudSyncAt, now);
      expect(restarted.cloudSyncError, isNull);
      final attempts = repository.actionAttempts;
      await restarted.retryCloudSync();
      expect(repository.actionAttempts, attempts);
      final again = await load();
      expect(again.lastCloudSyncAt, now);
    },
  );

  test(
    'offline-generated records are created with payload and existing unrelated fields are kept',
    () async {
      repository.failDerived = true;
      final controller = await load();
      final id = controller.recommendations.first.id;
      expect(await repository.recommendationsForDay('owner', now), isEmpty);
      repository.actionFailure = StateError('Offline');
      await controller.setRecommendationStatus(
        id,
        RecommendationStatus.completed,
      );
      repository.actionFailure = null;
      await controller.syncPendingChanges();
      final created = await remote(id);
      expect(created.title, controller.recommendations.first.title);
      expect(created.day, isNotNull);
      expect(created.status, RecommendationStatus.completed);
      await repository.setRecommendationFeedback('owner', id, helpful: true);
      await controller.setRecommendationStatus(
        id,
        RecommendationStatus.accepted,
      );
      expect((await remote(id)).helpful, isTrue);
      expect((await remote(id)).status, RecommendationStatus.accepted);
    },
  );

  test('a newer action survives acknowledgement of an older upload', () async {
    final controller = await load();
    final id = controller.recommendations.first.id;
    final gate = repository.actionGate = Completer<void>();
    final started = repository.actionStarted = Completer<void>();
    final first = controller.setRecommendationStatus(
      id,
      RecommendationStatus.accepted,
    );
    await started.future;
    final second = controller.setRecommendationStatus(
      id,
      RecommendationStatus.completed,
    );
    gate.complete();
    await Future.wait([first, second]);
    expect((await remote(id)).status, RecommendationStatus.completed);
    expect(controller.hasPendingCoachChanges, isFalse);
  });

  test('a stale guidance read cannot undo a completed action', () async {
    final controller = await load();
    final id = controller.recommendations.first.id;
    final gate = repository.readGate = Completer<void>();
    final started = repository.readStarted = Completer<void>();
    final refresh = controller.refreshGuidance();
    await started.future;
    await controller.setRecommendationStatus(
      id,
      RecommendationStatus.completed,
    );
    gate.complete();
    await refresh;
    expect(
      controller.recommendations.first.status,
      RecommendationStatus.completed,
    );
    expect((await remote(id)).status, RecommendationStatus.completed);
    expect(controller.isGuidanceLoading, isFalse);
  });

  test(
    'an issued plan replacement finishes before a newer action is sent',
    () async {
      final controller = await load();
      final id = controller.recommendations.first.id;
      final gate = repository.derivedGate = Completer<void>();
      final started = repository.derivedStarted = Completer<void>();
      final refresh = controller.refreshGuidance();
      await started.future;
      final action = controller.setRecommendationStatus(
        id,
        RecommendationStatus.completed,
      );
      gate.complete();
      await Future.wait([refresh, action]);
      expect((await remote(id)).status, RecommendationStatus.completed);
      expect(
        controller.recommendations.first.status,
        RecommendationStatus.completed,
      );
    },
  );

  test(
    'another account never inherits pending Coach actions or last upload time',
    () async {
      final controller = await load();
      final id = controller.recommendations.first.id;
      await controller.setRecommendationStatus(
        id,
        RecommendationStatus.accepted,
      );
      repository.actionFailure = StateError('Offline');
      await controller.setRecommendationStatus(
        id,
        RecommendationStatus.completed,
      );
      final attempts = repository.actionAttempts;
      repository.signedInUid = 'other';
      repository.seed('other', state(email: 'other@example.com'));
      auth.session = const AccountSession(
        uid: 'other',
        email: 'other@example.com',
      );
      repository.actionFailure = null;
      final other = await load();
      expect(other.hasPendingCoachChanges, isFalse);
      expect(repository.actionAttempts, attempts);
      expect(
        other.recommendations.first.status,
        RecommendationStatus.suggested,
      );
      expect(other.lastCloudSyncAt, isNull);
    },
  );

  test(
    'late failure after sign-out cannot change the next visible sync status',
    () async {
      final controller = await load();
      final gate = repository.actionGate = Completer<void>();
      final started = repository.actionStarted = Completer<void>();
      final action = controller.setRecommendationStatus(
        controller.recommendations.first.id,
        RecommendationStatus.completed,
      );
      final stopped = expectLater(action, throwsStateError);
      await started.future;
      await controller.signOut();
      gate.completeError(StateError('Offline'));
      await stopped;
      expect(controller.cloudSyncError, isNull);
      expect(controller.isSignedOut, isTrue);
    },
  );

  test(
    'clear tracking waits for action completion before deleting its record',
    () async {
      final controller = await load();
      final id = controller.recommendations.first.id;
      final gate = repository.actionGate = Completer<void>();
      final started = repository.actionStarted = Completer<void>();
      final action = controller.setRecommendationStatus(
        id,
        RecommendationStatus.completed,
      );
      await started.future;
      final clear = controller.clearTrackingData();
      gate.complete();
      await Future.wait([action, clear]);
      expect(controller.hasPendingCoachChanges, isFalse);
      expect(
        (await repository.recommendationsForDay('owner', now)).any(
          (item) =>
              item.id == id && item.status == RecommendationStatus.completed,
        ),
        isFalse,
      );
    },
  );

  test(
    'pending count includes one profile, outcome and Coach record',
    () async {
      final controller = await load();
      repository.failInputs = true;
      repository.failOutcomes = true;
      repository.actionFailure = StateError('Offline');
      await controller.updateProfile(
        controller.profile.copyWith(name: 'New name'),
      );
      await controller.recordObservedEnergy(7, observedAt: now);
      await controller.setRecommendationStatus(
        controller.recommendations.first.id,
        RecommendationStatus.completed,
      );
      expect(controller.pendingCloudRecordCount, 3);
      expect(controller.cloudSyncFailureKind, CloudSyncFailureKind.connection);
      expect(controller.cloudSyncStatusMessage, contains('connection'));
    },
  );

  test(
    'a Coach network failure cannot hide an unresolved input conflict',
    () async {
      final controller = await load();
      repository.inputFailure = const InputSyncConflict('profile');
      await controller.updateProfile(
        controller.profile.copyWith(name: 'Edited'),
      );
      expect(controller.cloudSyncConflict, isTrue);
      repository.actionFailure = StateError('Offline');
      await controller.setRecommendationStatus(
        controller.recommendations.first.id,
        RecommendationStatus.completed,
      );
      expect(controller.cloudSyncConflict, isTrue);
      expect(controller.cloudSyncFailureKind, CloudSyncFailureKind.conflict);
      expect(controller.cloudSyncStatusMessage, contains('other device'));
      expect(controller.hasPendingCoachChanges, isTrue);
    },
  );

  test(
    'pending Coach backup restores absent records offline and replays idempotently',
    () async {
      final source = await load();
      final id = source.recommendations.first.id;
      final alertId = source.alerts.first.id;
      repository.actionFailure = StateError('Offline');
      await source.setRecommendationStatus(id, RecommendationStatus.completed);
      await source.setRecommendationFeedback(id, false);
      await source.dismissRiskAlert(alertId);
      final backup = await source.exportDeviceBackup();
      final exported = jsonDecode(backup) as Map;
      expect(exported['sync']['pendingCoach'], true);
      expect(
        exported['local']['coachSync']['recommendations'][id]['status'],
        'completed',
      );
      expect(
        exported['local']['coachSync']['recommendations'][id]['helpful'],
        false,
      );
      expect(
        exported['local']['coachSync']['alerts'][alertId]['dismissed'],
        true,
      );

      SharedPreferences.setMockInitialValues({});
      await repository.clearGuidance('owner');
      repository.seed('owner', state(onboarding: false));
      final restored = await load();
      expect(restored.recommendations, isEmpty);
      final preview = restored.previewDeviceBackup(backup);
      expect(preview.coachCount, 2);
      expect(preview.newRecords, 2);
      await restored.restoreDeviceBackup(preview);
      expect(restored.hasPendingCoachChanges, isTrue);
      expect(restored.pendingCloudRecordCount, 2);
      expect(await repository.recommendationsForDay('owner', now), isEmpty);
      expect(await repository.riskAlertsForDay('owner', now), isEmpty);
      final persisted =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'tonyo_state_v1',
                )!,
              )
              as Map;
      expect(
        persisted['coachSync']['recommendations'][id]['status'],
        'completed',
      );
      expect(persisted['coachSync']['alerts'][alertId]['dismissed'], true);

      final restarted = await load();
      expect(restarted.hasPendingCoachChanges, isTrue);
      repository.actionFailure = null;
      await restarted.retryCloudSync();
      expect((await remote(id)).status, RecommendationStatus.completed);
      expect((await remote(id)).helpful, false);
      expect(
        (await repository.riskAlertsForDay('owner', now)).single.dismissed,
        true,
      );
      expect(restarted.hasAnyPendingCloudChanges, false);
      final attempts = repository.actionAttempts;
      final replay = restarted.previewDeviceBackup(backup);
      expect(replay.newRecords, 0);
      expect(replay.differingRecords, 0);
      await restarted.restoreDeviceBackup(replay, replaceExisting: true);
      expect(repository.actionAttempts, attempts);
      expect(
        await repository.recommendationsForDay('owner', now),
        hasLength(1),
      );
      expect(await repository.riskAlertsForDay('owner', now), hasLength(1));
    },
  );

  test(
    'backup keeps an entire differing Coach record until replacement is selected',
    () async {
      final source = await load();
      final id = source.recommendations.first.id;
      final alertId = source.alerts.first.id;
      repository.actionFailure = StateError('Offline');
      await source.setRecommendationStatus(id, RecommendationStatus.completed);
      await source.setRecommendationFeedback(id, false);
      await source.dismissRiskAlert(alertId);
      final file =
          jsonDecode(await source.exportDeviceBackup()) as Map<String, dynamic>;
      // A genuine new input forces the merge path even when Coach records differ.
      file['local']['signals'] = [
        SignalReading(
          id: 'backup-only',
          type: SignalType.hydration,
          value: 1,
          timestamp: now,
          recordedAt: now,
        ).toJson(),
      ];
      final backup = jsonEncode(file);

      SharedPreferences.setMockInitialValues({});
      repository.actionFailure = null;
      final destination = await load();
      await destination.setRecommendationStatus(
        id,
        RecommendationStatus.accepted,
      );
      final preview = destination.previewDeviceBackup(backup);
      expect(preview.newRecords, 1);
      expect(preview.differingRecords, 2);
      expect(preview.coachCount, 2);
      await destination.restoreDeviceBackup(preview);
      expect(destination.signals.single.id, 'backup-only');
      expect((await remote(id)).status, RecommendationStatus.accepted);
      expect((await remote(id)).helpful, isNull);
      expect(
        destination.recommendations
            .singleWhere((record) => record.id == id)
            .helpful,
        isNull,
      );
      expect(destination.alerts.any((record) => record.id == alertId), isTrue);
      expect(
        (await repository.riskAlertsForDay(
          'owner',
          now,
        )).singleWhere((record) => record.id == alertId).dismissed,
        false,
      );

      final replace = destination.previewDeviceBackup(backup);
      expect(replace.differingRecords, 2);
      await destination.restoreDeviceBackup(replace, replaceExisting: true);
      expect((await remote(id)).status, RecommendationStatus.completed);
      expect((await remote(id)).helpful, false);
      expect(destination.alerts.any((record) => record.id == alertId), isFalse);
      expect(destination.hasPendingCoachChanges, false);
    },
  );

  test(
    'backup preview explicitly counts unsupported legacy Coach actions as skipped',
    () async {
      final controller = await load();
      final file =
          jsonDecode(await controller.exportDeviceBackup())
              as Map<String, dynamic>;
      final local = file['local'] as Map;
      local.remove('coachSync');
      local['recommendationStatuses'] = {'retired-plan': 'completed'};
      local['recommendationFeedback'] = {'retired-plan': true};
      local['dismissedRiskAlertIds'] = ['retired-alert'];
      final preview = controller.previewDeviceBackup(jsonEncode(file));
      expect(preview.skippedCoachActions, 2);
      expect(preview.coachCount, 0);
      expect(preview.newRecords, 0);
      expect(preview.differingRecords, 0);
      final attempts = repository.actionAttempts;
      await controller.restoreDeviceBackup(preview, replaceExisting: true);
      expect(repository.actionAttempts, attempts);
      expect(controller.hasPendingCoachChanges, false);
      final exported = jsonDecode(await controller.exportDeviceBackup()) as Map;
      expect(
        exported['local']['recommendationStatuses'].containsKey('retired-plan'),
        false,
      );
      expect(
        exported['local']['recommendationFeedback'].containsKey('retired-plan'),
        false,
      );
      expect(
        exported['local']['dismissedRiskAlertIds'],
        isNot(contains('retired-alert')),
      );
    },
  );

  Future<Map<String, dynamic>> coachBackup(AppController controller) async {
    final backup =
        jsonDecode(await controller.exportDeviceBackup())
            as Map<String, dynamic>;
    final recommendation = controller.recommendations.first;
    final alert = controller.alerts.first;
    backup['local']['coachSync'] = {
      'version': 1,
      'uid': 'owner',
      'recommendations': {
        recommendation.id: {
          'record': syncCanonical(recommendationToCloud(recommendation)),
          'status': 'completed',
          'helpful': true,
        },
      },
      'alerts': {
        alert.id: syncCanonical(riskAlertToCloud(alert, dismissed: true)),
      },
    };
    return backup;
  }

  test(
    'Coach backup validates IDs in legacy maps, pending records, and evidence',
    () async {
      final controller = await load();
      final valid = await coachBackup(controller);
      final before = controller.exportJson();
      expect(controller.previewDeviceBackup(jsonEncode(valid)).coachCount, 2);
      for (final invalidId in ['', '../record', '.', '..', 'x' * 1501]) {
        for (final field in [
          'recommendationStatuses',
          'recommendationFeedback',
          'dismissedRiskAlertIds',
        ]) {
          final invalid = jsonDecode(jsonEncode(valid)) as Map;
          invalid['local'][field] = field == 'dismissedRiskAlertIds'
              ? [invalidId]
              : {
                  invalidId: field == 'recommendationStatuses'
                      ? 'completed'
                      : true,
                };
          expect(
            () => controller.previewDeviceBackup(jsonEncode(invalid)),
            throwsFormatException,
            reason: '$field rejects invalid ID',
          );
        }
        for (final collection in ['recommendations', 'alerts']) {
          final invalid = jsonDecode(jsonEncode(valid)) as Map;
          final records = invalid['local']['coachSync'][collection] as Map;
          invalid['local']['coachSync'][collection] = {
            invalidId: records.values.first,
          };
          expect(
            () => controller.previewDeviceBackup(jsonEncode(invalid)),
            throwsFormatException,
            reason: '$collection rejects invalid ID',
          );
        }
      }
      for (final collection in ['recommendations', 'alerts']) {
        for (final field in ['signalEvidenceIds', 'checkInEvidenceIds']) {
          final invalid = jsonDecode(jsonEncode(valid)) as Map;
          final entry =
              (invalid['local']['coachSync'][collection] as Map).values.first;
          final record = collection == 'recommendations'
              ? entry['record']
              : entry;
          record[field] = ['../unowned-record'];
          expect(
            () => controller.previewDeviceBackup(jsonEncode(invalid)),
            throwsFormatException,
          );
        }
      }
      expect(controller.exportJson(), before);
      expect(repository.actionAttempts, 0);
    },
  );

  test(
    'Coach backup rejects normalized, missing, or timezone-free dates before restoring',
    () async {
      final controller = await load();
      final valid = await coachBackup(controller);
      final before = controller.exportJson();
      for (final invalidDate in [
        '2026-02-30T12:00:00Z',
        '2026-09-20T25:00:00Z',
        '2026-09-20T12:61:00Z',
        '2026-09-20T12:00:00+26:00',
        '2026-09-20T12:00:00',
        42,
      ]) {
        for (final field in ['day', 'scheduledAt', 'generatedAt']) {
          final invalid = jsonDecode(jsonEncode(valid)) as Map;
          (invalid['local']['coachSync']['recommendations'] as Map)
                  .values
                  .first['record'][field] =
              invalidDate;
          expect(
            () => controller.previewDeviceBackup(jsonEncode(invalid)),
            throwsFormatException,
            reason: 'recommendation $field rejects $invalidDate',
          );
        }
        for (final field in ['day', 'detectedAt']) {
          final invalid = jsonDecode(jsonEncode(valid)) as Map;
          (invalid['local']['coachSync']['alerts'] as Map).values.first[field] =
              invalidDate;
          expect(
            () => controller.previewDeviceBackup(jsonEncode(invalid)),
            throwsFormatException,
            reason: 'alert $field rejects $invalidDate',
          );
        }
      }
      for (final collection in ['recommendations', 'alerts']) {
        final invalid = jsonDecode(jsonEncode(valid)) as Map;
        final entry =
            (invalid['local']['coachSync'][collection] as Map).values.first;
        final record = collection == 'recommendations'
            ? entry['record']
            : entry;
        record.remove('day');
        expect(
          () => controller.previewDeviceBackup(jsonEncode(invalid)),
          throwsFormatException,
        );
      }
      expect(controller.exportJson(), before);
      expect(repository.actionAttempts, 0);
    },
  );

  test(
    'Coach backup rejects malformed action and record payloads without partial restore',
    () async {
      final controller = await load();
      final valid = await coachBackup(controller);
      final before = controller.exportJson();
      for (final mutate in <void Function(Map)>[
        (backup) => backup['local']['coachSync']['version'] = 2,
        (backup) => backup['local']['coachSync']['recommendations'] = [],
        (backup) => backup['local']['coachSync']['alerts'] = 'invalid',
        (backup) =>
            (backup['local']['coachSync']['recommendations'] as Map)
                    .values
                    .first['status'] =
                'unknown',
        (backup) =>
            (backup['local']['coachSync']['recommendations'] as Map)
                    .values
                    .first['helpful'] =
                'true',
        (backup) =>
            (backup['local']['coachSync']['recommendations'] as Map)
                    .values
                    .first['record'] =
                [],
        (backup) =>
            (backup['local']['coachSync']['recommendations'] as Map)
                    .values
                    .first['record']['title'] =
                123,
        (backup) =>
            (backup['local']['coachSync']['alerts'] as Map)
                    .values
                    .first['dismissed'] =
                false,
        (backup) =>
            (backup['local']['coachSync']['alerts'] as Map)
                    .values
                    .first['severity'] =
                'unknown',
        (backup) =>
            (backup['local']['coachSync']['alerts'] as Map)
                    .values
                    .first['signalEvidenceIds'] =
                'invalid',
      ]) {
        final invalid = jsonDecode(jsonEncode(valid)) as Map;
        mutate(invalid);
        expect(
          () => controller.previewDeviceBackup(jsonEncode(invalid)),
          throwsFormatException,
        );
      }
      expect(controller.exportJson(), before);
      expect(repository.actionAttempts, 0);
    },
  );

  test(
    'a review superseding retry privacy verification releases its syncing indicator',
    () async {
      final controller = await load();
      repository.actionFailure = StateError('Offline');
      await controller.setRecommendationStatus(
        controller.recommendations.first.id,
        RecommendationStatus.completed,
      );
      final gate = repository.privacyGate = Completer<void>();
      final started = repository.privacyStarted = Completer<void>();
      final retry = controller.syncPendingChanges();
      await started.future;
      expect(controller.isCloudSyncing, true);
      await controller.reviewInputConflicts();
      gate.complete();
      await retry;
      expect(controller.isCloudSyncing, false);
      expect(controller.hasPendingCoachChanges, true);
    },
  );

  test(
    'a superseded retry cannot clear the indicator of a newer active upload',
    () async {
      final controller = await load();
      repository.actionFailure = StateError('Offline');
      await controller.setRecommendationStatus(
        controller.recommendations.first.id,
        RecommendationStatus.completed,
      );
      final olderGate = repository.privacyGate = Completer<void>();
      final olderStarted = repository.privacyStarted = Completer<void>();
      final older = controller.syncPendingChanges();
      await olderStarted.future;
      final newerGate = repository.privacyGate = Completer<void>();
      final newerStarted = repository.privacyStarted = Completer<void>();
      repository.actionFailure = null;
      final newer = controller.retryCloudSync();
      await newerStarted.future;
      olderGate.complete();
      await older;
      expect(controller.isCloudSyncing, true);
      newerGate.complete();
      await newer;
      expect(controller.isCloudSyncing, false);
      expect(controller.hasPendingCoachChanges, false);
    },
  );

  testWidgets(
    'foreground automatically retries pending changes and background cancels retries',
    (tester) async {
      final controller = (await tester.runAsync(load))!;
      repository.actionFailure = StateError('Offline');
      final id = controller.recommendations.first.id;
      await controller.setRecommendationStatus(
        id,
        RecommendationStatus.completed,
      );
      controller.setAppForeground(true);
      final attempts = repository.actionAttempts;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(repository.actionAttempts, greaterThan(attempts));
      controller.setAppForeground(false);
      final pausedAttempts = repository.actionAttempts;
      repository.actionFailure = null;
      await tester.pump(const Duration(minutes: 2));
      expect(repository.actionAttempts, pausedAttempts);
      controller.setAppForeground(true);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(controller.hasPendingCoachChanges, isFalse);
      expect((await remote(id)).status, RecommendationStatus.completed);
      controller.setAppForeground(false);
    },
  );

  testWidgets(
    'permission failure gives actionable status and does not keep polling',
    (tester) async {
      final controller = (await tester.runAsync(load))!;
      repository.actionFailure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await controller.setRecommendationStatus(
        controller.recommendations.first.id,
        RecommendationStatus.completed,
      );
      expect(controller.cloudSyncFailureKind, CloudSyncFailureKind.permission);
      expect(controller.cloudSyncStatusMessage, contains('privacy'));
      controller.setAppForeground(true);
      final attempts = repository.actionAttempts;
      await tester.pump(const Duration(minutes: 2));
      expect(repository.actionAttempts, attempts);
      controller.setAppForeground(false);
    },
  );
}
