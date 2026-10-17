import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai1_protocol.dart';
import '../app_controller.dart';
import '../device_backup_service.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// Opening this screen never starts a plan, reads an export or saves a file.
class StudyToolsScreen extends StatefulWidget {
  const StudyToolsScreen({
    super.key,
    required this.controller,
    this.backupService = const DeviceBackupService(),
  });

  final AppController controller;
  final DeviceBackupService backupService;

  @override
  State<StudyToolsScreen> createState() => _StudyToolsScreenState();
}

class _StudyToolsScreenState extends State<StudyToolsScreen> {
  final _days = TextEditingController(text: '28');
  Ai1SleepSource _source = Ai1SleepSource.manual;
  bool _working = false;
  String? _message;
  bool _messageIsError = false;
  int? _resultRevision;
  String? _resultOwner;
  ({int opportunities, int outcomes, int pairs})? _summary;

  AppController get _controller => widget.controller;
  bool get _busy => _working || _controller.ai1CaptureBusy;
  int? get _dayCount => int.tryParse(_days.text);
  bool get _validDays =>
      _dayCount != null && _dayCount! >= 1 && _dayCount! <= 366;
  bool get _sessionAvailable =>
      !_controller.isSignedOut && _controller.canExportDeviceBackup;
  bool get _canStart =>
      !_busy &&
      _sessionAvailable &&
      _controller.ai1CaptureEnabled &&
      !_controller.ai1StudyActive &&
      _validDays;
  bool get _canAssess =>
      !_busy && _sessionAvailable && _controller.ai1StudyActive;
  bool get _showResult =>
      _sessionAvailable &&
      _controller.ai1CaptureEnabled &&
      _resultRevision == _controller.sessionRevision &&
      _resultOwner == _controller.cloudUid;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_discardStaleResults);
  }

  @override
  void didUpdateWidget(covariant StudyToolsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != _controller) {
      oldWidget.controller.removeListener(_discardStaleResults);
      _controller.addListener(_discardStaleResults);
      _summary = null;
      _message = null;
    }
  }

  void _discardStaleResults() {
    if (!_showResult || !_controller.ai1StudyActive) {
      _summary = null;
      if (!_showResult) _message = null;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_discardStaleResults);
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final active = _controller.ai1StudyActive && _sessionAvailable;
      final summary = _showResult && active ? _summary : null;
      return PopScope(
        canPop: !_working,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !_working,
            title: Text(context.tr('Local study tools')),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              key: const Key('study-tools-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                TonyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('A prospective measurement plan'),
                      Text(
                        context.tr(
                          'Optional and off by default. Keep new sleep and '
                          'check-in history on this device to review timing, '
                          'missing answers and usable days. This plan creates '
                          'no model predictions and does not train a model.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _sessionAvailable
                            ? context.tr(_controller.ai1StudyStatus)
                            : context.tr(
                                'Study tools are unavailable in this session.',
                              ),
                        key: const Key('study-plan-status'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (!_controller.ai1CaptureEnabled) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            'Enable “Keep local study history” in Privacy '
                            'center before starting a plan.',
                          ),
                        ),
                      ],
                      if (_controller.ai1CaptureError case final error?) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.tr(error),
                          key: const Key('study-capture-error'),
                          style: TextStyle(
                            color: TonyoPalette.of(context).error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TonyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        active
                            ? 'Saved study schedule'
                            : 'Plan starting tomorrow',
                      ),
                      Text(
                        context.tr(
                          'The plan fixes the timezone at start and uses '
                          'one sleep source. Use English Evening check-ins from '
                          '6 pm until before 10 pm. Sleep must be saved by '
                          '10 am. Open Tonyo from 10 am until before 10:15 am '
                          'for the morning snapshot; background execution '
                          'is not guaranteed. Unopened days still count.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr(
                          'For Apple Health, connect in Sleep Log and allow sleep reads before the morning cutoff.',
                        ),
                      ),
                      if (!active) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<Ai1SleepSource>(
                          key: const Key('study-source'),
                          initialValue: _source,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: context.tr('Sleep source'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: Ai1SleepSource.manual,
                              child: Text(context.tr('Manual sleep')),
                            ),
                            DropdownMenuItem(
                              value: Ai1SleepSource.appleHealth,
                              child: Text(context.tr('Apple Health')),
                            ),
                          ],
                          onChanged: _busy || active || !_sessionAvailable
                              ? null
                              : (value) => setState(() => _source = value!),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('study-days'),
                          controller: _days,
                          enabled: !_busy && !active && _sessionAvailable,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: context.tr('Calendar days'),
                            errorText: _validDays
                                ? null
                                : context.tr('Choose 1–366 calendar days.'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            '28 days is a scheduling convenience, not evidence '
                            'that enough data will be collected. Source and '
                            'dates cannot be changed after starting. To replace '
                            'the plan, clear local study history in Privacy center.',
                          ),
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                          ),
                        ),
                        if (_source == Ai1SleepSource.appleHealth &&
                            !active) ...[
                          const SizedBox(height: 8),
                          Text(
                            context.tr(
                              'Apple Health must be connected separately. '
                              'Missing Health sleep is not replaced with manual sleep.',
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          key: const Key('study-start'),
                          onPressed: _canStart ? _start : null,
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(context.tr('Start tomorrow’s plan')),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            'The saved source, timezone and dates are fixed. '
                            'To replace this plan, clear local study history '
                            'in Privacy center.',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TonyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader('Review local readiness'),
                      Text(
                        context.tr(
                          'Assess completed daily windows, including missed '
                          'days. Counts alone do not establish measurement '
                          'quality, study approval or readiness for modeling.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('study-assess'),
                        onPressed: _canAssess ? _assess : null,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(context.tr('Assess local readiness')),
                      ),
                      if (summary != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Column(
                            key: const Key('study-readiness-summary'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr(
                                  'Modeling readiness is not established.',
                                ),
                              ),
                              Text(
                                context.tr(
                                  'Closed opportunities: {count}',
                                  args: {'count': summary.opportunities},
                                ),
                              ),
                              Text(
                                context.tr(
                                  'Completed Energy outcomes: {count}',
                                  args: {'count': summary.outcomes},
                                ),
                              ),
                              Text(
                                context.tr(
                                  'Paired days: {count}',
                                  args: {'count': summary.pairs},
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('study-export'),
                        onPressed:
                            _canAssess && widget.backupService.isSupported
                            ? _export
                            : null,
                        icon: const Icon(Icons.save_alt_rounded),
                        label: Text(context.tr('Save private study export')),
                      ),
                      if (!widget.backupService.isSupported)
                        Text(
                          context.tr(
                            'Saving a private file is unavailable on this device.',
                          ),
                        ),
                      Text(
                        context.tr(
                          'The export contains sensitive, pseudonymous '
                          'measurements and a readiness report. No data is '
                          'saved to a file until you choose to export.',
                        ),
                        style: TextStyle(color: TonyoPalette.of(context).muted),
                      ),
                    ],
                  ),
                ),
                if (_working) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(key: Key('study-working')),
                ],
                if (_showResult && _message != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr(_message!),
                      key: const Key('study-action-message'),
                      style: TextStyle(
                        color: _messageIsError
                            ? TonyoPalette.of(context).error
                            : TonyoPalette.of(context).muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  bool _current(int revision, String? owner, AppController controller) =>
      mounted &&
      identical(controller, _controller) &&
      _sessionAvailable &&
      revision == _controller.sessionRevision &&
      owner == _controller.cloudUid;

  void _begin() => setState(() {
    _working = true;
    _message = null;
    _summary = null;
    _resultRevision = _controller.sessionRevision;
    _resultOwner = _controller.cloudUid;
  });

  void _showMessage(String value, {bool error = false}) => setState(() {
    _message = value;
    _messageIsError = error;
  });

  Future<void> _start() async {
    if (!_canStart) return;
    final controller = _controller;
    final revision = _controller.sessionRevision;
    final owner = _controller.cloudUid;
    final days = _dayCount!;
    _begin();
    try {
      await _controller.startAi1Study(source: _source, days: days);
      if (_current(revision, owner, controller)) {
        _showMessage('Study plan saved. The first opportunity is tomorrow.');
      }
    } on Object {
      if (_current(revision, owner, controller)) {
        _showMessage(
          'Could not start the study plan. Check local history and timezone, then try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _assess() {
    if (!_canAssess) return;
    _begin();
    try {
      final data = jsonDecode(_controller.exportAi1Study()) as Map;
      final coverage = (data['readiness'] as Map)['coverage'] as Map;
      int count(String key) {
        final value = coverage[key];
        if (value is! int || value < 0) {
          throw const FormatException('Invalid count.');
        }
        return value;
      }

      setState(
        () => _summary = (
          opportunities: count('opportunities'),
          outcomes: count('completedOutcomes'),
          pairs: count('pairedOutcomes'),
        ),
      );
    } on Object {
      _showMessage(
        'Could not assess local history. Please try again.',
        error: true,
      );
    } finally {
      setState(() => _working = false);
    }
  }

  Future<void> _export() async {
    if (!_canAssess || !widget.backupService.isSupported) return;
    final controller = _controller;
    final revision = _controller.sessionRevision;
    final owner = _controller.cloudUid;
    _begin();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('study-export-dialog'),
          scrollable: true,
          title: Text(dialogContext.tr('Save a private study copy?')),
          content: Text(
            dialogContext.tr(
              'This file contains sensitive sleep and self-report history '
              'with pseudonymous IDs. Choose an on-device folder to keep it '
              'local. Tonyo does not upload this export or copy it to the '
              'clipboard. The system picker may offer cloud locations. '
              'Deleting study history cannot recall saved or shared files.',
            ),
          ),
          actions: [
            TextButton(
              key: const Key('study-export-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.tr('Cancel')),
            ),
            FilledButton(
              key: const Key('study-export-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.tr('Choose private location')),
            ),
          ],
        ),
      );
      if (!_current(revision, owner, controller) ||
          !_controller.ai1StudyActive ||
          _controller.ai1CaptureBusy) {
        return;
      }
      if (confirmed != true) return;
      final json = _controller.exportAi1Study();
      if (!_current(revision, owner, controller)) return;
      final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      final saved = await widget.backupService.save(
        json: json,
        filename: 'tonyo-private-study-$stamp.json',
      );
      if (_current(revision, owner, controller)) {
        _showMessage(
          saved
              ? 'Private study export saved. Keep track of any copies you share.'
              : 'Export canceled. No file was saved.',
        );
      }
    } on Object {
      if (_current(revision, owner, controller)) {
        _showMessage(
          'Could not save the private study export. Please try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
