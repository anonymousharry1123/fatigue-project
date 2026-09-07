import 'dart:async';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _DelayedRepository extends MemoryCloudRepository {
  _DelayedRepository() : super(signedInUid: 'owner');
  final started = Completer<void>();
  final released = Completer<void>();
  bool fail = false;
  int guidanceWrites = 0;

  Future<void> pause() async {
    if (!started.isCompleted) started.complete();
    await released.future;
    if (fail) throw StateError('Old account request failed late');
  }

  @override
  Future<List<SignalReading>> signalsByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
    SignalType? type,
  }) async {
    await pause();
    return [
      SignalReading(
        id: 'old-private-row',
        type: SignalType.hydration,
        value: 2,
        timestamp: DateTime.now(),
      ),
    ];
  }

  @override
  Future<List<OutcomeRecord>> outcomesByRange(
    String uid, {
    required DateTime start,
    required DateTime end,
  }) async {
    await pause();
    return [
      OutcomeRecord(
        id: 'old-private-outcome',
        type: OutcomeType.observedEnergy,
        value: 8,
        observedAt: DateTime.now(),
        recordedAt: DateTime.now(),
        source: OutcomeSource.checkIn,
        sourceId: 'old-private-checkin',
      ),
    ];
  }

  @override
  Future<void> replaceRecommendationsForDay(
    String uid, {
    required DateTime day,
    required List<Recommendation> recommendations,
  }) async {
    guidanceWrites++;
    await super.replaceRecommendationsForDay(
      uid,
      day: day,
      recommendations: recommendations,
    );
  }

  @override
  Future<void> replaceRiskAlertsForDay(
    String uid, {
    required DateTime day,
    required List<RiskAlert> alerts,
  }) async {
    guidanceWrites++;
    await super.replaceRiskAlertsForDay(uid, day: day, alerts: alerts);
  }
}

CloudUserState _state({bool consented = true}) => CloudUserState(
  privacyConsent: consented ? testAdultPrivacyConsent : null,
  profile: const UserProfile(),
  accountEmail: 'owner@example.com',
  onboardingComplete: false,
  notificationsEnabled: false,
  outcomeConsent: consented,
  healthAuthorized: false,
  migrationVersion: localMigrationVersion,
  signals: const [],
  checkIns: const [],
);

class _DelayedNotifications implements NotificationService {
  _DelayedNotifications({required this.delayReconcile});
  final bool delayReconcile;
  final started = Completer<void>();
  final released = Completer<void>();
  int reconciliations = 0;
  int cancellations = 0;
  bool scheduled = false;
  @override
  bool get supportsScheduling => true;
  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.granted;
  @override
  Future<NotificationPermissionState> permissionStatus() async {
    if (!delayReconcile) {
      started.complete();
      await released.future;
    }
    return NotificationPermissionState.granted;
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {
    reconciliations++;
    if (delayReconcile) {
      started.complete();
      await released.future;
    }
    scheduled = true;
  }

  @override
  Future<void> cancelGuidance() async {
    cancellations++;
    scheduled = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final delayReconcile in [false, true]) {
    for (final boundary in ['sign-out', 'privacy withdrawal']) {
      test(
        'notification ${delayReconcile ? 'scheduling' : 'permission'} finishing after $boundary stays cancelled',
        () async {
          final repository = MemoryCloudRepository(signedInUid: 'owner')
            ..seed('owner', _state());
          final notifications = _DelayedNotifications(
            delayReconcile: delayReconcile,
          );
          final controller = AppController(
            initialPrivacyConsent: testAdultPrivacyConsent,
            accountAuth: MemoryAccountAuth(
              session: const AccountSession(
                uid: 'owner',
                email: 'owner@example.com',
              ),
            ),
            cloudRepository: repository,
            notificationService: notifications,
          )..notificationsEnabled = true;
          addTearDown(controller.dispose);
          final pending = controller.refreshNotifications();
          await notifications.started.future;
          if (boundary == 'sign-out') {
            await controller.signOut();
          } else {
            repository.seed('owner', _state(consented: false));
            await controller.handleAppResumed();
          }
          notifications.released.complete();
          await pending;
          expect(notifications.scheduled, isFalse);
          expect(notifications.reconciliations, delayReconcile ? 1 : 0);
          expect(notifications.cancellations, greaterThan(0));
          expect(controller.notificationError, isNull);
        },
      );
    }
  }
  for (final refresh in [
    'scores',
    'forecasts',
    'guidance',
    'insights',
    'outcomes',
  ]) {
    for (final boundary in ['sign-out', 'privacy withdrawal']) {
      for (final lateFailure in [false, true]) {
        test(
          '$refresh ignores late ${lateFailure ? 'failure' : 'data'} after $boundary',
          () async {
            final repository = _DelayedRepository()..seed('owner', _state());
            final controller = AppController(
              initialPrivacyConsent: testAdultPrivacyConsent,
              accountAuth: MemoryAccountAuth(
                session: const AccountSession(
                  uid: 'owner',
                  email: 'owner@example.com',
                ),
              ),
              cloudRepository: repository,
            )..outcomeConsent = true;
            addTearDown(controller.dispose);
            final pending = switch (refresh) {
              'scores' => controller.refreshScores(),
              'forecasts' => controller.refreshForecasts(
                forceRecalculate: true,
              ),
              'guidance' => controller.refreshGuidance(),
              'insights' => controller.refreshInsights(),
              _ => controller.refreshOutcomes(),
            };
            await repository.started.future;
            if (boundary == 'sign-out') {
              await controller.signOut();
            } else {
              repository.seed('owner', _state(consented: false));
              await controller.handleAppResumed();
            }
            expect(
              controller.privacyFeaturesAllowed && !controller.isSignedOut,
              isFalse,
            );
            repository.fail = lateFailure;
            repository.released.complete();
            await pending;
            expect(repository.scoreUpsertCallCount, 0);
            expect(repository.forecastReplaceCallCount, 0);
            expect(repository.guidanceWrites, 0);
            expect(controller.recommendations, isEmpty);
            expect(controller.allAlerts, isEmpty);
            expect(controller.insightsLoadedFromCloud, isFalse);
            expect(controller.insightsSnapshot.sourceSignalCount, 0);
            expect(controller.outcomes, isEmpty);
            expect(controller.energyScoreError, isNull);
            expect(controller.forecastError, isNull);
            expect(controller.guidanceError, isNull);
            expect(controller.insightsError, isNull);
            expect(controller.outcomeError, isNull);
            expect(controller.exportJson(), isNot(contains('old-private')));
          },
        );
      }
    }
  }
}
