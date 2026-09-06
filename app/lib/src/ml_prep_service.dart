import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ml_prep_builder.dart';
import 'ml_prep_models.dart';

abstract interface class PrepCacheStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> clear();
}

class MemoryPrepCache implements PrepCacheStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> clear() async => values.clear();
}

/// These keys are separate from tonyo_state_v1. Clearing prep never erases
/// check-ins, HealthKit history, consent settings, or authentication.
class SharedPreferencesPrepCache implements PrepCacheStore {
  static const _prefix = 'tonyo_ml_prep_v1_';

  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString('$_prefix$key');

  @override
  Future<void> write(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    // Retain at most one bounded snapshot. A second window is an explicit run,
    // not an ever-growing archive of sensitive records.
    for (final oldKey in preferences.getKeys().where(
      (v) => v.startsWith(_prefix),
    )) {
      if (oldKey != '$_prefix$key') await preferences.remove(oldKey);
    }
    if (!await preferences.setString('$_prefix$key', value)) {
      throw StateError('Could not save the private prep cache.');
    }
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().where(
      (v) => v.startsWith(_prefix),
    )) {
      await preferences.remove(key);
    }
  }
}

class PrepRun {
  const PrepRun({
    required this.snapshot,
    required this.report,
    required this.cacheHit,
    required this.collectionQueries,
    required this.metadataReads,
    required this.returnedDocuments,
  });
  final PrepSnapshot snapshot;
  final PrepReport report;
  final bool cacheHit;
  final int collectionQueries;
  final int metadataReads;
  final Map<String, int> returnedDocuments;

  Map<String, dynamic> toJson() => {
    'report': report.toJson(),
    'snapshot': snapshot.toJson(),
    'database': {
      'cacheHit': cacheHit,
      'collectionQueries': collectionQueries,
      'metadataReads': metadataReads,
      'returnedDocuments': returnedDocuments,
      'writes': 0,
      'billingNote':
          'Requests and returned documents are not billed-read '
          'equivalents. Rules, index reads and minimum query charges are separate.',
    },
  };
}

/// Only explicit foreground callers invoke prepare. There are no timers or
/// listeners. Current UID is checked across every async boundary, and an edit,
/// deletion or consent change invalidates in-flight work as well as the cache.
class MlPrepService {
  MlPrepService({required this.source, required this.cache});

  final PrepDataSource source;
  final PrepCacheStore cache;
  int _generation = 0;
  final _inFlight = <String, Future<PrepRun>>{};
  Future<void> _invalidation = Future.value();

  Future<void> invalidate() {
    _generation++;
    _inFlight.clear();
    // A transient failure is surfaced to the caller but must not poison every
    // later invalidation after storage becomes available again.
    _invalidation = _invalidation.onError((_, _) {}).then((_) => cache.clear());
    return _invalidation;
  }

  Future<PrepRun> prepare({
    required PrepWindow window,
    bool refresh = false,
    bool coverageOnly = true,
    PrepConsent? knownConsent,
    PrepAccountMetadata? knownAccount,
    PrepSnapshot? loadedSnapshot,
  }) {
    final uid = source.currentUid;
    if (uid == null || uid.isEmpty) {
      return Future.error(
        StateError('Sign in to prepare your private account data.'),
      );
    }
    final generation = _generation;
    final requestKey = prepFingerprint({
      'uid': uid,
      'window': window.toJson(),
      'prepVersion': mlPrepVersion,
    });
    final effectiveConsent = knownAccount?.consent ?? knownConsent;
    if (!coverageOnly &&
        effectiveConsent != null &&
        !effectiveConsent.allowed) {
      return Future.error(
        StateError('Both outcome and training-record consent are required.'),
      );
    }
    final inFlightKey = prepFingerprint({
      'request': requestKey,
      'generation': generation,
      'coverageOnly': coverageOnly,
      'refresh': refresh,
      'knownConsent': effectiveConsent?.toJson(),
      'knownSchema': knownAccount?.schemaVersion,
      'loadedSnapshot': loadedSnapshot?.fingerprint,
      'loadedOwner': loadedSnapshot?.uid,
    });
    return _inFlight.putIfAbsent(inFlightKey, () async {
      try {
        return await _prepare(
          uid: uid,
          window: window,
          requestKey: requestKey,
          generation: generation,
          refresh: refresh,
          coverageOnly: coverageOnly,
          knownConsent: knownAccount?.consent ?? knownConsent,
          knownAccount: knownAccount,
          loadedSnapshot: loadedSnapshot,
        );
      } finally {
        _inFlight.remove(inFlightKey);
      }
    });
  }

  void _assertCurrent(String uid, int generation) {
    if (source.currentUid != uid || generation != _generation) {
      throw StateError(
        'Account data changed during prep. Run preparation again.',
      );
    }
  }

  String _identity(PrepSnapshot snapshot) => prepFingerprint({
    'uid': snapshot.uid,
    'window': snapshot.window.toJson(),
    'prepVersion': mlPrepVersion,
    'schemaVersion': snapshot.schemaVersion,
    'consent': snapshot.consent.toJson(),
  });

  Future<PrepRun> _prepare({
    required String uid,
    required PrepWindow window,
    required String requestKey,
    required int generation,
    required bool refresh,
    required bool coverageOnly,
    PrepConsent? knownConsent,
    PrepAccountMetadata? knownAccount,
    PrepSnapshot? loadedSnapshot,
  }) async {
    await _invalidation;
    _assertCurrent(uid, generation);
    if (!coverageOnly && knownConsent != null && !knownConsent.allowed) {
      throw StateError(
        'Both outcome and training-record consent are required.',
      );
    }

    if (!refresh) {
      final raw = await cache.read(requestKey);
      _assertCurrent(uid, generation);
      if (raw != null) {
        PrepSnapshot? cached;
        try {
          final envelope = jsonDecode(raw) as Map<String, dynamic>;
          cached = PrepSnapshot.fromJson(
            Map<String, dynamic>.from(envelope['snapshot'] as Map),
            uid: uid,
          );
          final valid =
              envelope['identity'] == _identity(cached) &&
              canonicalPrepJson(cached.window.toJson()) ==
                  canonicalPrepJson(window.toJson()) &&
              (knownConsent == null ||
                  canonicalPrepJson(knownConsent.toJson()) ==
                      canonicalPrepJson(cached.consent.toJson())) &&
              (knownAccount == null ||
                  knownAccount.schemaVersion == cached.schemaVersion);
          if (!valid) cached = null;
        } on Object {
          // Invalid, edited or incompatible local cache: rebuild once from the
          // bounded source. Do not treat a corrupt cache as authoritative.
          cached = null;
        }
        if (cached != null) {
          if (!coverageOnly && !cached.consent.allowed) {
            throw StateError(
              'Both outcome and training-record consent are required.',
            );
          }
          return _run(cached, cacheHit: true, metadataReads: 0, queries: 0);
        }
      }
    }

    PrepSnapshot snapshot;
    var metadataReads = 0;
    var queries = 0;
    if (!refresh && loadedSnapshot != null) {
      if (loadedSnapshot.uid != uid ||
          canonicalPrepJson(loadedSnapshot.window.toJson()) !=
              canonicalPrepJson(window.toJson()) ||
          (knownAccount != null &&
              knownAccount.schemaVersion != loadedSnapshot.schemaVersion) ||
          (knownConsent != null &&
              canonicalPrepJson(knownConsent.toJson()) !=
                  canonicalPrepJson(loadedSnapshot.consent.toJson()))) {
        throw StateError(
          'Loaded snapshot does not match this account, window or consent.',
        );
      }
      snapshot = loadedSnapshot;
    } else {
      // Share one consent/profile read. The collection adapters must not repeat it.
      final metadata = knownAccount ?? await source.readAccount(uid);
      metadataReads = knownAccount == null ? 1 : 0;
      _assertCurrent(uid, generation);
      if (!coverageOnly && !metadata.consent.allowed) {
        throw StateError(
          'Both outcome and training-record consent are required.',
        );
      }
      final rows = await Future.wait([
        for (final collection in PrepCollection.values)
          source.readCollection(
            uid,
            collection,
            window,
            limit: collection.maximumDocuments,
          ),
      ]);
      queries = 3;
      _assertCurrent(uid, generation);
      snapshot = PrepSnapshot(
        uid: uid,
        window: window,
        consent: metadata.consent,
        fetchedAt: DateTime.now().toUtc(),
        schemaVersion: metadata.schemaVersion,
        signals: rows[0],
        checkIns: rows[1],
        outcomes: rows[2],
      );
    }
    if (!coverageOnly && !snapshot.consent.allowed) {
      throw StateError(
        'Both outcome and training-record consent are required.',
      );
    }
    if (snapshot.signals.length > PrepCollection.signals.maximumDocuments ||
        snapshot.checkIns.length > PrepCollection.checkIns.maximumDocuments ||
        snapshot.outcomes.length > PrepCollection.outcomes.maximumDocuments) {
      throw StateError('Source exceeded the bounded prep document budget.');
    }
    _assertCurrent(uid, generation);
    await cache.write(
      requestKey,
      jsonEncode({
        'identity': _identity(snapshot),
        'snapshot': snapshot.toJson(),
      }),
    );
    if (source.currentUid != uid || generation != _generation) {
      await cache.clear();
      _assertCurrent(uid, generation);
    }
    return _run(
      snapshot,
      cacheHit: false,
      metadataReads: metadataReads,
      queries: queries,
    );
  }

  PrepRun _run(
    PrepSnapshot snapshot, {
    required bool cacheHit,
    required int metadataReads,
    required int queries,
  }) => PrepRun(
    snapshot: snapshot,
    report: MlPrepBuilder.build(snapshot),
    cacheHit: cacheHit,
    collectionQueries: queries,
    metadataReads: metadataReads,
    returnedDocuments: queries == 0
        ? const {'signals': 0, 'checkIns': 0, 'outcomes': 0}
        : Map.unmodifiable(snapshot.counts),
  );
}
