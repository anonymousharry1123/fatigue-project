import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

enum NotificationPermissionState { unknown, granted, denied, unavailable }

enum GuidanceNotificationKind { crash, recovery }

class GuidanceNotification {
  const GuidanceNotification({
    required this.id,
    required this.platformId,
    required this.kind,
    required this.scheduledAt,
    required this.title,
    required this.body,
    this.sourceRiskAlertIds = const [],
  });

  final String id;
  final int platformId;
  final GuidanceNotificationKind kind;
  final DateTime scheduledAt;
  final String title;
  final String body;
  final List<String> sourceRiskAlertIds;

  String get payload => 'tonyo-guidance:$id';
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

class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _payloadPrefix = 'tonyo-guidance:';
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

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

  Future<void> _initialize() async {
    if (_initialized || !supportsScheduling) return;
    timezone_data.initializeTimeZones();
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
    );
    _initialized = true;
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
    await _initialize();
    await _cancelManagedPending();
    for (final notification in notifications) {
      await _plugin.zonedSchedule(
        id: notification.platformId,
        title: notification.title,
        body: notification.body,
        scheduledDate: timezone.TZDateTime.from(
          notification.scheduledAt.toUtc(),
          timezone.UTC,
        ),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'tonyo_forecast_guidance',
            'Forecast guidance',
            channelDescription:
                'Opt-in reminders for predicted energy and recovery windows.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
          windows: WindowsNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: notification.payload,
      );
    }
  }

  @override
  Future<void> cancelGuidance() async {
    if (!supportsScheduling) return;
    await _initialize();
    await _cancelManagedPending();
  }

  Future<void> _cancelManagedPending() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.payload?.startsWith(_payloadPrefix) ?? false) {
        await _plugin.cancel(id: notification.id);
      }
    }
  }
}
