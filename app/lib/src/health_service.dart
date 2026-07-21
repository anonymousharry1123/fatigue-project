import 'package:flutter/services.dart';

import 'models.dart';

class HealthService {
  const HealthService();

  static const _channel = MethodChannel('tonyo/health');

  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestAuthorization() async {
    try {
      return await _channel.invokeMethod<bool>('requestAuthorization') ?? false;
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
    } on PlatformException {
      return [];
    }
  }
}
