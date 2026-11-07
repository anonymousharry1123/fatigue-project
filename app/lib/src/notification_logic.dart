import 'package:timezone/timezone.dart' as timezone;
import 'timezone_database.dart';
import 'models.dart';
import 'daily_plan_logic.dart';
import 'local_day.dart';
import 'notification_service.dart';

enum NotificationPlanState {
  ready,
  disabled,
  missingForecast,
  staleForecast,
  lowConfidence,
  noFutureWindows,
  uncalibratedForecast,
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
  static const defaultMorningMinutes = 9 * 60;
  static const defaultEveningMinutes = 19 * 60;
  static const _coachIdNamespace = 0x40000000;
  static const _studyIdNamespace = 0x20000000;
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
    bool currentEvidenceEligible = false,
    bool studyLogEnabled = false,
    int morningReminderMinutes = defaultMorningMinutes,
    int eveningReminderMinutes = defaultEveningMinutes,
    String? timezoneName,
    List<SignalReading> signals = const [],
    List<DailyCheckIn> checkIns = const [],
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
    final coach = enabled && coachPlanEnabled && currentEvidenceEligible
        ? _coachReminders(now, recommendations)
        : const <GuidanceNotification>[];
    final study = enabled && studyLogEnabled
        ? _studyReminders(
            now: now,
            morningMinutes: morningReminderMinutes,
            eveningMinutes: eveningReminderMinutes,
            timezoneName: timezoneName,
          )
        : const <GuidanceNotification>[];
    if (coach.isEmpty && study.isEmpty) return forecast;
    final notifications = [...forecast.notifications, ...coach, ...study]
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
      final freshEvidence = item.evidence.any(
        (evidence) =>
            time != null &&
            sameLocalDay(evidence.timestamp, now) &&
            sameLocalDay(evidence.timestamp, time) &&
            time.difference(evidence.timestamp) <= maximumCoachPlanAge &&
            !evidence.timestamp.isAfter(now) &&
            now.difference(evidence.timestamp) <= maximumCoachPlanAge &&
            (evidence.kind == ForecastEvidenceKind.signal
                ? item.signalEvidenceIds.contains(evidence.id)
                : item.checkInEvidenceIds.contains(evidence.id)),
      );
      if (!DailyPlanLogic.isCurrentPlan(item) ||
          !freshEvidence ||
          item.id.trim().isEmpty ||
          item.title.trim().isEmpty ||
          !grounded ||
          item.day == null ||
          !sameLocalDay(item.day!, now) ||
          time == null ||
          !time.isAfter(threshold) ||
          !time.isBefore(end) ||
          generated == null ||
          generated.isAfter(now.add(const Duration(minutes: 5))) ||
          now.difference(generated) > maximumCoachPlanAge ||
          time.difference(generated) > maximumCoachPlanAge) {
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
      result.add(
        GuidanceNotification(
          id: '${_dayId(localDay(now))}-coach-${item.id}',
          platformId: _coachIdNamespace | id,
          kind: GuidanceNotificationKind.coachPlan,
          scheduledAt: item.scheduledAt!,
          title: item.title.trim(),
          body:
              '${durationLabel}Optional schedule reminder. Open Coach for your daily plan.',
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

    // No current forecast is prospectively calibrated. Neither its timing nor
    // its heuristic coverage can justify a precise peak/crash notification.
    return suppressed(NotificationPlanState.uncalibratedForecast);
  }

  static List<GuidanceNotification> _studyReminders({
    required DateTime now,
    required int morningMinutes,
    required int eveningMinutes,
    required String? timezoneName,
  }) {
    for (final minutes in [morningMinutes, eveningMinutes]) {
      if (minutes < 0 || minutes >= 24 * 60) {
        throw ArgumentError.value(
          minutes,
          'minutes',
          'Use a local time within one day.',
        );
      }
    }
    DateTime next(int minutes) {
      if (timezoneName != null) {
        initializeTimezoneDatabase();
        final location = timezone.getLocation(timezoneName);
        final local = timezone.TZDateTime.from(now, location);
        var at = timezone.TZDateTime(
          location,
          local.year,
          local.month,
          local.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (!at.isAfter(now)) {
          at = timezone.TZDateTime(
            location,
            local.year,
            local.month,
            local.day + 1,
            minutes ~/ 60,
            minutes % 60,
          );
        }
        return at;
      }
      final local = now.toLocal();
      var at = DateTime(
        local.year,
        local.month,
        local.day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (!at.isAfter(now)) {
        at = DateTime(
          local.year,
          local.month,
          local.day + 1,
          minutes ~/ 60,
          minutes % 60,
        );
      }
      return at;
    }

    // Two OS-managed daily requests do not expire when the app stays closed.
    // Completed entries do not cancel tomorrow's recurring reminder.
    return [
      GuidanceNotification(
        id: 'daily-morning-check-in',
        platformId: _studyIdNamespace | 0x100,
        kind: GuidanceNotificationKind.studyMorning,
        scheduledAt: next(morningMinutes),
        repeatsDaily: true,
        timezoneName: timezoneName,
        title: 'Morning check-in',
        body: 'Take a moment to record how energetic you feel this morning.',
      ),
      GuidanceNotification(
        id: 'daily-evening-check-in',
        platformId: _studyIdNamespace | 0x200,
        kind: GuidanceNotificationKind.studyEnergy,
        scheduledAt: next(eveningMinutes),
        repeatsDaily: true,
        timezoneName: timezoneName,
        title: 'Evening check-in',
        body: 'Record your evening Energy and review your main sleep.',
      ),
    ];
  }

  static String _dayId(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
