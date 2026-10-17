import 'dart:convert';
import 'dart:math';

import 'ai1_capture_store.dart';
import 'ai1_protocol.dart';
import 'models.dart';

/// Whitelisted observation content. Notes, account IDs and model scores never
/// enter the history. Original-local provenance comes from an explicit save.
class Ai1CaptureObservation {
  Ai1CaptureObservation._({
    required this.collection,
    required this.sourceId,
    required Map<String, Object?> data,
    required this.originalLocal,
  }) : data = _freezeMap(data) {
    _validateSource(collection, sourceId);
    _validateData(collection, this.data);
  }

  factory Ai1CaptureObservation.manualSleep({
    required String sourceId,
    required DateTime startedAt,
    required DateTime endedAt,
    required double durationHours,
    required bool isNap,
    required bool originalLocal,
  }) => Ai1CaptureObservation._(
    collection: 'sleepLogs',
    sourceId: sourceId,
    originalLocal: originalLocal,
    data: {
      'startedAt': startedAt.toUtc().toIso8601String(),
      'endedAt': endedAt.toUtc().toIso8601String(),
      'durationHours': durationHours,
      'isNap': isNap,
      'source': 'manual',
    },
  );

  factory Ai1CaptureObservation.selfReport({
    required DailyCheckIn checkIn,
    required String sharedHeading,
    required bool originalLocal,
  }) {
    if (!checkIn.isValidResearchResponse) {
      throw const FormatException('A valid versioned self-report is required.');
    }
    return Ai1CaptureObservation._(
      collection: 'checkIns',
      sourceId: checkIn.id,
      originalLocal: originalLocal,
      data: {
        'observedAt': checkIn.timestamp.toUtc().toIso8601String(),
        'localDate': checkIn.localDate,
        'timezone': checkIn.timezone,
        'utcOffsetMinutes': checkIn.utcOffsetMinutes,
        'period': checkIn.period.name,
        'questionnaireVersion': checkIn.questionnaireVersion,
        'questionnaireLanguage': checkIn.questionnaireLanguage,
        'source': 'selfReport',
        'sharedHeading': sharedHeading,
        'definition': checkIn.questionnaireSnapshot,
        'ratings': checkIn.ratings,
      },
    );
  }

  final String collection;
  final String sourceId;
  final Map<String, Object?> data;
  final bool originalLocal;
  String get key => sourceKey(collection, sourceId);
  String get fingerprint => ai1CanonicalJson(data);

  static String sourceKey(String collection, String sourceId) =>
      ai1CanonicalJson([collection, sourceId]);
}

/// A null receipt represents an interrupted write, never inferred availability.
class Ai1CaptureEntry {
  Ai1CaptureEntry._({
    required this.collection,
    required this.sourceId,
    required this.revision,
    required Map<String, Object?> data,
    required this.originalLocal,
    required this.lineageComplete,
    required this.acknowledgedAt,
  }) : data = _freezeMap(data);

  final String collection;
  final String sourceId;
  final int revision;
  final Map<String, Object?> data;
  final bool originalLocal;
  final bool lineageComplete;
  final DateTime? acknowledgedAt;

  String get key => Ai1CaptureObservation.sourceKey(collection, sourceId);
  String get fingerprint => ai1CanonicalJson(data);

  Map<String, Object?> toJson() => {
    'collection': collection,
    'sourceId': sourceId,
    'revision': revision,
    'data': data,
    'originalLocal': originalLocal,
    'lineageComplete': lineageComplete,
    'acknowledgedAt': acknowledgedAt?.toUtc().toIso8601String(),
  };

  static Ai1CaptureEntry _parse(Object? value) {
    final json = _map(value);
    _keys(json, const {
      'collection',
      'sourceId',
      'revision',
      'data',
      'originalLocal',
      'lineageComplete',
      'acknowledgedAt',
    });
    final collection = _string(json['collection']);
    final sourceId = _string(json['sourceId']);
    _validateSource(collection, sourceId);
    final data = _map(json['data']);
    _validateData(collection, data);
    if (json['revision'] is! int ||
        (json['revision'] as int) < 1 ||
        json['originalLocal'] is! bool ||
        json['lineageComplete'] is! bool) {
      throw const FormatException('Invalid local history revision.');
    }
    final acknowledgedAt = json['acknowledgedAt'] == null
        ? null
        : _time(json['acknowledgedAt']);
    if (acknowledgedAt == null && json['lineageComplete'] == true) {
      throw const FormatException(
        'Pending history cannot have complete lineage.',
      );
    }
    return Ai1CaptureEntry._(
      collection: collection,
      sourceId: sourceId,
      revision: json['revision'] as int,
      data: data,
      originalLocal: json['originalLocal'] as bool,
      lineageComplete: json['lineageComplete'] as bool,
      acknowledgedAt: acknowledgedAt,
    );
  }
}

/// Optional device-local persistence evidence, separate from training and from
/// ordinary backups. A source save is followed by two native journal writes:
/// the immutable payload, then a receipt for its acknowledged durable write.
/// A missing/failed receipt fails closed; it is never backdated on restart.
class Ai1CaptureJournal {
  Ai1CaptureJournal({
    required Ai1CaptureStore store,
    DateTime Function()? clock,
    // Keep the public injection parameter independent of the private field.
    // ignore: prefer_initializing_formals
  }) : _store = store,
       _clock = clock ?? DateTime.now;

  static const _maximumEntries = 4000;
  static const _maximumTombstones = 4000;
  final Ai1CaptureStore _store;
  final DateTime Function() _clock;
  Future<void>? _queue;
  int _generation = 0;
  String? _owner;
  String? _captureId;
  DateTime? _startedAt;
  bool _available = false;
  bool _enabled = false;
  bool _requiresClear = false;
  String? _error;
  List<Ai1CaptureEntry> _entries = [];
  Set<String> _tombstones = {};
  int _operations = 0;

  bool get available => _available;
  bool get enabled => _enabled;
  bool get busy => _operations > 0;
  String? get error => _error;
  String? get owner => _owner;
  int get revisionCount =>
      _entries.where((entry) => entry.acknowledgedAt != null).length;
  List<Ai1CaptureEntry> get entries => List.unmodifiable(_entries);

  /// Invalid optional capture content must not prevent the ordinary app save.
  void pauseAfterCaptureFailure() {
    _generation++;
    _failWrite();
  }

  void unload() {
    _generation++;
    _owner = null;
    _enabled = false;
    _captureId = null;
    _startedAt = null;
    _requiresClear = false;
    _error = null;
    _entries = [];
    _tombstones = {};
  }

  Future<void> load(String owner) async {
    _validateOwner(owner);
    unload();
    _owner = owner;
    final generation = _generation;
    await _serialized(() async {
      if (!_current(owner, generation)) return;
      try {
        final available = await _store.isAvailable();
        if (!_current(owner, generation)) return;
        _available = available;
        if (!available) return;
        final raw = await _store.read(owner);
        if (!_current(owner, generation)) return;
        if (raw == null) return;
        _restore(raw, owner);
      } on Object {
        if (!_current(owner, generation)) return;
        _enabled = false;
        _requiresClear = true;
        _error =
            'Local history could not be read. Clear it before starting again.';
      }
    });
  }

  Future<void> start(String owner) async {
    _validateOwner(owner);
    if (_owner != owner) await load(owner);
    final generation = _generation;
    await _serialized(() async {
      if (!_current(owner, generation)) return;
      if (!_available) throw StateError('Local history is unavailable.');
      if (_requiresClear) {
        throw StateError('Clear local history before starting again.');
      }
      if (_enabled) return;
      final random = Random.secure();
      final id = List.generate(16, (_) => random.nextInt(256));
      final startedAt = _clock().toUtc();
      final captureId = base64Url.encode(id);
      try {
        await _store.write(
          owner,
          _encode(
            owner: owner,
            captureId: captureId,
            startedAt: startedAt,
            entries: const [],
            tombstones: const {},
          ),
        );
        if (!_current(owner, generation)) return;
        _captureId = captureId;
        _startedAt = startedAt;
        _entries = [];
        _tombstones = {};
        _enabled = true;
        _error = null;
      } on Object {
        if (_current(owner, generation)) _failWrite();
        rethrow;
      }
    });
  }

  Future<void> stopAndClear(String owner) async {
    _validateOwner(owner);
    unload();
    _owner = owner;
    final generation = _generation;
    await _serialized(() async {
      try {
        await _store.clear(owner);
        if (_current(owner, generation)) {
          _requiresClear = false;
          _error = null;
        }
      } on Object {
        if (_current(owner, generation)) {
          _requiresClear = true;
          _error = 'Local history could not be cleared. Retry clearing it.';
        }
        rethrow;
      }
    });
  }

  Future<void> clearAll() async {
    unload();
    await _serialized(_store.clearAll);
  }

  Future<void> capture({
    required String owner,
    required Ai1CaptureObservation observation,
  }) async {
    final generation = _generation;
    await _serialized(() async {
      if (!_current(owner, generation) || !_enabled) return;
      if (_tombstones.contains(observation.key)) return;
      final previous = _entries
          .where((entry) => entry.key == observation.key)
          .lastOrNull;
      if (previous?.fingerprint == observation.fingerprint) return;
      if (_entries.length >= _maximumEntries) {
        _error = 'Local history is full. Clear it to start a new capture.';
        _enabled = false;
        _requiresClear = true;
        return;
      }
      final original = previous?.originalLocal ?? observation.originalLocal;
      final pending = Ai1CaptureEntry._(
        collection: observation.collection,
        sourceId: observation.sourceId,
        revision: (previous?.revision ?? 0) + 1,
        data: observation.data,
        originalLocal: original,
        lineageComplete: false,
        acknowledgedAt: null,
      );
      final pendingEntries = [..._entries, pending];
      try {
        // Payload is durable before this timestamp is obtained. The receipt
        // write cannot turn a failed/interrupted payload into an earlier save.
        final acknowledgedAt = (await _store.write(
          owner,
          _envelope(entries: pendingEntries),
        )).toUtc();
        if (!_current(owner, generation) || !_enabled) return;
        _entries = pendingEntries;
        // Clock rollback affects new source identities too, not just edits.
        final precedingTime = _entries
            .map((entry) => entry.acknowledgedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (latest, time) =>
                  latest == null || time.isAfter(latest) ? time : latest,
            );
        if (acknowledgedAt.isBefore(_startedAt!) ||
            (precedingTime != null && acknowledgedAt.isBefore(precedingTime))) {
          throw const FormatException('Local history clock moved backwards.');
        }
        final observedAt = _time(
          observation.data[observation.collection == 'sleepLogs'
              ? 'endedAt'
              : 'observedAt'],
        );
        final complete =
            original &&
            (previous == null || previous.lineageComplete) &&
            !acknowledgedAt.isBefore(observedAt) &&
            (observation.collection != 'checkIns' ||
                observation.data['timezone'] != null);
        final committed = Ai1CaptureEntry._(
          collection: pending.collection,
          sourceId: pending.sourceId,
          revision: pending.revision,
          data: pending.data,
          originalLocal: original,
          lineageComplete: complete,
          acknowledgedAt: acknowledgedAt,
        );
        final committedEntries = [
          ..._entries.take(_entries.length - 1),
          committed,
        ];
        await _store.write(owner, _envelope(entries: committedEntries));
        if (!_current(owner, generation) || !_enabled) return;
        _entries = committedEntries;
        _error = null;
      } on Object {
        if (_current(owner, generation)) _failWrite();
        // Optional capture failure must not pretend that the user's ordinary
        // sleep/check-in save failed. Status explicitly pauses further capture.
      }
    });
  }

  Future<void> deleteSource({
    required String owner,
    required String collection,
    required String sourceId,
  }) => _purge(
    owner,
    () => {Ai1CaptureObservation.sourceKey(collection, sourceId)},
  );

  /// Remote edits, ordinary backup restore or missing records cannot reuse old
  /// captured answers. Only already-captured identities are reconciled here.
  Future<void> reconcile({
    required String owner,
    required Map<String, String> currentFingerprints,
  }) {
    final fingerprints = Map<String, String>.of(currentFingerprints);
    return _purge(owner, () {
      final latest = <String, Ai1CaptureEntry>{};
      for (final entry in _entries) {
        latest[entry.key] = entry;
      }
      return latest.entries
          .where((entry) => fingerprints[entry.key] != entry.value.fingerprint)
          .map((entry) => entry.key)
          .toSet();
    }, clearUnreadable: false);
  }

  Future<void> _purge(
    String owner,
    Set<String> Function() selectKeys, {
    bool clearUnreadable = true,
  }) async {
    if (_owner != owner) return;
    final generation = _generation;
    await _serialized(() async {
      if (!_current(owner, generation)) return;
      if (_captureId == null) {
        // A corrupt journal cannot be inspected to isolate one source. An
        // explicit deletion must erase it instead of leaving unknown payloads.
        if (clearUnreadable && _requiresClear) {
          await _store.clear(owner);
          if (_current(owner, generation)) {
            unload();
            _owner = owner;
          }
        }
        return;
      }
      final keys = selectKeys();
      final presentKeys = _entries.map((entry) => entry.key).toSet();
      final relevant = keys.intersection(presentKeys);
      if (relevant.isEmpty) return;
      final kept = _entries
          .where((entry) => !relevant.contains(entry.key))
          .toList();
      final tombstones = {..._tombstones, ...relevant};
      if (tombstones.length > _maximumTombstones) {
        // Erasing optional history is safer than retaining deleted payloads.
        await _store.clear(owner);
        if (_current(owner, generation)) unload();
        return;
      }
      try {
        await _store.write(
          owner,
          _envelope(entries: kept, tombstones: tombstones),
        );
        if (!_current(owner, generation)) return;
        _entries = kept;
        _tombstones = tombstones;
      } on Object {
        if (_current(owner, generation)) {
          _failWrite();
          _error = 'Local history could not be cleared. Retry clearing it.';
        }
        // Deletion must not claim success while a captured payload survives.
        rethrow;
      }
    });
  }

  void _failWrite() {
    _enabled = false;
    _requiresClear = true;
    _error = 'Local history was interrupted. Clear it before starting again.';
  }

  bool _current(String owner, int generation) =>
      _owner == owner && _generation == generation;

  Future<void> _serialized(Future<void> Function() action) async {
    _operations++;
    final previous = _queue;
    final pending = previous == null
        ? action()
        : previous.then((_) => action());
    final tail = pending.catchError((Object _) {});
    _queue = tail;
    try {
      await pending;
    } finally {
      _operations--;
      if (identical(_queue, tail)) _queue = null;
    }
  }

  String _envelope({
    required List<Ai1CaptureEntry> entries,
    Set<String>? tombstones,
  }) => _encode(
    owner: _owner!,
    captureId: _captureId!,
    startedAt: _startedAt!,
    entries: entries,
    tombstones: tombstones ?? _tombstones,
  );

  static String _encode({
    required String owner,
    required String captureId,
    required DateTime startedAt,
    required List<Ai1CaptureEntry> entries,
    required Set<String> tombstones,
  }) {
    final value = ai1CanonicalJson({
      'schemaVersion': 1,
      'owner': owner,
      'captureId': captureId,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'enabled': true,
      'trainingEligible': false,
      'entries': [for (final entry in entries) entry.toJson()],
      'tombstones': tombstones.toList()..sort(),
    });
    if (utf8.encode(value).length > ai1CaptureMaximumBytes) {
      throw const FormatException('Local history exceeds its storage limit.');
    }
    return value;
  }

  void _restore(String raw, String expectedOwner) {
    if (utf8.encode(raw).length > ai1CaptureMaximumBytes) {
      throw const FormatException('Local history exceeds its storage limit.');
    }
    final json = _map(jsonDecode(raw));
    _keys(json, const {
      'schemaVersion',
      'owner',
      'captureId',
      'startedAt',
      'enabled',
      'trainingEligible',
      'entries',
      'tombstones',
    });
    if (json['schemaVersion'] != 1 ||
        json['schemaVersion'] is! int ||
        json['owner'] != expectedOwner ||
        json['enabled'] != true ||
        json['trainingEligible'] != false ||
        json['entries'] is! List ||
        json['tombstones'] is! List) {
      throw const FormatException('Invalid local history envelope.');
    }
    final captureId = _string(json['captureId']);
    if (captureId.length > 100) {
      throw const FormatException('Invalid capture ID.');
    }
    final startedAt = _time(json['startedAt']);
    final rawEntries = json['entries'] as List;
    final rawTombstones = json['tombstones'] as List;
    if (rawEntries.length > _maximumEntries ||
        rawTombstones.length > _maximumTombstones) {
      throw const FormatException('Local history exceeds its record limit.');
    }
    final tombstones = <String>{};
    for (final value in rawTombstones) {
      final key = _string(value);
      final decoded = jsonDecode(key);
      if (decoded is! List || decoded.length != 2) {
        throw const FormatException('Invalid deleted source identity.');
      }
      _validateSource(_string(decoded[0]), _string(decoded[1]));
      if (ai1CanonicalJson(decoded) != key || !tombstones.add(key)) {
        throw const FormatException('Invalid deleted source identity.');
      }
    }
    final entries = rawEntries.map(Ai1CaptureEntry._parse).toList();
    final latest = <String, Ai1CaptureEntry>{};
    DateTime? latestReceipt;
    for (final entry in entries) {
      final previous = latest[entry.key];
      final observedAt = _time(
        entry.data[entry.collection == 'sleepLogs' ? 'endedAt' : 'observedAt'],
      );
      if (tombstones.contains(entry.key) ||
          entry.revision != (previous?.revision ?? 0) + 1 ||
          (previous != null && entry.originalLocal != previous.originalLocal) ||
          (entry.lineageComplete &&
              (!entry.originalLocal ||
                  entry.acknowledgedAt!.isBefore(observedAt) ||
                  (entry.collection == 'checkIns' &&
                      entry.data['timezone'] == null) ||
                  (previous != null && !previous.lineageComplete))) ||
          (entry.acknowledgedAt != null &&
              entry.acknowledgedAt!.isBefore(startedAt)) ||
          (entry.acknowledgedAt != null &&
              latestReceipt != null &&
              entry.acknowledgedAt!.isBefore(latestReceipt)) ||
          (previous?.acknowledgedAt != null &&
              entry.acknowledgedAt != null &&
              entry.acknowledgedAt!.isBefore(previous!.acknowledgedAt!))) {
        throw const FormatException('Invalid local history lineage.');
      }
      latest[entry.key] = entry;
      latestReceipt = entry.acknowledgedAt ?? latestReceipt;
    }
    _captureId = captureId;
    _startedAt = startedAt;
    _entries = entries;
    _tombstones = tombstones;
    _requiresClear = entries.any((entry) => entry.acknowledgedAt == null);
    _enabled = !_requiresClear;
    if (_requiresClear) {
      _error = 'Local history was interrupted. Clear it before starting again.';
    }
  }
}

void _validateOwner(String owner) {
  if (owner.trim().isEmpty || owner.length > 200) {
    throw ArgumentError('Invalid history owner.');
  }
}

void _validateSource(String collection, String sourceId) {
  if (!const {'sleepLogs', 'checkIns'}.contains(collection) ||
      sourceId.isEmpty ||
      sourceId.length > 200 ||
      sourceId.contains('/')) {
    throw const FormatException('Invalid history source.');
  }
}

void _validateData(String collection, Map<String, Object?> data) {
  if (collection == 'sleepLogs') {
    _keys(data, const {
      'startedAt',
      'endedAt',
      'durationHours',
      'isNap',
      'source',
    });
    final start = _time(data['startedAt']);
    final end = _time(data['endedAt']);
    final hours = data['durationHours'];
    if (!end.isAfter(start) ||
        hours is! num ||
        !hours.isFinite ||
        hours <= 0 ||
        hours > 24 ||
        data['isNap'] is! bool ||
        data['source'] != 'manual' ||
        (end.difference(start).inMicroseconds / Duration.microsecondsPerHour -
                    hours)
                .abs() >
            1 / 60) {
      throw const FormatException('Invalid sleep history.');
    }
    return;
  }
  _keys(data, const {
    'observedAt',
    'localDate',
    'timezone',
    'utcOffsetMinutes',
    'period',
    'questionnaireVersion',
    'questionnaireLanguage',
    'source',
    'sharedHeading',
    'definition',
    'ratings',
  });
  final observedAt = _time(data['observedAt']);
  final definition = _map(data['definition']);
  final ratings = _map(data['ratings']);
  _keys(ratings, DailyCheckIn.measurementIds.toSet());
  if (data['source'] != 'selfReport' ||
      !const {'morning', 'evening'}.contains(data['period']) ||
      !const {
        'en',
        'es',
        'zh-Hans',
        'zh-Hant',
      }.contains(data['questionnaireLanguage']) ||
      _string(data['sharedHeading']).length > 500 ||
      _string(data['questionnaireVersion']).length > 100 ||
      definition['version'] != data['questionnaireVersion'] ||
      definition['language'] != data['questionnaireLanguage'] ||
      data['localDate'] is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data['localDate'] as String) ||
      (data['timezone'] != null && _string(data['timezone']).length > 100) ||
      data['utcOffsetMinutes'] is! int ||
      (data['utcOffsetMinutes'] as int).abs() > 840 ||
      ratings.values.every((value) => value == null) ||
      ratings.values.any(
        (value) =>
            value != null &&
            (value is! num ||
                !value.isFinite ||
                value < 1 ||
                value > 10 ||
                value != value.roundToDouble()),
      )) {
    throw const FormatException('Invalid self-report history.');
  }
  final atOffset = observedAt.add(
    Duration(minutes: data['utcOffsetMinutes'] as int),
  );
  final expectedDate =
      '${atOffset.year.toString().padLeft(4, '0')}-${atOffset.month.toString().padLeft(2, '0')}-${atOffset.day.toString().padLeft(2, '0')}';
  if (data['localDate'] != expectedDate) {
    throw const FormatException('Invalid captured local date.');
  }
  // Stored snapshots carry the entire question context, never arbitrary notes.
  _keys(definition, const {
    'version',
    'language',
    'kind',
    'status',
    'recallPeriod',
    'recallPeriodText',
    'items',
  });
  if (!DailyCheckIn.validQuestionnaireSnapshot(
        definition,
        version: data['questionnaireVersion'] as String,
        language: data['questionnaireLanguage'] as String,
      ) ||
      utf8.encode(ai1CanonicalJson(definition)).length > 32 * 1024) {
    throw const FormatException('Invalid measurement snapshot.');
  }
  for (final item in definition['items'] as List) {
    final fields = _map(item);
    _keys(fields, const {'id', 'label', 'prompt', 'anchors', 'optional'});
    _keys(_map(fields['anchors']), const {'1', '5', '10'});
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid history object.');
  }
  return value.cast<String, Object?>();
}

void _keys(Map<String, Object?> value, Set<String> keys) {
  if (value.length != keys.length || !keys.every(value.containsKey)) {
    throw const FormatException('Unexpected local history fields.');
  }
}

String _string(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid history text.');
  }
  return value;
}

DateTime _time(Object? value) {
  final raw = _string(value);
  final parsed = DateTime.tryParse(raw);
  if (!raw.endsWith('Z') ||
      parsed == null ||
      parsed.toUtc().toIso8601String() != raw) {
    throw const FormatException('Invalid history timestamp.');
  }
  return parsed.toUtc();
}

Map<String, Object?> _freezeMap(Map<String, Object?> input) =>
    _freeze(jsonDecode(jsonEncode(input))) as Map<String, Object?>;

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry(key as String, _freeze(item))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}
