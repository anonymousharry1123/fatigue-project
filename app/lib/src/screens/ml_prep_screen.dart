import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../ml_prep_models.dart';
import '../ml_prep_service.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// Preparation and model refresh are separate, explicit foreground actions.
class MlPrepScreen extends StatefulWidget {
  const MlPrepScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<MlPrepScreen> createState() => _MlPrepScreenState();
}

class _MlPrepScreenState extends State<MlPrepScreen> {
  final _timezone = TextEditingController(text: 'America/Los_Angeles');
  DateTime _endDay = DateTime.now();
  PrepRun? _run;
  int? _runRevision;
  String? _error;
  bool _busy = false;
  bool _modelBusy = false;

  bool get _refreshingModel =>
      _modelBusy || widget.controller.isRefreshingPersonalizedModel;

  bool _isCurrentRun(PrepRun run) =>
      _runRevision == widget.controller.modelPreparationRevision &&
      run.snapshot.uid == widget.controller.cloudUid;

  @override
  void initState() {
    super.initState();
    final window = widget.controller.lastModelPreparationWindow;
    if (window != null) {
      final last = window.localTime(
        window.end.subtract(const Duration(seconds: 1)),
      );
      _endDay = DateTime(last.year, last.month, last.day);
      _timezone.text = window.timezone;
    }
  }

  @override
  void dispose() {
    _timezone.dispose();
    super.dispose();
  }

  String _date(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Future<void> _chooseEndDay() async {
    if (_busy || _refreshingModel) return;
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDay,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Last date of the 30-day window',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _endDay = selected;
      _run = null;
      _error = null;
    });
  }

  Future<void> _prepare({bool refresh = false}) async {
    if (_busy || _refreshingModel) return;
    setState(() {
      _busy = true;
      _error = null;
      _run = null;
    });
    try {
      final window = PrepWindow.endingOn(
        _endDay,
        timezone: _timezone.text.trim(),
      );
      final result = await widget.controller.prepareModelSnapshot(
        window: window,
        refresh: refresh,
      );
      if (mounted) {
        setState(() {
          _run = result;
          _runRevision = widget.controller.modelPreparationRevision;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshModel() async {
    final run = _run;
    if (_busy ||
        _refreshingModel ||
        run == null ||
        !_isCurrentRun(run) ||
        !run.report.energyReady ||
        widget.controller.personalizedModelBlocker != null) {
      return;
    }
    setState(() {
      _modelBusy = true;
      _error = null;
    });
    try {
      await widget.controller.refreshPersonalizedModel(
        window: run.snapshot.window,
      );
    } on Object {
      if (mounted) {
        setState(() {
          _error =
              'The Energy model could not be refreshed. Deterministic scoring '
              'remains available. Check the model status, then try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _modelBusy = false);
    }
  }

  Future<void> _exportReport(PrepRun run) async {
    final json = const JsonEncoder.withIndent('  ').convert({
      'report': run.report.toJson(),
      'database': {
        'cacheHit': run.cacheHit,
        'collectionQueries': run.collectionQueries,
        'metadataReads': run.metadataReads,
        'returnedDocuments': run.returnedDocuments,
        'writes': 0,
      },
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local preparation report'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contains private account-derived information. Nothing is '
                  'uploaded. Copy only if you want to export this report.',
                ),
                const SizedBox(height: 12),
                SelectableText(json, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copy JSON'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final blocker = widget.controller.modelPreparationBlocker;
      final actionsBusy = _busy || _refreshingModel;
      final canPrepare = !actionsBusy && blocker == null;
      final run = _run;
      final modelBlocker = widget.controller.personalizedModelBlocker;
      final canRefreshModel =
          !actionsBusy &&
          run != null &&
          _isCurrentRun(run) &&
          run.report.energyReady &&
          modelBlocker == null;
      final startDay = DateTime(_endDay.year, _endDay.month, _endDay.day - 29);
      return Scaffold(
        appBar: AppBar(title: const Text('Model preparation')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              const Text(
                'Version 0.32 prep · read-only',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Inspect exactly 30 days from your signed-in account. Preparing '
                'a snapshot does not train a model, change confidence, enable consent, '
                'or upload training rows.',
                style: TextStyle(color: TonyoColors.muted),
              ),
              if (blocker != null) ...[
                const SizedBox(height: 16),
                _notice(blocker),
              ],
              const SectionHeader('Choose the account window'),
              OutlinedButton.icon(
                key: const Key('prep-window-end'),
                onPressed: actionsBusy ? null : _chooseEndDay,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('Window ends ${_date(_endDay)}'),
              ),
              const SizedBox(height: 8),
              Text('${_date(startDay)} through ${_date(_endDay)} · 30 dates'),
              const SizedBox(height: 14),
              TextField(
                key: const Key('prep-timezone'),
                controller: _timezone,
                enabled: !actionsBusy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Window timezone (IANA name)',
                  helperText: 'For example America/Los_Angeles or UTC',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {
                  _run = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('prepare-model-snapshot'),
                onPressed: canPrepare ? () => _prepare() : null,
                icon: const Icon(Icons.dataset_outlined),
                label: const Text('Prepare / inspect 30-day snapshot'),
              ),
              OutlinedButton.icon(
                key: const Key('refresh-model-snapshot'),
                onPressed: canPrepare ? () => _prepare(refresh: true) : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh from Firebase'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Prepare reuses the saved snapshot when valid. Refresh '
                'explicitly checks Firebase again. No automatic refresh or '
                'background queries.',
                style: TextStyle(color: TonyoColors.muted, fontSize: 12),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Preparing bounded account coverage…'),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _notice(_error!),
              ],
              const SectionHeader('Personalized Energy model'),
              TonyoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.controller.personalizedModelStatus,
                      key: const Key('personalized-energy-model-status'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Refresh trains a tiny Energy model on this device using '
                      'only the prepared snapshot. It requires at least 14 '
                      'genuine, consented labeled days. Preparing or opening '
                      'this screen never starts training.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The newest 20% of labeled days (at least 3 days) stay '
                      'out of training. The model is accepted only if its '
                      'holdout error improves by at least 5%. Corrections are '
                      'limited to ±10 score points and shrink for missing or '
                      'stale inputs.',
                      style: TextStyle(color: TonyoColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Refresh is explicit, at most once per 24 hours, and '
                      'requires a new eligible outcome. Weights and training '
                      'rows stay on-device; an accepted change sends only one '
                      'small metadata update to Firebase, not your full account.',
                      style: TextStyle(color: TonyoColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Deterministic scoring remains the fallback. Cognitive '
                      'is not personalized, and this does not boost confidence.',
                      style: TextStyle(color: TonyoColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (modelBlocker != null && modelBlocker != blocker)
                _notice(modelBlocker)
              else if (modelBlocker == null &&
                  (run == null || !_isCurrentRun(run)))
                _notice(
                  'Prepare a current snapshot before refreshing the model.',
                )
              else if (modelBlocker == null &&
                  run != null &&
                  !run.report.energyReady)
                _notice(
                  'This snapshot is not ready for Energy training. Review '
                  'the readiness reasons below; deterministic scoring continues.',
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('refresh-personalized-energy-model'),
                onPressed: canRefreshModel ? _refreshModel : null,
                icon: const Icon(Icons.tune_rounded),
                label: Text(
                  _refreshingModel
                      ? 'Refreshing Energy model…'
                      : 'Refresh Energy model',
                ),
              ),
              if (_refreshingModel) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (_run case final result?)
                if (_isCurrentRun(result))
                  ..._report(result)
                else ...[
                  const SizedBox(height: 16),
                  _notice(
                    'Account data or consent changed. Prepare again to '
                    'inspect a current snapshot.',
                  ),
                ],
            ],
          ),
        ),
      );
    },
  );

  Widget _notice(String text) => TonyoCard(
    child: Text(text, style: const TextStyle(color: TonyoColors.muted)),
  );

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  String _label(String value) => value
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ');

  List<Widget> _report(PrepRun run) {
    final report = run.report.toJson();
    final counts = _map(report['counts']);
    final readiness = _map(report['readiness']);
    final missingness = _map(report['featureMissingness']);
    final provenance = _map(report['provenance']);
    final rejected = report['rejectedRows'] as List? ?? const [];
    final rejectedCounts = <String, int>{};
    for (final row in rejected) {
      final reason = _map(row)['reason']?.toString() ?? 'unspecified';
      rejectedCounts.update(reason, (count) => count + 1, ifAbsent: () => 1);
    }
    return [
      const SectionHeader('Snapshot and read budget'),
      TonyoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              run.cacheHit
                  ? 'Saved snapshot reused'
                  : 'Account snapshot fetched',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('Fetched at ${run.snapshot.fetchedAt.toIso8601String()}'),
            const SizedBox(height: 8),
            Text(
              'This run: ${run.collectionQueries}/3 collection queries · '
              '${run.metadataReads}/1 user-document reads · 0 writes',
            ),
            for (final entry in run.returnedDocuments.entries)
              Text('${_label(entry.key)} documents returned: ${entry.value}'),
            const SizedBox(height: 8),
            const Text(
              'Caps: 1,500 signals, 100 check-ins, 100 outcomes. Request '
              'counts are not billed reads; rule, index and minimum-query '
              'charges may also apply. Remote edits require explicit refresh.',
              style: TextStyle(color: TonyoColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      const SectionHeader('Account coverage'),
      _entriesCard(counts),
      const SectionHeader('Model readiness'),
      for (final head in ['energy', 'cognitive']) ...[
        _readinessCard(head, _map(readiness[head])),
        const SizedBox(height: 10),
      ],
      _notice(
        'Coverage inspection is allowed with consent off, but training '
        'examples require both consent flags. Synthetic and uncertain rows '
        'do not count toward readiness. FatigueEngine remains active.',
      ),
      const SectionHeader('Source provenance'),
      for (final entry in provenance.entries) ...[
        Text(_label(entry.key)),
        const SizedBox(height: 6),
        _entriesCard(_map(entry.value)),
        const SizedBox(height: 10),
      ],
      const SectionHeader('Feature missingness'),
      for (final head in missingness.entries) ...[
        Text(_label(head.key)),
        const SizedBox(height: 6),
        _entriesCard({
          for (final feature in _map(head.value).entries)
            feature.key:
                '${_map(feature.value)['missing'] ?? 0} missing / '
                '${_map(feature.value)['total'] ?? 0} examples',
        }),
        const SizedBox(height: 10),
      ],
      const SectionHeader('Rejected rows'),
      rejectedCounts.isEmpty
          ? const Text('No rejected rows reported.')
          : _entriesCard(rejectedCounts),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: _refreshingModel ? null : () => _exportReport(run),
        icon: const Icon(Icons.file_download_outlined),
        label: const Text('View / copy local JSON report'),
      ),
    ];
  }

  Widget _entriesCard(Map<String, dynamic> entries) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entries.isEmpty) const Text('No data in this section.'),
        for (final entry in entries.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text('${_label(entry.key)}: ${entry.value}'),
          ),
      ],
    ),
  );

  Widget _readinessCard(String head, Map<String, dynamic> status) {
    final reasons = status['reasons'] as List? ?? const [];
    final trainingDays = status['trainingDays'] as List? ?? const [];
    final holdoutDays = status['holdoutDays'] as List? ?? const [];
    final title = '${head[0].toUpperCase()}${head.substring(1)}';
    return TonyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: ${status['ready'] == true ? 'snapshot data-ready' : 'not ready'}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final reason in reasons) Text('• ${_label(reason.toString())}'),
          const SizedBox(height: 8),
          Text(
            '${trainingDays.length} training days · '
            '${holdoutDays.length} newest holdout days',
          ),
          if (holdoutDays.isNotEmpty)
            Text('Holdout: ${holdoutDays.join(', ')}'),
        ],
      ),
    );
  }
}
