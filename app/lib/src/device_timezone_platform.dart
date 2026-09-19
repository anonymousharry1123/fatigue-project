import 'package:flutter/services.dart';

const _channel = MethodChannel('tonyo/timezone');

Future<String?> readDeviceTimezone() async {
  try {
    return await _channel.invokeMethod<String>('getTimezone');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
