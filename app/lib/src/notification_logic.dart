import 'models.dart';
import 'notification_service.dart';

enum NotificationPlanState {
  ready,
  disabled,
  missingForecast,
  staleForecast,
  lowConfidence,
  noFutureWindows,
}

class NotificationPlan {
  const NotificationPlan({
    required this.state,
    this.notifications = const [],
    this.dismissedRiskAlertCount = 0,
  });

  final NotificationPlanState state;
  final List<GuidanceNotification> notifications;
  final int dismissedRiskAlertCount;

  bool get isScheduled => notifications.isNotEmpty;
}

abstract final class NotificationLogic {
  static const leadTime = Duration(minutes: 15);
  static const minimumLeadTime = Duration(minutes: 1);
  static const maximumForecastAge = Duration(hours: 12);

  static NotificationPlan build({
    required DateTime now,
    required List<ForecastPoint> points,
    required List<ForecastWindow> windows,
    required List<RiskAlert> riskAlerts,
    required bool enabled,
    required bool crashEnabled,
    required bool recoveryEnabled,
  }) {
    final dismissedCount = riskAlerts.where((item) => item.dismissed).length;
    NotificationPlan suppressed(NotificationPlanState state) =>
        NotificationPlan(state: state, dismissedRiskAlertCount: dismissedCount);

    if (!enabled) return suppressed(NotificationPlanState.disabled);
    if (points.isEmpty || windows.isEmpty) {
      return suppressed(NotificationPlanState.missingForecast);
    }
    final summary = ForecastDaySummary.fromPoints(points.first.time, points);
    final updatedAt = summary.updatedAt;
    if (updatedAt == null ||
        updatedAt.isAfter(now.add(const Duration(minutes: 5))) ||
        now.difference(updatedAt) > maximumForecastAge) {
      return suppressed(NotificationPlanState.staleForecast);
    }
    if (summary.isLowConfidence) {
      return suppressed(NotificationPlanState.lowConfidence);
    }

    final byType = {for (final window in windows) window.type: window};
    final activeRisks = riskAlerts
        .where((item) => !item.dismissed)
        .toList(growable: false);
    final riskIds = activeRisks
        .map((item) => item.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final day = DateTime(
      points.first.time.year,
      points.first.time.month,
      points.first.time.day,
    );
    final notifications = <GuidanceNotification>[];
    final threshold = now.add(minimumLeadTime);

    final crash = byType[ForecastWindowType.crash];
    if (crashEnabled && crash != null) {
      final scheduledAt = crash.start.subtract(leadTime);
      if (scheduledAt.isAfter(threshold)) {
        notifications.add(
          GuidanceNotification(
            id: '${_dayId(day)}-crash',
            platformId: _platformId(day, GuidanceNotificationKind.crash),
            kind: GuidanceNotificationKind.crash,
            scheduledAt: scheduledAt,
            title: 'Lower-energy window ahead',
            body: activeRisks.isEmpty
                ? 'Your forecast suggests lower energy soon. Consider switching to a lighter task.'
                : 'Your forecast and recent wellness patterns favor a lighter block with room to recover.',
            sourceRiskAlertIds: riskIds,
          ),
        );
      }
    }

    final recovery = byType[ForecastWindowType.recovery];
    if (recoveryEnabled && recovery != null) {
      if (recovery.start.isAfter(threshold)) {
        notifications.add(
          GuidanceNotification(
            id: '${_dayId(day)}-recovery',
            platformId: _platformId(day, GuidanceNotificationKind.recovery),
            kind: GuidanceNotificationKind.recovery,
            scheduledAt: recovery.start,
            title: 'Recovery window starting',
            body:
                'Your forecast is moving out of its lower-energy stretch. Check how you feel before increasing demand.',
            sourceRiskAlertIds: riskIds,
          ),
        );
      }
    }

    notifications.sort(
      (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
    );
    return NotificationPlan(
      state: notifications.isEmpty
          ? NotificationPlanState.noFutureWindows
          : NotificationPlanState.ready,
      notifications: List.unmodifiable(notifications),
      dismissedRiskAlertCount: dismissedCount,
    );
  }

  static int _platformId(DateTime day, GuidanceNotificationKind kind) {
    final dayNumber = day.year * 10000 + day.month * 100 + day.day;
    return dayNumber * 10 + kind.index;
  }

  static String _dayId(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
