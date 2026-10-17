import 'ai1_protocol.dart';

/// A retained revision and its known availability on the prediction device.
/// These fixture records deliberately do not adapt mutable application data.
/// Fixture histories start at revision one and retain consecutive revisions.
class Ai1SleepRevision {
  Ai1SleepRevision({
    required this.participantKey,
    required this.collection,
    required this.sourceId,
    required this.revision,
    required this.source,
    required DateTime endedAt,
    DateTime? startedAt,
    required this.durationHours,
    DateTime? availableAt,
    List<DateTime?> selectionDependencies = const [],
    this.lineageComplete = true,
    this.isMainSleep = true,
    this.deleted = false,
  }) : endedAt = endedAt.toUtc(),
       startedAt = startedAt?.toUtc(),
       availableAt = availableAt?.toUtc(),
       selectionDependencies = List.unmodifiable(
         selectionDependencies.map((time) => time?.toUtc()),
       );

  final String participantKey;
  final String collection;
  final String sourceId;
  final int revision;
  final Ai1SleepSource source;
  final DateTime endedAt;
  final DateTime? startedAt;
  final double durationHours;
  final DateTime? availableAt;
  final List<DateTime?> selectionDependencies;
  final bool lineageComplete;
  final bool isMainSleep;
  final bool deleted;

  String get key => ai1CanonicalJson([collection, sourceId]);

  String get fingerprint => ai1CanonicalJson({
    'participantKey': participantKey,
    'collection': collection,
    'sourceId': sourceId,
    'revision': revision,
    'source': source.name,
    'endedAt': endedAt.toIso8601String(),
    'startedAt': startedAt?.toIso8601String(),
    'durationHours': _fingerprintNumber(durationHours),
    'availableAt': availableAt?.toIso8601String(),
    'selectionDependencies': [
      for (final time in selectionDependencies) time?.toIso8601String(),
    ],
    'lineageComplete': lineageComplete,
    'isMainSleep': isMainSleep,
    'deleted': deleted,
  });
}

/// An original response or later correction; revision one is the original.
/// No notes or account identifiers belong in this offline fixture schema.
/// Revisions represent substantive measurement edits, not note-only saves.
/// [initialSavedAt] is the original local durable completion; [availableAt]
/// is when this revision became available to the analysis (uploads may be late).
class Ai1ResponseRevision {
  Ai1ResponseRevision({
    required this.participantKey,
    required this.sourceId,
    required this.revision,
    required DateTime observedAt,
    required DateTime initialSavedAt,
    required DateTime availableAt,
    required this.localDate,
    required this.timezone,
    required this.measurement,
    required this.period,
    required this.energy,
    this.lineageComplete = true,
    this.deleted = false,
  }) : observedAt = observedAt.toUtc(),
       initialSavedAt = initialSavedAt.toUtc(),
       availableAt = availableAt.toUtc();

  final String participantKey;
  final String sourceId;
  final int revision;
  final DateTime observedAt;
  final DateTime initialSavedAt;
  final DateTime availableAt;
  final String localDate;
  final String timezone;
  final String measurement;
  final String period;
  final num? energy;
  final bool lineageComplete;
  final bool deleted;

  String get key => sourceId;

  String get fingerprint => ai1CanonicalJson({
    'participantKey': participantKey,
    'sourceId': sourceId,
    'revision': revision,
    'observedAt': observedAt.toIso8601String(),
    'initialSavedAt': initialSavedAt.toIso8601String(),
    'availableAt': availableAt.toIso8601String(),
    'localDate': localDate,
    'timezone': timezone,
    'measurement': measurement,
    'period': period,
    'energy': _fingerprintNumber(energy),
    'lineageComplete': lineageComplete,
    'deleted': deleted,
  });
}

/// Explicitly synthetic, local input for offline protocol checks only.
/// A caller cannot turn this record into evidence of a real durable save.
class Ai1FixtureDay {
  Ai1FixtureDay({
    required this.opportunity,
    required this.synthetic,
    required this.sleepHistoryComplete,
    required this.responseHistoryComplete,
    required List<Ai1SleepRevision> sleepRevisions,
    required List<Ai1ResponseRevision> responseRevisions,
    DateTime? issuedAt,
    DateTime? durableAt,
    List<DateTime> timezoneChanges = const [],
    this.withdrawn = false,
  }) : sleepRevisions = List.unmodifiable(sleepRevisions),
       responseRevisions = List.unmodifiable(responseRevisions),
       issuedAt = issuedAt?.toUtc(),
       durableAt = durableAt?.toUtc(),
       timezoneChanges = List.unmodifiable(
         timezoneChanges.map((time) => time.toUtc()),
       );

  final Ai1Opportunity opportunity;
  final bool synthetic;
  final bool sleepHistoryComplete;
  final bool responseHistoryComplete;
  final List<Ai1SleepRevision> sleepRevisions;
  final List<Ai1ResponseRevision> responseRevisions;
  final DateTime? issuedAt;
  final DateTime? durableAt;
  final List<DateTime> timezoneChanges;
  final bool withdrawn;
}

// Invalid numeric fixture values must be auditable without JSON encoding
// throwing before the builder can classify them as invalid.
Object? _fingerprintNumber(num? value) => value == null || value.isFinite
    ? value
    : {'nonFiniteNumber': value.toString()};
