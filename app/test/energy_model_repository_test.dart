// Strict SDK doubles below reject every unexpected read, query, or write.
// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';

import 'package:app/src/cloud_repository.dart';
import 'package:app/src/energy_model_repository.dart';
import 'package:app/src/firebase_services.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, create) in <(String, EnergyModelStore Function())>[
    ('memory', MemoryEnergyModelStore.new),
    ('device', SharedPreferencesEnergyModelStore.new),
  ]) {
    group('$name model envelopes', () {
      test('remain isolated by owner and overwrite only that owner', () async {
        final store = create();
        expect(await store.read('owner'), isNull);
        await store.write('owner', '{"attempt":"one"}');
        await store.write('second-owner', '{"attempt":"two"}');
        await store.write('owner', '{"attempt":"three"}');
        expect(await store.read('owner'), '{"attempt":"three"}');
        expect(await store.read('second-owner'), '{"attempt":"two"}');
        await store.clear();
        expect(await store.read('owner'), isNull);
        expect(await store.read('second-owner'), isNull);
      });

      test('enforces 16 KiB UTF-8 limit before overwriting', () async {
        final store = create();
        final boundary = 'x' * energyModelEnvelopeMaximumBytes;
        await store.write('owner', boundary);
        await expectLater(
          store.write('owner', '$boundary!'),
          throwsFormatException,
        );
        await expectLater(
          store.write('owner', '🙂' * 5000),
          throwsFormatException,
        );
        expect(await store.read('owner'), boundary);
      });

      test('rejects missing, path, and oversized owner identifiers', () async {
        final store = create();
        for (final uid in ['', 'owner/child', 'x' * 129]) {
          await expectLater(store.read(uid), throwsArgumentError);
          await expectLater(store.write(uid, '{}'), throwsArgumentError);
        }
      });
    });
  }

  test(
    'device envelopes survive new instances without touching other caches',
    () async {
      SharedPreferences.setMockInitialValues({
        'tonyo_state_v1': 'private profile and check-ins',
        'tonyo_ml_prep_v1_cached': 'private snapshot',
        'tonyo_signed_out_v1': true,
      });
      await SharedPreferencesEnergyModelStore().write('owner', '{"attempt":1}');
      expect(
        await SharedPreferencesEnergyModelStore().read('owner'),
        '{"attempt":1}',
      );
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences
            .getKeys()
            .where((key) => key.startsWith('tonyo_energy_model_v1_'))
            .length,
        1,
      );
      await SharedPreferencesEnergyModelStore().clear();
      expect(
        preferences.getString('tonyo_state_v1'),
        'private profile and check-ins',
      );
      expect(
        preferences.getString('tonyo_ml_prep_v1_cached'),
        'private snapshot',
      );
      expect(preferences.getBool('tonyo_signed_out_v1'), isTrue);
      expect(preferences.getKeys().length, 3);
    },
  );

  test(
    'corrupt stored type and oversized device records fall back to absent',
    () async {
      final key =
          'tonyo_energy_model_v1_${base64Url.encode(utf8.encode('owner'))}';
      SharedPreferences.setMockInitialValues({key: 42});
      expect(await SharedPreferencesEnergyModelStore().read('owner'), isNull);
      SharedPreferences.setMockInitialValues({key: 'x' * 17000});
      expect(await SharedPreferencesEnergyModelStore().read('owner'), isNull);
    },
  );

  test('accepted metadata is detached and remains well below 4 KiB', () {
    final input = validMetadata();
    final output = EnergyModelMetadata.validate(input);
    (input['featureCoverage'] as Map)['mood'] = 0;
    expect((output['featureCoverage'] as Map)['mood'], 0.75);
    expect(utf8.encode(jsonEncode(output)).length, lessThan(4096));
    expect(output.keys.toSet(), EnergyModelMetadata.fields);
  });

  test(
    'metadata accepts exact 5 percent improvement and DST calendar bounds',
    () {
      final input = validMetadata()
        ..['holdoutMae'] = 9.5
        ..['window'] = PrepWindow.endingOn(
          DateTime.utc(2026, 3, 31),
          timezone: 'America/Los_Angeles',
        ).toJson();
      expect(() => EnergyModelMetadata.validate(input), returnsNormally);
    },
  );

  test('metadata rejects unapproved fields and missing summary fields', () {
    for (final key in [
      'weights',
      'rows',
      'uid',
      'sourceIds',
      'trainingSnapshot',
    ]) {
      expect(
        () => EnergyModelMetadata.validate(validMetadata()..[key] = []),
        throwsFormatException,
      );
    }
    for (final field in EnergyModelMetadata.fields) {
      expect(
        () => EnergyModelMetadata.validate(validMetadata()..remove(field)),
        throwsFormatException,
      );
    }
  });

  test('metadata rejects unsafe numbers, versions, and underperformance', () {
    final invalid = <String, List<Object?>>{
      'modelVersion': [0, 2, 1.0, '1'],
      'schemaVersion': [0, 2, 1.0],
      'labelCount': [13, 101, 14.5, null],
      'holdoutMae': [-1, 9.5001, 101, double.nan, double.infinity],
      'deterministicMae': [0, -1, 101, double.nan, double.infinity],
    };
    for (final entry in invalid.entries) {
      for (final value in entry.value) {
        expect(
          () => EnergyModelMetadata.validate(
            validMetadata()..[entry.key] = value,
          ),
          throwsFormatException,
          reason: '${entry.key}: $value',
        );
      }
    }
  });

  test('metadata rejects unknown, missing, or nonfinite feature coverage', () {
    for (final coverage in [
      <String, Object?>{},
      {...coverageValues(), 'unknown': 1},
      {...coverageValues()}..remove('sleepDeviation'),
      {...coverageValues(), 'mood': -0.1},
      {...coverageValues(), 'stress': 1.1},
      {...coverageValues(), 'movement': double.nan},
      {...coverageValues(), 'caffeine': null},
    ]) {
      expect(
        () => EnergyModelMetadata.validate(
          validMetadata()..['featureCoverage'] = coverage,
        ),
        throwsFormatException,
      );
    }
  });

  test('metadata rejects malformed UTC times and non-30-day windows', () {
    for (final trainedAt in [
      '2026-08-01',
      '2026-08-01T12:00:00',
      '2026-08-01T12:00:00+00:00',
      '2026-02-30T12:00:00Z',
      'invalid',
    ]) {
      expect(
        () => EnergyModelMetadata.validate(
          validMetadata()..['trainedAt'] = trainedAt,
        ),
        throwsFormatException,
      );
    }
    for (final change in [
      {'start': '2026-07-01T00:00:00.000Z'},
      {'end': '2026-08-02T00:00:00.000Z'},
      {'timezone': 'not/a/timezone'},
      {'timezone': 'x' * 4096},
      {'extra': 'not-allowed'},
    ]) {
      final input = validMetadata();
      input['window'] = {...(input['window'] as Map), ...change};
      expect(() => EnergyModelMetadata.validate(input), throwsFormatException);
    }
  });

  test(
    'memory writer optionally enforces owner scope and counts only accepted writes',
    () async {
      final auth = ownerAuth();
      final writer = MemoryEnergyModelMetadataWriter(auth: auth);
      await expectLater(
        writer.writeAccepted('other', validMetadata()),
        throwsStateError,
      );
      await expectLater(
        writer.writeAccepted('owner', {}),
        throwsFormatException,
      );
      expect(writer.writes, 0);
      await writer.writeAccepted('owner', validMetadata());
      expect(writer.writes, 1);
      expect(writer.values.keys, ['owner']);
      auth.session = null;
      await expectLater(
        writer.writeAccepted('owner', validMetadata()),
        throwsStateError,
      );
      expect(writer.writes, 1);
    },
  );

  test(
    'Firestore accepted writer makes exactly one targeted merge and no reads',
    () async {
      final firestore = _MetadataOnlyFirestore();
      final writer = FirestoreEnergyModelMetadataWriter(
        firestore: firestore,
        auth: ownerAuth(),
      );
      await writer.writeAccepted('owner', validMetadata());
      expect(firestore.calls, ['set users/owner merge=true']);
      expect(firestore.payload!.keys, ['personalizedEnergyModel']);
      expect(firestore.payload!['personalizedEnergyModel'], validMetadata());
    },
  );

  test(
    'Firestore writer rejects invalid owners or payloads before touching SDK',
    () async {
      final firestore = _MetadataOnlyFirestore();
      final auth = ownerAuth();
      final writer = FirestoreEnergyModelMetadataWriter(
        firestore: firestore,
        auth: auth,
      );
      for (final uid in ['', 'other', 'owner/child']) {
        await expectLater(
          writer.writeAccepted(uid, validMetadata()),
          throwsStateError,
        );
      }
      await expectLater(
        writer.writeAccepted('owner', validMetadata()..['weights'] = [1]),
        throwsFormatException,
      );
      auth.session = null;
      await expectLater(
        writer.writeAccepted('owner', validMetadata()),
        throwsStateError,
      );
      expect(firestore.calls, isEmpty);
      expect(firestore.collectionsOpened, 0);
    },
  );

  test(
    'Firebase account restore requires both outcome and training consent',
    () async {
      final firestore = _ProfileOnlyFirestore();
      final repository = FirestoreCloudRepository(
        firestore: firestore,
        auth: ownerAuth(),
      );
      for (final flags in <Map<String, Object?>>[
        {},
        {'outcomeCollection': true},
        {'outcomeCollection': true, 'trainingRecordUse': false},
        {'outcomeCollection': false, 'trainingRecordUse': true},
        {'outcomeCollection': 'true', 'trainingRecordUse': true},
      ]) {
        firestore.flags = flags;
        expect((await repository.readUser('owner'))!.outcomeConsent, isFalse);
      }
      firestore.flags = {'outcomeCollection': true, 'trainingRecordUse': true};
      expect((await repository.readUser('owner'))!.outcomeConsent, isTrue);
    },
  );
}

Map<String, Object?> coverageValues() => {
  for (final feature in MlPrepBuilder.energyFeatureNames) feature: 0.75,
};

Map<String, Object?> validMetadata() => {
  'modelVersion': 1,
  'schemaVersion': 1,
  'window': PrepWindow.endingOn(
    DateTime.utc(2026, 7, 31),
    timezone: 'Etc/UTC',
  ).toJson(),
  'trainedAt': '2026-08-01T12:00:00.000Z',
  'labelCount': 20,
  'holdoutMae': 8.0,
  'deterministicMae': 10.0,
  'featureCoverage': coverageValues(),
};

MemoryAccountAuth ownerAuth() => MemoryAccountAuth(
  session: const AccountSession(uid: 'owner', email: 'owner@example.test'),
);

class _MetadataOnlyFirestore implements FirebaseFirestore {
  final calls = <String>[];
  int collectionsOpened = 0;
  Map<String, dynamic>? payload;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    collectionsOpened++;
    if (collectionPath != 'users') throw StateError('Unexpected collection');
    return _MetadataCollection(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected Firestore operation ${invocation.memberName}',
  );
}

class _MetadataCollection implements CollectionReference<Map<String, dynamic>> {
  _MetadataCollection(this.store);
  final _MetadataOnlyFirestore store;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    if (path != 'owner') throw StateError('Unexpected owner');
    return _MetadataDocument(store);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected collection operation ${invocation.memberName}',
  );
}

class _MetadataDocument implements DocumentReference<Map<String, dynamic>> {
  _MetadataDocument(this.store);
  final _MetadataOnlyFirestore store;
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    store.calls.add('set users/owner merge=${options?.merge}');
    store.payload = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected document operation ${invocation.memberName}',
  );
}

class _ProfileOnlyFirestore implements FirebaseFirestore {
  Map<String, Object?> flags = {};
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _ProfileCollection(this);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Firestore operation');
}

class _ProfileCollection implements CollectionReference<Map<String, dynamic>> {
  _ProfileCollection(this.store);
  final _ProfileOnlyFirestore store;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _ProfileDocument(store);
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _EmptyRows();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected collection operation');
}

class _ProfileDocument implements DocumentReference<Map<String, dynamic>> {
  _ProfileDocument(this.store);
  final _ProfileOnlyFirestore store;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _ProfileSnapshot(store.flags);
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _ProfileCollection(store);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected document operation');
}

class _ProfileSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _ProfileSnapshot(this.flags);
  final Map<String, Object?> flags;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => {
    'profile': const UserProfile().toJson(),
    'accountEmail': 'owner@example.test',
    'consentFlags': flags,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected snapshot operation');
}

class _EmptyRows implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected result operation');
}
