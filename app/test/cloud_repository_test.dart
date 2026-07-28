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

  test('exports and permanently deletes the authenticated user tree', () async {
    final exported = await repository.exportUser('maya-uid');
    expect(exported['uid'], 'maya-uid');
    expect(exported['signals'], hasLength(3));

    await repository.deleteUserTree('maya-uid');
    expect(await repository.readUser('maya-uid'), isNull);
  });
}
