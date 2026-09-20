import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class SyncConflictScreen extends StatefulWidget {
  const SyncConflictScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SyncConflictScreen> createState() => _SyncConflictScreenState();
}

class _SyncConflictScreenState extends State<SyncConflictScreen> {
  InputConflictReview? _review;
  final Map<String, bool> _choices = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _review = null;
      _choices.clear();
    });
    try {
      final review = await widget.controller.reviewInputConflicts();
      if (mounted) setState(() => _review = review);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final review = _review;
    if (_saving || review == null || _choices.length != review.items.length) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.resolveInputConflicts(review, _choices);
      if (!mounted) return;
      final pending =
          widget.controller.hasPendingCloudChanges ||
          widget.controller.cloudSyncError != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending
                ? 'Choices saved on this device. Cloud sync still needs attention.'
                : 'Your choices are saved and synced.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _message(Object error) => error is StateError
      ? error.message
      : 'Could not reach your cloud account. Check your connection and refresh the review.';

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Review sync changes')),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  key: const Key('sync-conflict-list'),
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (review != null) ...[
                      Text(
                        review.items.isEmpty
                            ? 'No conflicting items remain.'
                            : 'Choose the version to keep for each item.',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Other phone edits and records from your cloud account are kept. '
                        'Nothing is replaced until you save your choices.',
                        style: TextStyle(color: TonyoPalette.of(context).muted),
                      ),
                      const SizedBox(height: 16),
                      for (final item in review.items) ...[
                        _ConflictCard(
                          item: item,
                          selection: _choices[item.key],
                          onSelect: _saving
                              ? null
                              : (value) =>
                                    setState(() => _choices[item.key] = value),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: TonyoPalette.of(context).warning,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (review != null) ...[
                      Text(
                        '${_choices.length} of ${review.items.length} choices made',
                        key: const Key('sync-conflict-progress'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('sync-conflict-save'),
                        onPressed:
                            _saving || _choices.length != review.items.length
                            ? null
                            : _save,
                        child: Text(
                          _saving
                              ? 'Saving choices…'
                              : review.items.isEmpty
                              ? 'Merge and retry sync'
                              : 'Save choices and sync',
                        ),
                      ),
                    ],
                    OutlinedButton.icon(
                      key: const Key('sync-conflict-refresh'),
                      onPressed: _saving ? null : _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh review'),
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Decide later'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.item,
    required this.selection,
    required this.onSelect,
  });
  final InputConflictItem item;
  final bool? selection;
  final ValueChanged<bool>? onSelect;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            item.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'On this phone',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(item.phoneDescription),
        const SizedBox(height: 8),
        _choice(true),
        const Divider(height: 32),
        const Text(
          'In your cloud account',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(item.cloudDescription),
        const SizedBox(height: 8),
        _choice(false),
      ],
    ),
  );

  Widget _choice(bool phone) => Semantics(
    selected: selection == phone,
    child: OutlinedButton.icon(
      key: ValueKey('sync-conflict-${phone ? 'phone' : 'cloud'}-${item.key}'),
      onPressed: onSelect == null ? null : () => onSelect!(phone),
      icon: Icon(
        selection == phone
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      label: Text(phone ? 'Keep phone version' : 'Keep cloud version'),
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}
