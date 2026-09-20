import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Saves or opens a local snapshot through the system's file picker, without
/// an account or network connection. Neither action changes cloud sync state.
class DeviceBackupService {
  const DeviceBackupService();

  static const _channel = MethodChannel('tonyo/device_backup');

  bool get isSupported =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.macOS => true,
        _ => false,
      };

  /// Returns the selected UTF-8 JSON contents, or null when the picker is
  /// canceled. Native readers reject files over 20 MiB and invalid UTF-8 before
  /// returning. Callers must validate the backup before restoring any data.
  Future<String?> open() async {
    if (!isSupported) {
      throw PlatformException(
        code: 'backup_unsupported',
        message: 'Opening a backup is unavailable on this device.',
      );
    }
    try {
      return await _channel.invokeMethod<String>('open');
    } on MissingPluginException {
      throw PlatformException(
        code: 'backup_unsupported',
        message: 'Opening a backup is unavailable in this app build.',
      );
    }
  }

  /// Returns false when the user cancels. Failures throw instead of claiming
  /// that an unsaved backup was saved or deliberately canceled.
  Future<bool> save({required String json, required String filename}) async {
    if (!isSupported) {
      throw PlatformException(
        code: 'backup_unsupported',
        message: 'Saving a backup is unavailable on this device.',
      );
    }
    if (filename.trim().isEmpty ||
        !filename.endsWith('.json') ||
        RegExp(r'[/\\\x00-\x1f]').hasMatch(filename)) {
      throw ArgumentError.value(filename, 'filename', 'Use a JSON file name.');
    }
    try {
      final saved = await _channel.invokeMethod<bool>('save', {
        'json': json,
        'filename': filename,
      });
      if (saved == null) {
        throw PlatformException(
          code: 'backup_failed',
          message: 'The device did not confirm that the backup was saved.',
        );
      }
      return saved;
    } on MissingPluginException {
      throw PlatformException(
        code: 'backup_unsupported',
        message: 'Saving a backup is unavailable in this app build.',
      );
    }
  }
}
