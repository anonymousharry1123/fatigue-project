import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import 'check_in_measurement.dart';
import 'timezone_database.dart';

/// Source variants are separate experiments; neither silently fills the other.
enum Ai1SleepSource { manual, appleHealth }

/// Stable JSON for exact snapshots: map order is irrelevant, list order is not.
String ai1CanonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw const FormatException('AI-1 JSON keys must be strings.');
    }
    final keys = value.keys.cast<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  return value;
}

/// Draft configuration for offline synthetic checks, not collection approval.
class Ai1Protocol {
  Ai1Protocol._({required this.sleepSource, required this.measurement});

  factory Ai1Protocol.draft({
    Ai1SleepSource sleepSource = Ai1SleepSource.manual,
  }) => Ai1Protocol._(
    sleepSource: sleepSource,
    measurement: canonicalMeasurement({
      ...CheckInMeasurement.snapshot(language: 'en', translate: (text) => text),
      'sharedHeading': 'How do you feel right now?',
    }),
  );

  static const draftVersion = 'tonyo-sleep-evening-energy-v0.3-draft';

  final Ai1SleepSource sleepSource;

  /// Includes the shared heading, language, recall and all ordered items.
  final String measurement;

  String get version => draftVersion;
  String get id => jsonEncode([version, sleepSource.name, 'en']);

  static String canonicalMeasurement(Map<String, dynamic> measurement) =>
      ai1CanonicalJson(measurement);
}

/// One calendar opportunity with immutable UTC boundaries in a frozen zone.
class Ai1Opportunity {
  Ai1Opportunity._({
    required this.id,
    required this.protocolId,
    required this.participantKey,
    required this.localDate,
    required this.timezone,
    required this.dayStart,
    required this.cutoff,
    required this.issuanceDeadline,
    required this.outcomeStart,
    required this.outcomeEnd,
  });

  factory Ai1Opportunity.forDate({
    required Ai1Protocol protocol,
    required String participantKey,
    required String localDate,
    required String timezone,
  }) {
    if (participantKey.trim().isEmpty || timezone.trim().isEmpty) {
      throw const FormatException('Participant and timezone must be nonempty.');
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(localDate);
    if (match == null) {
      throw const FormatException('Local date must be YYYY-MM-DD.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    if (year < 1 ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      throw const FormatException('Local date must be a valid Gregorian date.');
    }

    initializeTimezoneDatabase();
    final tz.Location location;
    try {
      location = tz.getLocation(timezone);
    } on tz.LocationNotFoundException {
      throw FormatException('Unknown IANA timezone: $timezone');
    }

    DateTime boundary(int hour, [int minute = 0]) =>
        _uniqueBoundary(location, DateTime.utc(year, month, day, hour, minute));

    return Ai1Opportunity._(
      // The zone is metadata, not permission to issue twice on one date.
      id: jsonEncode([protocol.id, participantKey, localDate]),
      protocolId: protocol.id,
      participantKey: participantKey,
      localDate: localDate,
      timezone: timezone,
      dayStart: boundary(0),
      cutoff: boundary(10),
      issuanceDeadline: boundary(10, 15),
      outcomeStart: boundary(18),
      outcomeEnd: boundary(22),
    );
  }

  final String id;
  final String protocolId;
  final String participantKey;
  final String localDate;
  final String timezone;
  final DateTime dayStart;
  final DateTime cutoff;
  final DateTime issuanceDeadline;
  final DateTime outcomeStart;
  final DateTime outcomeEnd;
}

/// TZDateTime normalizes gaps and picks one side of overlaps. A prospective
/// opportunity must instead reject either case explicitly.
DateTime _uniqueBoundary(tz.Location location, DateTime wallClock) {
  final offsets = location.zones.map((zone) => zone.offset).toSet();
  if (offsets.isEmpty) offsets.add(Duration.zero);
  final candidates = <DateTime>{};
  for (final offset in offsets) {
    final candidate = wallClock.subtract(offset);
    final local = tz.TZDateTime.from(candidate, location);
    if (local.year == wallClock.year &&
        local.month == wallClock.month &&
        local.day == wallClock.day &&
        local.hour == wallClock.hour &&
        local.minute == wallClock.minute &&
        local.second == wallClock.second &&
        local.millisecond == wallClock.millisecond &&
        local.microsecond == wallClock.microsecond) {
      candidates.add(candidate);
    }
  }
  if (candidates.length != 1) {
    throw FormatException(
      'AI-1 boundary ${wallClock.toIso8601String()} in ${location.name} is '
      '${candidates.isEmpty ? 'nonexistent' : 'ambiguous'}.',
    );
  }
  return candidates.single;
}
