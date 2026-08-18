import 'package:flutter/services.dart';

import 'models.dart';

/// The permission workflow state reported by the platform Health integration.
///
/// Apple intentionally does not reveal which read-only HealthKit categories a
/// person approved. On iOS, [authorized] therefore means the system permission
/// sheet was completed, not that every requested category was granted.
enum HealthAuthorizationState {
  unavailable,
  notDetermined,
  authorized,
  denied,
  revoked,
  error,
}

class HealthPermissionInfo {
  const HealthPermissionInfo({
    required this.title,
    required this.detail,
    required this.iconName,
  });

  final String title;
  final String detail;
  final String iconName;
}

class HealthSyncException implements Exception {
  const HealthSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The read-only permission groups shown before opening Apple's category sheet.
const healthPermissions = <HealthPermissionInfo>[
  HealthPermissionInfo(
    title: 'Sleep',
    detail: 'Sleep timing and stages for recovery and forecast context.',
    iconName: 'sleep',
  ),
  HealthPermissionInfo(
    title: 'Heart',
    detail:
        'Heart-rate variability and resting heart rate for recovery trends and future personalization.',
    iconName: 'heart',
  ),
  HealthPermissionInfo(
    title: 'Workouts',
    detail:
        'Workout duration and daily steps for movement and training-load estimates.',
    iconName: 'workout',
  ),
  HealthPermissionInfo(
    title: 'Hydration',
    detail: 'Water samples for daily hydration and recovery context.',
    iconName: 'water',
  ),
];

class HealthService {
  const HealthService();

  static const _channel = MethodChannel('tonyo/health');

  Future<bool> isAvailable() async =>
      (await authorizationStatus()) != HealthAuthorizationState.unavailable;

  Future<HealthAuthorizationState> authorizationStatus() async {
    try {
      final value = await _channel.invokeMethod<String>('authorizationStatus');
      return _stateFromPlatform(value);
    } on MissingPluginException {
      return HealthAuthorizationState.unavailable;
    } on PlatformException {
      return HealthAuthorizationState.error;
    }
  }

  Future<HealthAuthorizationState> requestAuthorization() async {
    try {
      final value = await _channel.invokeMethod<String>('requestAuthorization');
      return _stateFromPlatform(value);
    } on MissingPluginException {
      return HealthAuthorizationState.unavailable;
    } on PlatformException {
      return HealthAuthorizationState.error;
    }
  }

  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<SignalReading>> sync() async {
    try {
      final result =
          await _channel.invokeListMethod<Map<Object?, Object?>>('sync') ??
          const [];
      return result.map((raw) {
        final json = raw.map((key, value) => MapEntry(key.toString(), value));
        return SignalReading.fromJson(json);
      }).toList();
    } on MissingPluginException {
      return [];
    } on PlatformException catch (error) {
      throw HealthSyncException(
        error.message ?? 'Apple Health heart data could not be read.',
      );
    }
  }

  Future<List<SignalReading>> syncSleep() async {
    try {
      final result =
          await _channel.invokeListMethod<Map<Object?, Object?>>('syncSleep') ??
          const [];
      return result.map((raw) {
        final json = raw.map((key, value) => MapEntry(key.toString(), value));
        return SignalReading.fromJson(json);
      }).toList();
    } on MissingPluginException {
      return [];
    } on PlatformException catch (error) {
      throw HealthSyncException(
        error.message ?? 'Apple Health sleep data could not be read.',
      );
    }
  }

  Future<List<SignalReading>> syncActivity() async {
    try {
      final result =
          await _channel.invokeListMethod<Map<Object?, Object?>>(
            'syncActivity',
          ) ??
          const [];
      return result.map((raw) {
        final json = raw.map((key, value) => MapEntry(key.toString(), value));
        return SignalReading.fromJson(json);
      }).toList();
    } on MissingPluginException {
      return [];
    } on PlatformException catch (error) {
      throw HealthSyncException(
        error.message ??
            'Apple Health workout, step, and hydration data could not be read.',
      );
    }
  }

  static HealthAuthorizationState _stateFromPlatform(String? value) =>
      switch (value) {
        'notDetermined' => HealthAuthorizationState.notDetermined,
        'authorized' => HealthAuthorizationState.authorized,
        'denied' => HealthAuthorizationState.denied,
        'revoked' => HealthAuthorizationState.revoked,
        'error' => HealthAuthorizationState.error,
        _ => HealthAuthorizationState.unavailable,
      };
}
