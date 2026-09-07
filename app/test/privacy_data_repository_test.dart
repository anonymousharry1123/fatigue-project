// Firestore's plugin facade has no public test transport; strict call spies
// intentionally implement it to verify server-only reads and bounded writes.
// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/firebase_services.dart';
import 'package:app/src/models.dart';
import 'package:app/src/privacy_consent.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _RawStore store;
  late String? uid;
  late AccountDataLifecycle lifecycle;

  setUp(() {
    uid = 'owner';
    store = _RawStore();
    lifecycle = AccountDataLifecycle(
      store: store,
      currentUid: () => uid,
      now: () => DateTime.utc(2026, 9, 7),
    );
  });

  test(
    'exports all raw root fields and all known documents with original IDs',
    () async {
      store.root = {
        'unknownMetadata': {
          'preserve': ['every', 42, true, null],
        },
        'consentFlags': {'trainingRecordUse': false},
        'privacyConsent': {'acceptedAt': 'historical'},
        'backendVerification': {'status': 'not-lost'},
      };
      for (final collection in userDataChildCollections) {
        store.children[collection]!['untyped-document'] = {
          'unknownField': collection,
          'notTypedByApp': true,
        };
      }
      final result = await lifecycle.exportUser('owner');
      expect(result['exportVersion'], 2);
      expect(result['uid'], 'owner');
      expect(result['userDocument'], store.root);
      expect((result['collections'] as Map).keys, userDataChildCollections);
      for (final collection in userDataChildCollections) {
        expect(
          (result['collections'] as Map)[collection],
          store.children[collection],
        );
      }
      expect((result['scope'] as Map)['nestedCollectionsIncluded'], false);
      expect((result['scope'] as Map)['pointInTimeSnapshot'], false);
      expect(
        store.events.where((event) => event.startsWith('delete')),
        isEmpty,
      );
      expect(store.events, isNot(contains('begin')));
      expect(jsonDecode(jsonEncode(result))['userDocument'], store.root);
    },
  );

  test('paginates 205 raw records without duplicates or omissions', () async {
    store.fill('signals', 205);
    final result = await lifecycle.exportUser('owner');
    expect(((result['collections'] as Map)['signals'] as Map), hasLength(205));
    expect(store.events.where((event) => event.startsWith('read signals')), [
      'read signals 100 null',
      'read signals 100 doc-0099',
      'read signals 100 doc-0199',
    ]);
  });

  test(
    'export includes orphaned known children when root is already absent',
    () async {
      store.root = null;
      store.fill('outcomes', 1);
      final result = await lifecycle.exportUser('owner');
      expect(result['userDocument'], isNull);
      expect((result['collections'] as Map)['outcomes'], hasLength(1));
    },
  );

  test('cross-account export and deletion perform no requests', () async {
    await expectLater(lifecycle.exportUser('other'), throwsStateError);
    await expectLater(lifecycle.deleteUserTree('other'), throwsStateError);
    expect(store.events, isEmpty);
  });

  test('export stops on owner change after root or any page read', () async {
    store.after = (event) {
      if (event == 'root-read') uid = 'other';
    };
    await expectLater(lifecycle.exportUser('owner'), throwsStateError);
    expect(store.events, ['root-read']);
    uid = 'owner';
    store.events.clear();
    store.after = (event) {
      if (event.startsWith('read signals')) uid = null;
    };
    await expectLater(lifecycle.exportUser('owner'), throwsStateError);
    expect(store.events, ['root-read', 'read signals 100 null']);
  });

  test('failed page never returns a partial export or mutates data', () async {
    store.fill('signals', 105);
    store.fail = 'read signals 100 doc-0099';
    await expectLater(lifecycle.exportUser('owner'), throwsStateError);
    expect(store.children['signals'], hasLength(105));
    expect(store.events.any((event) => event.startsWith('delete')), false);
  });

  test(
    'document, byte, and read caps fail explicitly without partial export',
    () async {
      store.fill('signals', 2);
      for (final bounded in [
        AccountDataLifecycle(
          store: store,
          currentUid: () => uid,
          maxDocuments: 1,
        ),
        AccountDataLifecycle(
          store: store,
          currentUid: () => uid,
          maxExportBytes: 10,
        ),
        AccountDataLifecycle(
          store: store,
          currentUid: () => uid,
          maxRequests: 1,
        ),
      ]) {
        await expectLater(bounded.exportUser('owner'), throwsStateError);
      }
      expect(store.events, isNot(contains('begin')));
    },
  );

  test(
    'invalid repeated or oversized pages fail rather than looping',
    () async {
      store.overridePage = [
        const UserDataDocument('same-id', {}),
        const UserDataDocument('same-id', {}),
      ];
      await expectLater(lifecycle.exportUser('owner'), throwsStateError);
      store.overridePage = List.generate(
        101,
        (i) => UserDataDocument('$i', {}),
      );
      await expectLater(lifecycle.exportUser('owner'), throwsStateError);
    },
  );

  test(
    'deletion marks first, uses 100-doc batches, and deletes root last',
    () async {
      store.fill('signals', 205);
      for (final name in userDataChildCollections.skip(1)) {
        store.fill(name, 1);
      }
      await lifecycle.deleteUserTree('owner');
      expect(store.events.first, 'begin');
      expect(store.events.last, 'delete-root');
      expect(
        store.events.where((event) => event.startsWith('delete signals')),
        ['delete signals 100', 'delete signals 100', 'delete signals 5'],
      );
      expect(store.children.values.every((items) => items.isEmpty), true);
      expect(store.root, isNull);
      expect(
        store.events.where((event) => event.contains(' 1 null')),
        hasLength(7),
      );
    },
  );

  test(
    'partial failure retains marked root and retry safely finishes',
    () async {
      store.fill('signals', 150);
      store.fill('outcomes', 3);
      store.fail = 'delete outcomes 3';
      await expectLater(lifecycle.deleteUserTree('owner'), throwsStateError);
      expect(store.children['signals'], isEmpty);
      expect(store.children['outcomes'], hasLength(3));
      expect(store.root?['privacyDeletion'], isNotNull);
      expect(store.events, isNot(contains('delete-root')));
      store.fail = null;
      await lifecycle.deleteUserTree('owner');
      expect(store.root, isNull);
      expect(store.children.values.every((items) => items.isEmpty), true);
      // A retry after root removal (e.g. Auth deletion failed) is also safe.
      await lifecycle.deleteUserTree('owner');
      expect(store.root, isNull);
    },
  );

  test('marker failure does not delete a single child', () async {
    store.fill('signals', 2);
    store.fail = 'begin';
    await expectLater(lifecycle.deleteUserTree('owner'), throwsStateError);
    expect(store.events, ['begin']);
    expect(store.children['signals'], hasLength(2));
  });

  test(
    'deletion stops after account changes during marker, read, or commit',
    () async {
      for (final boundary in [
        'begin',
        'read signals 100 null',
        'delete signals 1',
      ]) {
        uid = 'owner';
        store = _RawStore()..fill('signals', 1);
        store.after = (event) {
          if (event == boundary) uid = 'other';
        };
        final operation = AccountDataLifecycle(
          store: store,
          currentUid: () => uid,
        );
        await expectLater(operation.deleteUserTree('owner'), throwsStateError);
        expect(store.events.last, boundary);
        expect(store.events, isNot(contains('delete-root')));
      }
    },
  );

  test(
    'bounded interrupted deletion is retryable and never deletes root early',
    () async {
      store.fill('signals', 150);
      final bounded = AccountDataLifecycle(
        store: store,
        currentUid: () => uid,
        maxDocuments: 100,
      );
      await expectLater(bounded.deleteUserTree('owner'), throwsStateError);
      expect(store.children['signals'], hasLength(50));
      expect(store.root, isNotNull);
      await lifecycle.deleteUserTree('owner');
      expect(store.root, isNull);
    },
  );

  test(
    'final verification catches a late write in an earlier collection',
    () async {
      var inserted = false;
      store.after = (event) {
        if (event == 'read riskAlerts 100 null' && !inserted) {
          inserted = true;
          store.fill('signals', 1);
        }
      };
      await lifecycle.deleteUserTree('owner');
      expect(store.children['signals'], isEmpty);
      expect(store.events, contains('delete signals 1'));
      expect(store.events.last, 'delete-root');
    },
  );

  test(
    'Firestore export reads raw server pages and preserves special field types',
    () async {
      final firestore = _FirestoreSpy(store);
      store.root = {
        'unknown': Timestamp(10, 123456789),
        'location': const GeoPoint(10, 20),
        'bytes': Blob(Uint8List.fromList([0, 1, 255])),
        'nonFinite': double.nan,
      };
      store.fill('signals', 105);
      final repository = FirestoreCloudRepository(
        firestore: firestore,
        auth: MemoryAccountAuth(
          session: const AccountSession(uid: 'owner', email: 'a@b.test'),
        ),
      );
      final result = await repository.exportUser('owner');
      final root = result['userDocument'] as Map;
      expect(root['unknown'], {
        '__firestoreType': 'timestamp',
        'seconds': 10,
        'nanoseconds': 123456789,
        'iso8601': '1970-01-01T00:00:10.123456Z',
      });
      expect(root['location'], {
        '__firestoreType': 'geopoint',
        'latitude': 10.0,
        'longitude': 20.0,
      });
      expect(root['bytes'], {'__firestoreType': 'bytes', 'base64': 'AAH/'});
      expect(root['nonFinite'], {'__firestoreType': 'double', 'value': 'NaN'});
      expect(firestore.sources, everyElement(Source.server));
      expect(firestore.limits, everyElement(100));
      expect(firestore.orderFields, everyElement(FieldPath.documentId));
      expect((result['collections'] as Map)['signals'], hasLength(105));
      expect(store.events, isNot(contains('begin')));
    },
  );

  test(
    'Firestore deletion uses marker merge, server reads and bounded batches',
    () async {
      store.fill('signals', 101);
      final firestore = _FirestoreSpy(store);
      final repository = FirestoreCloudRepository(
        firestore: firestore,
        auth: MemoryAccountAuth(
          session: const AccountSession(uid: 'owner', email: 'a@b.test'),
        ),
      );
      await repository.deleteUserTree('owner');
      expect(firestore.markerOptions?.merge, true);
      expect((firestore.marker?['privacyDeletion'] as Map)['version'], 1);
      expect(
        (firestore.marker?['privacyDeletion'] as Map)['requestedAt'],
        isA<FieldValue>(),
      );
      expect(firestore.sources, everyElement(Source.server));
      expect(firestore.batchSizes, [100, 1]);
      expect(store.events.first, 'begin');
      expect(store.events.last, 'delete-root');
    },
  );

  test(
    'Firebase reauthentication verifies only the existing user credential',
    () async {
      final firebase = _AuthSpy();
      final auth = FirebaseAccountAuth(firebase);
      await auth.reauthenticate(password: 'secret');
      expect(firebase.user.credential, isA<EmailAuthCredential>());
      final credential = firebase.user.credential! as EmailAuthCredential;
      expect(credential.email, 'owner@example.test');
      expect(credential.password, 'secret');
      expect(firebase.signIns, 0);
      expect(auth.currentSession?.uid, 'owner');
    },
  );

  test(
    'Firebase reauthentication rejects empty credentials and changed owners',
    () async {
      final firebase = _AuthSpy();
      final auth = FirebaseAccountAuth(firebase);
      await expectLater(auth.reauthenticate(password: ''), throwsArgumentError);
      expect(firebase.user.credential, isNull);
      firebase.user.afterReauth = () => firebase.current = null;
      await expectLater(
        auth.reauthenticate(password: 'secret'),
        throwsStateError,
      );
      await expectLater(
        auth.reauthenticate(password: 'secret'),
        throwsStateError,
      );
      expect(firebase.signIns, 0);
    },
  );

  test(
    'memory reauthentication rejects wrong password without switching user',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        ),
        expectedPassword: 'right',
      );
      await expectLater(
        auth.reauthenticate(password: 'wrong'),
        throwsStateError,
      );
      expect(auth.currentSession?.uid, 'owner');
      await auth.reauthenticate(password: 'right');
      await auth.signOut();
      await expectLater(
        auth.reauthenticate(password: 'right'),
        throwsStateError,
      );
      await expectLater(
        const LocalOnlyAccountAuth().reauthenticate(password: 'right'),
        throwsStateError,
      );
    },
  );

  test(
    'guardian access requires both fresh current-version trusted Auth claims',
    () async {
      final firebase = _AuthSpy();
      final auth = FirebaseAccountAuth(firebase);
      expect(auth.currentSession?.guardianConsentVerified, false);
      firebase.user.claims = {'guardianConsentVerified': true};
      await auth.refreshPrivacyClaims();
      expect(auth.currentSession?.guardianConsentVerified, false);
      firebase.user.claims = {
        'guardianConsentVerified': true,
        'guardianConsentPolicyVersion': 1,
      };
      await auth.refreshPrivacyClaims();
      expect(auth.currentSession?.guardianConsentVerified, true);
      expect(firebase.user.forceRefreshes, [true, true]);
      firebase.user.claims = {
        'guardianConsentVerified': true,
        'guardianConsentPolicyVersion': 2,
      };
      await auth.refreshPrivacyClaims();
      expect(auth.currentSession?.guardianConsentVerified, false);
    },
  );

  test(
    'failed or account-switched guardian refresh never retains permission',
    () async {
      final firebase = _AuthSpy();
      final auth = FirebaseAccountAuth(firebase);
      firebase.user.claims = {
        'guardianConsentVerified': true,
        'guardianConsentPolicyVersion': 1,
      };
      await auth.refreshPrivacyClaims();
      expect(auth.currentSession?.guardianConsentVerified, true);
      firebase.user.failToken = true;
      await expectLater(auth.refreshPrivacyClaims(), throwsStateError);
      expect(auth.currentSession?.guardianConsentVerified, false);
      firebase.user.failToken = false;
      firebase.user.afterToken = () => firebase.current = null;
      await expectLater(auth.refreshPrivacyClaims(), throwsStateError);
      firebase.current = firebase.user;
      expect(auth.currentSession?.guardianConsentVerified, false);
    },
  );
  final receipt = PrivacyConsent(
    ageBand: PrivacyAgeBand.adult,
    region: PrivacyRegion.us,
    acceptedAt: DateTime.utc(2026, 1, 1),
  );

  test(
    'ordinary profile mapper never manufactures privacy acknowledgement',
    () {
      final profile = profileToCloud(
        profile: const UserProfile(),
        email: 'owner@example.test',
        onboardingComplete: true,
        notificationsEnabled: false,
        outcomeConsent: false,
        healthAuthorized: false,
      );
      expect(cloudSchemaVersion, 14);
      expect(profile.keys, isNot(contains('privacyConsent')));
      expect(profile.keys, isNot(contains('outcomeConsentUpdatedAt')));
      expect(
        (profile['consentFlags'] as Map).keys,
        isNot(contains('wellnessOnlyAcknowledged')),
      );
      const legacy = CloudUserState(
        profile: UserProfile(),
        accountEmail: 'owner@example.test',
        onboardingComplete: false,
        notificationsEnabled: false,
        outcomeConsent: false,
        healthAuthorized: false,
        signals: [],
        checkIns: [],
      );
      expect(legacy.privacyConsent, isNull);
      expect(legacy.outcomeConsentUpdatedAt, isNull);
      final preserved = legacy
          .copyWith(
            privacyConsent: receipt,
            deletionPending: true,
            outcomeConsentUpdatedAt: receipt.acceptedAt,
          )
          .copyWith(migrationVersion: 4);
      expect(preserved.privacyConsent, same(receipt));
      expect(preserved.deletionPending, true);
      expect(preserved.outcomeConsentUpdatedAt, receipt.acceptedAt);
    },
  );

  test(
    'explicit privacy write is narrow and returns server-stamped receipt',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        ),
      );
      final firestore = _FirestoreSpy(store);
      final repository = FirestoreCloudRepository(
        firestore: firestore,
        auth: auth,
      );
      final accepted = await repository.savePrivacyConsent('owner', receipt);
      expect(accepted.acceptedAt, _serverTime);
      expect(accepted.sameIdentity(receipt), true);
      expect(firestore.rootWrites, hasLength(1));
      final payload = firestore.rootWrites.single;
      expect(payload.keys.toSet(), {
        'privacyConsent',
        'consentFlags',
        'outcomeConsentUpdatedAt',
        'schemaVersion',
        'updatedAt',
      });
      expect(
        (payload['privacyConsent'] as Map)['acceptedAt'],
        isA<FieldValue>(),
      );
      expect(payload['outcomeConsentUpdatedAt'], isA<FieldValue>());
      expect(payload['consentFlags'], {
        'outcomeCollection': false,
        'trainingRecordUse': false,
        'wellnessOnlyAcknowledged': true,
      });
      expect(firestore.sources, [Source.server]);
      expect(store.events, ['root-write', 'root-read']);
    },
  );

  test(
    'optional-learning write preserves acknowledgement and raw metadata',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        ),
      );
      final firestore = _FirestoreSpy(store);
      final repository = FirestoreCloudRepository(
        firestore: firestore,
        auth: auth,
      );
      store.root = {
        'privacyConsent': receipt.toCloud(),
        'consentFlags': {
          'wellnessOnlyAcknowledged': true,
          'outcomeCollection': false,
          'trainingRecordUse': false,
        },
        'unknownMetadata': 'preserve-me',
      };
      final at = await repository.saveOutcomeConsent('owner', true);
      expect(at, _serverTime);
      final payload = firestore.rootWrites.single;
      expect(payload.keys.toSet(), {
        'consentFlags',
        'outcomeConsentUpdatedAt',
        'updatedAt',
      });
      expect(payload['consentFlags'], {
        'outcomeCollection': true,
        'trainingRecordUse': true,
      });
      expect(store.root?['privacyConsent'], receipt.toCloud());
      expect(
        (store.root?['consentFlags'] as Map)['wellnessOnlyAcknowledged'],
        true,
      );
      expect(store.root?['unknownMetadata'], 'preserve-me');
      expect(firestore.sources, [Source.server]);
      expect(store.events, ['root-write', 'root-read']);
    },
  );

  test(
    'resume privacy read is one server root; malformed deletion fails closed',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        ),
      );
      final firestore = _FirestoreSpy(store);
      final repository = FirestoreCloudRepository(
        firestore: firestore,
        auth: auth,
      );
      store.root = {
        'privacyConsent': {
          ...receipt.toCloud(),
          'acceptedAt': Timestamp.fromDate(_serverTime),
        },
        'outcomeConsentUpdatedAt': Timestamp.fromDate(_serverTime),
        'consentFlags': {'outcomeCollection': true, 'trainingRecordUse': true},
        'privacyDeletion': null,
      };
      final privacy = await repository.readAccountPrivacy('owner');
      expect(privacy.consent?.acceptedAt, _serverTime);
      expect(privacy.outcomeConsentUpdatedAt, _serverTime);
      expect(privacy.outcomeConsent, true);
      expect(privacy.deletionPending, true);
      expect(firestore.sources, [Source.server]);
      expect(store.events, ['root-read']);
      store.root = null;
      await expectLater(
        repository.readAccountPrivacy('owner'),
        throwsStateError,
      );
    },
  );

  test(
    'typed account read supports minimal receipt-only and legacy roots',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        ),
      );
      final firestore = _FirestoreSpy(store);
      final repository = FirestoreCloudRepository(
        firestore: firestore,
        auth: auth,
      );
      store.root = {
        'privacyConsent': {
          ...receipt.toCloud(),
          'acceptedAt': Timestamp.fromDate(_serverTime),
        },
      };
      final minimal = await repository.readUser('owner');
      expect(minimal?.privacyConsent?.acceptedAt, _serverTime);
      expect(minimal?.accountEmail, 'owner@example.test');
      expect(minimal?.onboardingComplete, false);
      expect(minimal?.signals, isEmpty);
      expect(firestore.sources, [Source.server]);
      store.root = {
        'consentFlags': {'wellnessOnlyAcknowledged': true},
      };
      final legacy = await repository.readUser('owner');
      expect(legacy?.privacyConsent, isNull);
      expect(legacy?.outcomeConsentUpdatedAt, isNull);
      expect(legacy?.outcomeConsent, false);
    },
  );

  test(
    'consent operations stop after owner changes during write or read',
    () async {
      for (final operation in ['privacy', 'outcome', 'read']) {
        for (final boundary
            in operation == 'read'
                ? ['root-read']
                : ['root-write', 'root-read']) {
          final auth = MemoryAccountAuth(
            session: const AccountSession(
              uid: 'owner',
              email: 'owner@example.test',
            ),
          );
          store = _RawStore();
          store.after = (event) {
            if (event == boundary) auth.session = null;
          };
          final repository = FirestoreCloudRepository(
            firestore: _FirestoreSpy(store),
            auth: auth,
          );
          final future = switch (operation) {
            'privacy' => repository.savePrivacyConsent('owner', receipt),
            'outcome' => repository.saveOutcomeConsent('owner', false),
            _ => repository.readAccountPrivacy('owner'),
          };
          await expectLater(future, throwsStateError);
          expect(store.events.last, boundary);
        }
      }
    },
  );

  test(
    'consent success needs an authoritative saved receipt and timestamp',
    () async {
      final auth = MemoryAccountAuth(
        session: const AccountSession(
          uid: 'owner',
          email: 'owner@example.test',
        ),
      );
      final repository = FirestoreCloudRepository(
        firestore: _FirestoreSpy(store),
        auth: auth,
      );
      store.after = (event) {
        if (event == 'root-write') store.root?.remove('privacyConsent');
      };
      await expectLater(
        repository.savePrivacyConsent('owner', receipt),
        throwsStateError,
      );
      store.after = (event) {
        if (event == 'root-write') {
          store.root?.remove('outcomeConsentUpdatedAt');
        }
      };
      await expectLater(
        repository.saveOutcomeConsent('owner', false),
        throwsStateError,
      );
      store.after = null;
      store.events.clear();
      await expectLater(
        repository.savePrivacyConsent('other', receipt),
        throwsStateError,
      );
      expect(store.events, isEmpty);
    },
  );

  test(
    'memory receipt and optional choices preserve explicit export timestamps',
    () async {
      final repository = MemoryCloudRepository(signedInUid: 'owner');
      await expectLater(
        repository.readAccountPrivacy('owner'),
        throwsStateError,
      );
      final saved = await repository.savePrivacyConsent('owner', receipt);
      expect(saved.acceptedAt.isAfter(receipt.acceptedAt), true);
      final optInAt = await repository.saveOutcomeConsent('owner', true);
      final privacy = await repository.readAccountPrivacy('owner');
      expect(privacy.consent, same(saved));
      expect(privacy.outcomeConsent, true);
      expect(privacy.outcomeConsentUpdatedAt, optInAt);
      final state = (await repository.readUser('owner'))!;
      await repository.replaceUser(
        'owner',
        state.copyWith(migrationVersion: 2),
      );
      expect(
        (await repository.readAccountPrivacy('owner')).consent,
        same(saved),
      );
      final exported = await repository.exportUser('owner');
      expect(
        (exported['userDocument'] as Map)['privacyConsent'],
        saved.toJson(),
      );
      expect(
        (exported['userDocument'] as Map)['outcomeConsentUpdatedAt'],
        optInAt.toIso8601String(),
      );
      await repository.saveOutcomeConsent('owner', false);
      expect(
        (await repository.readAccountPrivacy('owner')).outcomeConsent,
        false,
      );
      await repository.savePrivacyConsent('owner', receipt);
      expect(
        (await repository.readAccountPrivacy('owner')).outcomeConsent,
        false,
      );
    },
  );
}

final _serverTime = DateTime.utc(2026, 9, 7, 14);

class _RawStore implements UserDataLifecycleStore {
  Map<String, Object?>? root = {'unknown': true};
  final children = <String, Map<String, Map<String, Object?>>>{
    for (final name in userDataChildCollections) name: {},
  };
  final events = <String>[];
  String? fail;
  void Function(String)? after;
  List<UserDataDocument>? overridePage;

  void fill(String collection, int count) {
    for (var i = 0; i < count; i++) {
      children[collection]!['doc-${i.toString().padLeft(4, '0')}'] = {'raw': i};
    }
  }

  void _before(String event) {
    events.add(event);
    if (event == fail) throw StateError('Simulated offline/failure');
  }

  @override
  Future<Map<String, Object?>?> readUserDocument(String uid) async {
    _before('root-read');
    after?.call('root-read');
    return root;
  }

  @override
  Future<void> beginDeletion(String uid) async {
    _before('begin');
    root ??= {};
    root!['privacyDeletion'] = {'version': 1, 'requestedAt': 'server-time'};
    after?.call('begin');
  }

  @override
  Future<List<UserDataDocument>> readCollectionPage(
    String uid,
    String collection, {
    required int limit,
    String? afterId,
  }) async {
    final event = 'read $collection $limit $afterId';
    _before(event);
    final keys =
        children[collection]!.keys
            .where((id) => afterId == null || id.compareTo(afterId) > 0)
            .toList()
          ..sort();
    final page =
        overridePage ??
        keys
            .take(limit)
            .map((id) => UserDataDocument(id, children[collection]![id]!))
            .toList();
    after?.call(event);
    return page;
  }

  @override
  Future<void> deleteDocuments(
    String uid,
    String collection,
    List<String> ids,
  ) async {
    final event = 'delete $collection ${ids.length}';
    _before(event);
    for (final id in ids) {
      children[collection]!.remove(id);
    }
    after?.call(event);
  }

  @override
  Future<void> deleteUserDocument(String uid) async {
    _before('delete-root');
    root = null;
    after?.call('delete-root');
  }
}

class _FirestoreSpy implements FirebaseFirestore {
  _FirestoreSpy(this.store);
  final _RawStore store;
  final sources = <Source?>[];
  final limits = <int>[];
  final orderFields = <Object>[];
  final batchSizes = <int>[];
  final rootWrites = <Map<String, dynamic>>[];
  Map<String, dynamic>? marker;
  SetOptions? markerOptions;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    expect(collectionPath, 'users');
    return _CollectionSpy(this, collectionPath);
  }

  @override
  WriteBatch batch() => _BatchSpy(this);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Firestore call ${invocation.memberName}');
}

class _CollectionSpy implements CollectionReference<Map<String, dynamic>> {
  _CollectionSpy(this.firestoreSpy, this.name);
  final _FirestoreSpy firestoreSpy;
  final String name;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _DocumentSpy(firestoreSpy, name, path!);
  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    firestoreSpy.orderFields.add(field);
    return _QuerySpy(firestoreSpy, name);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _RowsSpy([
    for (final entry in firestoreSpy.store.children[name]!.entries)
      _RowSpy(firestoreSpy, name, UserDataDocument(entry.key, entry.value)),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected collection call ${invocation.memberName}');
}

class _QuerySpy implements Query<Map<String, dynamic>> {
  _QuerySpy(this.firestoreSpy, this.name, {this.pageLimit = 100, this.afterId});
  final _FirestoreSpy firestoreSpy;
  final String name;
  final int pageLimit;
  final String? afterId;
  @override
  Query<Map<String, dynamic>> limit(int value) {
    firestoreSpy.limits.add(value);
    return _QuerySpy(firestoreSpy, name, pageLimit: value, afterId: afterId);
  }

  @override
  Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) => _QuerySpy(
    firestoreSpy,
    name,
    pageLimit: pageLimit,
    afterId: values.single as String,
  );
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    firestoreSpy.sources.add(options?.source);
    final rows = await firestoreSpy.store.readCollectionPage(
      'owner',
      name,
      limit: pageLimit,
      afterId: afterId,
    );
    return _RowsSpy(
      rows.map((row) => _RowSpy(firestoreSpy, name, row)).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected query call ${invocation.memberName}');
}

class _DocumentSpy implements DocumentReference<Map<String, dynamic>> {
  _DocumentSpy(this.firestoreSpy, this.name, this.id);
  final _FirestoreSpy firestoreSpy;
  final String name;
  @override
  final String id;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    expect(name, 'users');
    expect(id, 'owner');
    firestoreSpy.sources.add(options?.source);
    return _RootSpy(await firestoreSpy.store.readUserDocument(id));
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _CollectionSpy(firestoreSpy, collectionPath);
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    expect(name, 'users');
    if (!data.containsKey('privacyDeletion')) {
      firestoreSpy.rootWrites.add(data);
      expect(options?.merge, true);
      final store = firestoreSpy.store;
      store._before('root-write');
      store.root ??= {};
      void merge(Map<String, Object?> target, Map<String, dynamic> values) {
        for (final entry in values.entries) {
          if (entry.value is Map) {
            final nested = Map<String, Object?>.from(
              target[entry.key] as Map? ?? const {},
            );
            merge(nested, (entry.value as Map).cast<String, dynamic>());
            target[entry.key] = nested;
          } else {
            target[entry.key] = entry.value is FieldValue
                ? Timestamp.fromDate(_serverTime)
                : entry.value;
          }
        }
      }

      merge(store.root!, data);
      store.after?.call('root-write');
      return;
    }
    firestoreSpy.marker = data;
    firestoreSpy.markerOptions = options;
    await firestoreSpy.store.beginDeletion(id);
  }

  @override
  Future<void> delete() => firestoreSpy.store.deleteUserDocument(id);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected document call ${invocation.memberName}');
}

class _BatchSpy implements WriteBatch {
  _BatchSpy(this.firestoreSpy);
  final _FirestoreSpy firestoreSpy;
  final documents = <_DocumentSpy>[];
  @override
  void delete(DocumentReference<Object?> document) =>
      documents.add(document as _DocumentSpy);
  @override
  Future<void> commit() async {
    firestoreSpy.batchSizes.add(documents.length);
    await firestoreSpy.store.deleteDocuments(
      'owner',
      documents.first.name,
      documents.map((document) => document.id).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected batch call ${invocation.memberName}');
}

class _RootSpy implements DocumentSnapshot<Map<String, dynamic>> {
  _RootSpy(this.value);
  final Map<String, Object?>? value;
  @override
  Map<String, dynamic>? data() => value;
  @override
  bool get exists => value != null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected root snapshot call');
}

class _RowSpy implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _RowSpy(this.firestoreSpy, this.collection, this.value);
  final _FirestoreSpy firestoreSpy;
  final String collection;
  final UserDataDocument value;
  @override
  String get id => value.id;
  @override
  Map<String, dynamic> data() => value.data;
  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      _DocumentSpy(firestoreSpy, collection, id);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected row call');
}

class _RowsSpy implements QuerySnapshot<Map<String, dynamic>> {
  _RowsSpy(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected rows call');
}

class _AuthSpy implements FirebaseAuth {
  _AuthSpy() {
    current = user;
  }
  final user = _UserSpy();
  User? current;
  int signIns = 0;
  @override
  User? get currentUser => current;
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signIns++;
    throw StateError('Must not sign in as part of reauthentication');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Auth call ${invocation.memberName}');
}

class _UserSpy implements User {
  AuthCredential? credential;
  void Function()? afterReauth;
  void Function()? afterToken;
  Map<String, dynamic> claims = {};
  bool failToken = false;
  final forceRefreshes = <bool>[];
  @override
  String get uid => 'owner';
  @override
  String? get email => 'owner@example.test';
  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential value,
  ) async {
    credential = value;
    afterReauth?.call();
    return _CredentialSpy(this);
  }

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    forceRefreshes.add(forceRefresh);
    if (failToken) throw StateError('Token refresh failed');
    afterToken?.call();
    return _TokenSpy(claims);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected User call');
}

class _TokenSpy implements IdTokenResult {
  _TokenSpy(this.claims);
  @override
  final Map<String, dynamic> claims;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected token call');
}

class _CredentialSpy implements UserCredential {
  _CredentialSpy(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected credential call');
}
