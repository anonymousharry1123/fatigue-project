import 'package:flutter/services.dart';

enum ScreenTimeSyncAvailability {
  unavailable,
  unsupportedOS,
  entitlementRequired,
  notDetermined,
  authorized,
  denied,
  regionUnavailable,
  error,
}

extension ScreenTimeSyncAvailabilityInfo on ScreenTimeSyncAvailability {
  bool get canRequest =>
      this == ScreenTimeSyncAvailability.authorized ||
      this == ScreenTimeSyncAvailability.notDetermined ||
      this == ScreenTimeSyncAvailability.denied ||
      this == ScreenTimeSyncAvailability.error;

  String get message => switch (this) {
    ScreenTimeSyncAvailability.authorized =>
      'Apple data access is allowed. Daily totals can sync automatically.',
    ScreenTimeSyncAvailability.notDetermined =>
      'Allow Apple Screen Time data access to import daily totals.',
    ScreenTimeSyncAvailability.denied =>
      'Screen Time data access was not granted. Reconnect to allow it, or continue with manual entry.',
    ScreenTimeSyncAvailability.entitlementRequired =>
      'Automatic sync is not available in this build yet. Apple approval is required.',
    ScreenTimeSyncAvailability.unsupportedOS =>
      'Automatic Screen Time sync requires iOS 26.4 or later.',
    ScreenTimeSyncAvailability.regionUnavailable =>
      'Apple limits this sync to eligible EU devices and Apple Accounts. Manual entry is available here.',
    ScreenTimeSyncAvailability.unavailable =>
      'Automatic Apple Screen Time sync is unavailable on this device.',
    ScreenTimeSyncAvailability.error =>
      'Screen Time access could not be checked. Try connecting again.',
  };
}

/// Only daily totals from Apple's separately authorized data-access API.
/// The private DeviceActivityReport extension never exports its data.
class ScreenTimeDailyTotal {
  const ScreenTimeDailyTotal({
    required this.day,
    required this.seconds,
    required this.updatedAt,
  });

  final DateTime day;
  final double seconds;
  final DateTime updatedAt;

  factory ScreenTimeDailyTotal.fromPlatform(Map<Object?, Object?> value) {
    final dayText = value['day'] as String;
    final day = DateTime.parse(dayText);
    final seconds = (value['seconds'] as num).toDouble();
    final updatedAt = DateTime.parse(value['updatedAt'] as String).toLocal();
    final end = DateTime(day.year, day.month, day.day + 1);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dayText) ||
        day.toIso8601String().substring(0, 10) != dayText ||
        !seconds.isFinite ||
        seconds < 0 ||
        seconds > end.difference(day).inSeconds ||
        updatedAt.isBefore(day)) {
      throw const FormatException('Invalid Apple Screen Time daily total.');
    }
    return ScreenTimeDailyTotal(
      day: day,
      seconds: seconds,
      updatedAt: updatedAt,
    );
  }
}

/// Authorization state for Apple's entitlement-gated Device Activity report.
enum ScreenTimeAuthorizationState {
  unavailable,
  entitlementRequired,
  notDetermined,
  authorized,
  denied,
  error,
}

/// Opens Apple's privacy-preserving Device Activity report.
///
/// Report presentation is separate from the opt-in, entitlement-gated daily
/// total importer. Application, category, pickup, and web-domain data never
/// crosses into Flutter.
class ScreenTimeService {
  const ScreenTimeService();

  static const _channel = MethodChannel('tonyo/screen_time');

  Future<ScreenTimeSyncAvailability> syncAvailability() =>
      _syncState('syncAvailability');

  Future<ScreenTimeSyncAvailability> requestSyncAuthorization() =>
      _syncState('requestSyncAuthorization');

  Future<ScreenTimeSyncAvailability> _syncState(String method) async {
    try {
      final value = await _channel.invokeMethod<String>(method);
      return ScreenTimeSyncAvailability.values.firstWhere(
        (state) => state.name == value,
        orElse: () => ScreenTimeSyncAvailability.unavailable,
      );
    } on MissingPluginException {
      return ScreenTimeSyncAvailability.unavailable;
    } on PlatformException {
      return ScreenTimeSyncAvailability.error;
    }
  }

  Future<List<ScreenTimeDailyTotal>> readDailyTotals() async {
    final rows = await _channel.invokeListMethod<Object?>('readDailyTotals');
    if (rows == null) {
      throw const FormatException('Apple Screen Time returned no response.');
    }
    return rows
        .map(
          (row) => ScreenTimeDailyTotal.fromPlatform(
            (row as Map).cast<Object?, Object?>(),
          ),
        )
        .toList();
  }

  Future<ScreenTimeAuthorizationState> authorizationStatus() async {
    try {
      final value = await _channel.invokeMethod<String>('authorizationStatus');
      return _stateFromPlatform(value);
    } on MissingPluginException {
      return ScreenTimeAuthorizationState.unavailable;
    } on PlatformException {
      return ScreenTimeAuthorizationState.error;
    }
  }

  Future<ScreenTimeAuthorizationState> requestAuthorization() async {
    try {
      final value = await _channel.invokeMethod<String>('requestAuthorization');
      return _stateFromPlatform(value);
    } on MissingPluginException {
      return ScreenTimeAuthorizationState.unavailable;
    } on PlatformException {
      return ScreenTimeAuthorizationState.error;
    }
  }

  Future<bool> showReport() async {
    try {
      return await _channel.invokeMethod<bool>('showReport') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static ScreenTimeAuthorizationState _stateFromPlatform(String? value) =>
      switch (value) {
        'entitlementRequired' =>
          ScreenTimeAuthorizationState.entitlementRequired,
        'notDetermined' => ScreenTimeAuthorizationState.notDetermined,
        'authorized' => ScreenTimeAuthorizationState.authorized,
        'denied' => ScreenTimeAuthorizationState.denied,
        'error' => ScreenTimeAuthorizationState.error,
        _ => ScreenTimeAuthorizationState.unavailable,
      };
}
