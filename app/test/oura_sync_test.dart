import 'dart:async';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/models.dart';
import 'package:app/src/oura_service.dart';
import 'package:app/src/personal_baseline_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

final _now = DateTime.utc(2026, 10, 25, 20);
const _session = AccountSession(uid: 'oura-owner', email: 'owner@example.test');

Map<String, dynamic> _response({double? hrv = 48}) => {
  'connected': true,
  'syncedAt': _now.toIso8601String(),
  'startDate': '2026-09-26',
  'endDate': '2026-10-25',
  'sleep': [
    {
      'id': 'night-a',
      'day': '2026-10-25',
      'type': 'long_sleep',
      'bedtime_start': '2026-10-24T23:00:00Z',
      'bedtime_end': '2026-10-25T07:00:00Z',
      'total_sleep_duration': 28000,
      'average_hrv': hrv,
      'lowest_heart_rate': 49,
    },
  ],
};

class _Oura extends OuraService {
  bool connected = true;
  bool failDisconnect = false;
  int reads = 0;
  int disconnects = 0;
  Completer<void>? pendingDisconnect;
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> response = _response();
  @override
  bool get supported => true;
  @override
  bool get configured => true;
  @override
  Future<bool> status(String uid) async => connected;
  @override
  Future<void> connect(String uid) async {
    connected = true;
  }

  @override
  Future<Map<String, dynamic>> sync(String uid) {
    reads++;
    return pending?.future ?? Future.value(response);
  }

  @override
  Future<void> disconnect(String uid) async {
    disconnects++;
    await pendingDisconnect?.future;
    if (failDisconnect) throw const OuraException('provider_unavailable');
    connected = false;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppController controller(_Oura service, {MemoryAccountAuth? auth}) {
    final value = AppController(
      ouraService: service,
      accountAuth: auth ?? MemoryAccountAuth(session: _session),
      initialPrivacyConsent: testAdultPrivacyConsent,
      clock: () => _now,
    );
    addTearDown(value.dispose);
    return value;
  }

  test(
    'Oura connects alongside Apple Health and repeat sync is idempotent',
    () async {
      final service = _Oura();
      final app = controller(service)..healthAuthorized = true;
      final apple = SignalReading(
        id: 'apple-hrv',
        type: SignalType.hrv,
        value: 70,
        timestamp: _now.subtract(const Duration(hours: 1)),
        source: SignalSource.healthKit,
      );
      app.signals = [apple];
      await app.connectOura();
      expect(app.ouraConnected, isTrue);
      expect(app.ouraSignalCount, 2);
      expect(app.healthAuthorized, isTrue);
      final saved = app.signals
          .where((s) => s.source == SignalSource.oura)
          .first;
      await app.syncOura();
      expect(app.signals, hasLength(3));
      expect(app.signals, contains(apple));
      expect(app.signals.where((s) => s.id == saved.id).single, same(saved));
    },
  );

  test('complete correction removes a null Oura metric only', () async {
    final service = _Oura();
    final app = controller(service);
    await app.syncOura();
    service.response = _response(hrv: null);
    await app.syncOura();
    expect(app.ouraSignalCount, 1);
    expect(app.signals.single.type, SignalType.restingHeartRate);
  });

  test('invalid response leaves all saved readings untouched', () async {
    final service = _Oura();
    final app = controller(service);
    await app.syncOura();
    final saved = [...app.signals];
    service.response = {'sleep': [], 'syncedAt': 'invalid'};
    await app.syncOura();
    expect(app.signals, saved);
    expect(app.ouraError, isNotNull);
  });

  test('account switch discards an in-flight Oura result', () async {
    final service = _Oura()..pending = Completer();
    final auth = MemoryAccountAuth(session: _session);
    final app = controller(service, auth: auth);
    final work = app.syncOura();
    while (service.reads == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    auth.session = const AccountSession(
      uid: 'other',
      email: 'other@example.test',
    );
    service.pending!.complete(_response());
    await work;
    expect(app.signals, isEmpty);
  });

  test(
    'disconnect cancels pending import and leaves Apple access enabled',
    () async {
      final service = _Oura()..pending = Completer();
      final app = controller(service)..healthAuthorized = true;
      final work = app.syncOura();
      while (service.reads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await app.disconnectOura();
      service.pending!.complete(_response());
      await work;
      expect(app.signals, isEmpty);
      expect(app.ouraConnected, isFalse);
      expect(app.healthAuthorized, isTrue);
    },
  );

  test('failed disconnect persists pause across controller restart', () async {
    final service = _Oura()..failDisconnect = true;
    final app = controller(service);
    await app.syncOura();
    await app.disconnectOura();
    expect(app.ouraDisconnectPending, isTrue);
    final restarted = controller(service);
    await restarted.syncOura();
    expect(service.reads, 1);
    expect(restarted.ouraDisconnectPending, isTrue);
    service.failDisconnect = false;
    await restarted.syncOura();
    expect(service.reads, 1);
    expect(restarted.ouraDisconnectPending, isFalse);
  });

  test('account switch during clear never clears the new account', () async {
    final service = _Oura()..pendingDisconnect = Completer<void>();
    final auth = MemoryAccountAuth(session: _session);
    final app = controller(service, auth: auth);
    final work = app.clearTrackingData();
    final assertion = expectLater(work, throwsStateError);
    while (service.disconnects == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    auth.session = const AccountSession(
      uid: 'new-owner',
      email: 'new@example.test',
    );
    final newRecord = SignalReading(
      id: 'new-owner-record',
      type: SignalType.hrv,
      value: 50,
      timestamp: _now,
    );
    app.signals = [newRecord];
    service.pendingDisconnect!.complete();
    await assertion;
    expect(app.signals, [newRecord]);
  });

  test('automatic refresh is throttled and manual refresh can retry', () async {
    final service = _Oura();
    final app = controller(service);
    await app.syncOura(automatic: true);
    await app.syncOura(automatic: true);
    expect(service.reads, 1);
    await app.syncOura();
    expect(service.reads, 2);
  });

  test('Oura and its Health mirrors do not enter Apple recovery baselines', () {
    final readings = [
      for (var i = 1; i <= 20; i++)
        SignalReading(
          id: 'oura-$i',
          type: SignalType.hrv,
          value: 150,
          timestamp: _now.subtract(Duration(days: i)),
          source: SignalSource.oura,
        ),
      SignalReading(
        id: 'mirror',
        type: SignalType.hrv,
        value: 150,
        timestamp: _now.subtract(const Duration(days: 1)),
        source: SignalSource.healthKit,
        sourceBundleId: 'com.ouraring.oura',
      ),
    ];
    final baselines = PersonalBaselineLogic.build(
      signals: readings,
      asOf: _now,
    );
    expect(baselines.metrics.every((m) => m.sampleCount == 0), isTrue);
    final empty = FatigueEngine.score(signals: [], checkIns: [], now: _now);
    final actual = FatigueEngine.score(
      signals: readings,
      checkIns: [],
      now: _now,
    );
    expect(actual.energy, empty.energy);
    expect(actual.confidence, empty.confidence);
  });
}
