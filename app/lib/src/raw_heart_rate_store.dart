import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'heart_rate_summary.dart';
import 'models.dart';

/// Private, owner-scoped device history. Successful replacement means all raw
/// samples are durable before a caller may remove their legacy preferences or
/// cloud copies. Replacements are full snapshots, not append-only imports.
abstract interface class RawHeartRateStore {
  /// Distinguishes an intentionally empty saved snapshot from a missing file.
  Future<bool> hasSnapshot(String uid);
  Future<List<SignalReading>> load(String uid);
  Future<Map<String, HeartRateSampleProvenance>> loadProvenance(String uid);
  Future<void> replace(
    String uid,
    Iterable<SignalReading> readings, {
    Map<String, HeartRateSampleProvenance> provenance = const {},
  });
  Future<void> clear(String uid);
  Future<void> close();
}

class MemoryRawHeartRateStore implements RawHeartRateStore {
  final _owners = <String, Map<String, _RawRecord>>{};

  @override
  Future<bool> hasSnapshot(String uid) async {
    _validateOwner(uid);
    return _owners.containsKey(uid);
  }

  @override
  Future<List<SignalReading>> load(String uid) async {
    _validateOwner(uid);
    return _decodeReadings(_owners[uid]?.values ?? const []);
  }

  @override
  Future<Map<String, HeartRateSampleProvenance>> loadProvenance(
    String uid,
  ) async {
    _validateOwner(uid);
    return _decodeProvenance(_owners[uid]?.values ?? const []);
  }

  @override
  Future<void> replace(
    String uid,
    Iterable<SignalReading> readings, {
    Map<String, HeartRateSampleProvenance> provenance = const {},
  }) async {
    _validateOwner(uid);
    final replacement = _records(readings, provenance);
    final old = _owners[uid] ?? const {};
    _owners[uid] = {
      for (final record in replacement)
        record.id: record.withRetainedProvenance(old[record.id]?.provenance),
    };
  }

  @override
  Future<void> clear(String uid) async {
    _validateOwner(uid);
    _owners.remove(uid);
  }

  @override
  Future<void> close() async {}
}

/// SQLite transactions preserve the previous complete snapshot on failure.
/// Individual INSERT/UPDATE/DELETE operations are issued only for changed
/// records, avoiding a rewrite of thousands of unchanged samples per refresh.
/// The database factory is injectable for real SQLite persistence tests.
class SqliteRawHeartRateStore implements RawHeartRateStore {
  SqliteRawHeartRateStore({DatabaseFactory? databaseFactory, String? path})
    : this._(databaseFactory, path);

  SqliteRawHeartRateStore._(this._factory, this._path);

  final DatabaseFactory? _factory;
  final String? _path;
  Database? _database;
  Future<void> _tail = Future.value();
  bool _closed = false;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) {
      if (_closed) throw StateError('The raw heart-rate store is closed.');
      return operation();
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<Database> _open() async {
    if (_database != null) return _database!;
    final factory = _factory ?? databaseFactory;
    final path =
        _path ??
        '${await factory.getDatabasesPath()}/tonyo_raw_heart_rate_v1.db';
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE raw_heart_rate_owners (
              owner TEXT PRIMARY KEY NOT NULL
            ) WITHOUT ROWID
          ''');
          await db.execute('''
            CREATE TABLE raw_heart_rate (
              owner TEXT NOT NULL,
              sample_id TEXT NOT NULL,
              observed_micros INTEGER NOT NULL,
              payload TEXT NOT NULL,
              provenance TEXT,
              PRIMARY KEY (owner, sample_id)
            ) WITHOUT ROWID
          ''');
          await db.execute('''
            CREATE INDEX raw_heart_rate_owner_time
            ON raw_heart_rate (owner, observed_micros DESC)
          ''');
        },
      ),
    );
    _database = database;
    return database;
  }

  @override
  Future<bool> hasSnapshot(String uid) {
    _validateOwner(uid);
    return _serial(() async {
      final db = await _open();
      return (await db.query(
        'raw_heart_rate_owners',
        columns: ['owner'],
        where: 'owner = ?',
        whereArgs: [uid],
        limit: 1,
      )).isNotEmpty;
    });
  }

  @override
  Future<List<SignalReading>> load(String uid) {
    _validateOwner(uid);
    return _serial(() async {
      final db = await _open();
      final rows = await db.query(
        'raw_heart_rate',
        where: 'owner = ?',
        whereArgs: [uid],
        orderBy: 'observed_micros DESC, sample_id ASC',
      );
      return _decodeReadings(rows.map(_RawRecord.fromSql));
    });
  }

  @override
  Future<Map<String, HeartRateSampleProvenance>> loadProvenance(String uid) {
    _validateOwner(uid);
    return _serial(() async {
      final db = await _open();
      final rows = await db.query(
        'raw_heart_rate',
        where: 'owner = ? AND provenance IS NOT NULL',
        whereArgs: [uid],
      );
      return _decodeProvenance(rows.map(_RawRecord.fromSql));
    });
  }

  @override
  Future<void> replace(
    String uid,
    Iterable<SignalReading> readings, {
    Map<String, HeartRateSampleProvenance> provenance = const {},
  }) {
    _validateOwner(uid);
    // Capture and validate before scheduling so mutable caller lists cannot
    // change while another account's transaction is in flight.
    final replacement = _records(readings, provenance);
    return _serial(() async {
      final db = await _open();
      await db.transaction((txn) async {
        final ownerRows = await txn.query(
          'raw_heart_rate_owners',
          columns: ['owner'],
          where: 'owner = ?',
          whereArgs: [uid],
          limit: 1,
        );
        final existingRows = await txn.query(
          'raw_heart_rate',
          where: 'owner = ?',
          whereArgs: [uid],
        );
        final existing = {
          for (final row in existingRows)
            row['sample_id'] as String: _RawRecord.fromSql(row),
        };
        final batch = txn.batch();
        var changed = false;
        if (ownerRows.isEmpty) {
          batch.insert('raw_heart_rate_owners', {'owner': uid});
          changed = true;
        }
        for (final incoming in replacement) {
          final old = existing.remove(incoming.id);
          final record = incoming.withRetainedProvenance(old?.provenance);
          if (old == null) {
            batch.insert('raw_heart_rate', record.toSql(uid));
            changed = true;
          } else if (record.payload != old.payload ||
              record.provenance != old.provenance) {
            batch.update(
              'raw_heart_rate',
              record.toSql(uid),
              where: 'owner = ? AND sample_id = ?',
              whereArgs: [uid, record.id],
            );
            changed = true;
          }
        }
        for (final removed in existing.keys) {
          batch.delete(
            'raw_heart_rate',
            where: 'owner = ? AND sample_id = ?',
            whereArgs: [uid, removed],
          );
          changed = true;
        }
        if (changed) await batch.commit(noResult: true);
      });
    });
  }

  @override
  Future<void> clear(String uid) {
    _validateOwner(uid);
    return _serial(() async {
      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete(
          'raw_heart_rate',
          where: 'owner = ?',
          whereArgs: [uid],
        );
        await txn.delete(
          'raw_heart_rate_owners',
          where: 'owner = ?',
          whereArgs: [uid],
        );
      });
    });
  }

  @override
  Future<void> close() {
    final result = _tail.then((_) async {
      if (_closed) return;
      _closed = true;
      await _database?.close();
      _database = null;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

class _RawRecord {
  const _RawRecord({
    required this.id,
    required this.observedMicros,
    required this.payload,
    this.provenance,
  });

  final String id;
  final int observedMicros;
  final String payload;
  final String? provenance;

  factory _RawRecord.fromSql(Map<String, Object?> row) => _RawRecord(
    id: row['sample_id'] as String,
    observedMicros: row['observed_micros'] as int,
    payload: row['payload'] as String,
    provenance: row['provenance'] as String?,
  );

  _RawRecord withRetainedProvenance(String? old) => _RawRecord(
    id: id,
    observedMicros: observedMicros,
    payload: payload,
    // The first known import provenance wins across travel/re-imports.
    provenance: old ?? provenance,
  );

  Map<String, Object?> toSql(String uid) => {
    'owner': uid,
    'sample_id': id,
    'observed_micros': observedMicros,
    'payload': payload,
    'provenance': provenance,
  };
}

List<_RawRecord> _records(
  Iterable<SignalReading> readings,
  Map<String, HeartRateSampleProvenance> provenance,
) => [
  for (final reading in HeartRateSummary.uniqueRawReadings(readings))
    _RawRecord(
      id: rawHeartRateSampleId(reading),
      observedMicros: reading.timestamp.microsecondsSinceEpoch,
      payload: jsonEncode(reading.toJson()),
      provenance: provenance[rawHeartRateSampleId(reading)] == null
          ? null
          : jsonEncode(
              HeartRateSampleProvenance.fromJson(
                provenance[rawHeartRateSampleId(reading)]!.toJson(),
              ).toJson(),
            ),
    ),
];

List<SignalReading> _decodeReadings(Iterable<_RawRecord> rows) =>
    rows
        .map(
          (row) => SignalReading.fromJson(
            jsonDecode(row.payload) as Map<String, dynamic>,
          ),
        )
        .toList()
      ..sort((a, b) {
        final time = b.timestamp.compareTo(a.timestamp);
        return time != 0 ? time : a.id.compareTo(b.id);
      });

Map<String, HeartRateSampleProvenance> _decodeProvenance(
  Iterable<_RawRecord> rows,
) => {
  for (final row in rows)
    if (row.provenance != null)
      row.id: HeartRateSampleProvenance.fromJson(
        jsonDecode(row.provenance!) as Map<String, dynamic>,
      ),
};

void _validateOwner(String uid) {
  if (uid.trim().isEmpty || uid.length > 200 || uid.contains('\u0000')) {
    throw const FormatException('Invalid raw heart-rate storage owner.');
  }
}
