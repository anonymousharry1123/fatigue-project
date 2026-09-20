import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as timezone;

import 'timezone_database.dart';

enum NotificationPermissionState { unknown, granted, denied, unavailable }

enum GuidanceNotificationKind { crash, recovery, coachPlan }

class GuidanceNotification {
  const GuidanceNotification({
    required this.id,
    required this.platformId,
    required this.kind,
    required this.scheduledAt,
    required this.title,
    required this.body,
    this.sourceRiskAlertIds = const [],
    this.sourceRecommendationId,
  });

  final String id;
  final int platformId;
  final GuidanceNotificationKind kind;
  final DateTime scheduledAt;
  final String title;
  final String body;
  final List<String> sourceRiskAlertIds;
  final String? sourceRecommendationId;

  String get payload =>
      kind == GuidanceNotificationKind.coachPlan &&
          sourceRecommendationId != null
      ? 'tonyo-guidance:coach:${Uri.encodeComponent(sourceRecommendationId!)}'
      : 'tonyo-guidance:$id';
}

abstract interface class NotificationService {
  bool get supportsScheduling;

  Future<NotificationPermissionState> permissionStatus();

  /// Must only be called in response to an explicit user interaction.
  Future<NotificationPermissionState> requestPermission();

  /// Replaces Tonyo-managed pending guidance while preserving unrelated
  /// notifications created by the host app or another plugin.
  Future<void> reconcile(List<GuidanceNotification> notifications);

  Future<void> cancelGuidance();
}

/// Optional capability so tests and other notification implementations need not
/// implement routing. Attaching a listener never requests notification access.
abstract interface class NotificationResponseSource {
  Future<void> initializeResponses(void Function(String payload) onTap);
}

class LocalNotificationService
    implements NotificationService, NotificationResponseSource {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _payloadPrefix = 'tonyo-guidance:';
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  Future<void>? _initialization;
  Future<void>? _mutationTail;
  void Function(String payload)? _onTap;
  bool _launchDetailsConsumed = false;
  Future<void>? _launchDetailsRead;

  @override
  bool get supportsScheduling =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        _ => false,
      };

  Future<void> _initialize() {
    if (_initialized || !supportsScheduling) return Future<void>.value();
    return _initialization ??= _initializePlugin().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initializePlugin() async {
    initializeTimezoneDatabase();
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: darwin,
        macOS: darwin,
        windows: WindowsInitializationSettings(
          appName: 'Tonyo',
          appUserModelId: 'Tonyo.FatigueCoach',
          guid: '17195fa7-c248-4bb0-89e6-f06099687c9f',
        ),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
    );
    _initialized = true;
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) _onTap?.call(payload);
  }

  @override
  Future<void> initializeResponses(void Function(String payload) onTap) async {
    _onTap = onTap;
    if (!supportsScheduling) return;
    await _initialize();
    if (_launchDetailsConsumed) return;
    await (_launchDetailsRead ??= _readLaunchDetails().whenComplete(() {
      _launchDetailsRead = null;
    }));
  }

  Future<void> _readLaunchDetails() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    _launchDetailsConsumed = true;
    if (details?.didNotificationLaunchApp == true &&
        details?.notificationResponse != null) {
      _handleResponse(details!.notificationResponse!);
    }
  }

  Future<void> _serializeMutation(Future<void> Function() action) {
    final previous = _mutationTail;
    final task = previous == null ? action() : previous.then((_) => action());
    // Keep later requests runnable after an earlier failure while preserving
    // that failure on the future returned to the original caller. An idle
    // service must not retain a future tied to its construction/caller zone.
    late final Future<void> tail;
    void release() {
      if (identical(_mutationTail, tail)) _mutationTail = null;
    }

    tail = task.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    _mutationTail = tail;
    return task;
  }

  @override
  Future<NotificationPermissionState> permissionStatus() async {
    if (!supportsScheduling) return NotificationPermissionState.unavailable;
    await _initialize();
    final enabled = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled(),
      TargetPlatform.iOS =>
        (await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions())
            ?.isEnabled,
      TargetPlatform.macOS =>
        (await _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions())
            ?.isEnabled,
      TargetPlatform.windows => true,
      _ => false,
    };
    if (enabled == null) return NotificationPermissionState.unknown;
    return enabled
        ? NotificationPermissionState.granted
        : NotificationPermissionState.denied;
  }

  @override
  Future<NotificationPermissionState> requestPermission() async {
    if (!supportsScheduling) return NotificationPermissionState.unavailable;
    await _initialize();
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission(),
      TargetPlatform.iOS =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: false, sound: true),
      TargetPlatform.macOS =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: false, sound: true),
      TargetPlatform.windows => true,
      _ => false,
    };
    if (granted == null) return NotificationPermissionState.unknown;
    return granted
        ? NotificationPermissionState.granted
        : NotificationPermissionState.denied;
  }

  @override
  Future<void> reconcile(List<GuidanceNotification> notifications) async {
    if (!supportsScheduling) return;
    final desired = List<GuidanceNotification>.unmodifiable(notifications);
    await _serializeMutation(() => _replaceGuidance(desired));
  }

  Future<void> _replaceGuidance(
    List<GuidanceNotification> notifications,
  ) async {
    if (!supportsScheduling) return;
    final ids = <int>{};
    for (final item in notifications) {
      if (item.platformId < 0 ||
          item.platformId > 0x7fffffff ||
          !ids.add(item.platformId)) {
        throw ArgumentError(
          'Every reminder needs a distinct signed-32-bit ID.',
        );
      }
    }
    await _initialize();
    try {
      await _cancelManagedPending(replacementIds: ids);
      for (final notification in notifications) {
        final coach = notification.kind == GuidanceNotificationKind.coachPlan;
        await _plugin.zonedSchedule(
          id: notification.platformId,
          title: notification.title,
          body: notification.body,
          // One-shot instants retain their meaning across DST gaps/repeats.
          scheduledDate: timezone.TZDateTime.from(
            notification.scheduledAt.toUtc(),
            timezone.UTC,
          ),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              coach ? 'tonyo_coach_plan' : 'tonyo_forecast_guidance',
              coach ? 'Daily Coach plan' : 'Forecast guidance',
              channelDescription: coach
                  ? 'Opt-in reminders for the scheduled steps in your daily Coach plan.'
                  : 'Opt-in reminders for predicted energy and recovery windows.',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
            ),
            macOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
            ),
            windows: const WindowsNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: notification.payload,
        );
      }
    } on Object catch (error, stack) {
      // A partially scheduled plan must not remain active behind an error UI.
      // Reconciliation is serialized, so cleanup cannot cancel a newer plan.
      try {
        await _cancelManagedPending();
      } on Object {
        /* preserve original failure */
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  @override
  Future<void> cancelGuidance() async {
    if (!supportsScheduling) return;
    await _serializeMutation(() async {
      await _initialize();
      await _cancelManagedPending();
    });
  }

  Future<void> _cancelManagedPending({
    Set<int> replacementIds = const {},
  }) async {
    final pending = await _plugin.pendingNotificationRequests();
    if (pending.any(
      (notification) =>
          replacementIds.contains(notification.id) &&
          !(notification.payload?.startsWith(_payloadPrefix) ?? false),
    )) {
      throw StateError(
        'A reminder ID is already used by an unrelated notification.',
      );
    }
    for (final notification in pending) {
      if (notification.payload?.startsWith(_payloadPrefix) ?? false) {
        await _plugin.cancel(id: notification.id);
      }
    }
  }
}
