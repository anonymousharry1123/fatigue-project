import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app.dart';
import '../app_controller.dart';
import '../models.dart';
import '../reaction_test_logic.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

enum _ReactionPhase {
  idle,
  waiting,
  ready,
  result,
  interrupted,
  saving,
  saveFailed,
  complete,
}

class ReactionTestScreen extends StatefulWidget {
  const ReactionTestScreen({
    super.key,
    @visibleForTesting this.waitDuration,
    @visibleForTesting this.stopwatch,
  });

  final Duration? waitDuration;
  final Stopwatch? stopwatch;

  @override
  State<ReactionTestScreen> createState() => _ReactionTestScreenState();
}

class _ReactionTestScreenState extends State<ReactionTestScreen>
    with WidgetsBindingObserver {
  _ReactionPhase phase = _ReactionPhase.idle;
  final results = <int>[];
  Timer? timer;
  late final Stopwatch stopwatch = widget.stopwatch ?? Stopwatch();
  AppController? _controller;
  int? _sessionRevision;
  String? _sessionUid;
  int _roundGeneration = 0;
  int _saveGeneration = 0;
  String? _resultId;
  DateTime? _observedAt;
  bool _foreground = true;
  int earlyTaps = 0;
  int invalidAttempts = 0;
  double? savedAverage;
  double? baselineAtSave;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    final accountChanged =
        _controller != null &&
        (_controller != controller ||
            _sessionRevision != controller.sessionRevision ||
            _sessionUid != controller.cloudUid ||
            controller.isSignedOut ||
            !controller.privacyFeaturesAllowed);
    _controller = controller;
    _sessionRevision = controller.sessionRevision;
    _sessionUid = controller.cloudUid;
    if (accountChanged) {
      _resetSession();
      phase = _ReactionPhase.interrupted;
    } else if (ModalRoute.of(context)?.isCurrent == false) {
      _interrupt();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_interrupt);
  }

  bool get _canMeasure =>
      _foreground &&
      mounted &&
      ModalRoute.of(context)?.isCurrent != false &&
      _controller?.sessionRevision == _sessionRevision &&
      _controller?.cloudUid == _sessionUid &&
      _controller?.isSignedOut == false &&
      _controller?.privacyFeaturesAllowed == true;

  void _cancelRound() {
    _roundGeneration++;
    timer?.cancel();
    timer = null;
    stopwatch.stop();
    stopwatch.reset();
  }

  void _resetSession() {
    _cancelRound();
    _saveGeneration++;
    results.clear();
    earlyTaps = 0;
    invalidAttempts = 0;
    savedAverage = null;
    baselineAtSave = null;
    _resultId = null;
    _observedAt = null;
  }

  void _interrupt() {
    if (phase == _ReactionPhase.waiting ||
        phase == _ReactionPhase.ready ||
        phase == _ReactionPhase.result ||
        (phase == _ReactionPhase.idle && results.isNotEmpty)) {
      _resetSession();
      phase = _ReactionPhase.interrupted;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelRound();
    _saveGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final colors = TonyoPalette.of(context);
    // Measurement cues are semantic and must not change with custom accents.
    final panelColor = switch (phase) {
      _ReactionPhase.ready => colors.success,
      _ReactionPhase.waiting => colors.warning,
      _ReactionPhase.saveFailed => colors.error,
      _ => colors.surfaceRaised,
    };
    final panelForeground = panelColor.computeLuminance() > .179
        ? Colors.black
        : Colors.white;
    // Keep the pre-test baseline even when there was not enough history to
    // compute one. Saving this result must not compare it against itself.
    final baseline = _resultId != null
        ? baselineAtSave
        : controller.reactionBaseline;
    final latest =
        savedAverage?.round() ?? (results.isEmpty ? 0 : results.last);
    final history = controller.signals
        .where((item) => item.type == SignalType.reactionTime)
        .take(7)
        .map((item) => item.value.round())
        .toList();
    while (history.length < 7) {
      history.add(0);
    }
    final chartValues = history.reversed.toList();
    if (savedAverage != null) {
      chartValues[chartValues.length - 1] = savedAverage!.round();
    } else if (results.isNotEmpty) {
      chartValues[chartValues.length - 1] = latest;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reaction Test'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton.filledTonal(
            onPressed: _help,
            tooltip: 'Reaction test instructions',
            icon: const Icon(Icons.question_mark_rounded, size: 20),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Semantics(
            key: const Key('reaction-test-panel'),
            button: true,
            enabled: phase != _ReactionPhase.saving,
            liveRegion: true,
            label:
                '$_instruction. $_footer'
                '${results.isNotEmpty ? '. ${savedAverage == null ? 'Latest round' : 'Test average'}: $latest milliseconds' : ''}',
            onTap: phase == _ReactionPhase.saving ? null : _tap,
            child: ExcludeSemantics(
              child: Material(
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: BoxDecoration(color: panelColor),
                  child: InkWell(
                    onTap: phase == _ReactionPhase.saving ? null : _tap,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 276),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 24,
                        ),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(color: panelForeground),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _instruction,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: .8,
                                ),
                              ),
                              const SizedBox(height: 22),
                              if (phase == _ReactionPhase.saving)
                                SizedBox(
                                  height: 100,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: panelForeground,
                                    ),
                                  ),
                                )
                              else if (phase == _ReactionPhase.result ||
                                  phase == _ReactionPhase.saveFailed ||
                                  phase == _ReactionPhase.complete)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      latest == 0 ? '—' : '$latest',
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Text(
                                      'ms',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: panelForeground.withValues(
                                        alpha: .45,
                                      ),
                                      width: 3,
                                    ),
                                  ),
                                  child: Icon(
                                    _phaseIcon,
                                    size: 54,
                                    color: panelForeground,
                                  ),
                                ),
                              const SizedBox(height: 20),
                              Text(
                                _footer,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _StatCard(
                  icon: Icons.timer_outlined,
                  color: TonyoPalette.of(context).secondary,
                  title: 'Reaction time',
                  value: results.isEmpty && savedAverage == null
                      ? '—'
                      : '${savedAverage?.round() ?? latest} ms',
                  detail: results.isEmpty
                      ? 'Complete ${ReactionTestLogic.roundsRequired} rounds'
                      : '${results.length} valid round${results.length == 1 ? '' : 's'}',
                ),
                _StatCard(
                  icon: Icons.warning_amber_rounded,
                  color: TonyoPalette.of(context).warning,
                  title: 'Invalid attempts',
                  value: '${earlyTaps + invalidAttempts}',
                  detail: earlyTaps == 0 && invalidAttempts == 0
                      ? 'Stay sharp'
                      : '$earlyTaps early · $invalidAttempts out of range',
                ),
              ];
              if (constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [cards[0], const SizedBox(height: 10), cards[1]],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                ],
              );
            },
          ),
          if (baseline != null) ...[
            const SizedBox(height: 12),
            TonyoCard(
              child: Row(
                children: [
                  MetricIcon(
                    icon: Icons.insights_rounded,
                    color: TonyoPalette.of(context).secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Personal baseline',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${baseline.round()} ms',
                          style: TextStyle(
                            color: TonyoPalette.of(context).secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          savedAverage == null
                              ? 'Your baseline is ${baseline.round()} ms from recent tests.'
                              : ReactionTestLogic.comparisonLabel(
                                  savedAverage!,
                                  baseline,
                                ),
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            TonyoCard(
              child: Text(
                'Complete a few valid tests to build your personal reaction baseline.',
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SectionHeader('Reaction time · recent tests'),
          TonyoCard(
            child: Column(
              children: [
                Semantics(
                  label: chartValues.every((value) => value == 0)
                      ? 'No reaction times to display yet.'
                      : 'Recent reaction times, oldest to newest: '
                            '${chartValues.where((value) => value > 0).join(', ')} milliseconds.',
                  child: ExcludeSemantics(
                    child: SizedBox(
                      height: 115,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: chartValues.asMap().entries.map((entry) {
                          final value = entry.value == 0 ? 300 : entry.value;
                          final height = (380 - value)
                              .clamp(35, 120)
                              .toDouble();
                          return Expanded(
                            child: Container(
                              height: height,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: entry.key == chartValues.length - 1
                                    ? colors.secondary
                                    : colors.primary,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  phase == _ReactionPhase.saveFailed
                      ? 'Your three rounds are ready. Tap Retry saving to try again without repeating the test.'
                      : phase == _ReactionPhase.complete
                      ? controller.outcomeConsent
                            ? 'Result saved as a signal and private cognitive outcome. Early or invalid taps do not count.'
                            : 'Result saved as a signal. Outcome learning is off, so no training record was created.'
                      : 'Three valid rounds make one daily benchmark. Early taps reset the current round.',
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _instruction => switch (phase) {
    _ReactionPhase.idle => 'TAP TO BEGIN',
    _ReactionPhase.waiting => 'WAIT FOR GREEN',
    _ReactionPhase.ready => 'TAP NOW',
    _ReactionPhase.result => 'NICE — TAP FOR NEXT ROUND',
    _ReactionPhase.interrupted => 'TAP TO RESTART',
    _ReactionPhase.saving => 'SAVING RESULT',
    _ReactionPhase.saveFailed => 'RETRY SAVING',
    _ReactionPhase.complete => 'TEST COMPLETE',
  };

  String get _footer => switch (phase) {
    _ReactionPhase.idle => 'Three quick rounds',
    _ReactionPhase.waiting => 'Hold steady…',
    _ReactionPhase.ready => 'Go!',
    _ReactionPhase.result =>
      '${ReactionTestLogic.roundsRequired - results.length} round${ReactionTestLogic.roundsRequired - results.length == 1 ? '' : 's'} left',
    _ReactionPhase.interrupted =>
      'Test interrupted. Start three fresh rounds when you are ready.',
    _ReactionPhase.saving => 'Keeping your three rounds together…',
    _ReactionPhase.saveFailed =>
      'Could not finish saving. Your rounds are kept here.',
    _ReactionPhase.complete =>
      _controller?.cloudSyncError != null ||
              _controller?.hasPendingOutcomeChanges == true
          ? 'Saved on this device · cloud sync pending'
          : 'Saved to this device · tap to close',
  };

  IconData get _phaseIcon => switch (phase) {
    _ReactionPhase.idle => Icons.touch_app_rounded,
    _ReactionPhase.waiting => Icons.more_horiz_rounded,
    _ReactionPhase.ready => Icons.bolt_rounded,
    _ReactionPhase.interrupted => Icons.restart_alt_rounded,
    _ReactionPhase.saveFailed => Icons.cloud_off_rounded,
    _ReactionPhase.result ||
    _ReactionPhase.saving ||
    _ReactionPhase.complete => Icons.check_rounded,
  };

  void _tap() {
    if (!_canMeasure) return;
    switch (phase) {
      case _ReactionPhase.interrupted:
        _resetSession();
        _startRound();
      case _ReactionPhase.idle:
      case _ReactionPhase.result:
        _startRound();
      case _ReactionPhase.waiting:
        _cancelRound();
        setState(() {
          earlyTaps++;
          phase = _ReactionPhase.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Too soon — wait until the panel turns green.'),
          ),
        );
      case _ReactionPhase.ready:
        // A round starts after the green frame is drawn, never while a frame
        // is still queued or after a lifecycle/route interruption.
        if (!stopwatch.isRunning) return;
        final elapsed = stopwatch.elapsedMilliseconds;
        _cancelRound();
        if (!ReactionTestLogic.isValidReaction(elapsed)) {
          setState(() {
            invalidAttempts++;
            phase = _ReactionPhase.idle;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                elapsed < ReactionTestLogic.minValidMs
                    ? 'That tap was unrealistically fast and was discarded.'
                    : 'That reaction was too slow and was discarded.',
              ),
            ),
          );
          return;
        }
        setState(() {
          results.add(elapsed);
          phase = _ReactionPhase.result;
        });
        if (ReactionTestLogic.isComplete(results)) {
          _observedAt = DateTime.now();
          _resultId =
              'reaction-${_observedAt!.microsecondsSinceEpoch}-'
              '${Random().nextInt(1 << 32)}';
          baselineAtSave = _controller!.reactionBaseline;
          _saveResults();
        }
      case _ReactionPhase.saveFailed:
        _saveResults();
      case _ReactionPhase.saving:
        return;
      case _ReactionPhase.complete:
        Navigator.of(context).maybePop();
    }
  }

  Future<void> _saveResults() async {
    if (phase == _ReactionPhase.saving ||
        !ReactionTestLogic.isComplete(results) ||
        !_canMeasure) {
      return;
    }
    final average = ReactionTestLogic.averageMs(results);
    final controller = _controller!;
    final revision = _sessionRevision;
    final uid = _sessionUid;
    final generation = ++_saveGeneration;
    bool stillCurrent() =>
        mounted &&
        generation == _saveGeneration &&
        identical(controller, _controller) &&
        controller.sessionRevision == revision &&
        controller.cloudUid == uid &&
        !controller.isSignedOut &&
        controller.privacyFeaturesAllowed;
    setState(() => phase = _ReactionPhase.saving);
    try {
      await controller.addReactionResult(
        average,
        resultId: _resultId,
        observedAt: _observedAt,
      );
      if (!stillCurrent()) return;
      setState(() {
        savedAverage = average;
        phase = _ReactionPhase.complete;
      });
    } on Object {
      if (!stillCurrent()) return;
      setState(() => phase = _ReactionPhase.saveFailed);
    }
  }

  void _startRound() {
    if (!_canMeasure) return;
    _cancelRound();
    final generation = _roundGeneration;
    setState(() => phase = _ReactionPhase.waiting);
    timer = Timer(
      widget.waitDuration ??
          Duration(milliseconds: 900 + Random().nextInt(1500)),
      () {
        if (!mounted || generation != _roundGeneration) return;
        if (!_canMeasure) {
          setState(_interrupt);
          return;
        }
        setState(() => phase = _ReactionPhase.ready);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              generation != _roundGeneration ||
              phase != _ReactionPhase.ready) {
            return;
          }
          if (!_canMeasure) {
            setState(_interrupt);
            return;
          }
          stopwatch.start();
        });
      },
    );
  }

  void _help() {
    setState(_interrupt);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How it works'),
        scrollable: true,
        content: const Text(
          'Start a round, wait for the panel to turn green and display “TAP NOW”, '
          'then tap as quickly as you can. Early taps and out-of-range times '
          'do not count. After three valid rounds, Tonyo compares your average '
          'with your personal baseline. Leaving the test or opening these '
          'instructions discards unfinished rounds so you can restart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.detail,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => TonyoCard(
    padding: const EdgeInsets.all(13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        Text(
          detail,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
