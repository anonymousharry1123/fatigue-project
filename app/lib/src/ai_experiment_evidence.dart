import 'ai1_dataset_builder.dart';
import 'ai1_records.dart';

/// Shared operational rules for explicitly synthetic comparison consumers.
/// A successful status is not permission to use a real participant's records.
abstract final class AiExperimentEvidence {
  static String executionStatus(Ai1FixtureDay day) {
    if (day.withdrawn) return 'withdrawn';
    final issued = day.issuedAt;
    if (issued == null) return 'not_executed';
    final opportunity = day.opportunity;
    bool inWindow(DateTime time) =>
        !time.isBefore(opportunity.cutoff) &&
        time.isBefore(opportunity.issuanceDeadline);
    if (!inWindow(issued)) return 'missed_window';
    final durable = day.durableAt;
    if (durable == null || durable.isBefore(issued)) return 'save_not_proven';
    if (!inWindow(durable)) return 'missed_window';
    if (day.timezoneChanges.any((time) => !time.isAfter(durable))) {
      return 'timezone_changed_before_execution';
    }
    return 'executed';
  }

  static ({String status, int? energy}) target(
    Ai1FixtureDay day,
    Ai1DatasetRow row,
  ) {
    if (row.outcomeStatus != 'matched') {
      return (status: row.outcomeStatus, energy: null);
    }
    if (day.timezoneChanges.any(
      (time) => !time.isAfter(row.outcome!.observedAt),
    )) {
      return (status: 'timezone_changed', energy: null);
    }
    return (status: 'matched', energy: row.energy);
  }
}
