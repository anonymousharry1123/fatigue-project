import 'cloud_schema.dart';
import 'cloud_sync.dart';

/// Optional repository capability for a durable, acknowledged remote baseline.
/// A controller's conflict-before overlay is not a valid substitute for that
/// baseline because it can intentionally contain locally edited values.
abstract interface class EfficientInputRepository {
  /// Explicit migration barrier. Follow with a full read before assigning a
  /// cursor to a previously unversioned account's local baseline.
  Future<void> activateInputSync(String uid);

  /// Called only after summary acknowledgement and legacy sample cleanup.
  Future<void> finishHeartRateMigration(String uid);

  Future<CloudUserState?> readUserSince(
    String uid, {
    required InputSyncSnapshot baseline,
    required int revision,
  });
}

String inputChangeDocumentId(String collection, String id) =>
    '${collection}__$id';

/// One document's latest mutation, including a durable deletion tombstone.
///
/// The repository must write this record and increment the account's revision
/// in the same transaction as the source mutation. Observation timestamps are
/// deliberately not cursors: an old observation can be edited or imported now.
class InputChangeRecord {
  InputChangeRecord({
    required this.collection,
    required this.id,
    required this.revision,
    required Map<String, dynamic>? after,
  }) : after = after == null ? null : _copyMap(after) {
    if (!const {'signals', 'checkIns'}.contains(collection)) {
      throw const FormatException('Unsupported input change collection.');
    }
    if (id.isEmpty || id.contains('/')) {
      throw const FormatException('Invalid input change document ID.');
    }
    _requireRevision(revision, minimum: 1);
  }

  factory InputChangeRecord.fromJson(Map<String, dynamic> data) {
    final collection = data['collection'];
    final id = data['id'];
    final after = data['after'];
    if (collection is! String ||
        id is! String ||
        !data.containsKey('after') ||
        (after != null && after is! Map)) {
      throw const FormatException('Incomplete input change record.');
    }
    return InputChangeRecord(
      collection: collection,
      id: id,
      revision: parseInputRevision(data['revision']),
      after: after == null ? null : Map<String, dynamic>.from(after as Map),
    );
  }

  final String collection;
  final String id;
  final int revision;
  final Map<String, dynamic>? after;

  Map<String, Object?> toJson() => {
    'collection': collection,
    'id': id,
    'revision': revision,
    'after': after == null ? null : _copyMap(after!),
  };
}

/// A candidate read result. Persist snapshot and revision together only after
/// all pages have loaded and the account/session is still the same owner.
class InputReadResult {
  const InputReadResult({required this.snapshot, required this.revision});

  final InputSyncSnapshot snapshot;
  final int revision;
}

/// Retry the whole read from its original durable cursor when this is thrown.
/// Repeated contention can fall back to a later foreground attempt; partial
/// pages must never become an acknowledged sync baseline.
class InputRevisionChanged implements Exception {
  const InputRevisionChanged(this.readRevision, this.confirmedRevision);

  final int readRevision;
  final int confirmedRevision;

  @override
  String toString() =>
      'Input revision changed while reading '
      '($readRevision to $confirmedRevision).';
}

/// Parse an exact revision usable by both native Dart and the web client.
/// Missing or malformed revision metadata requires a full bootstrap/migration;
/// it is never silently interpreted as a successfully synchronized cursor.
int parseInputRevision(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > _maximumRevision ||
      value != value.roundToDouble()) {
    throw const FormatException('Invalid input revision.');
  }
  return value.toInt();
}

/// Use for both the full bootstrap and an incremental read. With one latest
/// change per document, a concurrent update can move that row beyond a query's
/// captured upper bound. A server-confirmed, unchanged root revision after all
/// pages is required before advancing the cursor.
void verifyStableInputRevision({
  required int readRevision,
  required int confirmedRevision,
}) {
  _requireRevision(readRevision);
  _requireRevision(confirmedRevision);
  if (readRevision != confirmedRevision) {
    throw InputRevisionChanged(readRevision, confirmedRevision);
  }
}

/// Apply a fully fetched, stable change window without mutating the baseline.
///
/// [root] is the authoritative root input projection fetched with
/// [readRevision]. [changes] must include every change newer than
/// [baselineRevision] up to [readRevision]; pagination/truncation and owner
/// checks belong to the repository. Root-only revisions and coalesced changes
/// mean revision numbers need not be contiguous. Old overlapping records are
/// ignored, allowing idempotent page replay. A later record always wins for a
/// document, regardless of response order.
InputReadResult reduceIncrementalInputs({
  required InputSyncSnapshot baseline,
  required int baselineRevision,
  required Map<String, dynamic> root,
  required int readRevision,
  required int confirmedRevision,
  required Iterable<InputChangeRecord> changes,
}) {
  _requireRevision(baselineRevision);
  verifyStableInputRevision(
    readRevision: readRevision,
    confirmedRevision: confirmedRevision,
  );
  if (readRevision < baselineRevision) {
    throw const FormatException('Input revision moved behind the baseline.');
  }
  final latest = <String, InputChangeRecord>{};
  for (final change in changes) {
    if (change.revision > readRevision) {
      throw const FormatException('Input change is beyond the read boundary.');
    }
    if (change.revision <= baselineRevision) continue;
    final key = '${change.collection}/${change.id}';
    final previous = latest[key];
    if (previous != null && previous.revision == change.revision) {
      if (!sameSyncValue(previous.after, change.after)) {
        throw const FormatException(
          'Conflicting input changes at one revision.',
        );
      }
    } else if (previous == null || previous.revision < change.revision) {
      latest[key] = change;
    }
  }
  final signals = _copyDocuments(baseline.signals);
  final checkIns = _copyDocuments(baseline.checkIns);
  for (final change in latest.values) {
    final target = change.collection == 'signals' ? signals : checkIns;
    final after = change.after;
    if (after == null) {
      target.remove(change.id);
    } else {
      target[change.id] = _copyMap(after);
    }
  }
  return InputReadResult(
    snapshot: InputSyncSnapshot(
      root: _copyMap(root),
      signals: signals,
      checkIns: checkIns,
    ),
    revision: readRevision,
  );
}

const _maximumRevision = 9007199254740991;

void _requireRevision(int value, {int minimum = 0}) {
  if (value < minimum || value > _maximumRevision) {
    throw const FormatException('Invalid input revision.');
  }
}

Map<String, Map<String, dynamic>> _copyDocuments(
  Map<String, Map<String, dynamic>> values,
) => values.map((key, value) => MapEntry(key, _copyMap(value)));

Map<String, dynamic> _copyMap(Map<String, dynamic> value) =>
    value.map((key, child) => MapEntry(key, _copyValue(child)));

Object? _copyValue(Object? value) => switch (value) {
  Map() => _copyMap(Map<String, dynamic>.from(value)),
  List() => value.map(_copyValue).toList(),
  _ => value,
};
