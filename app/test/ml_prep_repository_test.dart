// SDK interfaces are implemented only by strict read-only test doubles below.
// ignore_for_file: subtype_of_sealed_class

import 'package:app/src/cloud_repository.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/ml_prep_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final window = PrepWindow.endingOn(
    DateTime.utc(2026, 7, 31),
    timezone: 'Etc/UTC',
  );

  group('Bounded prep query specification', () {
    test('keeps the exact window and collection-specific timestamp field', () {
      for (final collection in PrepCollection.values) {
        final spec = PrepQuerySpec(
          uid: 'owner',
          authenticatedUid: 'owner',
          collection: collection,
          window: window,
          requestedLimit: 30,
        );
        expect(spec.start, window.start);
        expect(spec.end, window.end);
        expect(spec.limit, 30);
        expect(
          spec.timestampField,
          collection == PrepCollection.outcomes ? 'observedAt' : 'timestamp',
        );
      }
    });

    test('clamps oversized requests to the server-side document budget', () {
      for (final collection in PrepCollection.values) {
        final spec = PrepQuerySpec(
          uid: 'owner',
          authenticatedUid: 'owner',
          collection: collection,
          window: window,
          requestedLimit: 1000000,
        );
        expect(spec.limit, collection == PrepCollection.signals ? 1500 : 100);
      }
    });

    test(
      'rejects invalid limits and unauthenticated or cross-account reads',
      () {
        for (final limit in [0, -1]) {
          expect(
            () => PrepQuerySpec(
              uid: 'owner',
              authenticatedUid: 'owner',
              collection: PrepCollection.signals,
              window: window,
              requestedLimit: limit,
            ),
            throwsArgumentError,
          );
        }
        for (final currentUid in <String?>[null, 'different-owner']) {
          expect(
            () => PrepQuerySpec.requireAccount('owner', currentUid),
            throwsStateError,
          );
        }
        expect(() => PrepQuerySpec.requireAccount('', ''), throwsStateError);
        expect(
          () => PrepQuerySpec.requireAccount('owner/child', 'owner/child'),
          throwsStateError,
        );
      },
    );
  });

  group('Read-only Firebase prep adapter', () {
    late MemoryAccountAuth auth;
    late _ReadOnlyFirestore firestore;
    late FirestorePrepDataSource source;

    setUp(() {
      auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        ),
      );
      firestore = _ReadOnlyFirestore();
      source = FirestorePrepDataSource(firestore: firestore, auth: auth);
    });

    test(
      'one server profile read extracts dual consent and legacy version',
      () async {
        firestore.profile = {
          'schemaVersion': 11,
          'consentFlags': {
            'outcomeCollection': true,
            'trainingRecordUse': true,
          },
        };
        final metadata = await source.readAccount('owner');
        expect(metadata.schemaVersion, 11);
        expect(metadata.consent.collection, isTrue);
        expect(metadata.consent.trainingUse, isTrue);
        expect(metadata.consent.version, 1);
        expect(firestore.calls, ['document.get users/owner server']);
      },
    );

    test(
      'missing flags stay off and explicit versions are preserved',
      () async {
        firestore.profile = {'schemaVersion': 7};
        var metadata = await source.readAccount('owner');
        expect(metadata.consent.collection, isFalse);
        expect(metadata.consent.trainingUse, isFalse);
        expect(metadata.consent.version, 0);
        firestore.profile = {
          'schemaVersion': 11,
          'consentFlags': {
            'outcomeCollection': true,
            'trainingRecordUse': true,
            'version': 2,
          },
        };
        metadata = await source.readAccount('owner');
        expect(metadata.consent.version, 2);
      },
    );

    test(
      'one bounded server query per collection, without consent rereads',
      () async {
        for (final collection in PrepCollection.values) {
          firestore.calls.clear();
          await source.readCollection(
            'owner',
            collection,
            window,
            limit: 999999,
          );
          final field = collection == PrepCollection.outcomes
              ? 'observedAt'
              : 'timestamp';
          expect(firestore.calls, [
            'where $field >= ${window.start.toIso8601String()}',
            'where $field < ${window.end.toIso8601String()}',
            'orderBy $field false',
            'limit ${collection == PrepCollection.signals ? 1500 : 100}',
            'query.get users/owner/${collection.name} server',
          ]);
        }
      },
    );

    test(
      'normalizes nested timestamps and uses authoritative document IDs',
      () async {
        final at = DateTime.utc(2026, 7, 25, 12, 15);
        firestore.rows = [
          _Row('actual-id', {
            'id': 'spoofed-id',
            'timestamp': Timestamp.fromDate(at),
            'nested': {
              'times': [Timestamp.fromDate(at), null, 3],
            },
          }),
        ];
        final rows = await source.readCollection(
          'owner',
          PrepCollection.signals,
          window,
          limit: 1500,
        );
        expect(rows.single, {
          'id': 'actual-id',
          'timestamp': at.toIso8601String(),
          'nested': {
            'times': [at.toIso8601String(), null, 3],
          },
        });
      },
    );

    test(
      'rejects wrong accounts before issuing either kind of request',
      () async {
        await expectLater(source.readAccount('stranger'), throwsStateError);
        await expectLater(
          source.readCollection(
            'stranger',
            PrepCollection.signals,
            window,
            limit: 1,
          ),
          throwsStateError,
        );
        auth.session = null;
        await expectLater(source.readAccount('owner'), throwsStateError);
        expect(firestore.calls, isEmpty);
      },
    );

    test(
      'discards profile and collection responses after an account change',
      () async {
        firestore.afterRead = () => auth.session = null;
        await expectLater(source.readAccount('owner'), throwsStateError);
        auth.session = const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        );
        await expectLater(
          source.readCollection(
            'owner',
            PrepCollection.outcomes,
            window,
            limit: 100,
          ),
          throwsStateError,
        );
        expect(
          firestore.calls.where((call) => call.contains('.get')).length,
          2,
        );
      },
    );

    test('a missing profile fails without querying collections', () async {
      firestore.profile = null;
      await expectLater(source.readAccount('owner'), throwsStateError);
      expect(firestore.calls, ['document.get users/owner server']);
    });
  });
}

// This fake accepts only the exact read operations exercised by preparation.
// Unexpected SDK methods, including writes and listeners, fail the test.
class _ReadOnlyFirestore implements FirebaseFirestore {
  final List<String> calls = [];
  Map<String, dynamic>? profile = const {};
  List<_Row> rows = [];
  void Function()? afterRead;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(this, collectionPath);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected Firestore operation: ${invocation.memberName}',
  );
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);

  final _ReadOnlyFirestore store;
  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    if (path == null) {
      throw StateError('Automatic document IDs are not read-only.');
    }
    return _Document(store, '${this.path}/$path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.positionalArguments;
    final named = invocation.namedArguments;
    switch (invocation.memberName) {
      case #where:
        final lower = named[#isGreaterThanOrEqualTo] as DateTime?;
        final upper = named[#isLessThan] as DateTime?;
        if (lower != null && upper == null) {
          store.calls.add('where ${args.single} >= ${lower.toIso8601String()}');
        } else if (upper != null && lower == null) {
          store.calls.add('where ${args.single} < ${upper.toIso8601String()}');
        } else {
          throw StateError('Expected an exact half-open timestamp bound.');
        }
        return this;
      case #orderBy:
        store.calls.add('orderBy ${args.single} ${named[#descending]}');
        return this;
      case #limit:
        store.calls.add('limit ${args.single}');
        return this;
      case #get:
        final options = args.single as GetOptions;
        store.calls.add('query.get $path ${options.source.name}');
        store.afterRead?.call();
        return Future<QuerySnapshot<Map<String, dynamic>>>.value(
          _Rows(store.rows),
        );
      default:
        throw StateError(
          'Unexpected collection operation: ${invocation.memberName}',
        );
    }
  }
}

class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);

  final _ReadOnlyFirestore store;
  @override
  final String path;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(store, '$path/$collectionPath');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    store.calls.add('document.get $path ${options?.source.name}');
    store.afterRead?.call();
    return _Profile(store.profile);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected document operation: ${invocation.memberName}',
  );
}

class _Profile implements DocumentSnapshot<Map<String, dynamic>> {
  _Profile(this.value);
  final Map<String, dynamic>? value;

  @override
  Map<String, dynamic>? data() => value;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected snapshot operation: ${invocation.memberName}',
  );
}

class _Row implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Row(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;

  @override
  Map<String, dynamic> data() => value;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected row operation: ${invocation.memberName}');
}

class _Rows implements QuerySnapshot<Map<String, dynamic>> {
  _Rows(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected result operation: ${invocation.memberName}');
}
