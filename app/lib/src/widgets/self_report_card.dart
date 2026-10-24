import 'package:flutter/material.dart';

import '../check_in_measurement.dart';
import '../evidence_provenance.dart';
import '../l10n/app_localizations.dart';
import '../local_day.dart';
import '../models.dart';
import '../theme.dart';
import 'common_widgets.dart';
import 'data_source_badge.dart';
import 'self_report_reference_card.dart';

Map<String, double?> selfReportRatings(DailyCheckIn item) => {
  'energy': item.energy,
  'fatigue': item.fatigue,
  'sleepiness': item.sleepiness,
  'focus': item.focus,
  'mood': item.mood,
  'stress': item.stress,
};

bool selfReportIsSynthetic(DailyCheckIn item) =>
    EvidenceProvenance.hasDemoMarker([item.id, item.note]) ||
    item.id.toLowerCase().startsWith('syn-');

Map<String, double?> rawSelfReportRatings(DailyCheckIn item) {
  final original = item.originalLegacyRatings;
  if (original == null) return selfReportRatings(item);
  return {
    for (final id in DailyCheckIn.measurementIds)
      id: original[id] is num ? (original[id] as num).toDouble() : null,
  };
}

int selfReportScaleMaximum(DailyCheckIn item) =>
    item.originalLegacyRatings == null ? 10 : 5;

/// Raw self-reports are deliberately separate from calculated score tiles.
class TodaySelfReportCard extends StatelessWidget {
  const TodaySelfReportCard({
    super.key,
    required this.checkIns,
    required this.now,
  });
  final List<DailyCheckIn> checkIns;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final day =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final reports =
        checkIns
            .where(
              (item) =>
                  !selfReportIsSynthetic(item) &&
                  !item.timestamp.isAfter(now) &&
                  !(item.recordedAt?.isAfter(now) ?? false) &&
                  (item.isResearchCheckIn
                      ? item.localDate == day
                      : sameLocalDay(item.timestamp, now)),
            )
            .toList()
          ..sort((a, b) {
            final observed = b.timestamp.compareTo(a.timestamp);
            if (observed != 0) return observed;
            final recorded = (b.recordedAt ?? b.timestamp).compareTo(
              a.recordedAt ?? a.timestamp,
            );
            return recorded != 0 ? recorded : b.id.compareTo(a.id);
          });
    final latest = <CheckInPeriod, DailyCheckIn>{};
    for (final item in reports) {
      latest.putIfAbsent(item.period, () => item);
    }
    return TonyoCard(
      key: const Key('today-self-report'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Today’s self-report'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'Your reported answers, separate from experimental estimates.',
            ),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 12,
            ),
          ),
          if (latest.isEmpty) ...[
            const SizedBox(height: 8),
            Text(context.tr('No self-report recorded for today.')),
          ] else
            for (final period in CheckInPeriod.values)
              if (latest[period] case final item?) ...[
                const SizedBox(height: 14),
                SelfReportRecordCard(
                  checkIn: item,
                  embedded: true,
                  showNote: false,
                ),
                SelfReportReferenceCard(
                  current: item,
                  checkIns: checkIns,
                  now: now,
                ),
              ],
        ],
      ),
    );
  }
}

class SelfReportRecordCard extends StatelessWidget {
  const SelfReportRecordCard({
    super.key,
    required this.checkIn,
    this.embedded = false,
    this.showNote = true,
  });
  final DailyCheckIn checkIn;
  final bool embedded;
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final item = checkIn;
    final material = MaterialLocalizations.of(context);
    final stamp = item.isResearchCheckIn && item.utcOffsetMinutes != null
        ? item.timestamp.toUtc().add(Duration(minutes: item.utcOffsetMinutes!))
        : item.timestamp;
    final date = item.localDate ?? material.formatShortDate(stamp);
    final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(stamp));
    final ratings = rawSelfReportRatings(item);
    final maximum = selfReportScaleMaximum(item);
    final energyOnlyMorning =
        item.isResearchCheckIn &&
        item.period == CheckInPeriod.morning &&
        ratings.entries.every((e) => e.key == 'energy' || e.value == null);
    final ids = item.isResearchCheckIn
        ? energyOnlyMorning
              ? ['energy']
              : ratings.keys
        : ['energy', 'mood', 'stress'];
    final contents = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.legacyPeriodMissing
              ? context.tr('Earlier check-in (period not recorded)')
              : context.tr(
                  '{period} check-in',
                  args: {'period': context.tr(item.period.label)},
                ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '$date · $time${item.timezone == null ? '' : ' · ${item.timezone}'}',
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 11),
        ),
        const SizedBox(height: 5),
        DataSourceBadge(
          source: SignalSource.manual,
          recordId: item.id,
          isDemo: selfReportIsSynthetic(item),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final id in ids)
              Text(
                context.tr(
                  '{measure}: {value}',
                  args: {
                    'measure': context.tr(
                      CheckInMeasurement.items
                          .firstWhere((definition) => definition.id == id)
                          .label,
                    ),
                    'value': ratings[id] == null
                        ? context.tr('Not answered')
                        : '${_rating(ratings[id]!)} / $maximum',
                  },
                ),
                key: Key('self-report-${item.id}-$id'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          item.isResearchCheckIn
              ? context.tr(
                  energyOnlyMorning
                      ? 'Morning Energy · Custom draft · {version} · {language}'
                      : '{count}/6 answered · Custom draft · {version} · {language}',
                  args: {
                    'count': ratings.values.whereType<double>().length,
                    'version': item.questionnaireVersion,
                    'language': item.questionnaireLanguage,
                  },
                )
              : context.tr(
                  item.originalLegacyRatings != null
                      ? 'Earlier 1–5 self-report · Original answers'
                      : 'Earlier three-item self-report; new measures were not collected.',
                ),
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 11),
        ),
        if (selfReportIsSynthetic(item)) ...[
          const SizedBox(height: 6),
          Text(
            context.tr(
              'Synthetic demo record — not a participant observation.',
            ),
          ),
        ],
        if (showNote && item.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(item.note),
        ],
      ],
    );
    return embedded ? contents : TonyoCard(child: contents);
  }
}

String _rating(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';
