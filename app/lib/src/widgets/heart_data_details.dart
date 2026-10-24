import 'package:flutter/material.dart';

import '../heart_derivation_logic.dart';
import '../l10n/app_localizations.dart';
import '../models.dart';
import '../theme.dart';

/// Separates imported HRV, estimated resting HR and sampled bpm variation.
class HeartDataDetails extends StatelessWidget {
  const HeartDataDetails({
    super.key,
    required this.readings,
    required this.now,
  });

  final List<SignalReading> readings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final available = readings.where(
      (reading) =>
          reading.value.isFinite &&
          !reading.timestamp.isAfter(now) &&
          !(reading.syncedAt?.isAfter(now) ?? false) &&
          !(reading.recordedAt?.isAfter(now) ?? false),
    );
    final resting = _latest(
      available.where(
        (reading) =>
            reading.type == SignalType.restingHeartRate &&
            reading.value >= 20 &&
            reading.value <= 250,
      ),
    );
    final hrv = _latest(
      available.where(
        (reading) =>
            reading.type == SignalType.hrv &&
            reading.source == SignalSource.healthKit &&
            reading.value > 0 &&
            reading.value <= 1000,
      ),
    );
    final derivation = HeartDerivationLogic.reconcile(
      readings: readings,
      now: now,
    );
    final variationDays = derivation.days.where((day) => day.variation != null);
    final latestVariation = variationDays.isEmpty ? null : variationDays.first;
    final hasHeartSamples = derivation.days.any(
      (day) => day.overnightSampleCount + day.daytimeSampleCount > 0,
    );
    final muted = TextStyle(
      color: TonyoPalette.of(context).muted,
      fontSize: 10,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        if (resting != null)
          Text(
            context.tr(
              HeartDerivationLogic.isEstimatedRestingHeartRate(resting)
                  ? 'Latest estimated resting HR: {value} bpm · {date}'
                  : resting.source == SignalSource.healthKit
                  ? 'Latest resting HR from Apple Health: {value} bpm · {date}'
                  : 'Latest logged resting HR: {value} bpm · {date}',
              args: {
                'value': resting.value.toStringAsFixed(1),
                'date': _date(resting.timestamp),
              },
            ),
            key: const Key('heart-data-resting'),
            style: const TextStyle(fontSize: 11),
          )
        else if (hasHeartSamples)
          Text(
            context.tr(
              'A resting HR estimate needs at least 3 overnight readings (midnight–8 am). Wear your device overnight, sync its app to Apple Health, then tap Sync now.',
            ),
            key: const Key('heart-data-resting-guidance'),
            style: muted,
          ),
        if (resting != null &&
            HeartDerivationLogic.isEstimatedRestingHeartRate(resting)) ...[
          const SizedBox(height: 3),
          Text(
            context.tr(
              'Resting HR estimates are informational and do not affect your score or measured baselines.',
            ),
            key: const Key('heart-data-resting-estimate-context'),
            style: muted,
          ),
        ],
        const SizedBox(height: 4),
        Text(
          hrv == null
              ? context.tr(
                  'No native HRV imported. HRV needs beat-to-beat intervals; ordinary heart-rate samples cannot supply it. Check whether your device shares HRV with Apple Health.',
                )
              : context.tr(
                  'Latest HRV from Apple Health: {value} ms · {date}',
                  args: {
                    'value': hrv.value.toStringAsFixed(1),
                    'date': _date(hrv.timestamp),
                  },
                ),
          key: const Key('heart-data-native-hrv'),
          style: hrv == null ? muted : const TextStyle(fontSize: 11),
        ),
        if (latestVariation != null) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Sampled heart-rate variation: {value} bpm · {date}',
              args: {
                'value': latestVariation.variation!.rmsSuccessiveDifferenceBpm
                    .toStringAsFixed(1),
                'date': _date(latestVariation.localDay),
              },
            ),
            key: const Key('heart-data-sampled-variation'),
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 3),
          Text(
            context.tr(
              'Variation between sampled bpm readings; separate from HRV and not used in your score.',
            ),
            style: muted,
          ),
        ] else if (hasHeartSamples) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Daytime variation needs at least 6 readings across 2 hours, no more than 45 minutes apart.',
            ),
            key: const Key('heart-data-variation-guidance'),
            style: muted,
          ),
        ],
      ],
    );
  }

  static SignalReading? _latest(Iterable<SignalReading> readings) {
    SignalReading? latest;
    for (final reading in readings) {
      if (latest == null || reading.timestamp.isAfter(latest.timestamp)) {
        latest = reading;
      }
    }
    return latest;
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
