import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/cloud_sync.dart';
import 'package:app/src/heart_rate_cloud.dart';
import 'package:app/src/heart_rate_summary.dart';
import 'package:app/src/models.dart';
import 'package:app/src/raw_heart_rate_store.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

final _now = DateTime.utc(2026, 10, 24, 12);
const _owner = AccountSession(uid: 'owner', email: 'owner@example.com');

SignalReading _heart(String id, {int minute = 0, double value = 72}) =>
    SignalReading(
      id: id,
      type: SignalType.heartRate,
      source: SignalSource.healthKit,
      value: value,
      timestamp: _now.subtract(Duration(hours: 1, minutes: minute)),
      syncedAt: _now,
      note: 'Apple Health · original watch',
    );

CloudUserState _state({
  List<SignalReading> signals = const [],
  String email = 'owner@example.com',
}) => CloudUserState(
  profile: const UserProfile(name: 'Owner'),
  accountEmail: email,
  onboardingComplete: false,
  notificationsEnabled: false,
  outcomeConsent: false,
  healthAuthorized: false,
  signals: signals,
  checkIns: const [],
  migrationVersion: localMigrationVersion,
  notificationPrefsVersion: notificationPreferencesVersion,
  privacyConsent: testAdultPrivacyConsent,
);

void _legacyPreferences({
  required CloudUserState cloud,
  List<SignalReading>? local,
  String? owner = 'owner',
  bool baseline = true,
}) {
  SharedPreferences.setMockInitialValues({
    'tonyo_state_v1': jsonEncode({
      'onboardingComplete': false,
      'accountEmail': cloud.accountEmail,
      'profile': cloud.profile.toJson(),
      'privacyConsent': testAdultPrivacyConsent.toJson(),
      'privacyOwnerUid': ?owner,
      'signals': (local ?? cloud.signals).map((item) => item.toJson()).toList(),
      'checkIns': [],
      if (baseline && owner != null)
        'inputSync': {
          'version': 1,
          'uid': owner,
          'baseline': InputSyncSnapshot.fromState(cloud).toJson(),
        },
    }),
  });
}

class _CloudDays extends MemoryHeartRateCloudStore {
  _CloudDays(this.events);
  final List<String> events;
  Object? fail;
  Completer<void>? gate;
  Completer<void>? entered;

  @override
  Future<HeartRateSummaryAcknowledgement> saveDay(
    String uid, {
    required String writerId,
    required HeartRateDailySummary summary,
    String? expectedDigest,
  }) async {
    events.add('summary-start');
    if (entered != null && !entered!.isCompleted) entered!.complete();
    final pending = gate;
    gate = null;
    if (pending != null) await pending.future;
    if (fail != null) throw fail!;
    final ack = await super.saveDay(
      uid,
      writerId: writerId,
      summary: summary,
      expectedDigest: expectedDigest,
    );
    events.add('summary-ack');
    return ack;
  }
}

class _InterruptedRawStore extends MemoryRawHeartRateStore {
  void Function()? afterNextCommit;
  int commitsBeforeInterruption = 0;
  bool failWrites = false;

  @override
  Future<void> replace(
    String uid,
    Iterable<SignalReading> readings, {
    Map<String, HeartRateSampleProvenance> provenance = const {},
  }) async {
    if (failWrites) throw StateError('Device storage is full');
    // Capture and commit the submitted rows before simulating a newer edit
    // arriving while the caller is still awaiting this disk operation.
    await super.replace(uid, List.of(readings), provenance: provenance);
    if (commitsBeforeInterruption > 0) {
      commitsBeforeInterruption -= 1;
      return;
    }
    final afterCommit = afterNextCommit;
    afterNextCommit = null;
    afterCommit?.call();
  }
}

class _Repository extends MemoryCloudRepository {
  _Repository(this.events, this.raw, this.days) : super(signedInUid: 'owner');
  final List<String> events;
  final RawHeartRateStore raw;
  final _CloudDays days;
  int rawDeletePatches = 0;
  bool offlineWrites = false;
  int inputReads = 0;
  int privacyReads = 0;

  @override
  Future<CloudUserState?> readUser(String uid) {
    inputReads += 1;
    return super.readUser(uid);
  }

  @override
  Future<AccountPrivacySnapshot> readAccountPrivacy(String uid) {
    privacyReads += 1;
    return super.readAccountPrivacy(uid);
  }

  final explicitlyErasedIds = <String>{};

  @override
  Future<void> applyInputPatch(String uid, InputSyncPatch patch) async {
    if (offlineWrites) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    final removals = patch.signals.where(
      (edit) => edit.after == null && edit.before?['type'] == 'heartRate',
    );
    if (removals.isNotEmpty) {
      events.add('raw-cloud-delete');
      rawDeletePatches += 1;
      final durable = {for (final row in await raw.load(uid)) row.id: row};
      for (final removal in removals) {
        if (explicitlyErasedIds.contains(removal.id)) {
          expect(durable.containsKey(removal.id), isFalse);
          continue;
        }
        expect(durable.containsKey(removal.id), isTrue);
        final day = HeartRateSummary.dayId(durable[removal.id]!.timestamp);
        expect(days.values[uid]?.containsKey(day), isTrue);
      }
    }
    await super.applyInputPatch(uid, patch);
  }
}

AppController _app({
  required _Repository repository,
  required RawHeartRateStore raw,
  required _CloudDays days,
  AccountSession session = _owner,
  DateTime Function()? clock,
}) => AppController(
  cloudRepository: repository,
  accountAuth: MemoryAccountAuth(session: session),
  initialPrivacyConsent: testAdultPrivacyConsent,
  rawHeartRateStore: raw,
  heartRateCloudStore: days,
  clock: clock ?? () => _now,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'legacy preferences migrate durably before ack and raw cloud cleanup',
    () async {
      final samples = [_heart('healthkit-a'), _heart('healthkit-b', minute: 1)];
      final state = _state(signals: samples);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);

      await app.load();

      expect(
        (await raw.load('owner')).map((r) => r.toJson()),
        samples.map((r) => r.toJson()),
      );
      expect(app.signals.where(isRawHeartRate), hasLength(2));
      expect(
        events.indexOf('summary-ack'),
        lessThan(events.indexOf('raw-cloud-delete')),
      );
      expect(repository.rawDeletePatches, 1);
      expect(
        (await repository.readUser('owner'))!.signals.where(isRawHeartRate),
        isEmpty,
      );
      expect(app.hasPendingCloudChanges, isFalse);

      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('tonyo_state_v1')!) as Map;
      expect(saved['signals'], isEmpty);
      expect((saved['inputSync'] as Map)['baseline']['signals'], isEmpty);
      expect(saved['efficientSync']['legacyHeartRateCloud'], isEmpty);
      expect(saved['efficientSync']['heartRateDays'], hasLength(1));
    },
  );

  test(
    'restart keeps exact local raw when cloud contains summaries only',
    () async {
      final samples = [_heart('healthkit-a')];
      final state = _state(signals: samples);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final first = _app(repository: repository, raw: raw, days: days);
      await first.load();
      first.dispose();
      final writes = days.writes;
      final restarted = _app(repository: repository, raw: raw, days: days);
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(
        restarted.signals.where(isRawHeartRate).single.toJson(),
        samples.single.toJson(),
      );
      expect(days.writes, writes);
      expect(
        restarted.latestHealthKitHeartRate!.toJson(),
        samples.single.toJson(),
      );
    },
  );

  for (final failure in [
    StateError('unavailable'),
    FirebaseException(plugin: 'cloud_firestore', code: 'resource-exhausted'),
  ]) {
    test('$failure before summary ack prevents deleting legacy raw', () async {
      final state = _state(signals: [_heart('healthkit-a')]);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events)..fail = failure;
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      await app.load();
      expect(await raw.load('owner'), hasLength(1));
      expect(repository.rawDeletePatches, 0);
      expect(
        (await repository.readUser('owner'))!.signals.where(isRawHeartRate),
        hasLength(1),
      );
      expect(days.writes, 0);
      expect(app.hasPendingCloudChanges, isTrue);
      expect(app.cloudSyncError, isNotNull);
    });
  }

  test(
    'pending manual edit does not drop cloud-only raw during migration',
    () async {
      final state = _state(signals: [_heart('healthkit-cloud-only')]);
      final manual = SignalReading(
        id: 'manual-pending',
        type: SignalType.study,
        value: 2,
        timestamp: _now,
        recordedAt: _now,
      );
      _legacyPreferences(cloud: _state(), local: [manual]);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      await app.load();
      expect((await raw.load('owner')).map((r) => r.id), [
        'healthkit-cloud-only',
      ]);
      expect(
        app.signals.map((r) => r.id),
        containsAll(['manual-pending', 'healthkit-cloud-only']),
      );
      expect(
        (await repository.readUser('owner'))!.signals.single.id,
        'manual-pending',
      );
      expect(days.values['owner'], hasLength(1));
    },
  );

  test(
    'ownerless previous-account raw never becomes the new account history',
    () async {
      _legacyPreferences(
        cloud: _state(
          email: 'previous@example.com',
          signals: [_heart('previous-private')],
        ),
        owner: null,
        baseline: false,
      );
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)
        ..seed('owner', _state());
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      await app.load();
      expect(await raw.load('owner'), isEmpty);
      expect((await raw.load('local')).single.id, 'previous-private');
      expect(days.values['owner'] ?? {}, isEmpty);
      expect(app.signals.where((r) => r.id == 'previous-private'), isEmpty);
    },
  );

  test(
    'known previous owner raw stays isolated when a new account starts',
    () async {
      _legacyPreferences(
        cloud: _state(
          email: 'previous@example.com',
          signals: [_heart('previous-private')],
        ),
        owner: 'previous',
      );
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)
        ..seed('owner', _state());
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      await app.load();
      expect((await raw.load('previous')).single.id, 'previous-private');
      expect(await raw.load('owner'), isEmpty);
      expect(days.values['owner'] ?? {}, isEmpty);
      expect(app.signals.where(isRawHeartRate), isEmpty);
    },
  );

  test(
    'missing raw database after compaction stops without clearing summaries',
    () async {
      final state = _state(signals: [_heart('healthkit-a')]);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final first = _app(repository: repository, raw: raw, days: days);
      await first.load();
      first.dispose();
      final missingDatabase = MemoryRawHeartRateStore();
      final writes = days.writes;
      final restarted = _app(
        repository: repository,
        raw: missingDatabase,
        days: days,
      );
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.cloudSyncFailureKind?.name, 'deviceStorage');
      expect(restarted.cloudSyncError, isNotNull);
      expect(await missingDatabase.hasSnapshot('owner'), isFalse);
      expect(days.values['owner'], hasLength(1));
      expect(days.writes, writes);
    },
  );

  test(
    'deleting the final local pulse retires its acknowledged cloud summary',
    () async {
      final state = _state(signals: [_heart('healthkit-a')]);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      await app.load();
      expect(days.values['owner'], hasLength(1));
      await app.deleteSignal('healthkit-a');
      expect(await raw.load('owner'), isEmpty);
      expect(await raw.hasSnapshot('owner'), isTrue);
      expect(days.values['owner'] ?? {}, isEmpty);
      expect(app.latestHealthKitHeartRate, isNull);
    },
  );

  test(
    'sign-out during summary upload cannot continue with raw cloud cleanup',
    () async {
      final state = _state(signals: [_heart('healthkit-a')]);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final gate = Completer<void>();
      final entered = Completer<void>();
      final days = _CloudDays(events)
        ..gate = gate
        ..entered = entered;
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      final loading = app.load();
      await entered.future;
      await app.signOut();
      gate.complete();
      await loading;
      expect(app.isSignedOut, isTrue);
      expect(repository.rawDeletePatches, 0);
      expect(await raw.load('owner'), hasLength(1));
      expect(
        (await repository.readUser('owner'))!.signals.where(isRawHeartRate),
        hasLength(1),
      );
    },
  );

  test(
    'another phone owning a heart day does not block unrelated manual edits',
    () async {
      final samples = [_heart('healthkit-a'), _heart('healthkit-b', minute: 1)];
      final state = _state(signals: samples);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      await days.saveDay(
        'owner',
        writerId: 'another-phone',
        summary: HeartRateSummary.build([samples.first]).single,
      );
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      await app.load();
      await app.addSignal(SignalType.study, 2);
      final remote = (await repository.readUser('owner'))!;
      expect(
        remote.signals.where((r) => r.type == SignalType.study),
        hasLength(1),
      );
      expect(await raw.load('owner'), hasLength(2));
      expect(remote.signals.where(isRawHeartRate), hasLength(2));
      expect(days.values['owner']!.values.single.writerId, 'another-phone');
      expect(days.values['owner']!.values.single.summary.sampleCount, 1);
    },
  );

  test(
    'claimed server digest with altered statistics cannot authorize raw deletion',
    () async {
      final samples = [
        _heart('healthkit-a', value: 70),
        _heart('healthkit-b', value: 80),
      ];
      final state = _state(signals: samples);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final exact = HeartRateSummary.build(samples).single;
      final corrupt = exact.toJson();
      corrupt['latestValue'] = 70.0;
      (corrupt['hours'] as List).single['latestValue'] = 70.0;
      days.values['owner'] = {
        exact.day: StoredHeartRateDay(
          writerId: 'another-phone',
          summary: HeartRateDailySummary.fromJson(corrupt),
        ),
      };
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      await app.load();
      expect(await raw.load('owner'), hasLength(2));
      expect(repository.rawDeletePatches, 0);
      expect(
        (await repository.readUser('owner'))!.signals.where(isRawHeartRate),
        hasLength(2),
      );
      expect(app.cloudSyncError, isNotNull);
    },
  );

  test(
    'offline explicit deletion survives restart without resurrecting legacy raw',
    () async {
      final state = _state(signals: [_heart('healthkit-a')]);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events)..fail = StateError('offline');
      final repository = _Repository(events, raw, days)
        ..seed('owner', state)
        ..offlineWrites = true;
      final first = _app(repository: repository, raw: raw, days: days);
      await first.load();
      repository.explicitlyErasedIds.add('healthkit-a');
      await first.deleteSignal('healthkit-a');
      expect(await raw.load('owner'), isEmpty);
      expect(await raw.hasSnapshot('owner'), isTrue);
      expect(first.hasPendingCloudChanges, isTrue);
      expect(repository.rawDeletePatches, 0);
      expect((await repository.readUser('owner'))!.signals, hasLength(1));
      first.dispose();

      final restarted = _app(repository: repository, raw: raw, days: days);
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.signals.where(isRawHeartRate), isEmpty);
      expect(await raw.load('owner'), isEmpty);
      expect(restarted.hasPendingCloudChanges, isTrue);

      repository.offlineWrites = false;
      days.fail = null;
      await restarted.retryCloudSync();
      expect((await repository.readUser('owner'))!.signals, isEmpty);
      expect(await raw.load('owner'), isEmpty);
      expect(days.values['owner'] ?? {}, isEmpty);
      expect(days.writes, 0);
      expect(restarted.hasPendingCloudChanges, isFalse);
    },
  );

  test(
    'summary uses the durable snapshot when a newer edit cannot be saved',
    () async {
      final original = _heart('healthkit-a', value: 72);
      final correction = _heart('healthkit-a', value: 95);
      final state = _state(signals: [original]);
      _legacyPreferences(cloud: state);
      final raw = _InterruptedRawStore();
      final events = <String>[];
      final days = _CloudDays(events)..fail = StateError('offline');
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      await app.load();
      expect(days.writes, 0);
      expect(repository.rawDeletePatches, 0);

      days.fail = null;
      // Retry persists privacy and rehydrates raw storage; interrupt the
      // following durable write immediately before the cloud commit starts.
      raw.commitsBeforeInterruption = 2;
      raw.afterNextCommit = () {
        app.signals = [correction];
        raw.failWrites = true;
      };
      await app.retryCloudSync();

      final uploaded = days.values['owner']!.values.single.summary;
      expect(
        uploaded.contentDigest,
        HeartRateSummary.contentDigest([original]),
      );
      expect(uploaded.latestValue, 72);
      expect(
        uploaded.contentDigest,
        isNot(HeartRateSummary.contentDigest([correction])),
      );
      expect((await raw.load('owner')).single.toJson(), original.toJson());
      expect(app.signals.single.toJson(), correction.toJson());
      expect(repository.rawDeletePatches, 0);
      expect(
        (await repository.readUser('owner'))!.signals.single.toJson(),
        original.toJson(),
      );
      expect(app.hasPendingCloudChanges, isTrue);
      expect(app.cloudSyncError, isNotNull);
    },
  );

  test(
    'clear tracking waits for an active summary upload then clears raw and summaries',
    () async {
      final state = _state(signals: [_heart('healthkit-a')]);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final gate = Completer<void>();
      final entered = Completer<void>();
      final days = _CloudDays(events)
        ..gate = gate
        ..entered = entered;
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(repository: repository, raw: raw, days: days);
      addTearDown(app.dispose);
      final loading = app.load();
      await entered.future;
      var cleared = false;
      final clearing = app.clearTrackingData().then((_) => cleared = true);
      await Future<void>.delayed(Duration.zero);
      expect(cleared, isFalse);
      expect(await raw.load('owner'), hasLength(1));
      gate.complete();
      await Future.wait([loading, clearing]);
      expect(cleared, isTrue);
      expect(await raw.load('owner'), isEmpty);
      expect(await raw.hasSnapshot('owner'), isTrue);
      expect((await repository.readUser('owner'))!.signals, isEmpty);
      expect(days.values['owner'] ?? {}, isEmpty);
      expect(app.latestHealthKitHeartRate, isNull);
      expect(app.hasPendingCloudChanges, isFalse);
    },
  );
  test(
    'daily summary cadence survives restart and leaves ordinary edits immediate',
    () async {
      var clock = _now;
      final state = _state(signals: [_heart('healthkit-a')]);
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final first = _app(
        repository: repository,
        raw: raw,
        days: days,
        clock: () => clock,
      );
      await first.load();
      expect(days.writes, 1);

      first.signals = [...first.signals, _heart('healthkit-b', value: 80)];
      await first.updateProfile(first.profile.copyWith(name: 'Updated'));
      expect(days.writes, 1);
      expect((await repository.readUser('owner'))!.profile.name, 'Updated');
      expect(await raw.load('owner'), hasLength(2));
      expect(first.hasPendingCloudChanges, isTrue);
      expect(first.cloudSyncStatusMessage, contains('next daily update'));
      final privacyReads = repository.privacyReads;
      await first.syncPendingChanges();
      expect(repository.privacyReads, privacyReads);
      first.dispose();

      final restarted = _app(
        repository: repository,
        raw: raw,
        days: days,
        clock: () => clock,
      );
      addTearDown(restarted.dispose);
      final readsBeforeRestart = repository.inputReads;
      await restarted.load();
      expect(repository.inputReads, readsBeforeRestart);
      expect(days.writes, 1);
      expect(restarted.signals.where(isRawHeartRate), hasLength(2));
      clock = clock.add(const Duration(days: 1));
      await restarted.syncPendingChanges();
      expect(days.writes, 2);
      expect(days.values['owner']!.values.single.summary.sampleCount, 2);
      expect(restarted.hasPendingCloudChanges, isFalse);

      restarted.signals = [
        ...restarted.signals,
        _heart('healthkit-c', value: 90),
      ];
      await restarted.updateProfile(restarted.profile);
      expect(days.writes, 2);
      await restarted.retryCloudSync();
      expect(days.writes, 3);
      expect(days.values['owner']!.values.single.summary.sampleCount, 3);
      await restarted.deleteSignal('healthkit-c');
      expect(days.writes, 4);
      expect(days.values['owner']!.values.single.summary.sampleCount, 2);
    },
  );

  test(
    'input hydration has a three-hour TTL but explicit retry always pulls',
    () async {
      var clock = _now;
      final state = _state();
      _legacyPreferences(cloud: state);
      final raw = MemoryRawHeartRateStore();
      final events = <String>[];
      final days = _CloudDays(events);
      final repository = _Repository(events, raw, days)..seed('owner', state);
      final app = _app(
        repository: repository,
        raw: raw,
        days: days,
        clock: () => clock,
      );
      addTearDown(app.dispose);
      await app.load();
      final initialReads = repository.inputReads;
      final initialPrivacyReads = repository.privacyReads;
      clock = clock.add(const Duration(hours: 2, minutes: 59));
      await app.handleAppResumed();
      expect(repository.inputReads, initialReads);
      expect(repository.privacyReads, greaterThan(initialPrivacyReads));
      clock = clock.add(const Duration(minutes: 1));
      await app.handleAppResumed();
      expect(repository.inputReads, initialReads + 1);
      await app.retryCloudSync();
      expect(repository.inputReads, initialReads + 2);
    },
  );
}
