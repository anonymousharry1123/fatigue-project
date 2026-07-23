import 'models.dart';

/// Pure helpers for Version 0.9 reaction-time benchmarks.
abstract final class ReactionTestLogic {
  static const roundsRequired = 3;
  static const minValidMs = 100;
  static const maxValidMs = 1500;
  static const minBaselineSamples = 2;

  static bool isValidReaction(int milliseconds) =>
      milliseconds >= minValidMs && milliseconds <= maxValidMs;

  static double averageMs(List<int> results) {
    if (results.isEmpty) {
      throw ArgumentError('Cannot average an empty reaction result list');
    }
    return results.reduce((a, b) => a + b) / results.length;
  }

  /// Rolling personal baseline from prior reaction signals (newest first).
  static double? baselineMs(
    List<SignalReading> signals, {
    int minSamples = minBaselineSamples,
    SignalReading? exclude,
  }) {
    final values = signals
        .where(
          (item) =>
              item.type == SignalType.reactionTime &&
              (exclude == null || item.id != exclude.id),
        )
        .map((item) => item.value)
        .where((value) => isValidReaction(value.round()))
        .take(14)
        .toList();
    if (values.length < minSamples) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static int deltaMs(double result, double baseline) =>
      (result - baseline).round();

  static String comparisonLabel(double result, double baseline) {
    final delta = deltaMs(result, baseline);
    if (delta.abs() <= 15) return 'Near your baseline';
    if (delta < 0) return '${delta.abs()} ms faster than baseline';
    return '$delta ms slower than baseline';
  }

  static bool isComplete(List<int> validResults) =>
      validResults.length >= roundsRequired;
}
