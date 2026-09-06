import 'dart:convert';

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const mlPrepVersion = 1;

enum PrepCollection { signals, checkIns, outcomes }

extension PrepCollectionBudget on PrepCollection {
  int get maximumDocuments => this == PrepCollection.signals ? 1500 : 100;
  String get timeField =>
      this == PrepCollection.outcomes ? 'observedAt' : 'timestamp';
}

/// Exactly thirty calendar dates in an explicit IANA timezone, including DST.
class PrepWindow {
  PrepWindow._(this.start, this.end, this.timezone);

  factory PrepWindow.endingOn(DateTime endDay, {required String timezone}) {
    _initializeZones();
    timezone = timezone == 'UTC' ? 'Etc/UTC' : timezone;
    final location = tz.getLocation(timezone);
    final first = DateTime.utc(endDay.year, endDay.month, endDay.day - 29);
    final after = DateTime.utc(endDay.year, endDay.month, endDay.day + 1);
    return PrepWindow._(
      DateTime.fromMicrosecondsSinceEpoch(
        tz.TZDateTime(
          location,
          first.year,
          first.month,
          first.day,
        ).microsecondsSinceEpoch,
        isUtc: true,
      ),
      DateTime.fromMicrosecondsSinceEpoch(
        tz.TZDateTime(
          location,
          after.year,
          after.month,
          after.day,
        ).microsecondsSinceEpoch,
        isUtc: true,
      ),
      timezone,
    );
  }

  factory PrepWindow.fromJson(Map<String, dynamic> json) {
    _initializeZones();
    final timezone = json['timezone'] as String;
    final end = DateTime.parse(json['end'] as String).toUtc();
    final last = tz.TZDateTime.from(
      end.subtract(const Duration(microseconds: 1)),
      tz.getLocation(timezone),
    );
    final window = PrepWindow.endingOn(last, timezone: timezone);
    if (!window.start.isAtSameMomentAs(
          DateTime.parse(json['start'] as String),
        ) ||
        !window.end.isAtSameMomentAs(end)) {
      throw const FormatException(
        'Prep window must cover exactly 30 local dates.',
      );
    }
    return window;
  }

  static bool _zonesInitialized = false;
  static void _initializeZones() {
    if (_zonesInitialized) return;
    tzdata.initializeTimeZones();
    _zonesInitialized = true;
  }

  final DateTime start;
  final DateTime end;
  final String timezone;

  tz.TZDateTime localTime(DateTime value) =>
      tz.TZDateTime.from(value, tz.getLocation(timezone));

  String dayKey(DateTime value) {
    final local = localTime(value);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// Legacy cache strings have no offset. Interpret them in the chosen zone,
  /// never in the machine running the test/export. Cloud dates retain offsets.
  DateTime? parseTime(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    if (RegExp(
      r'(Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(value)) {
      return parsed.toUtc();
    }
    return tz.TZDateTime(
      tz.getLocation(timezone),
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).toUtc();
  }

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(end);

  Map<String, dynamic> toJson() => {
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'timezone': timezone,
  };
}

class PrepConsent {
  const PrepConsent({
    required this.collection,
    required this.trainingUse,
    required this.version,
  });

  final bool collection;
  final bool trainingUse;
  final int version;
  bool get allowed => collection && trainingUse && version == 1;

  Map<String, dynamic> toJson() => {
    'collection': collection,
    'trainingUse': trainingUse,
    'version': version,
  };

  factory PrepConsent.fromJson(Map<String, dynamic> json) => PrepConsent(
    collection: json['collection'] == true,
    trainingUse: json['trainingUse'] == true,
    version: (json['version'] as num?)?.toInt() ?? 0,
  );
}

class PrepAccountMetadata {
  const PrepAccountMetadata({
    required this.consent,
    required this.schemaVersion,
  });
  final PrepConsent consent;
  final int schemaVersion;
}

/// Deliberately contains no writes, listeners, unbounded reads, or score reads.
abstract interface class PrepDataSource {
  String? get currentUid;
  Future<PrepAccountMetadata> readAccount(String uid);
  Future<List<Map<String, dynamic>>> readCollection(
    String uid,
    PrepCollection collection,
    PrepWindow window, {
    required int limit,
  });
}

/// Raw source fields are retained for provenance and historical availability
/// checks. UID is scoped in memory and deliberately omitted from exports/cache.
class PrepSnapshot {
  PrepSnapshot({
    required this.uid,
    required this.window,
    required this.consent,
    required this.fetchedAt,
    required List<Map<String, dynamic>> signals,
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> outcomes,
    required this.schemaVersion,
  }) : signals = _copyRows(signals, uid),
       checkIns = _copyRows(checkIns, uid),
       outcomes = _copyRows(outcomes, uid);

  final String uid;
  final PrepWindow window;
  final PrepConsent consent;
  final DateTime fetchedAt;
  final List<Map<String, dynamic>> signals;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> outcomes;
  final int schemaVersion;

  bool get isTruncated =>
      signals.length >= PrepCollection.signals.maximumDocuments ||
      checkIns.length >= PrepCollection.checkIns.maximumDocuments ||
      outcomes.length >= PrepCollection.outcomes.maximumDocuments;

  Map<String, int> get counts => {
    'signals': signals.length,
    'checkIns': checkIns.length,
    'outcomes': outcomes.length,
  };

  Map<String, dynamic> _content() => {
    'prepVersion': mlPrepVersion,
    'schemaVersion': schemaVersion,
    'window': window.toJson(),
    'consent': consent.toJson(),
    'signals': _sortedRows(signals),
    'checkIns': _sortedRows(checkIns),
    'outcomes': _sortedRows(outcomes),
  };

  String get fingerprint => prepFingerprint(_content());

  Map<String, dynamic> toJson() => {
    ..._content(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'fingerprint': fingerprint,
  };

  factory PrepSnapshot.fromJson(
    Map<String, dynamic> json, {
    required String uid,
  }) {
    if (json['prepVersion'] != mlPrepVersion) {
      throw const FormatException('Unsupported prep cache version.');
    }
    final snapshot = PrepSnapshot(
      uid: uid,
      window: PrepWindow.fromJson(
        Map<String, dynamic>.from(json['window'] as Map),
      ),
      consent: PrepConsent.fromJson(
        Map<String, dynamic>.from(json['consent'] as Map),
      ),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      signals: _readRows(json['signals']),
      checkIns: _readRows(json['checkIns']),
      outcomes: _readRows(json['outcomes']),
      schemaVersion: (json['schemaVersion'] as num).toInt(),
    );
    if (snapshot.fingerprint != json['fingerprint']) {
      throw const FormatException('Prep cache fingerprint mismatch.');
    }
    return snapshot;
  }

  static List<Map<String, dynamic>> _readRows(Object? value) => (value as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  static List<Map<String, dynamic>> _copyRows(
    List<Map<String, dynamic>> rows,
    String uid,
  ) => List.unmodifiable(
    rows.map((row) {
      final sanitized = Map<String, dynamic>.from(row);
      for (final key in ['uid', 'userId', 'accountUid']) {
        final owner = sanitized.remove(key);
        if (owner != null && owner != uid) {
          sanitized['_prepForeignAccount'] = true;
        }
      }
      return _freeze(jsonDecode(canonicalPrepJson(sanitized)))
          as Map<String, dynamic>;
    }),
  );

  static Object? _freeze(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: _freeze(entry.value),
      });
    }
    if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
    return value;
  }

  static List<Map<String, dynamic>> _sortedRows(
    List<Map<String, dynamic>> rows,
  ) =>
      [...rows]
        ..sort((a, b) => canonicalPrepJson(a).compareTo(canonicalPrepJson(b)));
}

String canonicalPrepJson(Object? value) {
  Object? canonical(Object? item) {
    if (item is Map) {
      final keys = item.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(item[key])};
    }
    if (item is List) return item.map(canonical).toList();
    if (item is DateTime) return item.toUtc().toIso8601String();
    if (item is num && !item.isFinite) return item.toString();
    return item;
  }

  return jsonEncode(canonical(value));
}

/// Stable, non-security content checksum. Both streams cover every byte,
/// including edits/deletions, not only counts or the newest timestamp.
String prepFingerprint(Object? value) {
  final bytes = utf8.encode(canonicalPrepJson(value));
  var first = 0x811c9dc5;
  var second = 0x9e3779b9;
  // Split multiplication avoids JavaScript's 53-bit rounding on Flutter web.
  int multiply32(int value, int factor) =>
      ((value & 0xffff) * factor +
          ((((value >>> 16) * factor) & 0xffff) << 16)) &
      0xffffffff;
  for (final byte in bytes) {
    first = multiply32(first ^ byte, 0x01000193);
    second = multiply32(second ^ byte, 65599);
  }
  return '${first.toRadixString(16).padLeft(8, '0')}'
      '${second.toRadixString(16).padLeft(8, '0')}-${bytes.length}';
}
