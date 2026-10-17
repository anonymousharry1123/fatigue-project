import 'dart:convert';
import 'dart:math';

import 'ai1_capture.dart';
import 'ai1_dataset_builder.dart';
import 'ai1_protocol.dart';
import 'ai1_records.dart';
import 'models.dart';
import 'sleep_sync_logic.dart';

/// An explicitly started, single-device measurement plan. Morning records are
/// feature snapshots, not model predictions: AI-3 has not selected a model.
class Ai1Study {
  Ai1Study(this.journal);
  final Ai1CaptureJournal journal;

  Ai1CaptureEntry? get plan => journal.entries
      .where((e) => e.collection == 'study' && e.data['kind'] == 'plan')
      .firstOrNull;
  bool get active => journal.enabled && plan?.lineageComplete == true;
  Ai1Protocol get protocol => Ai1Protocol.draft(
    sleepSource: Ai1SleepSource.values.byName(plan!.data['source'] as String),
  );
  String get participantKey => journal.captureId!;

  /// Each plan starts tomorrow or later. Replacing it requires clearing history.
  Future<void> start({
    required String owner,
    required String timezone,
    required String startDate,
    required String endDate,
    required Ai1SleepSource source,
    required DateTime now,
  }) async {
    if (!journal.enabled || journal.owner != owner) {
      throw StateError('Enable local study history first.');
    }
    if (plan != null) {
      throw StateError('Clear history before changing the study plan.');
    }
    // Validate every calendar day now, including skipped/ambiguous dates.
    for (final date in dates(startDate, endDate)) {
      Ai1Opportunity.forDate(
        protocol: Ai1Protocol.draft(sleepSource: source),
        participantKey: participantKey,
        localDate: date,
        timezone: timezone,
      );
    }
    await journal.capture(
      owner: owner,
      observation: Ai1CaptureObservation.study(
        sourceId: 'plan',
        data: {
          'kind': 'plan',
          'observedAt': now.toUtc().toIso8601String(),
          'startDate': startDate,
          'endDate': endDate,
          'timezone': timezone,
          'source': source.name,
          'protocolVersion': Ai1Protocol.draftVersion,
        },
      ),
    );
    if (!active) throw StateError('The study plan could not be saved.');
    try {
      opportunities;
    } on Object {
      journal.pauseAfterCaptureFailure();
      rethrow;
    }
  }

  static List<String> dates(String startDate, String endDate) {
    final start = DateTime.tryParse('${startDate}T00:00:00Z');
    final end = DateTime.tryParse('${endDate}T00:00:00Z');
    if (start == null ||
        end == null ||
        dateKey(start) != startDate ||
        dateKey(end) != endDate ||
        end.isBefore(start) ||
        end.difference(start).inDays > 365) {
      throw const FormatException('Use a valid study calendar of 1–366 days.');
    }
    return [
      for (
        var day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))
      )
        dateKey(day),
    ];
  }

  static String dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  List<Ai1Opportunity> get opportunities {
    final saved = plan;
    if (saved == null || !saved.lineageComplete) return const [];
    final list =
        dates(
              saved.data['startDate'] as String,
              saved.data['endDate'] as String,
            )
            .map(
              (date) => Ai1Opportunity.forDate(
                protocol: protocol,
                participantKey: participantKey,
                localDate: date,
                timezone: saved.data['timezone'] as String,
              ),
            )
            .toList();
    // Native receipt, not the UI request time, proves advance scheduling.
    if (saved.acknowledgedAt == null ||
        !saved.acknowledgedAt!.isBefore(list.first.dayStart)) {
      throw StateError('Study scheduling was not saved before its first day.');
    }
    return list;
  }

  Future<void> tick({
    required String owner,
    required DateTime now,
    required String? deviceTimezone,
  }) async {
    // A queued or partly receipted write may change the cutoff selection.
    // Wait for a later execution rather than silently reading its predecessor.
    if (!active || journal.busy || journal.owner != owner) return;
    final at = now.toUtc();
    if (deviceTimezone != plan!.data['timezone']) {
      await journal.capture(
        owner: owner,
        observation: Ai1CaptureObservation.study(
          sourceId: 'timezone-change',
          data: {'kind': 'timezone', 'observedAt': at.toIso8601String()},
        ),
      );
      return;
    }
    // Freeze the first observed zone change; never infer travel while suspended.
    if (journal.entries.any(
      (e) => e.collection == 'study' && e.data['kind'] == 'timezone',
    )) {
      return;
    }
    final opportunity = opportunities
        .where((o) => !at.isBefore(o.cutoff) && at.isBefore(o.issuanceDeadline))
        .firstOrNull;
    if (opportunity == null) return; // No backdated events for unopened days.
    final sourceId = 'event-${opportunity.localDate}';
    if (journal.entries.any(
      (e) => e.collection == 'study' && e.sourceId == sourceId,
    )) {
      return;
    }
    final day = _day(opportunity, asOf: at, useEvent: false);
    final selected = Ai1DatasetBuilder.selectSleep(protocol, day);
    final row = selected.record;
    await journal.capture(
      owner: owner,
      observation: Ai1CaptureObservation.study(
        sourceId: sourceId,
        data: {
          'kind': 'event',
          'observedAt': at.toIso8601String(),
          'localDate': opportunity.localDate,
          'timezone': opportunity.timezone,
          'source': protocol.sleepSource.name,
          'sleepStatus': selected.status,
          'feature': row == null ? null : featureJson(row),
        },
      ),
    );
  }

  static Map<String, Object?> featureJson(Ai1SleepRevision row) => {
    'sourceKey': row.key,
    'revision': row.revision,
    'durationHours': row.durationHours,
    'startedAt': row.startedAt?.toIso8601String(),
    'endedAt': row.endedAt.toIso8601String(),
    'availableAt': row.availableAt?.toIso8601String(),
  };

  /// Capture successful native query output before app source reconciliation.
  /// Query receipts prove device availability, not complete Health permission.
  /// Retained sample ends span the first day's 24-hour lead-in through the
  /// final prediction cutoff. Later queries may correct those in-scope samples
  /// but cannot extend the saved Health history beyond the study calendar.
  Future<void> captureHealth({
    required String owner,
    required DateTime now,
    required List<SignalReading> samples,
    bool Function()? isCurrent,
  }) async {
    if ((isCurrent != null && !isCurrent()) ||
        !active ||
        journal.owner != owner ||
        protocol.sleepSource != Ai1SleepSource.appleHealth) {
      return;
    }
    final calendar = opportunities;
    final firstDay = calendar.first.dayStart;
    final minimum = firstDay.subtract(const Duration(hours: 24));
    final maximum = calendar.last.cutoff;
    final retained = samples.where((r) {
      final endedAt = r.timestamp.toUtc();
      return !endedAt.isBefore(minimum) && !endedAt.isAfter(maximum);
    }).toList();
    // Fail on conflicting IDs; collapse only byte-equivalent repeat samples.
    final byId = <String, Map<String, Object?>>{};
    for (final row in retained) {
      if (row.source != SignalSource.healthKit ||
          !SleepSyncLogic.stageTypes.contains(row.type) ||
          row.id.trim().isEmpty ||
          row.id.length > 200 ||
          row.groupId == null ||
          row.groupId!.trim().isEmpty ||
          row.groupId!.length > 200) {
        journal.pauseAfterCaptureFailure();
        return;
      }
      final value = <String, Object?>{
        'id': row.id,
        'type': row.type.name,
        'value': row.value,
        'timestamp': row.timestamp.toUtc().toIso8601String(),
        'sourceGroup': row.groupId!,
      };
      if (byId.containsKey(row.id) &&
          ai1CanonicalJson(byId[row.id]) != ai1CanonicalJson(value)) {
        journal.pauseAfterCaptureFailure();
        return;
      }
      byId[row.id] = value;
    }
    final prior = journal.entries
        .where((e) => e.collection == 'study' && e.data['kind'] == 'health')
        .lastOrNull;
    if (prior != null) {
      final oldSamples = (prior.data['samples'] as List).cast<Map>();
      // The native query uses strict sample starts in its last 30 calendar
      // days. Only recent 29-elapsed-day starts are safely inside that window
      // despite DST. Older absence may just be rolling-window expiry; retain
      // those historical copies until explicit erasure. Recent absence is
      // observed readable absence, not proof of deletion or complete access.
      final recentStart = now.toUtc().subtract(const Duration(days: 29));
      bool recentlyMissing(Map sample) {
        final end = DateTime.parse(sample['timestamp'] as String);
        final start = end.subtract(
          Duration(
            microseconds:
                ((sample['value'] as num) * Duration.microsecondsPerHour)
                    .round(),
          ),
        );
        return !start.isBefore(recentStart) && !byId.containsKey(sample['id']);
      }

      if (oldSamples.any(recentlyMissing)) {
        for (final entry
            in journal.entries
                .where(
                  (e) => e.collection == 'study' && e.data['kind'] == 'health',
                )
                .toList()) {
          if ((isCurrent != null && !isCurrent()) ||
              !active ||
              journal.owner != owner) {
            return;
          }
          await journal.deleteSource(
            owner: owner,
            collection: 'study',
            sourceId: entry.sourceId,
          );
        }
      }
    }
    final sorted = byId.values.toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    if (prior != null &&
        ai1CanonicalJson(prior.data['samples']) == ai1CanonicalJson(sorted)) {
      return;
    }
    if ((isCurrent != null && !isCurrent()) ||
        !active ||
        journal.owner != owner) {
      return;
    }
    await journal.capture(
      owner: owner,
      observation: Ai1CaptureObservation.study(
        sourceId:
            'health-${now.toUtc().microsecondsSinceEpoch}-${base64Url.encode(List.generate(12, (_) => Random.secure().nextInt(256)))}',
        data: {
          'kind': 'health',
          'observedAt': now.toUtc().toIso8601String(),
          'samples': sorted,
        },
      ),
    );
  }

  List<Ai1ResponseRevision> get responses {
    final initial = <String, DateTime>{};
    final result = <Ai1ResponseRevision>[];
    for (final e in journal.entries.where((e) => e.collection == 'checkIns')) {
      final receipt = e.acknowledgedAt;
      if (receipt == null) continue;
      initial.putIfAbsent(e.key, () => receipt);
      result.add(
        Ai1ResponseRevision(
          participantKey: participantKey,
          sourceId: e.sourceId,
          revision: e.revision,
          observedAt: DateTime.parse(e.data['observedAt'] as String),
          initialSavedAt: initial[e.key]!,
          availableAt: receipt,
          localDate: e.data['localDate'] as String,
          timezone: e.data['timezone'] as String? ?? 'unknown',
          measurement: Ai1Protocol.canonicalMeasurement({
            ...Map<String, dynamic>.from(e.data['definition'] as Map),
            'sharedHeading': e.data['sharedHeading'],
          }),
          period: e.data['period'] == 'evening' ? 'Evening' : 'Morning',
          energy: (e.data['ratings'] as Map)['energy'] as num?,
          lineageComplete: e.lineageComplete,
        ),
      );
    }
    return result;
  }

  Ai1FixtureDay _day(
    Ai1Opportunity o, {
    required DateTime asOf,
    bool useEvent = true,
  }) {
    final sleep = <Ai1SleepRevision>[];
    var complete = journal.enabled;
    final deletedKinds = journal.tombstones
        .map((key) => jsonDecode(key) as List)
        .toList();
    if (protocol.sleepSource == Ai1SleepSource.manual) {
      complete &= !deletedKinds.any((key) => key[0] == 'sleepLogs');
      final entries = journal.entries
          .where((e) => e.collection == 'sleepLogs')
          .toList();
      final keys = entries
          .where((e) {
            final end = DateTime.parse(e.data['endedAt'] as String);
            return !end.isBefore(o.dayStart) && !end.isAfter(o.cutoff);
          })
          .map((e) => e.key)
          .toSet();
      for (final e in entries.where((e) => keys.contains(e.key))) {
        sleep.add(
          Ai1SleepRevision(
            participantKey: participantKey,
            collection: e.collection,
            sourceId: e.sourceId,
            revision: e.revision,
            source: Ai1SleepSource.manual,
            endedAt: DateTime.parse(e.data['endedAt'] as String),
            startedAt: DateTime.parse(e.data['startedAt'] as String),
            durationHours: (e.data['durationHours'] as num).toDouble(),
            availableAt: e.acknowledgedAt,
            lineageComplete: e.lineageComplete,
            isMainSleep: e.data['isNap'] == false,
          ),
        );
      }
    } else {
      complete &= !deletedKinds.any(
        (key) => key[0] == 'study' && (key[1] as String).startsWith('health-'),
      );
      final batches = journal.entries
          .where(
            (e) =>
                e.collection == 'study' &&
                e.data['kind'] == 'health' &&
                e.acknowledgedAt != null &&
                !e.acknowledgedAt!.isAfter(o.cutoff),
          )
          .toList();
      if (batches.isEmpty) {
        complete = false;
      } else {
        final batch = batches.last;
        complete &= batch.lineageComplete;
        final samples = (batch.data['samples'] as List).cast<Map>().map(
          (s) => SignalReading(
            id: s['id'] as String,
            type: SignalType.values.byName(s['type'] as String),
            value: (s['value'] as num).toDouble(),
            timestamp: DateTime.parse(s['timestamp'] as String),
            source: SignalSource.healthKit,
            quality: 1,
            groupId: s['sourceGroup'] as String,
          ),
        );
        try {
          final episodes = SleepSyncLogic.studyEpisodes(samples);
          for (var index = 0; index < episodes.length; index++) {
            final e = episodes[index];
            sleep.add(
              Ai1SleepRevision(
                participantKey: participantKey,
                collection: 'healthQueries',
                sourceId: '${batch.sourceId}:$index',
                revision: 1,
                source: Ai1SleepSource.appleHealth,
                endedAt: e.end,
                startedAt: e.start,
                durationHours: e.hours,
                availableAt: batch.acknowledgedAt,
                selectionDependencies: [batch.acknowledgedAt],
                lineageComplete: batch.lineageComplete,
              ),
            );
          }
        } on FormatException {
          complete = false;
        }
      }
    }
    final event = useEvent
        ? journal.entries
              .where(
                (e) =>
                    e.collection == 'study' &&
                    e.sourceId == 'event-${o.localDate}' &&
                    e.acknowledgedAt != null &&
                    !e.acknowledgedAt!.isAfter(asOf),
              )
              .firstOrNull
        : null;
    final responseList = responses;
    final responseKeys = responseList
        .where((r) => r.localDate == o.localDate)
        .map((r) => r.key)
        .toSet();
    final day = Ai1FixtureDay(
      opportunity: o,
      synthetic: false,
      sleepHistoryComplete: complete,
      responseHistoryComplete:
          journal.enabled && !deletedKinds.any((key) => key[0] == 'checkIns'),
      sleepRevisions: sleep,
      responseRevisions: responseList
          .where((r) => responseKeys.contains(r.key))
          .toList(),
      issuedAt: event == null
          ? null
          : DateTime.parse(event.data['observedAt'] as String),
      durableAt: event?.lineageComplete == true ? event!.acknowledgedAt : null,
      timezoneChanges: journal.entries
          .where((e) => e.collection == 'study' && e.data['kind'] == 'timezone')
          .where(
            (e) => e.acknowledgedAt != null && !e.acknowledgedAt!.isAfter(asOf),
          )
          .map((e) => DateTime.parse(e.data['observedAt'] as String))
          .toList(),
    );
    if (event != null) {
      final selected = Ai1DatasetBuilder.selectSleep(protocol, day);
      final expected = selected.record == null
          ? null
          : featureJson(selected.record!);
      if (event.data['source'] != protocol.sleepSource.name ||
          event.data['timezone'] != o.timezone ||
          event.data['localDate'] != o.localDate ||
          event.data['sleepStatus'] != selected.status ||
          ai1CanonicalJson(event.data['feature']) !=
              ai1CanonicalJson(expected)) {
        return Ai1FixtureDay(
          opportunity: o,
          synthetic: false,
          sleepHistoryComplete: false,
          responseHistoryComplete: day.responseHistoryComplete,
          sleepRevisions: [],
          responseRevisions: day.responseRevisions,
          issuedAt: day.issuedAt,
          durableAt: day.durableAt,
          timezoneChanges: day.timezoneChanges,
        );
      }
    }
    return day;
  }

  List<Ai1FixtureDay> closedDays({required DateTime asOf}) {
    if (journal.busy) {
      throw StateError('Wait for local study history to finish saving.');
    }
    if (plan?.acknowledgedAt != null &&
        asOf.toUtc().isBefore(plan!.acknowledgedAt!)) {
      throw ArgumentError('Analysis freeze precedes the saved study plan.');
    }
    return opportunities
        .where((o) => !o.outcomeEnd.isAfter(asOf.toUtc()))
        .map((o) => _day(o, asOf: asOf.toUtc()))
        .toList();
  }

  Ai1DatasetReport dataset({
    required DateTime asOf,
    required String datasetVersion,
  }) {
    if (!active) throw StateError('A valid active study history is required.');
    return Ai1DatasetBuilder.buildCaptured(
      protocol: protocol,
      days: closedDays(asOf: asOf),
      asOf: asOf,
      datasetVersion: datasetVersion,
    );
  }

  /// Private, explicit export. Aliases are scoped to this export, never account
  /// IDs or hashes of account IDs. External files cannot be recalled by the app.
  Map<String, Object?> export({
    required DateTime asOf,
    required String datasetVersion,
  }) {
    final report = dataset(asOf: asOf, datasetVersion: datasetVersion);
    final aliases = <String, String>{};
    String alias(String key) =>
        aliases.putIfAbsent(key, () => 'record-${aliases.length + 1}');
    final eventRows = <Map<String, Object?>>[];
    for (final row in report.rows) {
      final data = row.toJson()..remove('fixturePair');
      data['participantKey'] = 'participant-1';
      data['opportunityId'] = 'day-${row.opportunity.localDate}';
      data['analysisPair'] = row.hasPair;
      data['eventKind'] = 'feature_snapshot';
      data['prediction'] = null;
      data['modelVersion'] = null;
      data['snapshotStatus'] = data.remove('issuanceStatus');
      if (data['snapshotStatus'] == 'issued') data['snapshotStatus'] = 'saved';
      if (row.responseId != null) {
        data['responseId'] = alias(
          Ai1CaptureObservation.sourceKey('checkIns', row.responseId!),
        );
      }
      if (data['feature'] case final Map<String, Object?> feature) {
        feature['sourceKey'] = alias(row.feature!.key);
        if (row.feature!.source == Ai1SleepSource.appleHealth) {
          final sourceId = row.feature!.sourceId;
          final separator = sourceId.lastIndexOf(':');
          final episodeIndex = separator < 0
              ? null
              : int.tryParse(sourceId.substring(separator + 1));
          final queryId = separator < 0
              ? null
              : sourceId.substring(0, separator);
          final parent = journal.entries
              .where(
                (entry) =>
                    entry.collection == 'study' &&
                    entry.data['kind'] == 'health' &&
                    entry.sourceId == queryId &&
                    entry.acknowledgedAt != null &&
                    !entry.acknowledgedAt!.isAfter(asOf),
              )
              .firstOrNull;
          if (episodeIndex == null || episodeIndex < 0 || parent == null) {
            throw StateError(
              'The selected Health feature has no retained query lineage.',
            );
          }
          feature['parentQueryId'] = alias(parent.key);
          feature['episodeIndex'] = episodeIndex;
        }
      }
      eventRows.add(data);
    }
    final raw = <Map<String, Object?>>[];
    for (final entry in journal.entries.where(
      (e) =>
          e.collection != 'study' &&
          e.acknowledgedAt != null &&
          !e.acknowledgedAt!.isAfter(asOf),
    )) {
      raw.add({
        'recordId': alias(entry.key),
        'collection': entry.collection,
        'revision': entry.revision,
        'availableAt': entry.acknowledgedAt?.toIso8601String(),
        'lineageComplete': entry.lineageComplete,
        'data': entry.data,
      });
    }
    // Health sample identity and producer identifiers are local-only. Query
    // contents retain interval/stage evidence under export-scoped aliases.
    final health = <Map<String, Object?>>[];
    for (final entry in journal.entries.where(
      (e) =>
          e.collection == 'study' &&
          e.data['kind'] == 'health' &&
          e.acknowledgedAt != null &&
          !e.acknowledgedAt!.isAfter(asOf),
    )) {
      health.add({
        'queryId': alias(entry.key),
        'availableAt': entry.acknowledgedAt?.toIso8601String(),
        'lineageComplete': entry.lineageComplete,
        'samples': [
          for (final item in (entry.data['samples'] as List).cast<Map>())
            {
              'sampleId': alias('health-sample:${item['id']}'),
              'type': item['type'],
              'valueHours': item['value'],
              'endedAt': item['timestamp'],
              'sourceGroup': alias('health-source:${item['sourceGroup']}'),
            },
        ],
      });
    }
    return {
      'schemaVersion': 'tonyo-study-export-v1',
      'datasetVersion': datasetVersion,
      'asOf': asOf.toUtc().toIso8601String(),
      'synthetic': false,
      'trainingEligible': false,
      'protocolVersion': protocol.version,
      'source': protocol.sleepSource.name,
      'measurement': jsonDecode(protocol.measurement),
      'provenance': {
        'planSavedAt': plan!.acknowledgedAt!.toIso8601String(),
        'sleepSelectionVersion': 'tonyo-study-sleep-v1',
        'timezoneChanges': [
          for (final entry in journal.entries.where(
            (e) =>
                e.collection == 'study' &&
                e.data['kind'] == 'timezone' &&
                e.acknowledgedAt != null &&
                !e.acknowledgedAt!.isAfter(asOf),
          ))
            {
              'observedAt': entry.data['observedAt'],
              'availableAt': entry.acknowledgedAt!.toIso8601String(),
            },
        ],
        'deletedSourceCategoryCounts': {
          for (final category in ['sleepLogs', 'checkIns', 'study'])
            category: journal.tombstones
                .where((key) => (jsonDecode(key) as List).first == category)
                .length,
        },
        'deletionPolicy':
            'Any source deletion removes event payloads; unresolvable source tombstones conservatively invalidate the corresponding whole-plan lineage.',
      },
      'calendar': {
        'startDate': plan!.data['startDate'],
        'endDate': plan!.data['endDate'],
        'timezone': plan!.data['timezone'],
        'plannedOpportunities': opportunities.length,
        'closedOpportunities': report.rows.length,
      },
      'coverage': {...report.toJson()['coverage'] as Map}
        ..remove('fixturePairs'),
      'predictionEvents': eventRows,
      'rawMeasurements': raw,
      'healthQueries': health,
      'limitations': [
        'No numeric predictions or training have been activated.',
        'Query receipts establish readable device evidence, not complete Health access.',
        'Only recent readable Health absence is detected; older retained history requires explicit clearing.',
        'Exported files are private copies; delete obsolete copies after source erasure.',
      ],
    };
  }
}
