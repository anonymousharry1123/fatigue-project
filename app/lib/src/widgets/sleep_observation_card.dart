import 'package:flutter/material.dart';

import '../models.dart';
import '../privacy_consent.dart';
import '../sleep_observation_logic.dart';
import 'common_widgets.dart';

class SleepObservationCard extends StatefulWidget {
  const SleepObservationCard({
    super.key,
    required this.signals,
    required this.now,
    required this.ageBand,
  });
  final List<SignalReading> signals;
  final DateTime now;
  final PrivacyAgeBand? ageBand;

  @override
  State<SleepObservationCard> createState() => _SleepObservationCardState();
}

class _SleepObservationCardState extends State<SleepObservationCard> {
  // Session-only attestation, never inferred from permissions, a device, or a
  // single sleep record. Changing the window/evidence/age invalidates it.
  String? _confirmedEvidence;

  @override
  Widget build(BuildContext context) {
    final sleep = SleepObservations.build(
      signals: widget.signals,
      now: widget.now,
      ageBand: widget.ageBand,
    );
    final confirmed = _confirmedEvidence == sleep.evidenceKey;
    final latest = sleep.latestMain;
    final comparison = sleep.compare(allSleepConfirmed: confirmed);
    return TonyoCard(
      key: const Key('sleep-observations'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recorded sleep',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            latest == null
                ? 'No completed main sleep recorded.'
                : 'Latest main sleep: ${_hours(latest.value)} h · '
                      '${_stamp(latest.timestamp)} · ${latest.source == SignalSource.healthKit ? 'Apple Health estimate' : 'Manual entry'}',
          ),
          if (latest?.source == SignalSource.manual)
            const Text(
              'Entered bed/wake times estimate sleep; they do not measure time asleep.',
            ),
          const SizedBox(height: 8),
          Text(
            '24-hour window: ${_stamp(sleep.windowStart)} → '
            '${_stamp(sleep.windowEnd)} (local time)',
          ),
          Text(
            'Estimated recorded sleep: ${_hours(sleep.totalHours)} h, '
            'including ${_hours(sleep.napHours)} h in ${sleep.napCount} naps.',
          ),
          const Text(
            'Overlaps are counted once. Naps are logged separately; '
            'their restorative effect is not treated as equivalent to main sleep.',
          ),
          const SizedBox(height: 8),
          Text(
            '${sleep.mainObservationCount}/7 recent dates have a main-sleep '
            'record; ${7 - sleep.mainObservationCount} dates are missing.',
          ),
          if (sleep.usualMainHours case final usual?)
            Text(
              'Usual in these records: ${_hours(usual)} h of main sleep. '
              'A personal pattern is not an age recommendation.',
            ),
          Text(
            'Clock-time variation (${sleep.bedtimeObservationCount} paired bedtimes, ${sleep.mainObservationCount} wakes): '
            'bedtime ${_variation(sleep.bedtimeVariationMinutes)}; '
            'wake ${_variation(sleep.wakeVariationMinutes)}. '
            'Mean distance from usual clock time, not a health rating.',
          ),
          ExpansionTile(
            key: const PageStorageKey('sleep-recent-observations'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Recent observations'),
            children: [
              for (final day in sleep.days)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${day.day.month}/${day.day.day}'),
                  subtitle: Text(
                    'Main sleep: ${day.mainHours == null ? 'not recorded' : '${_hours(day.mainHours!)} h'} · '
                    'Naps: ${day.napHours == null ? 'not recorded' : '${_hours(day.napHours!)} h (${day.naps})'}',
                  ),
                ),
            ],
          ),
          if (sleep.supportsTeenGuidance) ...[
            const Text(
              'AASM teen recommendation: 8–10 hours of sleep per '
              '24 hours. This is separate from the experimental score.',
            ),
            CheckboxListTile(
              key: const Key('sleep-coverage-confirmation'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I have recorded all sleep in this 24-hour window.',
              ),
              subtitle: const Text(
                'This confirmation lasts only for this window '
                'and these records; it is not device-verified coverage.',
              ),
              value: confirmed,
              onChanged: latest == null && sleep.napCount == 0
                  ? null
                  : (value) => setState(
                      () => _confirmedEvidence = value == true
                          ? sleep.evidenceKey
                          : null,
                    ),
            ),
            Text(switch (comparison) {
              SleepRangeComparison.unavailable =>
                sleep.boundaryUncertain
                    ? 'Comparison unavailable: sleep timing at the window boundary is incomplete.'
                    : 'Comparison unavailable until complete sleep coverage is confirmed.',
              SleepRangeComparison.below =>
                'The confirmed recorded total is below the teen range.',
              SleepRangeComparison.within =>
                'The confirmed recorded total is within the teen range. This does not establish recovery or readiness.',
              SleepRangeComparison.above =>
                'The confirmed recorded total is above the teen range. More hours do not earn more score points.',
            }, key: const Key('sleep-guideline-comparison')),
          ] else
            const Text(
              'No age-specific comparison is available for this age band.',
            ),
        ],
      ),
    );
  }

  static String _hours(double value) => value.toStringAsFixed(1);
  static String _variation(double? value) =>
      value == null ? 'not enough timing data' : '${value.round()} min';
  static String _stamp(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
