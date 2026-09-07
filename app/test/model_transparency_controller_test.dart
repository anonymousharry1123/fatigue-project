import 'privacy_test_support.dart';
import 'dart:async';
import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/energy_model_repository.dart';
import 'package:app/src/energy_model_summary.dart';
import 'package:app/src/fatigue_engine.dart';
import 'package:app/src/health_service.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screen_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 9, 7, 18);

EnergyModelSummary _summary() => EnergyModelSummary.tryParse({
  'modelVersion': 1,
  'schemaVersion': 1,
  'trainedAt': '2026-08-02T00:00:00Z',
  'window': {
    'start': '2026-07-02T00:00:00Z',
    'end': '2026-08-01T00:00:00Z',
    'timezone': 'UTC',
  },
  'labelCount': 20,
  'holdoutMae': 7,
  'deterministicMae': 10,
  'featureCoverage': {
    for (final name in MlPrepBuilder.energyFeatureNames) name: .8,
  },
})!;

CloudUserState _user() => CloudUserState(
  privacyConsent: testAdultPrivacyConsent,
  profile: const UserProfile(name: 'Private test account'),
  accountEmail: 'a@example.com',
  onboardingComplete: false,
  notificationsEnabled: false,
  outcomeConsent: true,
  healthAuthorized: false,
  signals: const [],
  checkIns: const [],
  migrationVersion: localMigrationVersion,
  personalizedEnergyModel: _summary(),
  userUpdatedAt: DateTime.utc(2026, 8, 3),
);

class _Repository extends MemoryCloudRepository {
  _Repository({String uid = 'a'}) : super(signedInUid: uid);
  int userReads = 0;
  bool fail = false;
  Completer<CloudUserState?>? pending;
  final started = Completer<void>();

  @override
  Future<CloudUserState?> readUser(String uid) async {
    userReads++;
    if (!started.isCompleted) started.complete();
    if (fail) throw StateError('offline');
    if (pending != null) return pending!.future;
    return super.readUser(uid);
  }
}

class _ScoreRaceRepository extends _Repository {
  final pendingScore = Completer<ScoreSnapshot?>();
  final scoreStarted = Completer<void>();
  bool delayNextScore = true;

  @override
  Future<ScoreSnapshot?> scoreSnapshotForDay(String uid, DateTime day) {
    if (delayNextScore) {
      delayNextScore = false;
      scoreStarted.complete();
      return pendingScore.future;
    }
    return super.scoreSnapshotForDay(uid, day);
  }
}

class _Health extends HealthService {
  @override
  Future<HealthAuthorizationState> authorizationStatus() async =>
      HealthAuthorizationState.unavailable;
  @override
  Future<void> disableBackgroundUpdates() async {}
}

class _Screen extends ScreenTimeService {
  @override
  Future<ScreenTimeAuthorizationState> authorizationStatus() async =>
      ScreenTimeAuthorizationState.unavailable;
}

AppController _controller(
  _Repository repository, {
  String uid = 'a',
  DateTime? now,
  MemoryEnergyModelMetadataWriter? writer,
  MemoryAccountAuth? auth,
}) => AppController(
  initialPrivacyConsent: testAdultPrivacyConsent,
  cloudRepository: repository,
  accountAuth:
      auth ??
      MemoryAccountAuth(
        session: AccountSession(uid: uid, email: '$uid@example.com'),
      ),
  healthService: _Health(),
  screenTimeService: _Screen(),
  energyModelStore: MemoryEnergyModelStore(),
  energyModelMetadataWriter: writer,
  clock: () => now ?? _now,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'existing user read supplies summary without installing a model',
    () async {
      final repository = _Repository()..seed('a', _user());
      final writer = MemoryEnergyModelMetadataWriter();
      final controller = _controller(repository, writer: writer);
      addTearDown(controller.dispose);
      await controller.load();
      expect(repository.userReads, 1);
      for (var i = 0; i < 50; i++) {
        final state = controller.modelTransparency;
        expect(state.cloudModel!.modelVersion, 1);
        expect(state.localModel, isNull);
        expect(state.personalizedEnergyApplied, isFalse);
        expect(state.metadataFetchedAt, _now);
        expect(state.accountUpdatedAt, DateTime.utc(2026, 8, 3));
        expect(state.modelStatusDetail, contains('not its weights'));
        expect(state.energyModelVersion, 'energy-rules-v1');
      }
      expect(repository.userReads, 1);
      expect(repository.replaceUserCallCount, 0);
      expect(repository.scoreUpsertCallCount, 0);
      expect(writer.writes, 0);
      expect(controller.isRefreshingPersonalizedModel, isFalse);
    },
  );

  test(
    'same-owner offline restart retains dated metadata, not live claims',
    () async {
      final first = _controller(_Repository()..seed('a', _user()));
      addTearDown(first.dispose);
      await first.load();
      final offline = _controller(
        _Repository()..fail = true,
        now: _now.add(const Duration(days: 1)),
      );
      addTearDown(offline.dispose);
      await offline.load();
      final state = offline.modelTransparency;
      expect(state.offline, isTrue);
      expect(state.cloudModel!.labelCount, 20);
      expect(state.metadataFetchedAt, _now);
      expect(state.notices.join(' '), contains('not a live connection'));
      expect(state.localModel, isNull);
    },
  );

  test(
    'another account cannot see cached model metadata when its read fails',
    () async {
      final first = _controller(_Repository()..seed('a', _user()));
      addTearDown(first.dispose);
      await first.load();
      final second = _controller(_Repository(uid: 'b')..fail = true, uid: 'b');
      addTearDown(second.dispose);
      await second.load();
      expect(second.modelTransparency.cloudModel, isNull);
      expect(second.modelTransparency.metadataFetchedAt, isNull);
      expect(second.modelTransparency.accountUpdatedAt, isNull);
    },
  );

  test(
    'sign-out hides summary and scores while retaining recoverable cache',
    () async {
      final controller = _controller(_Repository()..seed('a', _user()));
      addTearDown(controller.dispose);
      await controller.load();
      await controller.signOut();
      expect(controller.modelTransparency.cloudModel, isNull);
      expect(controller.modelTransparency.localModel, isNull);
      expect(controller.modelTransparency.metadataFetchedAt, isNull);
      expect(controller.modelTransparency.snapshot.drivers, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('tonyo_state_v1'),
        contains('modelTransparencyCache'),
      );
    },
  );

  test(
    'delayed old-owner account load cannot repopulate metadata after sign-out',
    () async {
      final repository = _Repository()..pending = Completer<CloudUserState?>();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final loading = controller.load();
      await repository.started.future;
      await controller.signOut();
      repository.pending!.complete(_user());
      await loading;
      expect(controller.modelTransparency.cloudModel, isNull);
      expect(controller.profile.name, isNot('Private test account'));
    },
  );

  test(
    'malformed optional metadata does not discard the offline profile',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'tonyo_state_v1',
        jsonEncode({
          'profile': const UserProfile(name: 'Keep this profile').toJson(),
          'accountEmail': 'a@example.com',
          'modelTransparencyCache': {
            'uid': 'a',
            'fetchedAt': 123,
            'userUpdatedAt': 'invalid',
            'personalizedEnergyModel': {
              'weights': [1, 2, 3],
            },
          },
        }),
      );
      final controller = _controller(_Repository()..fail = true);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.profile.name, 'Keep this profile');
      expect(controller.modelTransparency.cloudModel, isNull);
      expect(controller.modelTransparency.metadataFetchedAt, isNull);
    },
  );

  test('full reset removes metadata cache', () async {
    final controller = _controller(_Repository()..seed('a', _user()));
    addTearDown(controller.dispose);
    await controller.load();
    await controller.reset();
    expect(controller.modelTransparency.cloudModel, isNull);
    expect(controller.modelTransparency.metadataFetchedAt, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tonyo_state_v1'), isNull);
  });

  test(
    'delayed score cannot expose previous account drivers after switching',
    () async {
      final repository = _ScoreRaceRepository()..seed('a', _user());
      final auth = MemoryAccountAuth(
        session: const AccountSession(uid: 'a', email: 'a@example.com'),
      );
      final controller = _controller(repository, auth: auth);
      addTearDown(controller.dispose);
      final oldRefresh = controller.refreshScores();
      await repository.scoreStarted.future;
      await controller.signOut();
      auth.session = const AccountSession(uid: 'b', email: 'b@example.com');
      repository.signedInUid = 'b';
      controller.isSignedOut = false;
      await controller.refreshScores();
      final ownScore = controller.score;
      repository.pendingScore.complete(_oldPrivateScore());
      await oldRefresh;
      expect(controller.privacyReviewRequired, isTrue);
      expect(controller.score.energy, ownScore.energy);
      expect(controller.score.cognitive, ownScore.cognitive);
      expect(controller.score.confidence, ownScore.confidence);
      expect(
        controller.modelTransparency.snapshot.drivers,
        isNot(contains(predicate<ScoreDriver>((d) => d.label == 'Private A'))),
      );
      expect(controller.isScoreLoading, isFalse);
    },
  );

  test(
    'latest refresh wins when a prior same-account score query finishes late',
    () async {
      final repository = _ScoreRaceRepository()..seed('a', _user());
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final oldRefresh = controller.refreshScores();
      await repository.scoreStarted.future;
      await controller.refreshScores(forceRecalculate: true);
      final currentScore = controller.score;
      repository.pendingScore.complete(_oldPrivateScore());
      await oldRefresh;
      expect(controller.score, same(currentScore));
      expect(controller.modelTransparency.snapshot.drivers, isEmpty);
      expect(controller.isScoreLoading, isFalse);
    },
  );
}

ScoreSnapshot _oldPrivateScore() => ScoreSnapshot(
  energy: 9,
  cognitive: 12,
  confidence: .8,
  drivers: const [ScoreDriver('Private A', -51, 'Old account detail')],
  freshness: .9,
  cognitiveFreshness: .9,
  calculatedAt: _now,
  energyModelVersion: FatigueEngine.energyModelVersion,
  personalBaselines: PersonalBaselines(
    generatedAt: _now,
    windowDays: 42,
    metrics: const [],
  ),
);
