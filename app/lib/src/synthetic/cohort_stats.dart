import 'dart:math' as math;

import 'synthetic_person.dart';

class CohortHistogramBin {
  const CohortHistogramBin(this.label, this.count, this.midpoint);
  final String label;
  final int count;
  final double midpoint;
}

class CohortScatterPoint {
  const CohortScatterPoint(this.x, this.y, this.id);
  final double x;
  final double y;
  final String id;
}

class CohortGroupStat {
  const CohortGroupStat({
    required this.label,
    required this.count,
    required this.meanEnergy,
    required this.meanCognitive,
  });
  final String label;
  final int count;
  final double meanEnergy;
  final double meanCognitive;
}

class CohortSummary {
  const CohortSummary({
    required this.n,
    required this.meanEnergy,
    required this.medianEnergy,
    required this.meanCognitive,
    required this.medianCognitive,
    required this.energyHistogram,
    required this.cognitiveHistogram,
    required this.byEducation,
    required this.byGender,
    required this.sleepVsEnergy,
    required this.screenVsCognitive,
    required this.studyVsCognitive,
    required this.exerciseVsEnergy,
    required this.caffeineVsEnergy,
  });

  final int n;
  final double meanEnergy;
  final double medianEnergy;
  final double meanCognitive;
  final double medianCognitive;
  final List<CohortHistogramBin> energyHistogram;
  final List<CohortHistogramBin> cognitiveHistogram;
  final List<CohortGroupStat> byEducation;
  final List<CohortGroupStat> byGender;
  final List<CohortScatterPoint> sleepVsEnergy;
  final List<CohortScatterPoint> screenVsCognitive;
  final List<CohortScatterPoint> studyVsCognitive;
  final List<CohortScatterPoint> exerciseVsEnergy;
  final List<CohortScatterPoint> caffeineVsEnergy;

  Map<String, Object?> toCloud() => {
    'n': n,
    'meanEnergy': meanEnergy,
    'medianEnergy': medianEnergy,
    'meanCognitive': meanCognitive,
    'medianCognitive': medianCognitive,
    'energyHistogram': energyHistogram
        .map(
          (bin) => {
            'label': bin.label,
            'count': bin.count,
            'midpoint': bin.midpoint,
          },
        )
        .toList(),
    'cognitiveHistogram': cognitiveHistogram
        .map(
          (bin) => {
            'label': bin.label,
            'count': bin.count,
            'midpoint': bin.midpoint,
          },
        )
        .toList(),
    'byEducation': byEducation
        .map(
          (group) => {
            'label': group.label,
            'count': group.count,
            'meanEnergy': group.meanEnergy,
            'meanCognitive': group.meanCognitive,
          },
        )
        .toList(),
    'byGender': byGender
        .map(
          (group) => {
            'label': group.label,
            'count': group.count,
            'meanEnergy': group.meanEnergy,
            'meanCognitive': group.meanCognitive,
          },
        )
        .toList(),
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory CohortSummary.fromCloud(Map<String, dynamic> data) {
    List<CohortHistogramBin> hist(String key) =>
        ((data[key] as List?) ?? const [])
            .map(
              (raw) => CohortHistogramBin(
                raw['label'] as String,
                (raw['count'] as num).toInt(),
                (raw['midpoint'] as num).toDouble(),
              ),
            )
            .toList();
    List<CohortGroupStat> groups(String key) =>
        ((data[key] as List?) ?? const [])
            .map(
              (raw) => CohortGroupStat(
                label: raw['label'] as String,
                count: (raw['count'] as num).toInt(),
                meanEnergy: (raw['meanEnergy'] as num).toDouble(),
                meanCognitive: (raw['meanCognitive'] as num).toDouble(),
              ),
            )
            .toList();
    return CohortSummary(
      n: (data['n'] as num?)?.toInt() ?? 0,
      meanEnergy: (data['meanEnergy'] as num?)?.toDouble() ?? 0,
      medianEnergy: (data['medianEnergy'] as num?)?.toDouble() ?? 0,
      meanCognitive: (data['meanCognitive'] as num?)?.toDouble() ?? 0,
      medianCognitive: (data['medianCognitive'] as num?)?.toDouble() ?? 0,
      energyHistogram: hist('energyHistogram'),
      cognitiveHistogram: hist('cognitiveHistogram'),
      byEducation: groups('byEducation'),
      byGender: groups('byGender'),
      sleepVsEnergy: const [],
      screenVsCognitive: const [],
      studyVsCognitive: const [],
      exerciseVsEnergy: const [],
      caffeineVsEnergy: const [],
    );
  }
}

abstract final class CohortStats {
  static CohortSummary summarize(
    List<SyntheticPerson> people, {
    int scatterSample = 400,
  }) {
    if (people.isEmpty) {
      return const CohortSummary(
        n: 0,
        meanEnergy: 0,
        medianEnergy: 0,
        meanCognitive: 0,
        medianCognitive: 0,
        energyHistogram: [],
        cognitiveHistogram: [],
        byEducation: [],
        byGender: [],
        sleepVsEnergy: [],
        screenVsCognitive: [],
        studyVsCognitive: [],
        exerciseVsEnergy: [],
        caffeineVsEnergy: [],
      );
    }

    final energies = people.map((p) => p.score.energy.toDouble()).toList()
      ..sort();
    final cognitives = people.map((p) => p.score.cognitive.toDouble()).toList()
      ..sort();

    return CohortSummary(
      n: people.length,
      meanEnergy: _mean(energies),
      medianEnergy: _median(energies),
      meanCognitive: _mean(cognitives),
      medianCognitive: _median(cognitives),
      energyHistogram: histogram(energies, binWidth: 10, max: 100),
      cognitiveHistogram: histogram(cognitives, binWidth: 10, max: 100),
      byEducation: groupBy(people, (p) => p.education),
      byGender: groupBy(people, (p) => p.gender),
      sleepVsEnergy: sampleScatter(
        people,
        (p) => p.avgSleepHours,
        (p) => p.score.energy.toDouble(),
        sample: scatterSample,
      ),
      screenVsCognitive: sampleScatter(
        people,
        (p) => p.foldedScreenHours,
        (p) => p.score.cognitive.toDouble(),
        sample: scatterSample,
      ),
      studyVsCognitive: sampleScatter(
        people,
        (p) => p.studyHours,
        (p) => p.score.cognitive.toDouble(),
        sample: scatterSample,
      ),
      exerciseVsEnergy: sampleScatter(
        people,
        (p) => p.exerciseHoursDaily,
        (p) => p.score.energy.toDouble(),
        sample: scatterSample,
      ),
      caffeineVsEnergy: sampleScatter(
        people,
        (p) => p.caffeineDrinks,
        (p) => p.score.energy.toDouble(),
        sample: scatterSample,
      ),
    );
  }

  static List<CohortHistogramBin> histogram(
    List<double> values, {
    required double binWidth,
    required double max,
  }) {
    final bins = <CohortHistogramBin>[];
    for (var start = 0.0; start < max; start += binWidth) {
      final end = start + binWidth;
      final count = values
          .where((value) => value >= start && value < end)
          .length;
      // Include the exact max in the final bin.
      final inclusiveCount = end >= max
          ? values.where((value) => value >= start && value <= max).length
          : count;
      bins.add(
        CohortHistogramBin(
          '${start.round()}–${end.round()}',
          inclusiveCount,
          start + binWidth / 2,
        ),
      );
    }
    return bins;
  }

  static List<CohortGroupStat> groupBy(
    List<SyntheticPerson> people,
    String Function(SyntheticPerson) keyOf,
  ) {
    final groups = <String, List<SyntheticPerson>>{};
    for (final person in people) {
      groups.putIfAbsent(keyOf(person), () => []).add(person);
    }
    final stats = groups.entries.map((entry) {
      final energies = entry.value.map((p) => p.score.energy.toDouble());
      final cognitives = entry.value.map((p) => p.score.cognitive.toDouble());
      return CohortGroupStat(
        label: entry.key,
        count: entry.value.length,
        meanEnergy: _mean(energies.toList()),
        meanCognitive: _mean(cognitives.toList()),
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return stats;
  }

  static List<CohortScatterPoint> sampleScatter(
    List<SyntheticPerson> people,
    double Function(SyntheticPerson) xOf,
    double Function(SyntheticPerson) yOf, {
    required int sample,
  }) {
    if (people.isEmpty) return const [];
    if (people.length <= sample) {
      return people
          .map((p) => CohortScatterPoint(xOf(p), yOf(p), p.id))
          .toList();
    }
    final step = people.length / sample;
    final points = <CohortScatterPoint>[];
    for (var i = 0; i < sample; i++) {
      final person = people[(i * step).floor()];
      points.add(CohortScatterPoint(xOf(person), yOf(person), person.id));
    }
    return points;
  }

  static double _mean(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static double correlation(
    List<double> xs,
    List<double> ys,
  ) {
    if (xs.length != ys.length || xs.length < 2) return 0;
    final meanX = _mean(xs);
    final meanY = _mean(ys);
    var num = 0.0;
    var denX = 0.0;
    var denY = 0.0;
    for (var i = 0; i < xs.length; i++) {
      final dx = xs[i] - meanX;
      final dy = ys[i] - meanY;
      num += dx * dy;
      denX += dx * dx;
      denY += dy * dy;
    }
    final den = math.sqrt(denX * denY);
    if (den == 0) return 0;
    return num / den;
  }
}
