import 'package:flutter/material.dart';

import '../../models.dart';
import '../../synthetic/synthetic_person.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';

class AdminPersonScreen extends StatelessWidget {
  const AdminPersonScreen({super.key, required this.person});

  final SyntheticPerson person;

  @override
  Widget build(BuildContext context) {
    final score = person.score;
    return Scaffold(
      backgroundColor: TonyoPalette.of(context).background,
      appBar: AppBar(title: Text('Synthetic ${person.id}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          TonyoCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${person.age} · ${person.gender}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${person.education} · ${person.ageRange} · ${person.role}',
                        style: TextStyle(
                          color: TonyoPalette.of(context).muted,
                          fontSize: 12,
                        ),
                      ),
                      if (person.feelsBurnedOut)
                        Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'CSV flag: feels burned out',
                            style: TextStyle(
                              color: TonyoPalette.of(context).error,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ScoreRing(value: score.energy, label: 'Energy', size: 88),
                const SizedBox(width: 10),
                ScoreRing(
                  value: score.cognitive,
                  label: 'Cognitive',
                  size: 88,
                  color: TonyoPalette.of(context).secondary,
                ),
              ],
            ),
          ),
          const SectionHeader('Mapped signals'),
          for (final signal in person.signals)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TonyoCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            signal.type.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (signal.note != null && signal.note!.isNotEmpty)
                            Text(
                              signal.note!,
                              style: TextStyle(
                                color: TonyoPalette.of(context).muted,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${signal.value.toStringAsFixed(2)} ${signal.type.unit}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          const SectionHeader('Check-in'),
          for (final checkIn in person.checkIns)
            TonyoCard(
              child: Text(
                '${checkIn.period.label}: energy ${checkIn.energy.round()}/10 · '
                'mood ${checkIn.mood.round()}/10 · stress ${checkIn.stress.round()}/10'
                '${checkIn.note.isEmpty ? '' : '\n${checkIn.note}'}',
              ),
            ),
          const SectionHeader('Energy Score drivers'),
          _DriverCard(drivers: score.drivers, confidence: score.confidence),
          const SectionHeader('Cognitive Score drivers'),
          _DriverCard(
            drivers: score.cognitiveDrivers,
            confidence: score.cognitiveConfidence,
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.drivers, required this.confidence});

  final List<ScoreDriver> drivers;
  final double confidence;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      children: [
        if (drivers.isEmpty)
          Text(
            'No model inputs are available.',
            style: TextStyle(color: TonyoPalette.of(context).muted),
          ),
        for (final driver in drivers) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      driver.detail,
                      style: TextStyle(
                        color: TonyoPalette.of(context).muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${driver.contribution >= 0 ? '+' : ''}${driver.contribution.toStringAsFixed(1)}',
                style: TextStyle(
                  color: driver.contribution >= 0
                      ? TonyoPalette.of(context).success
                      : TonyoPalette.of(context).error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          'Confidence ${(confidence * 100).round()}%',
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 11),
        ),
      ],
    ),
  );
}
