import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 7, 28);
  late MemoryCloudRepository repository;

  CloudUserState state() => CloudUserState(
    profile: const UserProfile(name: 'Maya'),
    accountEmail: 'maya@example.com',
    onboardingComplete: true,
    notificationsEnabled: true,
    outcomeConsent: false,
    healthAuthorized: false,
    migrationVersion: localMigrationVersion,
    signals: [
      SignalReading(
        id: 'hydration',
        type: SignalType.hydration,
        value: 2.2,
        timestamp: day.add(const Duration(hours: 12)),
      ),
      SignalReading(
        id: 'reaction-old',
        type: SignalType.reactionTime,
        value: 280,
        timestamp: day.subtract(const Duration(days: 1)),
      ),
      SignalReading(
        id: 'reaction-new',
        type: SignalType.reactionTime,
        value: 260,
        timestamp: day.add(const Duration(hours: 9)),
      ),
    ],
    checkIns: [
      DailyCheckIn(
        id: 'morning',
        timestamp: day.add(const Duration(hours: 8)),
        energy: 7,
        mood: 8,
        stress: 3,
      ),
      DailyCheckIn(
        id: 'evening',
        timestamp: day.add(const Duration(hours: 19)),
        energy: 5,
        mood: 6,
        stress: 5,
        period: CheckInPeriod.evening,
      ),
    ],
  );

  setUp(() {
    repository = MemoryCloudRepository(signedInUid: 'maya-uid')
      ..seed('maya-uid', state());
  });

  test('rule-safe mock denies cross-user reads and writes', () async {
    await expectLater(repository.readUser('other-uid'), throwsStateError);
    await expectLater(
      repository.replaceUser('other-uid', state()),
      throwsStateError,
    );
    await expectLater(
      repository.checkInsByRange(
        'other-uid',
        start: day,
        end: day.add(const Duration(days: 1)),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.upsertScoreSnapshot(
        'other-uid',
        ScoreSnapshot(
          energy: 70,
          cognitive: 0,
          confidence: .5,
          drivers: const [],
          day: day,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.scoreSnapshotForDay('other-uid', day),
      throwsStateError,
    );
    await expectLater(repository.exportUser('other-uid'), throwsStateError);
    await expectLater(repository.deleteUserTree('other-uid'), throwsStateError);
  });

  test('queries signals by day range and SignalType', () async {
    final result = await repository.signalsByRange(
      'maya-uid',
      start: day,
      end: day.add(const Duration(days: 1)),
      type: SignalType.reactionTime,
    );

    expect(result.map((value) => value.id), ['reaction-new']);
  });

  test('queries latest check-in and reaction baseline window', () async {
    final latest = await repository.latestCheckIn('maya-uid');
    final reactions = await repository.reactionBaselineWindow(
      'maya-uid',
      limit: 1,
    );

    expect(latest?.id, 'evening');
    expect(reactions.single.id, 'reaction-new');
  });

  test('queries check-ins by score window', () async {
    final checkIns = await repository.checkInsByRange(
      'maya-uid',
      start: day,
      end: day.add(const Duration(hours: 14)),
    );

    expect(checkIns.map((value) => value.id), ['morning']);
  });

  test('upserts one shared daily Energy and Cognitive snapshot', () async {
    final calculatedAt = day.add(const Duration(hours: 12));
    final first = ScoreSnapshot(
      energy: 71,
      cognitive: 64,
      confidence: .74,
      drivers: const [ScoreDriver('Sleep', 6, '8.2 hr last night')],
      day: day,
      calculatedAt: calculatedAt,
      inputCount: 5,
      cognitiveConfidence: .7,
      cognitiveInputCount: 4,
      cognitiveDrivers: const [
        ScoreDriver('Reaction time', 5, '260 ms vs 275 ms baseline'),
      ],
    );
    await repository.upsertScoreSnapshot('maya-uid', first);
    await repository.upsertScoreSnapshot(
      'maya-uid',
      ScoreSnapshot(
        energy: 76,
        cognitive: 68,
        confidence: .84,
        drivers: const [ScoreDriver('Hydration', 4, '2.8 L logged today')],
        day: day.add(const Duration(hours: 9)),
        calculatedAt: calculatedAt.add(const Duration(hours: 1)),
        inputCount: 6,
        cognitiveConfidence: .8,
        cognitiveInputCount: 4,
        cognitiveDrivers: const [ScoreDriver('Sleep', 3, '8.0 hr last night')],
        previousCognitive: 64,
      ),
    );

    final stored = await repository.scoreSnapshotForDay('maya-uid', day);
    expect(scoreSnapshotId(day), '2026-07-28');
    expect(stored?.energy, 76);
    expect(stored?.inputCount, 6);
    expect(stored?.isEstimate, isTrue);
    expect(stored?.cognitive, 68);
    expect(stored?.hasCognitiveScore, isTrue);
    expect(stored?.cognitiveInputCount, 4);
    expect(stored?.cognitiveDrivers.single.label, 'Sleep');
    expect(stored?.cognitiveChange, 4);
  });

  test('exports and permanently deletes the authenticated user tree', () async {
    final exported = await repository.exportUser('maya-uid');
    expect(exported['uid'], 'maya-uid');
    expect(exported['signals'], hasLength(3));

    await repository.deleteUserTree('maya-uid');
    expect(await repository.readUser('maya-uid'), isNull);
  });
}
