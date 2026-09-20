import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../device_backup_service.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({
    super.key,
    required this.controller,
    this.service = const DeviceBackupService(),
  });
  final AppController controller;
  final DeviceBackupService service;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final _input = TextEditingController();
  String? _raw;
  DeviceBackupPreview? _preview;
  bool _busy = false;
  bool _replace = false;
  bool _profile = false;
  bool _restored = false;
  String? _error;

  String _message(Object error) => switch (error) {
    FormatException() => error.message,
    StateError() => error.message,
    PlatformException() =>
      error.message ?? 'The backup file could not be read.',
    _ => 'Could not open or restore this backup. Please try again.',
  };

  void _previewData(String raw, {int source = 0}) {
    setState(() {
      _preview = null;
      _raw = null;
      _replace = false;
      _profile = false;
    });
    final preview = widget.controller.previewDeviceBackup(
      raw,
      sourceIndex: source,
    );
    setState(() {
      _raw = raw;
      _preview = preview;
      _replace = false;
      _profile = false;
      _error = null;
    });
  }

  Future<void> _open() async {
    if (_busy) return;
    final revision = widget.controller.sessionRevision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = await widget.service.open();
      if (!mounted || revision != widget.controller.sessionRevision) return;
      if (raw != null) _previewData(raw);
    } on Object catch (error) {
      if (mounted && revision == widget.controller.sessionRevision) {
        setState(() {
          _preview = null;
          _raw = null;
          _replace = false;
          _profile = false;
          _error = _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    if (_busy) return;
    final revision = widget.controller.sessionRevision;
    _input.clear();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste backup JSON'),
        scrollable: true,
        content: TextField(
          controller: _input,
          key: const Key('backup-import-json'),
          minLines: 4,
          maxLines: 10,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Tonyo device backup',
            hintText: 'Paste the contents of your backup file',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('backup-import-preview'),
            onPressed: () => Navigator.pop(context, _input.text),
            child: const Text('Preview'),
          ),
        ],
      ),
    );
    if (!mounted || revision != widget.controller.sessionRevision) return;
    if (raw != null) {
      try {
        _previewData(raw);
      } on Object catch (error) {
        setState(() => _error = _message(error));
      }
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final preview = _preview;
    if (_busy || preview == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.restoreDeviceBackup(
        preview,
        replaceExisting: _replace,
        restoreProfile: _profile,
      );
      if (mounted) setState(() => _restored = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final changes = preview == null
        ? 0
        : preview.newRecords +
              (_replace ? preview.differingRecords : 0) +
              (_profile ? 1 : 0);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Restore from backup'),
          automaticallyImplyLeading: !_busy,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Choose a Tonyo backup to review before restoring. Existing '
                'records stay on this device. Identical records are skipped.',
              ),
              const SizedBox(height: 16),
              if (!_restored) ...[
                if (widget.service.isSupported)
                  FilledButton.icon(
                    key: const Key('backup-import-open'),
                    onPressed: _busy ? null : _open,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Open backup file'),
                  ),
                OutlinedButton.icon(
                  key: const Key('backup-import-paste'),
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(Icons.paste_rounded),
                  label: const Text('Paste backup JSON'),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: TonyoPalette.of(context).error),
                    ),
                  ),
                ),
              if (_restored) ...[
                const SizedBox(height: 16),
                const Text(
                  'Backup restored to this device.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.controller.hasAnyPendingCloudChanges
                      ? 'Your changes are saved. Pending uploads will retry when connected.'
                      : 'Your selected data has been saved.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ] else if (preview != null) ...[
                const SizedBox(height: 16),
                TonyoCard(
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Backup preview',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        if (preview.sourceLabels.length > 1) ...[
                          const Text('Choose which saved copy to restore:'),
                          for (var i = 0; i < preview.sourceLabels.length; i++)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(preview.sourceLabels[i]),
                              value: preview.sourceIndex == i,
                              onChanged: _busy
                                  ? null
                                  : (_) {
                                      try {
                                        _previewData(_raw!, source: i);
                                      } on Object catch (error) {
                                        setState(
                                          () => _error = _message(error),
                                        );
                                      }
                                    },
                            ),
                        ],
                        Text(
                          '${preview.signalCount} activity and sleep records · '
                          '${preview.checkInCount} check-ins · ${preview.outcomeCount} outcomes · '
                          '${preview.coachCount} Coach actions',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${preview.newRecords} new records\n${preview.duplicates} already saved\n'
                          '${preview.differingRecords} with different saved values',
                        ),
                        if (preview.differingRecords > 0)
                          CheckboxListTile(
                            key: const Key('backup-import-replace'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Replace differing records with backup values',
                            ),
                            subtitle: const Text(
                              'Leave unchecked to keep the values on this device.',
                            ),
                            value: _replace,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _replace = value!),
                          ),
                        if (preview.profileDiffers)
                          CheckboxListTile(
                            key: const Key('backup-import-profile'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Restore profile for ${preview.profileName}',
                            ),
                            subtitle: const Text(
                              'Includes name, goals and sleep schedule.',
                            ),
                            value: _profile,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _profile = value!),
                          ),
                        if (preview.skippedOutcomes > 0)
                          Text(
                            '${preview.skippedOutcomes} outcomes cannot be restored because their '
                            'Outcome learning consent differs from this account’s current choices.',
                          ),
                        const SizedBox(height: 10),
                        Text(
                          'Privacy choices, Health access, notification permissions, '
                          'and old deletion requests are not imported.',
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                          ),
                        ),
                        if (preview.skippedCoachActions > 0)
                          Text(
                            '${preview.skippedCoachActions} older Coach actions lack their original '
                            'plan or alert records and cannot be restored from this copy.',
                          ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('backup-import-confirm'),
                          onPressed: _busy || changes == 0 ? null : _restore,
                          icon: const Icon(Icons.restore_rounded),
                          label: Text(
                            _busy ? 'Restoring…' : 'Restore selected data',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  try {
                                    _previewData(
                                      _raw!,
                                      source: preview.sourceIndex,
                                    );
                                  } on Object catch (error) {
                                    setState(() => _error = _message(error));
                                  }
                                },
                          child: const Text('Refresh preview'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
