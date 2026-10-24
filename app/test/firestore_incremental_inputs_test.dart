// Strict SDK doubles exercise repository wiring without contacting Firebase.
// ignore_for_file: subtype_of_sealed_class
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/firebase_services.dart';
import 'package:app/src/incremental_inputs.dart';
import 'package:app/src/models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 24);
  late _Store store;
  late MemoryAccountAuth auth;
  late FirestoreCloudRepository repository;
  SignalReading signal(
    String id, {
    double value = 60,
    SignalType type = SignalType.hrv,
  }) => SignalReading(id: id, type: type, value: value, timestamp: day);
  Map<String, dynamic> payload(SignalReading value) =>
      Map<String, dynamic>.from(signalToCloud(value));

  setUp(() {
    auth = MemoryAccountAuth(
      session: const AccountSession(uid: 'owner', email: 'owner@example.test'),
    );
    store = _Store()
      ..documents['users/owner'] = {
        'profile': {'name': 'Owner'},
        'accountEmail': 'owner@example.test',
        'inputSyncVersion': 1,
        'inputRevision': 0,
      };
    store.documents['users/owner/signals/old'] = payload(signal('old'));
    store.documents['users/owner/signals/heart'] = payload(
      signal('heart', type: SignalType.heartRate),
    );
    repository = FirestoreCloudRepository(firestore: store, auth: auth);
  });

  test(
    'one authoritative bootstrap supplies all derived input ranges',
    () async {
      final restored = await repository.readUser('owner');
      expect(restored!.inputRevision, 0);
      expect(restored.signals.length, 2);
      final requests = store.reads.length;
      await repository.activateInputSync('owner');
      expect(
        (await repository.signalsByRange(
          'owner',
          start: day,
          end: day.add(const Duration(days: 1)),
          includeHeartRate: false,
        )).single.id,
        'old',
      );
      expect(
        await repository.checkInsByRange(
          'owner',
          start: day,
          end: day.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
      expect(await repository.latestCheckIn('owner'), isNull);
      expect(await repository.reactionBaselineWindow('owner'), isEmpty);
      expect(store.reads.length, requests);
      auth.session = null;
      await expectLater(repository.latestCheckIn('owner'), throwsStateError);
      expect(store.transactions, 0, reason: 'A restore must be read-only.');
    },
  );

  test('delta read edits old observations and propagates deletion', () async {
    final restored = await repository.readUser('owner');
    final baseline = InputSyncSnapshot.fromState(restored!);
    store.documents['users/owner']!['inputRevision'] = 2;
    store.documents['users/owner/inputChanges/signals__old'] =
        Map<String, dynamic>.from(
          InputChangeRecord(
            collection: 'signals',
            id: 'old',
            revision: 1,
            after: payload(signal('old', value: 90)),
          ).toJson(),
        );
    store.documents['users/owner/inputChanges/signals__heart'] = {
      'collection': 'signals',
      'id': 'heart',
      'revision': 2,
      'after': null,
    };
    store.reads.clear();
    final next = await repository.readUserSince(
      'owner',
      baseline: baseline,
      revision: 0,
    );
    expect(next!.inputRevision, 2);
    expect(next.signals.single.id, 'old');
    expect(next.signals.single.value, 90);
    expect(store.reads.where((value) => value.startsWith('query ')).toList(), [
      'query users/owner/inputChanges',
    ]);
    expect(baseline.signals['old']!['value'], 60);
  });

  test('a cursor ahead of server metadata performs a full bootstrap', () async {
    final restored = await repository.readUser('owner');
    final incomplete = InputSyncSnapshot(root: {}, signals: {}, checkIns: {});
    store.reads.clear();
    final next = await repository.readUserSince(
      'owner',
      baseline: incomplete,
      revision: restored!.inputRevision! + 100,
    );
    expect(next!.inputRevision, 0);
    expect(
      next.signals.map((row) => row.id),
      unorderedEquals(['old', 'heart']),
    );
    expect(store.reads, contains('query users/owner/signals'));
    expect(store.reads, isNot(contains('query users/owner/inputChanges')));
  });

  test(
    'legacy bootstrap detects nanosecond changes and tolerates unknown maps',
    () async {
      final root = store.documents['users/owner']!;
      root.remove('inputSyncVersion');
      root.remove('inputRevision');
      root['updatedAt'] = Timestamp(1234, 1);
      root['futureMetadata'] = {
        3: [double.nan, null],
      };
      var raced = false;
      store.afterQuery = (path) {
        root['futureMetadata'] = {
          3: [double.nan, null],
        };
        if (!raced && path.endsWith('/signals')) {
          raced = true;
          root['updatedAt'] = Timestamp(1234, 2);
          store.documents['users/owner/signals/old'] = payload(
            signal('old', value: 90),
          );
        }
      };
      final restored = await repository.readUser('owner');
      expect(restored!.signals.singleWhere((row) => row.id == 'old').value, 90);
      expect(
        store.reads.where((value) => value == 'query users/owner/signals'),
        hasLength(2),
      );
    },
  );

  test('pagination uses every document sharing a revision boundary', () async {
    final restored = await repository.readUser('owner');
    store.documents['users/owner']!['inputRevision'] = 1;
    for (var i = 0; i < 401; i++) {
      final id = 'added-${i.toString().padLeft(3, '0')}';
      store.documents['users/owner/inputChanges/signals__$id'] = {
        'collection': 'signals',
        'id': id,
        'revision': 1,
        'after': payload(signal(id)),
      };
    }
    store.reads.clear();
    final next = await repository.readUserSince(
      'owner',
      baseline: InputSyncSnapshot.fromState(restored!),
      revision: 0,
    );
    expect(next!.signals.length, 403);
    expect(
      store.reads
          .where((value) => value == 'query users/owner/inputChanges')
          .length,
      2,
    );
  });

  test(
    'concurrent update across upper boundary retries from durable baseline',
    () async {
      final restored = await repository.readUser('owner');
      store.documents['users/owner']!['inputRevision'] = 1;
      store.documents['users/owner/inputChanges/signals__old'] = {
        'collection': 'signals',
        'id': 'old',
        'revision': 1,
        'after': payload(signal('old', value: 70)),
      };
      var raced = false;
      store.afterQuery = (path) {
        if (!raced && path.endsWith('/inputChanges')) {
          raced = true;
          store.documents['users/owner']!['inputRevision'] = 2;
          store.documents['users/owner/inputChanges/signals__old'] = {
            'collection': 'signals',
            'id': 'old',
            'revision': 2,
            'after': null,
          };
        }
      };
      final next = await repository.readUserSince(
        'owner',
        baseline: InputSyncSnapshot.fromState(restored!),
        revision: 0,
      );
      expect(next!.inputRevision, 2);
      expect(next.signals.map((row) => row.id), ['heart']);
    },
  );

  test(
    'malformed journal data fails without retaining a successful cache',
    () async {
      final restored = await repository.readUser('owner');
      store.documents['users/owner']!['inputRevision'] = 1;
      store.documents['users/owner/inputChanges/wrong-identity'] = {
        'collection': 'signals',
        'id': 'old',
        'revision': 1,
        'after': null,
      };
      await expectLater(
        repository.readUserSince(
          'owner',
          baseline: InputSyncSnapshot.fromState(restored!),
          revision: 0,
        ),
        throwsFormatException,
      );
      store.reads.clear();
      await repository.signalsByRange(
        'owner',
        start: day,
        end: day.add(const Duration(days: 1)),
      );
      expect(store.reads, ['query users/owner/signals']);
    },
  );

  test(
    'atomic patches journal updates and deletes and advance the shared cache',
    () async {
      final restored = await repository.readUser('owner');
      final after = restored!.copyWith(signals: [signal('old', value: 88)]);
      await repository.applyInputPatch(
        'owner',
        InputSyncPatch(
          InputSyncSnapshot.fromState(restored),
          InputSyncSnapshot.fromState(after),
        ),
      );
      expect(store.documents['users/owner']!['inputRevision'], 1);
      expect(store.documents['users/owner/signals/heart'], isNull);
      expect(
        store.documents['users/owner/inputChanges/signals__heart']!['after'],
        isNull,
      );
      expect(
        (store.documents['users/owner/inputChanges/signals__old']!['after']
            as Map)['value'],
        88,
      );
      final journal =
          store.documents['users/owner/inputChanges/signals__old']!['after']
              as Map;
      for (final nullableField in ['note', 'groupId', 'syncedAt']) {
        expect(journal.containsKey(nullableField), isTrue);
        expect(journal[nullableField], isNull);
      }
      store.reads.clear();
      expect(
        (await repository.signalsByRange(
          'owner',
          start: day,
          end: day.add(const Duration(days: 1)),
        )).single.value,
        88,
      );
      expect(store.reads, isEmpty);
    },
  );

  test(
    'interleaved remote revision prevents advancing an incomplete cache',
    () async {
      final restored = await repository.readUser('owner');
      store.documents['users/owner']!['inputRevision'] = 1;
      store.documents['users/owner/signals/remote'] = payload(signal('remote'));
      await repository.applyInputPatch(
        'owner',
        InputSyncPatch(
          InputSyncSnapshot.fromState(restored!),
          InputSyncSnapshot.fromState(
            restored.copyWith(signals: [...restored.signals, signal('local')]),
          ),
        ),
      );
      store.reads.clear();
      final rows = await repository.signalsByRange(
        'owner',
        start: day,
        end: day.add(const Duration(days: 1)),
      );
      expect(rows.map((row) => row.id), contains('remote'));
      expect(store.reads, ['query users/owner/signals']);
    },
  );

  test(
    'partial chunk failure invalidates cache without inventing acknowledgements',
    () async {
      final restored = await repository.readUser('owner');
      store.failTransaction = 2;
      final after = restored!.copyWith(
        signals: [
          ...restored.signals,
          for (var i = 0; i < 17; i++) signal('added-$i'),
        ],
      );
      await expectLater(
        repository.applyInputPatch(
          'owner',
          InputSyncPatch(
            InputSyncSnapshot.fromState(restored),
            InputSyncSnapshot.fromState(after),
          ),
        ),
        throwsStateError,
      );
      expect(store.documents['users/owner']!['inputRevision'], 1);
      expect(
        store.documents.keys
            .where((path) => path.contains('/inputChanges/'))
            .length,
        16,
      );
      store.reads.clear();
      expect(
        (await repository.signalsByRange(
          'owner',
          start: day,
          end: day.add(const Duration(days: 1)),
        )).length,
        18,
      );
      expect(store.reads, ['query users/owner/signals']);
    },
  );

  test(
    'explicit protocol activation is idempotent and completion only sets metadata',
    () async {
      store.documents['users/owner']!.remove('inputSyncVersion');
      store.documents['users/owner']!.remove('inputRevision');
      final legacy = await repository.readUser('owner');
      expect(legacy!.inputRevision, isNull);
      expect(store.transactions, 0);
      await repository.activateInputSync('owner');
      await repository.activateInputSync('owner');
      final restored = await repository.readUser('owner');
      expect(restored!.inputRevision, 0);
      await repository.finishHeartRateMigration('owner');
      final completionTransactions = store.transactions;
      await repository.finishHeartRateMigration('owner');
      expect(store.transactions, completionTransactions);
      expect(store.documents['users/owner']!['heartRateStorageVersion'], 1);
      expect(store.documents['users/owner']!['inputRevision'], 0);
      expect(
        store.documents.keys.where((path) => path.contains('/inputChanges/')),
        isEmpty,
      );
    },
  );
}

class _Store implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final reads = <String>[];
  int transactions = 0;
  int? failTransaction;
  void Function(String)? afterQuery;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Query(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactions++;
    if (transactions == failTransaction) {
      throw StateError('Synthetic commit failure');
    }
    final tx = _Transaction(this);
    final result = await handler(tx);
    for (final write in tx.writes) {
      write();
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected store operation ${invocation.memberName}');
}

class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Query(store, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    store.reads.add('document $path');
    return store.documents[path] == null
        ? _MissingSnapshot(id)
        : _Snapshot(id, Map.of(store.documents[path]!));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected document operation ${invocation.memberName}',
  );
}

// This strict test double records each query chain in one mutable instance.
// ignore: must_be_immutable
class _Query implements CollectionReference<Map<String, dynamic>> {
  _Query(this.store, this.path);
  final _Store store;
  @override
  final String path;
  final filters = <(String, Symbol, Object?)>[];
  final orderings = <(String, bool)>[];
  int? maximum;
  _Snapshot? after;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(store, '${this.path}/$path');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.positionalArguments;
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #where:
        for (final condition in [
          #isGreaterThan,
          #isLessThanOrEqualTo,
          #isGreaterThanOrEqualTo,
          #isLessThan,
          #isEqualTo,
          #whereIn,
        ]) {
          if (named[condition] != null) {
            filters.add((args.single as String, condition, named[condition]));
          }
        }
        return this;
      case #orderBy:
        orderings.add((
          args.single == FieldPath.documentId
              ? '__name__'
              : args.single as String,
          named[#descending] == true,
        ));
        return this;
      case #limit:
        maximum = args.single as int;
        return this;
      case #startAfterDocument:
        after = args.single as _Snapshot;
        return this;
      case #get:
        store.reads.add('query $path');
        var rows = store.documents.entries
            .where(
              (entry) =>
                  entry.key.startsWith('$path/') &&
                  entry.key.split('/').length == path.split('/').length + 1,
            )
            .map(
              (entry) =>
                  _Snapshot(entry.key.split('/').last, Map.of(entry.value)),
            )
            .toList();
        rows = rows
            .where(
              (row) => filters.every((filter) {
                final value = row.value![filter.$1];
                if (filter.$2 == #whereIn) {
                  return (filter.$3 as Iterable).contains(value);
                }
                if (filter.$2 == #isEqualTo) return value == filter.$3;
                final comparison = _comparable(
                  value,
                ).compareTo(_comparable(filter.$3));
                return switch (filter.$2) {
                  #isGreaterThan => comparison > 0,
                  #isLessThanOrEqualTo => comparison <= 0,
                  #isGreaterThanOrEqualTo => comparison >= 0,
                  #isLessThan => comparison < 0,
                  _ => false,
                };
              }),
            )
            .toList();
        int compare(_Snapshot left, _Snapshot right) {
          for (final ordering in orderings) {
            final a = ordering.$1 == '__name__'
                ? left.id
                : left.value![ordering.$1];
            final b = ordering.$1 == '__name__'
                ? right.id
                : right.value![ordering.$1];
            final result = _comparable(a).compareTo(_comparable(b));
            if (result != 0) return ordering.$2 ? -result : result;
          }
          return left.id.compareTo(right.id);
        }
        rows.sort(compare);
        if (after != null) {
          rows = rows.where((row) => compare(row, after!) > 0).toList();
        }
        if (maximum != null) rows = rows.take(maximum!).toList();
        store.afterQuery?.call(path);
        return Future<QuerySnapshot<Map<String, dynamic>>>.value(_Rows(rows));
      default:
        throw StateError('Unexpected query operation ${invocation.memberName}');
    }
  }
}

class _Snapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic> data() => value ?? <String, dynamic>{};
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected snapshot operation ${invocation.memberName}',
  );
}

class _Rows implements QuerySnapshot<Map<String, dynamic>> {
  _Rows(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected rows operation ${invocation.memberName}');
}

class _MissingSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _MissingSnapshot(this.id);
  @override
  final String id;
  @override
  bool get exists => false;
  @override
  Map<String, dynamic>? data() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected missing snapshot operation ${invocation.memberName}',
  );
}

Comparable _comparable(Object? value) =>
    value is Timestamp ? value.toDate() : value as Comparable;

class _Transaction implements Transaction {
  _Transaction(this.store);
  final _Store store;
  final writes = <void Function()>[];
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async {
    if (writes.isNotEmpty) throw StateError('Transaction read after a write');
    final data = store.documents[ref.path];
    return (data == null
            ? _MissingSnapshot(ref.id)
            : _Snapshot(ref.id, Map.of(data)))
        as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    final values = Map<String, dynamic>.from(data as Map);
    writes.add(() {
      store.documents[ref.path] = options?.merge == true
          ? _merge(store.documents[ref.path] ?? {}, values)
          : values;
    });
    return this;
  }

  @override
  Transaction delete(DocumentReference ref) {
    writes.add(() {
      store.documents.remove(ref.path);
    });
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected transaction operation ${invocation.memberName}',
  );
}

Map<String, dynamic> _merge(
  Map<String, dynamic> old,
  Map<String, dynamic> next,
) => {
  ...old,
  for (final entry in next.entries)
    entry.key: entry.value is Map && old[entry.key] is Map
        ? _merge(
            Map<String, dynamic>.from(old[entry.key] as Map),
            Map<String, dynamic>.from(entry.value as Map),
          )
        : entry.value,
};
