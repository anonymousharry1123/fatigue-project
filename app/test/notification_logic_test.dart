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
    bool currentEvidenceEligible = true,
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
    currentEvidenceEligible: currentEvidenceEligible,
  );

  group('Version 0.20 notification planning', () {
    test('uncalibrated forecast windows never schedule precise alerts', () {
      final plan = build();
      expect(plan.state, NotificationPlanState.uncalibratedForecast);
      expect(plan.notifications, isEmpty);
      expect(plan.dismissedRiskAlertCount, 1);
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

    test('forecast preferences cannot re-enable unvalidated timing alerts', () {
      expect(
        build(forecastWindows: windows(past: true)).notifications,
        isEmpty,
      );
      expect(build(crashEnabled: false).notifications, isEmpty);
      expect(build(recoveryEnabled: false).notifications, isEmpty);
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
    id: '2026-08-15-phase1-$id',
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
    planPhase: CoachPlanPhase.deepWork,
    evidence: grounded
        ? [
            ForecastEvidence(
              id: 'private-signal-id',
              kind: ForecastEvidenceKind.signal,
              label: 'Observation',
              detail: 'Private details',
              timestamp: now,
            ),
          ]
        : [],
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
        expect(both.notifications.map((item) => item.kind).toSet(), {
          GuidanceNotificationKind.coachPlan,
        });
      },
    );

    test(
      'schedule-based Coach plan can use current observations independently of a forecast',
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
            contains('Optional schedule reminder'),
          );
        }
      },
    );

    test(
      'current evidence loss cancels otherwise fresh schedule reminders',
      () {
        final plan = build(
          recommendations: [step('focus')],
          coachPlanEnabled: true,
          currentEvidenceEligible: false,
        );
        expect(plan.notifications, isEmpty);
      },
    );

    test('pre-upgrade plan IDs cannot revive removed prescriptions', () {
      final plan = build(
        recommendations: [
          Recommendation(
            id: '2026-08-15-training',
            title: 'Normal intensity',
            detail: 'Legacy',
            timeLabel: '13:00',
            category: 'Training',
            day: day,
            scheduledAt: now.add(const Duration(hours: 1)),
            generatedAt: now,
            signalEvidenceIds: ['old'],
            planPhase: CoachPlanPhase.training,
          ),
        ],
        coachPlanEnabled: true,
      );
      expect(plan.notifications, isEmpty);
    });

    test(
      'post-midnight reminders are omitted when same-day evidence will have expired',
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
        expect(plan.notifications, isEmpty);
      },
    );

    test('does not schedule beyond supporting observation freshness', () {
      final plan = build(
        recommendations: [
          step('expired-at-delivery', at: now.add(const Duration(hours: 13))),
        ],
        coachPlanEnabled: true,
      );
      expect(plan.notifications, isEmpty);
    });

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
          '2026-08-15-phase1-valid',
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
              .singleWhere(
                (item) => item.sourceRecommendationId == '2026-08-15-phase1-Aa',
              )
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
          'tonyo-guidance:coach:${Uri.encodeComponent('2026-08-15-phase1-$id')}',
        );
        expect(
          Uri.decodeComponent(
            first.payload.substring('tonyo-guidance:coach:'.length),
          ),
          '2026-08-15-phase1-$id',
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

  group('study log reminders', () {
    test('study reminders use optional evening times without deadlines', () {
      final plan = NotificationLogic.build(
        now: DateTime(2026, 8, 15, 8),
        points: points(),
        windows: windows(),
        riskAlerts: const [],
        enabled: true,
        crashEnabled: false,
        recoveryEnabled: false,
        studyLogEnabled: true,
      );
      final study = plan.notifications
          .where(
            (item) =>
                item.kind == GuidanceNotificationKind.studySleep ||
                item.kind == GuidanceNotificationKind.studyEnergy,
          )
          .toList();

      expect(study.map((item) => item.scheduledAt).take(2), [
        DateTime(2026, 8, 15, 18),
        DateTime(2026, 8, 15, 19),
      ]);
      expect(
        study.where((item) => item.kind == GuidanceNotificationKind.studySleep),
        hasLength(14),
      );
      expect(
        study.where(
          (item) => item.kind == GuidanceNotificationKind.studyEnergy,
        ),
        hasLength(14),
      );
      expect(study.first.payload, 'tonyo-guidance:study:sleep');
      expect(
        study.first.body,
        'Log your main sleep whenever it suits you. There is no deadline.',
      );
      expect(
        study
            .firstWhere(
              (item) => item.kind == GuidanceNotificationKind.studyEnergy,
            )
            .body,
        'Choose Evening and rate your Energy whenever it suits you.',
      );
      expect(
        study
            .firstWhere(
              (item) => item.kind == GuidanceNotificationKind.studyEnergy,
            )
            .payload,
        'tonyo-guidance:study:energy',
      );
    });

    test('late-wake sleep and afternoon Evening Energy skip that day', () {
      final afternoon = DateTime(2026, 8, 15, 17);
      final plan = NotificationLogic.build(
        now: afternoon,
        points: points(),
        windows: windows(),
        riskAlerts: const [],
        enabled: true,
        crashEnabled: false,
        recoveryEnabled: false,
        studyLogEnabled: true,
        signals: [
          SignalReading(
            id: 'sleep',
            type: SignalType.sleep,
            value: 7.5,
            timestamp: DateTime(2026, 8, 15, 14),
          ),
          SignalReading(
            id: 'nap',
            type: SignalType.nap,
            value: 0.4,
            timestamp: DateTime(2026, 8, 16, 14),
          ),
        ],
        checkIns: [
          DailyCheckIn(
            id: 'afternoon',
            timestamp: DateTime(2026, 8, 15, 14, 30),
            period: CheckInPeriod.evening,
            energy: 6,
          ),
        ],
      );
      final study = plan.notifications
          .where(
            (item) =>
                item.kind == GuidanceNotificationKind.studySleep ||
                item.kind == GuidanceNotificationKind.studyEnergy,
          )
          .toList();

      expect(study.map((item) => (item.kind, item.scheduledAt)).take(2), [
        (GuidanceNotificationKind.studySleep, DateTime(2026, 8, 16, 18)),
        (GuidanceNotificationKind.studyEnergy, DateTime(2026, 8, 16, 19)),
      ]);
      expect(study, hasLength(26));
    });

    test('Morning Energy does not suppress the Evening reminder', () {
      final plan = NotificationLogic.build(
        now: DateTime(2026, 8, 15, 17),
        points: points(),
        windows: windows(),
        riskAlerts: const [],
        enabled: true,
        crashEnabled: false,
        recoveryEnabled: false,
        studyLogEnabled: true,
        checkIns: [
          DailyCheckIn(
            id: 'late-morning',
            timestamp: DateTime(2026, 8, 15, 14, 30),
            period: CheckInPeriod.morning,
            energy: 6,
          ),
        ],
      );

      final energy = plan.notifications.where(
        (item) => item.kind == GuidanceNotificationKind.studyEnergy,
      );
      expect(energy.first.scheduledAt, DateTime(2026, 8, 15, 19));
      expect(energy, hasLength(14));
    });

    test('study reminders stay off until the switch is enabled', () {
      final plan = NotificationLogic.build(
        now: DateTime(2026, 8, 15, 8),
        points: points(),
        windows: windows(),
        riskAlerts: const [],
        enabled: true,
        crashEnabled: false,
        recoveryEnabled: false,
      );

      expect(
        plan.notifications.where(
          (item) =>
              item.kind == GuidanceNotificationKind.studySleep ||
              item.kind == GuidanceNotificationKind.studyEnergy,
        ),
        isEmpty,
      );
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
