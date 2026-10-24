import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../evidence_provenance.dart';
import '../models.dart';
import '../privacy_consent.dart';
import '../sleep_observation_logic.dart';
import 'common_widgets.dart';
import 'data_source_badge.dart';

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
    final confirmed =
        !sleep.containsDemoEvidence && _confirmedEvidence == sleep.evidenceKey;
    final latest = sleep.latestMain;
    final comparison = sleep.compare(allSleepConfirmed: confirmed);
    return TonyoCard(
      key: const Key('sleep-observations'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              sleep.containsDemoEvidence
                  ? sleep.containsRecordedEvidence
                        ? 'Recorded and demo sleep'
                        : 'Demo sleep'
                  : 'Recorded sleep',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (sleep.containsDemoEvidence) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                'These summaries include demo/synthetic examples, not imported or measured sleep. '
                'Totals, recent patterns and timing variation do not establish your personal sleep history.',
              ),
              key: Key('sleep-demo-provenance'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            context.tr(
              latest == null
                  ? 'No completed main sleep recorded.'
                  : 'Latest main sleep: ${_hours(latest.value)} h · '
                        '${_stamp(latest.timestamp)} · ${EvidenceProvenance.signalIsDemo(latest)
                            ? context.tr('Demo / synthetic example')
                            : latest.source == SignalSource.healthKit
                            ? context.tr('Apple Health estimate')
                            : context.tr('Manual entry')}',
            ),
          ),
          if (latest != null) ...[
            const SizedBox(height: 5),
            DataSourceBadge(
              source: latest.source,
              recordId: latest.id,
              isDemo: EvidenceProvenance.signalIsDemo(latest),
            ),
          ],
          if (latest?.source == SignalSource.manual)
            Text(
              context.tr(
                'Entered bed/wake times estimate sleep; they do not measure time asleep.',
              ),
            ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              '24-hour window: ${_stamp(sleep.windowStart)} → '
              '${_stamp(sleep.windowEnd)} (local time)',
            ),
          ),
          Text(
            context.tr(
              '${context.tr(sleep.containsDemoEvidence ? 'Displayed sleep total' : 'Estimated recorded sleep')}: ${_hours(sleep.totalHours)} h, '
              'including ${_hours(sleep.napHours)} h in ${sleep.napCount} naps.',
            ),
          ),
          Text(
            context.tr(
              'Overlaps are counted once. Naps are logged separately; '
              'their restorative effect is not treated as equivalent to main sleep.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              '${sleep.mainObservationCount}/7 recent dates have a main-sleep '
              'record; ${7 - sleep.mainObservationCount} dates are missing.',
            ),
          ),
          if (sleep.usualMainHours case final usual?)
            Text(
              context.tr(
                sleep.containsDemoEvidence
                    ? 'Average in displayed records: ${_hours(usual)} h of main sleep.'
                    : 'Usual in these records: ${_hours(usual)} h of main sleep. '
                          'A personal pattern is not an age recommendation.',
              ),
            ),
          Text(
            context.tr(
              'Clock-time variation (${sleep.bedtimeObservationCount} paired bedtimes, ${sleep.mainObservationCount} wakes): '
              'bedtime ${context.tr(_variation(sleep.bedtimeVariationMinutes))}; '
              'wake ${context.tr(_variation(sleep.wakeVariationMinutes))}. '
              'Mean distance from usual clock time, not a health rating.',
            ),
          ),
          ExpansionTile(
            key: const PageStorageKey('sleep-recent-observations'),
            tilePadding: EdgeInsets.zero,
            title: Text(context.tr('Recent observations')),
            children: [
              for (final day in sleep.days)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('${day.day.month}/${day.day.day}')),
                  subtitle: Text(
                    context.tr(
                      'Main sleep: ${day.mainHours == null ? context.tr('not recorded') : '${_hours(day.mainHours!)} h'} · '
                      'Naps: ${day.napHours == null ? context.tr('not recorded') : '${_hours(day.napHours!)} h (${day.naps})'}',
                    ),
                  ),
                ),
            ],
          ),
          if (sleep.supportsTeenGuidance) ...[
            Text(
              context.tr(
                'AASM teen recommendation: 8–10 hours of sleep per '
                '24 hours. This is separate from the experimental score.',
              ),
            ),
            CheckboxListTile(
              key: const Key('sleep-coverage-confirmation'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                context.tr('I have recorded all sleep in this 24-hour window.'),
              ),
              subtitle: Text(
                context.tr(
                  'This confirmation lasts only for this window '
                  'and these records; it is not device-verified coverage.',
                ),
              ),
              value: confirmed,
              onChanged:
                  sleep.containsDemoEvidence ||
                      latest == null && sleep.napCount == 0
                  ? null
                  : (value) => setState(
                      () => _confirmedEvidence = value == true
                          ? sleep.evidenceKey
                          : null,
                    ),
            ),
            Text(
              context.tr(switch (comparison) {
                SleepRangeComparison.unavailable =>
                  sleep.containsDemoEvidence
                      ? 'Comparison unavailable: demo/synthetic examples cannot confirm your sleep coverage.'
                      : sleep.boundaryUncertain
                      ? 'Comparison unavailable: sleep timing at the window boundary is incomplete.'
                      : 'Comparison unavailable until complete sleep coverage is confirmed.',
                SleepRangeComparison.below =>
                  'The confirmed recorded total is below the teen range.',
                SleepRangeComparison.within =>
                  'The confirmed recorded total is within the teen range. This does not establish recovery or readiness.',
                SleepRangeComparison.above =>
                  'The confirmed recorded total is above the teen range. More hours do not earn more score points.',
              }),
              key: const Key('sleep-guideline-comparison'),
            ),
          ] else
            Text(
              context.tr(
                'No age-specific comparison is available for this age band.',
              ),
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
