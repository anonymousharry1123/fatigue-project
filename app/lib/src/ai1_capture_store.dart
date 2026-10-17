import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const ai1CaptureMaximumBytes = 4 * 1024 * 1024;

/// Private device storage for prospective capture evidence. This store neither
/// synchronizes its contents nor turns a saved journal into training approval.
abstract interface class Ai1CaptureStore {
  Future<bool> isAvailable();
  Future<String?> read(String owner);

  /// Completes after the native file replacement and flush. The returned time
  /// is measured by the native clock after completion, never before the write.
  Future<DateTime> write(String owner, String value);
  Future<void> clear(String owner);
  Future<void> clearAll();
}

class MethodChannelAi1CaptureStore implements Ai1CaptureStore {
  const MethodChannelAi1CaptureStore();

  static const _channel = MethodChannel('tonyo/ai1_capture');
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> isAvailable() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String?> read(String owner) async {
    _requireSupported();
    _validateOwner(owner);
    final value = await _channel.invokeMethod<String>('read', {'owner': owner});
    if (value != null) _validateValue(value);
    return value;
  }

  @override
  Future<DateTime> write(String owner, String value) async {
    _requireSupported();
    _validateOwner(owner);
    _validateValue(value);
    final receipt = await _channel.invokeMethod<String>('write', {
      'owner': owner,
      'value': value,
    });
    final completedAt = receipt == null ? null : DateTime.tryParse(receipt);
    if (completedAt == null ||
        !completedAt.isUtc ||
        !receipt!.endsWith('Z') ||
        completedAt.toIso8601String() != receipt) {
      throw StateError('The device did not confirm the capture save time.');
    }
    return completedAt;
  }

  @override
  Future<void> clear(String owner) async {
    if (!_supported) return;
    _validateOwner(owner);
    try {
      await _channel.invokeMethod<void>('clear', {'owner': owner});
    } on MissingPluginException {
      // Unsupported platforms cannot have created this native journal.
    }
  }

  @override
  Future<void> clearAll() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('clearAll');
    } on MissingPluginException {
      // Ordinary account reset must also work without this optional plugin.
    }
  }

  static void _requireSupported() {
    if (!_supported) {
      throw PlatformException(
        code: 'capture_unsupported',
        message: 'Local history is unavailable on this device.',
      );
    }
  }

  static void _validateOwner(String owner) {
    if (owner.trim().isEmpty || owner.length > 200) {
      throw const FormatException('Invalid capture storage owner.');
    }
  }

  static void _validateValue(String value) {
    if (utf8.encode(value).length > ai1CaptureMaximumBytes) {
      throw const FormatException('Capture history exceeds the storage limit.');
    }
    if (jsonDecode(value) is! Map<String, dynamic>) {
      throw const FormatException('Capture history must be a JSON object.');
    }
  }
}
