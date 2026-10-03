import 'models.dart';

/// Shared provenance markers used by existing score explanations and sleep
/// displays. A fixture's source enum never establishes a genuine Health import.
abstract final class EvidenceProvenance {
  static final _demoMarker = RegExp(
    r'(^|[^a-z])(seed(?:ed)?|synthetic|fake|demo|fixture|cohort)([^a-z]|$)',
    caseSensitive: false,
  );

  static bool hasDemoMarker(Iterable<String> values) =>
      values.any(_demoMarker.hasMatch);

  static bool signalIsDemo(SignalReading reading) =>
      hasDemoMarker([reading.id, reading.groupId ?? '', reading.note ?? '']);
}
