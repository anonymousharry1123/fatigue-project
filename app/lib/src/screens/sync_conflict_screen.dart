import 'package:material_ui/material_ui.dart';

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
  bool? _remainingChoice;
  final _picked = ValueNotifier<int>(0);
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _picked.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SyncConflictScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _review = null;
      _choices.clear();
      _remainingChoice = null;
      _saving = false;
      _load();
    }
  }

  Map<String, bool> _selectedVersions(InputConflictReview review) => {
    for (final item in review.items)
      if ((_choices[item.key] ?? _remainingChoice) case final bool choice)
        item.key: choice,
  };

  Future<void> _load() async {
    final previous = _review;
    final controller = widget.controller;
    bool current() => mounted && identical(widget.controller, controller);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final review = await controller.reviewInputConflicts();
      if (!current()) return;
      final retained = previous == null
          ? <String, bool>{}
          : review.retainChoicesFrom(previous, _selectedVersions(previous));
      setState(() {
        // A group selection covers only the item versions already reviewed.
        // New or changed conflicts always need another explicit choice.
        if (_remainingChoice != null &&
            retained.length == review.items.length) {
          _choices.removeWhere((key, _) => !retained.containsKey(key));
        } else {
          _remainingChoice = null;
          _choices
            ..clear()
            ..addAll(retained);
        }
        _review = review;
        _picked.value = _choiceCount(review);
        _loadFailed = false;
      });
    } on Object catch (error) {
      if (current()) {
        setState(() {
          _loadFailed = true;
          _error = _message(error);
        });
      }
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final review = _review;
    if (_loading ||
        _loadFailed ||
        _saving ||
        review == null ||
        _choiceCount(review) != review.items.length) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final controller = widget.controller;
    bool current() => mounted && identical(widget.controller, controller);
    var savedOnDevice = false;
    try {
      await controller.resolveInputConflicts(
        review,
        _selectedVersions(review),
        onChoicesSaved: () {
          savedOnDevice = true;
          if (!current()) return;
          if (ModalRoute.of(context)?.isCurrent != true) {
            setState(() => _saving = false);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Choices saved on this device. Finishing sync…'),
            ),
          );
          Navigator.of(context).pop(true);
        },
      );
    } on Object catch (error) {
      if (current() && !savedOnDevice) setState(() => _error = _message(error));
    } finally {
      if (current() && !savedOnDevice) setState(() => _saving = false);
    }
  }

  int _choiceCount(InputConflictReview review) =>
      _remainingChoice == null ? _choices.length : review.items.length;

  String _message(Object error) => error is StateError
      ? error.message
      : 'Could not reach your cloud account. Check your connection and refresh the review.';

  @override
  Widget build(BuildContext context) {
    final review = _loading || _loadFailed ? null : _review;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Review sync changes')),
        body: SafeArea(
          bottom: review == null,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  key: const Key('sync-conflict-list'),
                  padding: const EdgeInsets.all(20),
                  itemCount: review == null ? 1 : review.items.length + 2,
                  itemBuilder: (context, index) {
                    if (review != null) {
                      if (index == 0) return _header(context, review);
                      if (index <= review.items.length) {
                        final item = review.items[index - 1];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: StatefulBuilder(
                            builder: (context, updateCard) => _ConflictCard(
                              item: item,
                              selection: _choices[item.key] ?? _remainingChoice,
                              onSelect: _saving
                                  ? null
                                  : (value) {
                                      if (_choices[item.key] == value) return;
                                      updateCard(
                                        () => _choices[item.key] = value,
                                      );
                                      _picked.value = _choiceCount(review);
                                    },
                            ),
                          ),
                        );
                      }
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (review == null && _error != null)
                          _errorText(context),
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
                    );
                  },
                ),
        ),
        bottomNavigationBar: review == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _picked,
                    builder: (context, count, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) _errorText(context),
                        Text(
                          '$count of ${review.items.length} choices made',
                          key: const Key('sync-conflict-progress'),
                        ),
                        const SizedBox(height: 6),
                        FilledButton(
                          key: const Key('sync-conflict-save'),
                          onPressed: _saving || count != review.items.length
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
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _header(BuildContext context, InputConflictReview review) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (review.items.length > 1) ...[
          const SizedBox(height: 12),
          ValueListenableBuilder<int>(
            valueListenable: _picked,
            builder: (context, count, _) {
              if (_remainingChoice != null) {
                return TextButton(
                  onPressed: _saving
                      ? null
                      : () => _chooseRemaining(review, null),
                  child: Text(
                    _remainingChoice!
                        ? 'Undo group choice (phone)'
                        : 'Undo group choice (cloud)',
                  ),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final phone in [true, false])
                    OutlinedButton(
                      onPressed: _saving || count == review.items.length
                          ? null
                          : () => _chooseRemaining(review, phone),
                      child: Text(
                        phone
                            ? 'Use phone for remaining'
                            : 'Use cloud for remaining',
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    ),
  );

  void _chooseRemaining(InputConflictReview review, bool? usePhone) {
    setState(() {
      _remainingChoice = usePhone;
      _picked.value = _choiceCount(review);
    });
  }

  Widget _errorText(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        _error!,
        style: TextStyle(color: TonyoPalette.of(context).warning),
      ),
    ),
  );
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
          headingLevel: 2,
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
