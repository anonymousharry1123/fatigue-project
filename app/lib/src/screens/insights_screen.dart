import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final score = AppScope.of(context).score;
    return SafeArea(
      bottom: false,
      child: ListView(
        key: const PageStorageKey('insights-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Insights', style: Theme.of(context).textTheme.headlineMedium),
          const Text(
            'Clear evidence behind today’s estimates',
            style: TextStyle(color: TonyoColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TonyoCard(
            color: const Color(0xFF151923),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    MetricIcon(
                      icon: Icons.analytics_rounded,
                      color: TonyoColors.mint,
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Score Models',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            'Ranked drivers · evidence-aware confidence',
                            style: TextStyle(
                              color: TonyoColors.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _ConfidencePanel(
                  title: 'Energy',
                  score: score.energy,
                  confidence: score.confidence,
                  completeness: score.completeness,
                  freshness: score.freshness,
                  color: TonyoColors.mint,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(color: TonyoColors.border, height: 1),
                ),
                _ConfidencePanel(
                  title: 'Cognitive',
                  score: score.cognitive,
                  confidence: score.cognitiveConfidence,
                  completeness: score.cognitiveCompleteness,
                  freshness: score.cognitiveFreshness,
                  color: TonyoColors.blue,
                ),
              ],
            ),
          ),
          const SectionHeader('Energy Score drivers'),
          _RankedDriversCard(
            key: const Key('insights-energy-drivers'),
            positive: score.energyPositiveDrivers,
            negative: score.energyNegativeDrivers,
            neutral: score.energyNeutralDrivers,
            emptyMessage:
                'Log sleep, activity, and a check-in to explain your Energy estimate.',
          ),
          const SectionHeader('Cognitive Score drivers'),
          _RankedDriversCard(
            key: const Key('insights-cognitive-model'),
            positive: score.cognitivePositiveDrivers,
            negative: score.cognitiveNegativeDrivers,
            neutral: score.cognitiveNeutralDrivers,
            emptyMessage:
                'Complete a reaction test, sleep or activity log, and check-in to explain cognitive readiness.',
          ),
          const SizedBox(height: 14),
          const TonyoCard(
            color: Color(0xFF111722),
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: TonyoColors.blue,
                  size: 19,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Confidence combines input coverage with the age, source, and quality of supporting records. Contributions are associations used by this wellness model—not medical findings or proof of cause.',
                    style: TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidencePanel extends StatelessWidget {
  const _ConfidencePanel({
    required this.title,
    required this.score,
    required this.confidence,
    required this.completeness,
    required this.freshness,
    required this.color,
  });

  final String title;
  final int score;
  final double confidence;
  final double completeness;
  final double? freshness;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 58,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Text(
          '$score',
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title confidence',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  '${(confidence * 100).round()}%',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: confidence,
                minHeight: 6,
                color: color,
                backgroundColor: TonyoColors.surfaceRaised,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${(completeness * 100).round()}% coverage · ${freshness == null ? 'freshness unavailable' : '${(freshness! * 100).round()}% fresh'}',
              style: const TextStyle(color: TonyoColors.muted, fontSize: 9),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RankedDriversCard extends StatelessWidget {
  const _RankedDriversCard({
    super.key,
    required this.positive,
    required this.negative,
    required this.neutral,
    required this.emptyMessage,
  });

  final List<ScoreDriver> positive;
  final List<ScoreDriver> negative;
  final List<ScoreDriver> neutral;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (positive.isEmpty && negative.isEmpty && neutral.isEmpty) {
      return TonyoCard(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
        ),
      );
    }
    return TonyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (positive.isNotEmpty)
            _DriverGroup(
              title: 'SUPPORTING TODAY',
              icon: Icons.trending_up_rounded,
              color: TonyoColors.mint,
              drivers: positive,
            ),
          if (positive.isNotEmpty && negative.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: TonyoColors.border, height: 1),
            ),
          if (negative.isNotEmpty)
            _DriverGroup(
              title: 'REDUCING TODAY',
              icon: Icons.trending_down_rounded,
              color: TonyoColors.coral,
              drivers: negative,
            ),
          if (neutral.isNotEmpty &&
              (positive.isNotEmpty || negative.isNotEmpty))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: TonyoColors.border, height: 1),
            ),
          if (neutral.isNotEmpty)
            _DriverGroup(
              title: 'NEUTRAL',
              icon: Icons.horizontal_rule_rounded,
              color: TonyoColors.muted,
              drivers: neutral,
            ),
        ],
      ),
    );
  }
}

class _DriverGroup extends StatelessWidget {
  const _DriverGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.drivers,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<ScoreDriver> drivers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ...drivers.indexed.map(
        (entry) => _RankedDriverRow(
          rank: entry.$1 + 1,
          driver: entry.$2,
          color: color,
        ),
      ),
    ],
  );
}

class _RankedDriverRow extends StatelessWidget {
  const _RankedDriverRow({
    required this.rank,
    required this.driver,
    required this.color,
  });

  final int rank;
  final ScoreDriver driver;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      driver.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${driver.contribution > 0 ? '+' : ''}${driver.contribution.round()} pts',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                driver.detail,
                style: const TextStyle(color: TonyoColors.text, fontSize: 10),
              ),
              if (driver.explanation.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  driver.explanation,
                  style: const TextStyle(
                    color: TonyoColors.muted,
                    fontSize: 9.5,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  _EvidenceChip(label: _sourceLabel(driver)),
                  if (driver.freshness case final freshness?)
                    _EvidenceChip(label: '${(freshness * 100).round()}% fresh'),
                  if (driver.evidenceAt case final evidenceAt?)
                    _EvidenceChip(label: _dayLabel(evidenceAt)),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _sourceLabel(ScoreDriver driver) => switch (driver.source) {
    SignalSource.manual => 'Manual',
    SignalSource.healthKit => 'HealthKit',
    SignalSource.model => 'Model',
    null => driver.evidenceAt == null ? 'Legacy snapshot' : 'Check-in',
  };

  static String _dayLabel(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final days = today.difference(date).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: TonyoColors.surfaceRaised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TonyoColors.border),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: TonyoColors.muted,
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
