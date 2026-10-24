import 'package:app/src/cloud_sync.dart';
import 'package:app/src/incremental_inputs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InputSyncSnapshot baseline() => InputSyncSnapshot(
    root: {
      'profile': {'name': 'Before'},
    },
    signals: {
      'old': {'value': 60, 'timestamp': '2025-01-01T00:00:00.000Z'},
      'retained': {
        'value': 10,
        'nested': {'quality': 1},
      },
    },
    checkIns: {
      'check': {'energy': 4},
    },
  );

  InputChangeRecord change(
    String id,
    int revision,
    Map<String, dynamic>? after, {
    String collection = 'signals',
  }) => InputChangeRecord(
    collection: collection,
    id: id,
    revision: revision,
    after: after,
  );

  InputReadResult read(
    Iterable<InputChangeRecord> changes, {
    InputSyncSnapshot? from,
    int cursor = 2,
    int revision = 5,
    int? confirmed,
    Map<String, dynamic>? root,
  }) => reduceIncrementalInputs(
    baseline: from ?? baseline(),
    baselineRevision: cursor,
    root:
        root ??
        {
          'profile': {'name': 'After'},
        },
    readRevision: revision,
    confirmedRevision: confirmed ?? revision,
    changes: changes,
  );

  test('edits historical observations and preserves untouched documents', () {
    final original = baseline();
    final result = read([
      change('old', 3, {'value': 75, 'timestamp': '2025-01-01T00:00:00.000Z'}),
      change('new', 4, {'value': 20}),
      change('check', 5, {'energy': 7}, collection: 'checkIns'),
    ], from: original);
    expect(result.revision, 5);
    expect(result.snapshot.signals['old']!['value'], 75);
    expect(result.snapshot.signals['retained'], original.signals['retained']);
    expect(result.snapshot.checkIns['check']!['energy'], 7);
    expect(result.snapshot.root['profile'], {'name': 'After'});
    expect(original.signals['old']!['value'], 60);
    expect(original.root['profile'], {'name': 'Before'});
  });

  test('deletions remain deleted across overlapping page replay', () {
    final page = [change('old', 4, null), change('missing', 5, null)];
    final first = read(page);
    final replay = read(
      [
        change('old', 3, {'value': 100}),
        ...page,
      ],
      from: first.snapshot,
      cursor: first.revision,
      revision: 6,
    );
    expect(replay.snapshot.signals.containsKey('old'), isFalse);
    expect(replay.snapshot.signals.containsKey('missing'), isFalse);
    expect(replay.revision, 6);
  });

  test('newest change wins independently of page order', () {
    final result = read([
      change('old', 5, null),
      change('old', 3, {'value': 80}),
      change('old', 4, {'value': 90}),
      change('new', 5, {'value': 42}),
      change('new', 5, {'value': 42}),
    ]);
    expect(result.snapshot.signals.containsKey('old'), isFalse);
    expect(result.snapshot.signals['new']!['value'], 42);
  });

  test('same document ID in separate collections stays independent', () {
    final result = read([
      change('same', 3, {'value': 10}),
      change('same', 4, {'energy': 8}, collection: 'checkIns'),
    ]);
    expect(result.snapshot.signals['same'], {'value': 10});
    expect(result.snapshot.checkIns['same'], {'energy': 8});
  });

  test('root-only changes advance cursor without deleting unseen inputs', () {
    final result = read([]);
    expect(result.revision, 5);
    expect(result.snapshot.signals, baseline().signals);
    expect(result.snapshot.checkIns, baseline().checkIns);
    expect(result.snapshot.root['profile'], {'name': 'After'});
  });

  test('concurrent revision change rejects the complete candidate window', () {
    final original = baseline();
    expect(
      () => read([change('old', 3, null)], from: original, confirmed: 6),
      throwsA(isA<InputRevisionChanged>()),
    );
    expect(original.signals['old']!['value'], 60);
    expect(
      () => verifyStableInputRevision(readRevision: 4, confirmedRevision: 5),
      throwsA(isA<InputRevisionChanged>()),
    );
  });

  test('failed or incomplete iteration cannot expose an advanced cursor', () {
    Iterable<InputChangeRecord> failedPages() sync* {
      yield change('old', 3, null);
      throw StateError('Second page failed');
    }

    final original = baseline();
    expect(() => read(failedPages(), from: original), throwsStateError);
    expect(original.signals['old']!['value'], 60);
  });

  test('invalid boundary and conflicting duplicate records fail closed', () {
    expect(() => read([], cursor: 6), throwsFormatException);
    expect(() => read([change('old', 6, null)]), throwsFormatException);
    expect(
      () => read([
        change('old', 3, null),
        change('old', 3, {'value': 80}),
      ]),
      throwsFormatException,
    );
  });

  test('candidate result does not share mutable input maps', () {
    final original = baseline();
    final root = <String, dynamic>{
      'profile': {'name': 'After'},
    };
    final payload = <String, dynamic>{
      'nested': {
        'values': [1, 2],
      },
    };
    final event = change('new', 3, payload);
    final result = read([event], from: original, root: root);
    (result.snapshot.signals['retained']!['nested'] as Map)['quality'] = 0;
    (result.snapshot.root['profile'] as Map)['name'] = 'Changed';
    ((result.snapshot.signals['new']!['nested'] as Map)['values'] as List)[0] =
        9;
    expect((original.signals['retained']!['nested'] as Map)['quality'], 1);
    expect(root['profile'], {'name': 'After'});
    expect((event.after!['nested'] as Map)['values'], [1, 2]);
    expect((payload['nested'] as Map)['values'], [1, 2]);
  });

  test(
    'change serialization distinguishes deletion from malformed payload',
    () {
      final tombstone = change('old', 3, null);
      final decoded = InputChangeRecord.fromJson(
        Map<String, dynamic>.from(tombstone.toJson()),
      );
      expect(decoded.id, 'old');
      expect(decoded.after, isNull);
      expect(decoded.revision, 3);
      for (final invalid in [
        {'collection': 'signals', 'id': 'old', 'revision': 3},
        {'collection': 'signals', 'id': 'old', 'revision': 3, 'after': 1},
        {'collection': 'outcomes', 'id': 'old', 'revision': 3, 'after': null},
        {'collection': 'signals', 'id': '../old', 'revision': 3, 'after': null},
        {'collection': 'signals', 'id': 'old', 'revision': 0, 'after': null},
      ]) {
        expect(
          () => InputChangeRecord.fromJson(invalid),
          throwsFormatException,
        );
      }
    },
  );

  test('revision parsing rejects missing, rounded and unsafe cursors', () {
    expect(parseInputRevision(0), 0);
    expect(parseInputRevision(4.0), 4);
    expect(parseInputRevision(9007199254740991), 9007199254740991);
    for (final invalid in [
      null,
      '3',
      -1,
      1.2,
      double.nan,
      double.infinity,
      9007199254740992,
    ]) {
      expect(() => parseInputRevision(invalid), throwsFormatException);
    }
  });
}
