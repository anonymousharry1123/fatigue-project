// Strict SDK doubles reject any unexpected query, listener, or write.
// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';

import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/energy_model_summary.dart';
import 'package:app/src/firebase_services.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('read-only Energy model summary', () {
    test('parses supported metadata and returns a safe detached JSON copy', () {
      final input = _metadata();
      final summary = EnergyModelSummary.tryParse(input)!;
      expect(summary.modelVersion, 1);
      expect(summary.schemaVersion, 1);
      expect(summary.labelCount, 20);
      expect(summary.trainedAt, DateTime.utc(2026, 8, 1, 12));
      expect(summary.windowStart, DateTime.utc(2026, 7, 2));
      expect(summary.windowEnd, DateTime.utc(2026, 8));
      expect(summary.timezone, 'Etc/UTC');
      expect(summary.holdoutMae, 8);
      expect(summary.deterministicMae, 10);
      expect(summary.improvementPercent, closeTo(20, .00001));
      expect(summary.featureCoverage.values, everyElement(.75));
      final json = summary.toJson();
      expect(jsonDecode(jsonEncode(json)), input);
      expect(json.keys, isNot(contains('weights')));
      expect(json.keys, isNot(contains('examples')));
      expect(json.keys, isNot(contains('uid')));
      expect(
        EnergyModelSummary.tryParse(json)!.improvementPercent,
        summary.improvementPercent,
      );
      (input['featureCoverage'] as Map)['caffeine'] = 0;
      (json['featureCoverage'] as Map)['caffeine'] = 1.0;
      expect(summary.featureCoverage['caffeine'], .75);
      expect(
        () => summary.featureCoverage['caffeine'] = 1,
        throwsUnsupportedError,
      );
    });

    test('supports normalized dates and a daylight-saving 30-day window', () {
      final bounds = PrepWindow.endingOn(
        DateTime.utc(2026, 3, 15),
        timezone: 'America/Los_Angeles',
      );
      final input = _metadata()
        ..['trainedAt'] = DateTime.utc(2026, 3, 16)
        ..['window'] = {
          'start': bounds.start,
          'end': bounds.end,
          'timezone': bounds.timezone,
        };
      final summary = EnergyModelSummary.tryParse(input)!;
      expect(summary.windowStart, bounds.start);
      expect(summary.windowEnd, bounds.end);
      expect(summary.windowEnd.difference(summary.windowStart).inHours, 719);
    });

    test('accepts UTC aliases and dates without fractional seconds', () {
      for (final timezone in ['Etc/UTC', 'UTC']) {
        final input = _metadata()
          ..['trainedAt'] = '2026-08-02T00:00:00Z'
          ..['window'] = {
            'start': '2026-07-02T00:00:00Z',
            'end': '2026-08-01T00:00:00Z',
            'timezone': timezone,
          };
        final summary = EnergyModelSummary.tryParse(input);
        expect(summary, isNotNull, reason: timezone);
        expect(summary!.trainedAt, DateTime.utc(2026, 8, 2));
        expect(summary.timezone, 'Etc/UTC');
      }
    });

    test('absence and legacy or non-map values never throw', () {
      for (final value in [
        null,
        true,
        3,
        'old-model',
        [],
        {},
        {'version': 0},
      ]) {
        expect(EnergyModelSummary.tryParse(value), isNull);
      }
    });

    for (final (field, invalidValues) in <(String, List<Object?>)>[
      ('modelVersion', [null, 0, 2, 1.0, '1']),
      ('schemaVersion', [null, 0, 2, 1.0, '1']),
      ('labelCount', [null, 13, 101, 14.0, '20']),
      ('holdoutMae', [null, -1, 101, double.nan, double.infinity, '8', 9.51]),
      (
        'deterministicMae',
        [null, -1, 0, 101, double.nan, double.infinity, '10'],
      ),
      (
        'trainedAt',
        [
          null,
          123,
          '2026-08-01',
          '2026-08-01T12:00:00',
          '2026-08-01T12:00:00+00:00',
          '2026-02-30T12:00:00Z',
          '2026-08-01T25:00:00Z',
          '2026-06-01T00:00:00Z',
        ],
      ),
    ]) {
      test('rejects malformed $field values', () {
        for (final value in invalidValues) {
          expect(
            EnergyModelSummary.tryParse(_metadata()..[field] = value),
            isNull,
            reason: '$field=$value',
          );
        }
      });
    }

    test('rejects extra fields including private artifact data', () {
      for (final field in [
        'weights',
        'examples',
        'uid',
        'intercept',
        'future',
      ]) {
        expect(EnergyModelSummary.tryParse(_metadata()..[field] = []), isNull);
      }
      expect(
        EnergyModelSummary.tryParse(_metadata()..remove('trainedAt')),
        isNull,
      );
      expect(
        EnergyModelSummary.tryParse({..._metadata(), 1: 'invalid map key'}),
        isNull,
      );
    });

    test('requires exactly eight finite coverage fractions', () {
      for (final invalid in [null, -0.01, 1.01, double.nan, '0.5', true]) {
        final input = _metadata();
        (input['featureCoverage'] as Map)['caffeine'] = invalid;
        expect(EnergyModelSummary.tryParse(input), isNull);
      }
      final missing = _metadata();
      (missing['featureCoverage'] as Map).remove('caffeine');
      expect(EnergyModelSummary.tryParse(missing), isNull);
      final extra = _metadata();
      (extra['featureCoverage'] as Map)['newFeature'] = .5;
      expect(EnergyModelSummary.tryParse(extra), isNull);
    });

    test('requires an exact named-timezone 30-calendar-day window', () {
      for (final invalid in <Object?>[
        null,
        'July',
        {'start': '2026-07-02T00:00:00Z', 'end': '2026-08-01T00:00:00Z'},
        {
          'start': '2026-07-01T00:00:00Z',
          'end': '2026-08-01T00:00:00Z',
          'timezone': 'Etc/UTC',
        },
        {
          'start': '2026-08-01T00:00:00Z',
          'end': '2026-07-02T00:00:00Z',
          'timezone': 'Etc/UTC',
        },
        {
          'start': '2026-07-02T00:00:00Z',
          'end': '2026-08-01T00:00:00Z',
          'timezone': 'Missing/Timezone',
        },
        {
          'start': '2026-07-02T00:00:00Z',
          'end': '2026-08-01T00:00:00Z',
          'timezone': '',
        },
        {
          'start': '2026-07-02T00:00:00Z',
          'end': '2026-08-01T00:00:00Z',
          'timezone': 'Etc/UTC',
          'extra': true,
        },
      ]) {
        expect(
          EnergyModelSummary.tryParse(_metadata()..['window'] = invalid),
          isNull,
        );
      }
    });

    test(
      'accepts exactly five-percent improvement and zero candidate error',
      () {
        final boundary = EnergyModelSummary.tryParse(
          _metadata()..['holdoutMae'] = 9.5,
        )!;
        expect(boundary.improvementPercent, closeTo(5, .00001));
        final zeroError = EnergyModelSummary.tryParse(
          _metadata()..['holdoutMae'] = 0,
        )!;
        expect(zeroError.improvementPercent, 100);
      },
    );

    test(
      'cloud state copy preserves summary without adding executable data',
      () {
        final summary = EnergyModelSummary.tryParse(_metadata())!;
        final updated = DateTime.utc(2026, 8, 1, 13);
        final state = _state(summary: summary, updatedAt: updated);
        final copied = state.copyWith(migrationVersion: 99);
        expect(copied.personalizedEnergyModel, same(summary));
        expect(copied.userUpdatedAt, updated);
        expect(copied.migrationVersion, 99);
        expect(
          copied.toExportJson()['personalizedEnergyModel'],
          summary.toJson(),
        );
        expect(
          copied.toExportJson()['userUpdatedAt'],
          updated.toIso8601String(),
        );
        expect(_state().personalizedEnergyModel, isNull);
        expect(_state().userUpdatedAt, isNull);
        expect(
          _state().toExportJson(),
          isNot(contains('personalizedEnergyModel')),
        );
        expect(_state().toExportJson(), isNot(contains('userUpdatedAt')));
      },
    );
  });

  group('Firebase summary projection', () {
    test(
      'uses the existing user read with no extra reads, writes, or listeners',
      () async {
        final metadata = _metadata();
        metadata['trainedAt'] = Timestamp.fromDate(
          DateTime.utc(2026, 8, 1, 12),
        );
        final window = metadata['window'] as Map;
        window['start'] = Timestamp.fromDate(DateTime.utc(2026, 7, 2));
        window['end'] = Timestamp.fromDate(DateTime.utc(2026, 8));
        final store = _ReadOnlyFirestore({
          'personalizedEnergyModel': metadata,
          'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 13)),
        });
        final state = await _repository(store).readUser('owner');
        expect(state!.personalizedEnergyModel!.labelCount, 20);
        expect(
          state.personalizedEnergyModel!.trainedAt,
          DateTime.utc(2026, 8, 1, 12),
        );
        expect(state.userUpdatedAt, DateTime.utc(2026, 8, 1, 13));
        expect(store.calls, [
          'get users/owner',
          'get users/owner/signals',
          'get users/owner/checkIns',
        ]);
      },
    );

    test(
      'missing or malformed summaries do not prevent account restore',
      () async {
        for (final metadata in <Object?>[
          null,
          false,
          {},
          _metadata()..['weights'] = [1],
          _metadata()..['trainedAt'] = '2026-02-30T12:00:00Z',
          {..._metadata(), 3: 'invalid key'},
        ]) {
          final store = _ReadOnlyFirestore({
            'personalizedEnergyModel': metadata,
            'updatedAt': 'not-a-date',
          });
          final state = await _repository(store).readUser('owner');
          expect(state!.personalizedEnergyModel, isNull);
          expect(state.userUpdatedAt, isNull);
          expect(state.accountEmail, 'owner@example.test');
          expect(store.calls.length, 3);
        }
      },
    );
  });
}

Map<String, Object?> _metadata() => {
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
  'featureCoverage': <String, Object?>{
    for (final feature in MlPrepBuilder.energyFeatureNames) feature: .75,
  },
};

CloudUserState _state({EnergyModelSummary? summary, DateTime? updatedAt}) =>
    CloudUserState(
      profile: const UserProfile(),
      accountEmail: 'owner@example.test',
      onboardingComplete: true,
      notificationsEnabled: false,
      outcomeConsent: true,
      healthAuthorized: false,
      signals: const [],
      checkIns: const [],
      personalizedEnergyModel: summary,
      userUpdatedAt: updatedAt,
    );

FirestoreCloudRepository _repository(_ReadOnlyFirestore store) =>
    FirestoreCloudRepository(
      firestore: store,
      auth: MemoryAccountAuth(
        session: const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        ),
      ),
    );

class _ReadOnlyFirestore implements FirebaseFirestore {
  _ReadOnlyFirestore(this.metadata);
  final Map<String, Object?> metadata;
  final calls = <String>[];

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    if (collectionPath != 'users') throw StateError('Unexpected collection');
    return _ReadOnlyCollection(this, collectionPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected Firestore operation ${invocation.memberName}',
  );
}

class _ReadOnlyCollection implements CollectionReference<Map<String, dynamic>> {
  _ReadOnlyCollection(this.store, this.path);
  final _ReadOnlyFirestore store;

  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    if (this.path != 'users' || path != 'owner') {
      throw StateError('Unexpected owner document');
    }
    return _ReadOnlyDocument(store);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    if (!['users/owner/signals', 'users/owner/checkIns'].contains(path)) {
      throw StateError('Unexpected query');
    }
    store.calls.add('get $path');
    return _EmptyRows();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected collection operation ${invocation.memberName}',
  );
}

class _ReadOnlyDocument implements DocumentReference<Map<String, dynamic>> {
  _ReadOnlyDocument(this.store);
  final _ReadOnlyFirestore store;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    store.calls.add('get users/owner');
    return _UserSnapshot(store.metadata);
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _ReadOnlyCollection(store, 'users/owner/$collectionPath');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected document operation ${invocation.memberName}',
  );
}

class _UserSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _UserSnapshot(this.userFields);
  final Map<String, Object?> userFields;

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => {
    'profile': const UserProfile().toJson(),
    'accountEmail': 'owner@example.test',
    ...userFields,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected snapshot operation ${invocation.memberName}',
  );
}

class _EmptyRows implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected result operation ${invocation.memberName}');
}
