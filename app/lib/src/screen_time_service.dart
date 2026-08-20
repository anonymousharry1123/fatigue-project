import 'package:flutter/services.dart';

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
/// The platform channel intentionally exposes only authorization and report
/// presentation. Protected application, category, pickup, and web-domain data
/// never crosses into Flutter. Manual [SignalType.screenTime] readings remain
/// the model input and the only screen-time values Tonyo persists.
class ScreenTimeService {
  const ScreenTimeService();

  static const _channel = MethodChannel('tonyo/screen_time');

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
