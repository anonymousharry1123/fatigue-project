import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../device_backup_service.dart';

/// Explicit offline backup action shared by Profile and the privacy review gate.
/// Callers own the busy state; cloud sync must not block this local operation.
Future<void> saveDeviceBackup(
  BuildContext context,
  AppController controller,
  DeviceBackupService service,
) async {
  if (!controller.canExportDeviceBackup) return;
  final revision = controller.sessionRevision;
  final uid = controller.cloudUid;
  bool sessionIsCurrent() =>
      context.mounted &&
      controller.canExportDeviceBackup &&
      controller.sessionRevision == revision &&
      controller.cloudUid == uid;
  void showMessage(String message) {
    if (!sessionIsCurrent()) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> copyBackup() async {
    if (!sessionIsCurrent()) return;
    final copy = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('device-backup-copy-dialog'),
        scrollable: true,
        title: const Text('Copy device backup'),
        content: const Text(
          'Saving a file is unavailable on this platform. You can copy '
          'a JSON backup of the data on this device, including unsynced '
          'changes, and paste it into a file. No internet is needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('device-backup-copy-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Copy JSON'),
          ),
        ],
      ),
    );
    if (!sessionIsCurrent()) return;
    if (copy != true) {
      showMessage('Backup canceled. No file was saved.');
      return;
    }
    final json = await controller.exportDeviceBackup();
    if (!sessionIsCurrent()) return;
    await Clipboard.setData(ClipboardData(text: json));
    showMessage('Backup JSON copied. Paste it into a file to save it.');
  }

  try {
    if (!service.isSupported) {
      await copyBackup();
      return;
    }
    final json = await controller.exportDeviceBackup();
    if (!sessionIsCurrent()) return;
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    try {
      final saved = await service.save(
        json: json,
        filename: 'tonyo-device-backup-$timestamp.json',
      );
      showMessage(
        saved
            ? 'Device backup saved. Your pending changes can still sync.'
            : 'Backup canceled. No file was saved.',
      );
    } on PlatformException catch (error) {
      if (error.code != 'backup_unsupported') rethrow;
      await copyBackup();
    }
  } on Object {
    showMessage('Could not save device backup. Please try again.');
  }
}
