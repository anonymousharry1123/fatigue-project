import 'ai1_protocol.dart';

/// Whitelist for the extra on-device study records. No account identifiers,
/// notes, fitted outputs or arbitrary payloads belong in this schema.
void validateAi1StudyData(Map<String, Object?> data) {
  DateTime time(Object? value) {
    if (value is! String) throw const FormatException('Invalid study time.');
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
      throw const FormatException('Invalid study time.');
    }
    return parsed;
  }

  void keys(Set<String> expected) {
    if (data.length != expected.length || !expected.every(data.containsKey)) {
      throw const FormatException('Unexpected study fields.');
    }
  }

  time(data['observedAt']);
  switch (data['kind']) {
    case 'plan':
      keys({
        'kind',
        'observedAt',
        'startDate',
        'endDate',
        'timezone',
        'source',
        'protocolVersion',
      });
      if (data['protocolVersion'] != Ai1Protocol.draftVersion ||
          !Ai1SleepSource.values.any((s) => s.name == data['source'])) {
        throw const FormatException('Unsupported study protocol.');
      }
      final protocol = Ai1Protocol.draft();
      final start = Ai1Opportunity.forDate(
        protocol: protocol,
        participantKey: 'validation',
        localDate: data['startDate'] as String,
        timezone: data['timezone'] as String,
      );
      final end = Ai1Opportunity.forDate(
        protocol: protocol,
        participantKey: 'validation',
        localDate: data['endDate'] as String,
        timezone: data['timezone'] as String,
      );
      final days = DateTime.parse(
        data['endDate'] as String,
      ).difference(DateTime.parse(data['startDate'] as String)).inDays;
      if (days < 0 ||
          days > 365 ||
          !time(data['observedAt']).isBefore(start.dayStart) ||
          end.dayStart.isBefore(start.dayStart)) {
        throw const FormatException('Plan must start on a future local date.');
      }
    case 'event':
      keys({
        'kind',
        'observedAt',
        'localDate',
        'timezone',
        'source',
        'sleepStatus',
        'feature',
      });
      Ai1Opportunity.forDate(
        protocol: Ai1Protocol.draft(),
        participantKey: 'validation',
        localDate: data['localDate'] as String,
        timezone: data['timezone'] as String,
      );
      if (!Ai1SleepSource.values.any((s) => s.name == data['source']) ||
          data['sleepStatus'] is! String) {
        throw const FormatException('Invalid study event.');
      }
      final feature = data['feature'];
      if (feature != null) {
        if (feature is! Map ||
            feature.length != 6 ||
            !{
              'sourceKey',
              'revision',
              'durationHours',
              'startedAt',
              'endedAt',
              'availableAt',
            }.every(feature.containsKey) ||
            feature['sourceKey'] is! String ||
            feature['revision'] is! int ||
            (feature['revision'] as int) < 1 ||
            feature['durationHours'] is! num ||
            !(feature['durationHours'] as num).isFinite ||
            (feature['durationHours'] as num) < 0.5 ||
            (feature['durationHours'] as num) > 16) {
          throw const FormatException('Invalid frozen feature.');
        }
        time(feature['endedAt']);
        time(feature['availableAt']);
        if (feature['startedAt'] != null) time(feature['startedAt']);
      }
      if ((data['sleepStatus'] == 'eligible') != (feature != null)) {
        throw const FormatException('Feature status mismatch.');
      }
    case 'health':
      keys({'kind', 'observedAt', 'samples'});
      final samples = data['samples'];
      if (samples is! List || samples.length > 10000) {
        throw const FormatException('Invalid Health snapshot.');
      }
      final ids = <String>{};
      for (final raw in samples) {
        if (raw is! Map ||
            raw.length != 5 ||
            !{
              'id',
              'type',
              'value',
              'timestamp',
              'sourceGroup',
            }.every(raw.containsKey) ||
            raw['id'] is! String ||
            (raw['id'] as String).trim().isEmpty ||
            (raw['id'] as String).length > 200 ||
            !ids.add(raw['id'] as String) ||
            raw['sourceGroup'] is! String ||
            (raw['sourceGroup'] as String).trim().isEmpty ||
            (raw['sourceGroup'] as String).length > 200 ||
            !{
              'sleepAwake',
              'sleepCore',
              'sleepDeep',
              'sleepRem',
              'sleepUnspecified',
            }.contains(raw['type']) ||
            raw['value'] is! num ||
            !(raw['value'] as num).isFinite ||
            (raw['value'] as num) <= 0 ||
            (raw['value'] as num) > 24 ||
            time(raw['timestamp']).isAfter(time(data['observedAt']))) {
          throw const FormatException('Invalid Health sample.');
        }
      }
    case 'timezone':
      keys({'kind', 'observedAt'});
    default:
      throw const FormatException('Unknown study record kind.');
  }
}
