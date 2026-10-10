import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../device_backup_service.dart';
import '../l10n/app_localizations.dart';
import '../research_export.dart';
import '../widgets/common_widgets.dart';

class ResearchExportScreen extends StatefulWidget {
  const ResearchExportScreen({
    super.key,
    required this.controller,
    this.service = const DeviceBackupService(),
  });
  final AppController controller;
  final DeviceBackupService service;

  @override
  State<ResearchExportScreen> createState() => _ResearchExportScreenState();
}

class _ResearchExportScreenState extends State<ResearchExportScreen> {
  final _code = TextEditingController();
  ResearchExportBundle? _bundle;
  int? _revision;
  String? _owner;
  String? _status;
  bool _busy = false;

  bool get _current =>
      widget.controller.canExportDeviceBackup &&
      _revision == widget.controller.sessionRevision &&
      _owner == widget.controller.cloudUid;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final ready = _current ? _bundle : null;
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Research export'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TonyoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('A private measurement table'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr(
                      'Export saved device check-ins, including partial answers and pending edits. Names, account IDs and notes are excluded. Dates and wellness records remain sensitive; this is not anonymous data.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr(
                      'Use a study code, not your name or email. Keep any identity key separately. Nothing is uploaded by this export.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('research-study-code'),
                    controller: _code,
                    enabled: !_busy && widget.controller.canExportDeviceBackup,
                    maxLength: 32,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: context.tr('Study code'),
                      hintText: 'P001',
                    ),
                    onChanged: (_) => setState(() {
                      _bundle = null;
                      _status = null;
                    }),
                  ),
                  FilledButton.icon(
                    key: const Key('research-prepare'),
                    onPressed: _busy || !widget.controller.canExportDeviceBackup
                        ? null
                        : _prepare,
                    icon: const Icon(Icons.table_view_outlined),
                    label: Text(context.tr('Prepare research export')),
                  ),
                  if (!widget.controller.canExportDeviceBackup)
                    Text(
                      context.tr(
                        'Device data is unavailable for this account.',
                      ),
                    ),
                ],
              ),
            ),
            if (ready != null) ...[
              const SizedBox(height: 16),
              TonyoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr(
                        '{rows} responses · {partial} partial · {pairs} sleep pairs · {excluded} excluded',
                        args: {
                          'rows': ready.responseCount,
                          'partial': ready.partialCount,
                          'pairs': ready.pairedCount,
                          'excluded': ready.excludedCount,
                        },
                      ),
                      key: const Key('research-export-summary'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr(
                        'JSON includes the data dictionary, exact questionnaire definitions and sleep provenance. CSV contains the response table; empty cells mean missing.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr(
                        'Sleep pairs are descriptive matches using records available now, not approved research joins or prediction features. Repeated submissions remain separate rows.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr(
                        'This prepared snapshot does not update automatically. Prepare again to include later changes.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (widget.service.isSupported)
                      FilledButton.icon(
                        key: const Key('research-save-json'),
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save_alt_rounded),
                        label: Text(context.tr('Save research JSON')),
                      ),
                    OutlinedButton(
                      key: const Key('research-copy-csv'),
                      onPressed: _busy ? null : () => _copy(csv: true),
                      child: Text(context.tr('Copy research CSV')),
                    ),
                    OutlinedButton(
                      key: const Key('research-copy-json'),
                      onPressed: _busy ? null : () => _copy(csv: false),
                      child: Text(context.tr('Copy research JSON')),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _bundle = null),
                      child: Text(
                        context.tr('Dismiss export from this screen'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                context.tr(_status!),
                key: const Key('research-export-status'),
              ),
            ],
          ],
        ),
      );
    },
  );

  void _prepare() {
    if (!widget.controller.canExportDeviceBackup) return;
    try {
      final bundle = ResearchExport.build(
        checkIns: widget.controller.checkIns,
        signals: widget.controller.signals,
        studyCode: _code.text.trim(),
        generatedAt: widget.controller.currentTime,
      );
      setState(() {
        _bundle = bundle;
        _revision = widget.controller.sessionRevision;
        _owner = widget.controller.cloudUid;
        _status = null;
      });
    } on ArgumentError {
      setState(
        () => _status =
            'Use a study code of 1–32 letters, numbers, - or _, starting with a letter.',
      );
    } on Object {
      setState(
        () => _status =
            'Could not prepare the research export. Please try again.',
      );
    }
  }

  Future<void> _save() async {
    if (_busy || !_current || _bundle == null) return;
    final bundle = _bundle!;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final saved = await widget.service.save(
        json: bundle.json,
        filename:
            'tonyo-research-${widget.controller.currentTime.toUtc().millisecondsSinceEpoch}.json',
      );
      if (mounted && _current) {
        setState(
          () => _status = saved
              ? 'Research JSON saved.'
              : 'Export canceled. No file was saved.',
        );
      }
    } on Object {
      if (mounted && _current) {
        setState(
          () => _status =
              'Could not save the research export. Retry or use Copy JSON.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy({required bool csv}) async {
    if (_busy || !_current || _bundle == null) return;
    final bundle = _bundle!;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(context.tr('Copy sensitive research data?')),
          content: Text(
            context.tr(
              'Other apps may read your clipboard. Copy only when you are ready to paste into a private file.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              key: const Key('research-copy-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Copy')),
            ),
          ],
        ),
      );
      if (!mounted || !_current || confirmed != true) return;
      await Clipboard.setData(
        ClipboardData(text: csv ? bundle.csv : bundle.json),
      );
      if (mounted && _current) {
        setState(
          () => _status = 'Research data copied. Paste into a private file.',
        );
      }
    } on Object {
      if (mounted && _current) {
        setState(
          () => _status = 'Could not copy the research data. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
