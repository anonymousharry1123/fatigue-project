import 'models.dart';
import 'local_day.dart';
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
  static const maximumCoachPlanAge = Duration(hours: 12);
  static const maximumCoachReminders = 12;
  static const _coachIdNamespace = 0x40000000;
  static const _idMask = _coachIdNamespace - 1;

  static NotificationPlan build({
    required DateTime now,
    required List<ForecastPoint> points,
    required List<ForecastWindow> windows,
    required List<RiskAlert> riskAlerts,
    required bool enabled,
    required bool crashEnabled,
    required bool recoveryEnabled,
    List<Recommendation> recommendations = const [],
    bool coachPlanEnabled = false,
  }) {
    final forecast = _forecastPlan(
      now: now,
      points: points,
      windows: windows,
      riskAlerts: riskAlerts,
      enabled: enabled,
      crashEnabled: crashEnabled,
      recoveryEnabled: recoveryEnabled,
    );
    if (!enabled || !coachPlanEnabled) return forecast;
    final coach = _coachReminders(now, recommendations);
    if (coach.isEmpty) return forecast;
    final notifications = [...forecast.notifications, ...coach]
      ..sort((left, right) {
        final time = left.scheduledAt.compareTo(right.scheduledAt);
        return time != 0 ? time : left.id.compareTo(right.id);
      });
    return NotificationPlan(
      state: NotificationPlanState.ready,
      notifications: List.unmodifiable(notifications),
      dismissedRiskAlertCount: forecast.dismissedRiskAlertCount,
    );
  }

  static List<GuidanceNotification> _coachReminders(
    DateTime now,
    List<Recommendation> recommendations,
  ) {
    final threshold = now.add(minimumLeadTime);
    final end = localDay(now, 2);
    final byId = <String, Recommendation>{};
    for (final item in recommendations) {
      final time = item.scheduledAt;
      final generated = item.generatedAt;
      final grounded =
          item.signalEvidenceIds.any((id) => id.trim().isNotEmpty) ||
          item.checkInEvidenceIds.any((id) => id.trim().isNotEmpty);
      if (item.id.trim().isEmpty ||
          item.title.trim().isEmpty ||
          !grounded ||
          item.day == null ||
          !sameLocalDay(item.day!, now) ||
          time == null ||
          !time.isAfter(threshold) ||
          !time.isBefore(end) ||
          generated == null ||
          generated.isAfter(now.add(const Duration(minutes: 5))) ||
          now.difference(generated) > maximumCoachPlanAge) {
        continue;
      }
      final previous = byId[item.id];
      if (previous == null ||
          generated.isAfter(previous.generatedAt!) ||
          (generated.isAtSameMomentAs(previous.generatedAt!) &&
              time.isBefore(previous.scheduledAt!))) {
        byId[item.id] = item;
      }
    }
    final selected = byId.values.toList()
      ..sort((left, right) {
        final time = left.scheduledAt!.compareTo(right.scheduledAt!);
        return time != 0 ? time : left.id.compareTo(right.id);
      });
    final limited = selected.take(maximumCoachReminders).toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final used = <int>{};
    final result = <GuidanceNotification>[];
    for (final item in limited) {
      var id = _stableId('${_dayId(localDay(now))}|${item.id}');
      while (!used.add(id)) {
        id = (id + 1) & _idMask;
      }
      final duration = item.durationMinutes;
      final durationLabel = duration != null && duration > 0 && duration <= 1440
          ? '$duration min · '
          : '';
      final gentle =
          item.planConfidence == null ||
          !item.planConfidence!.isFinite ||
          item.planConfidence! < .65;
      result.add(
        GuidanceNotification(
          id: '${_dayId(localDay(now))}-coach-${item.id}',
          platformId: _coachIdNamespace | id,
          kind: GuidanceNotificationKind.coachPlan,
          scheduledAt: item.scheduledAt!,
          title: item.title.trim(),
          body:
              '$durationLabel${gentle ? "Keep it gentle and flexible. " : ""}Open Coach for your daily plan.',
          sourceRecommendationId: item.id,
        ),
      );
    }
    return result;
  }

  // Multiplication remains below 2^53 before masking, so native and web assign
  // identical IDs. Coach IDs use a disjoint signed-32-bit namespace; collision
  // probing in sorted record order keeps each scheduled ID unique and stable.
  static int _stableId(String value) {
    var result = 0;
    for (final unit in value.codeUnits) {
      result = (result * 31 + unit) & _idMask;
    }
    return result;
  }

  static NotificationPlan _forecastPlan({
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
    final day = localDay(points.first.time);
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
    return (dayNumber * 10 + kind.index) & _idMask;
  }

  static String _dayId(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
