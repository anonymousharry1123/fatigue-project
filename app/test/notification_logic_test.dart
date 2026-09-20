import 'privacy_test_support.dart';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/models.dart';
import 'package:app/src/notification_logic.dart';
import 'package:app/src/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 8, 15, 12);
  final day = DateTime(now.year, now.month, now.day);

  List<ForecastPoint> points({double uncertainty = 8, DateTime? updatedAt}) => [
    ForecastPoint(
      day.add(const Duration(hours: 9)),
      72,
      uncertainty,
      updatedAt: updatedAt ?? now.subtract(const Duration(minutes: 20)),
    ),
    ForecastPoint(
      day.add(const Duration(hours: 15)),
      42,
      uncertainty,
      updatedAt: updatedAt ?? now.subtract(const Duration(minutes: 20)),
    ),
    ForecastPoint(
      day.add(const Duration(hours: 18)),
      63,
      uncertainty,
      updatedAt: updatedAt ?? now.subtract(const Duration(minutes: 20)),
    ),
  ];

  List<ForecastWindow> windows({bool past = false}) {
    final offset = past ? -8 : 0;
    return [
      ForecastWindow(
        ForecastWindowType.crash,
        day.add(Duration(hours: 15 + offset)),
        day.add(Duration(hours: 16 + offset)),
        42,
        'Forecast energy change',
      ),
      ForecastWindow(
        ForecastWindowType.recovery,
        day.add(Duration(hours: 17 + offset)),
        day.add(Duration(hours: 19 + offset)),
        63,
        'Forecast recovery',
      ),
    ];
  }

  NotificationPlan build({
    List<ForecastPoint>? forecast,
    List<ForecastWindow>? forecastWindows,
    bool enabled = true,
    bool crashEnabled = true,
    bool recoveryEnabled = true,
    List<Recommendation> recommendations = const [],
    bool coachPlanEnabled = false,
  }) => NotificationLogic.build(
    now: now,
    points: forecast ?? points(),
    windows: forecastWindows ?? windows(),
    riskAlerts: [
      RiskAlert(
        'Private active title',
        'Private active detail',
        AlertSeverity.caution,
        id: 'active-risk',
      ),
      RiskAlert(
        'Private dismissed title',
        'Private dismissed detail',
        AlertSeverity.high,
        id: 'dismissed-risk',
        dismissed: true,
      ),
    ],
    enabled: enabled,
    crashEnabled: crashEnabled,
    recoveryEnabled: recoveryEnabled,
    recommendations: recommendations,
    coachPlanEnabled: coachPlanEnabled,
  );

  group('Version 0.20 notification planning', () {
    test('builds deterministic crash and recovery reminders', () {
      final first = build();
      final second = build();

      expect(first.state, NotificationPlanState.ready);
      expect(first.notifications, hasLength(2));
      expect(
        first.notifications.map((item) => item.id),
        second.notifications.map((item) => item.id),
      );
      expect(
        first.notifications.map((item) => item.platformId),
        second.notifications.map((item) => item.platformId),
      );
      expect(
        first.notifications.first.scheduledAt,
        day.add(const Duration(hours: 14, minutes: 45)),
      );
      expect(
        first.notifications.last.scheduledAt,
        day.add(const Duration(hours: 17)),
      );
      expect(first.dismissedRiskAlertCount, 1);
      for (final notification in first.notifications) {
        expect(notification.sourceRiskAlertIds, ['active-risk']);
        expect(notification.body, isNot(contains('Private')));
        expect(notification.body.toLowerCase(), isNot(contains('diagnos')));
        expect(notification.payload, startsWith('tonyo-guidance:'));
      }
    });

    test('suppresses stale forecasts', () {
      final plan = build(
        forecast: points(updatedAt: now.subtract(const Duration(hours: 13))),
      );

      expect(plan.state, NotificationPlanState.staleForecast);
      expect(plan.notifications, isEmpty);
    });

    test('suppresses low-confidence forecasts', () {
      final plan = build(forecast: points(uncertainty: 18));

      expect(plan.state, NotificationPlanState.lowConfidence);
      expect(plan.notifications, isEmpty);
    });

    test('suppresses past windows and honors category preferences', () {
      expect(
        build(forecastWindows: windows(past: true)).state,
        NotificationPlanState.noFutureWindows,
      );
      final recoveryOnly = build(crashEnabled: false);
      expect(recoveryOnly.notifications, hasLength(1));
      expect(
        recoveryOnly.notifications.single.kind,
        GuidanceNotificationKind.recovery,
      );
    });
  });

  Recommendation step(
    String id, {
    RecommendationStatus status = RecommendationStatus.suggested,
    DateTime? at,
    DateTime? planDay,
    DateTime? generated,
    bool timestamped = true,
    bool grounded = true,
    double confidence = .8,
  }) => Recommendation(
    id: id,
    title: 'Protect a focus block',
    detail:
        'Private notes and sensitive evidence do not belong on a lock screen.',
    timeLabel: '1 PM',
    category: 'Focus',
    status: status,
    scheduledAt: at ?? now.add(const Duration(hours: 1)),
    day: planDay ?? day,
    generatedAt: timestamped ? generated ?? now : null,
    durationMinutes: 35,
    planConfidence: confidence,
    signalEvidenceIds: grounded ? ['private-signal-id'] : [''],
  );

  group('daily Coach reminder planning', () {
    test('uses each actual plan time and ignores legacy action status', () {
      final recommendations = [
        for (final status in RecommendationStatus.values)
          step(
            status.name,
            status: status,
            at: now.add(Duration(hours: status.index + 1)),
          ),
      ];
      final plan = build(
        recommendations: recommendations,
        coachPlanEnabled: true,
        crashEnabled: false,
        recoveryEnabled: false,
      );
      expect(plan.notifications.length, RecommendationStatus.values.length);
      for (final item in plan.notifications) {
        final source = recommendations.singleWhere(
          (record) => record.id == item.sourceRecommendationId,
        );
        expect(item.scheduledAt, source.scheduledAt);
        expect(item.kind, GuidanceNotificationKind.coachPlan);
        expect(item.title, source.title);
        expect(item.body, contains('35 min'));
        expect(item.body, contains('Open Coach'));
        expect(item.body, isNot(contains('Private')));
        expect(item.body, isNot(contains('private-signal-id')));
        expect(item.sourceRiskAlertIds, isEmpty);
      }
    });

    test(
      'Coach preference and master preference remain independently required',
      () {
        final recommendations = [step('focus')];
        expect(
          build(
            recommendations: recommendations,
            coachPlanEnabled: false,
            crashEnabled: false,
            recoveryEnabled: false,
          ).notifications,
          isEmpty,
        );
        expect(
          build(
            recommendations: recommendations,
            coachPlanEnabled: true,
            enabled: false,
          ).state,
          NotificationPlanState.disabled,
        );
        final both = build(
          recommendations: recommendations,
          coachPlanEnabled: true,
        );
        expect(
          both.notifications.map((item) => item.kind).toSet(),
          GuidanceNotificationKind.values.toSet(),
        );
      },
    );

    test(
      'gentle grounded Coach plan is allowed with low, stale or absent forecast',
      () {
        for (final forecast in [
          points(uncertainty: 18),
          points(updatedAt: now.subtract(const Duration(hours: 13))),
          <ForecastPoint>[],
        ]) {
          final plan = build(
            forecast: forecast,
            recommendations: [step('gentle', confidence: .3)],
            coachPlanEnabled: true,
          );
          expect(plan.state, NotificationPlanState.ready);
          expect(plan.notifications, hasLength(1));
          expect(
            plan.notifications.single.kind,
            GuidanceNotificationKind.coachPlan,
          );
          expect(
            plan.notifications.single.body,
            contains('gentle and flexible'),
          );
        }
      },
    );

    test(
      'today plan includes its post-midnight bedtime but excludes other plan days',
      () {
        final bedtime = day.add(const Duration(days: 1, minutes: 30));
        final plan = build(
          crashEnabled: false,
          recoveryEnabled: false,
          coachPlanEnabled: true,
          recommendations: [
            step('bedtime', at: bedtime),
            step(
              'tomorrow-plan',
              at: bedtime,
              planDay: day.add(const Duration(days: 1)),
            ),
            step(
              'yesterday-plan',
              planDay: day.subtract(const Duration(days: 1)),
            ),
            step('too-far', at: day.add(const Duration(days: 2))),
          ],
        );
        expect(plan.notifications, hasLength(1));
        expect(plan.notifications.single.sourceRecommendationId, 'bedtime');
        expect(plan.notifications.single.scheduledAt, bedtime);
      },
    );

    test(
      'rejects past, insufficient lead, ungrounded and stale recommendations',
      () {
        final plan = build(
          crashEnabled: false,
          recoveryEnabled: false,
          coachPlanEnabled: true,
          recommendations: [
            step('past', at: now.subtract(const Duration(minutes: 1))),
            step('soon', at: now.add(NotificationLogic.minimumLeadTime)),
            step('ungrounded', grounded: false),
            step('stale', generated: now.subtract(const Duration(hours: 13))),
            step(
              'future-generated',
              generated: now.add(const Duration(minutes: 6)),
            ),
            step('no-generation-time', timestamped: false),
            step('valid', at: now.add(const Duration(minutes: 2))),
          ],
        );
        expect(plan.notifications.map((item) => item.sourceRecommendationId), [
          'valid',
        ]);
      },
    );

    test(
      'bounds reminders, deduplicates and resolves deterministic ID collisions',
      () {
        final recommendations = [
          step('Aa'),
          step('BB'), // Same polynomial hash before collision probing.
          for (var index = 0; index < 20; index++)
            step(
              'extra-$index',
              at: now.add(Duration(hours: 2, minutes: index)),
            ),
          step(
            'Aa',
            at: now.add(const Duration(hours: 5)),
            generated: now.subtract(const Duration(minutes: 1)),
          ),
        ];
        final first = build(
          recommendations: recommendations,
          coachPlanEnabled: true,
        );
        final reversed = build(
          recommendations: recommendations.reversed.toList(),
          coachPlanEnabled: true,
        );
        expect(
          first.notifications.where(
            (item) => item.kind == GuidanceNotificationKind.coachPlan,
          ),
          hasLength(NotificationLogic.maximumCoachReminders),
        );
        expect(
          first.notifications.map((item) => item.platformId).toSet().length,
          first.notifications.length,
        );
        expect(
          {for (final item in first.notifications) item.id: item.platformId},
          {for (final item in reversed.notifications) item.id: item.platformId},
        );
        expect(
          first.notifications.every(
            (item) => item.platformId >= 0 && item.platformId <= 0x7fffffff,
          ),
          true,
        );
        expect(
          first.notifications
              .singleWhere((item) => item.sourceRecommendationId == 'Aa')
              .scheduledAt,
          now.add(const Duration(hours: 1)),
        );
        expect(
          first.notifications
              .where((item) => item.kind == GuidanceNotificationKind.coachPlan)
              .every((item) => item.platformId >= 0x40000000),
          true,
        );
        expect(
          first.notifications
              .where((item) => item.kind != GuidanceNotificationKind.coachPlan)
              .every((item) => item.platformId < 0x40000000),
          true,
        );
      },
    );

    test(
      'time changes retain stable identity and payload safely encodes the source ID',
      () {
        const id = 'focus: afternoon / café';
        final first = build(
          recommendations: [step(id)],
          coachPlanEnabled: true,
          crashEnabled: false,
          recoveryEnabled: false,
        ).notifications.single;
        final later = build(
          recommendations: [step(id, at: now.add(const Duration(hours: 2)))],
          coachPlanEnabled: true,
          crashEnabled: false,
          recoveryEnabled: false,
        ).notifications.single;
        expect(first.platformId, later.platformId);
        expect(first.id, later.id);
        expect(
          first.payload,
          'tonyo-guidance:coach:${Uri.encodeComponent(id)}',
        );
        expect(
          Uri.decodeComponent(
            first.payload.substring('tonyo-guidance:coach:'.length),
          ),
          id,
        );
      },
    );
  });

  group('Version 0.20 notification consent', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'requests permission only during explicit opt-in and persists it',
      () async {
        final service = _FakeNotificationService();
        final controller = AppController(
          initialPrivacyConsent: testAdultPrivacyConsent,
          notificationService: service,
        );
        await controller.load();

        expect(controller.notificationsEnabled, isFalse);
        expect(service.permissionRequests, 0);

        final result = await controller.setNotifications(true);

        expect(result, NotificationPermissionState.granted);
        expect(controller.notificationsEnabled, isTrue);
        expect(service.permissionRequests, 1);
        expect(service.reconciliations, 1);
        final export =
            jsonDecode(controller.exportJson()) as Map<String, dynamic>;
        expect(export['notificationPreferencesVersion'], 1);
        expect(export['notificationsEnabled'], isTrue);

        final restored = AppController(
          initialPrivacyConsent: testAdultPrivacyConsent,
          notificationService: service,
        );
        await restored.load();
        expect(restored.notificationsEnabled, isTrue);
        expect(service.permissionRequests, 1);

        await restored.setNotifications(false);
        expect(restored.notificationsEnabled, isFalse);
        expect(service.cancellations, greaterThan(0));
      },
    );

    test('does not treat the legacy default-on flag as consent', () async {
      SharedPreferences.setMockInitialValues({
        'tonyo_state_v1': jsonEncode({
          'onboardingComplete': false,
          'notificationsEnabled': true,
          'profile': const UserProfile().toJson(),
          'signals': const [],
          'checkIns': const [],
        }),
      });
      final service = _FakeNotificationService();
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        notificationService: service,
      );

      await controller.load();

      expect(controller.notificationsEnabled, isFalse);
      expect(service.permissionRequests, 0);
      expect(service.reconciliations, 0);
    });

    test('keeps alerts off when platform permission is denied', () async {
      final service = _FakeNotificationService(
        permission: NotificationPermissionState.denied,
      );
      final controller = AppController(
        initialPrivacyConsent: testAdultPrivacyConsent,
        notificationService: service,
      );
      await controller.load();

      final result = await controller.setNotifications(true);

      expect(result, NotificationPermissionState.denied);
      expect(controller.notificationsEnabled, isFalse);
      expect(controller.notificationError, contains('blocked'));
      expect(service.reconciliations, 0);
    });
  });
}

class _FakeNotificationService implements NotificationService {
  _FakeNotificationService({
    this.permission = NotificationPermissionState.granted,
  });

  NotificationPermissionState permission;
  int permissionRequests = 0;
  int reconciliations = 0;
  int cancellations = 0;
  List<GuidanceNotification> scheduled = const [];

  @override
  bool get supportsScheduling => true;

  @override
  Future<NotificationPermissionState> permissionStatus() async => permission;

  @override
  Future<NotificationPermissionState> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {
    reconciliations += 1;
    scheduled = List.unmodifiable(notifications);
  }

  @override
  Future<void> cancelGuidance() async {
    cancellations += 1;
    scheduled = const [];
  }
}
