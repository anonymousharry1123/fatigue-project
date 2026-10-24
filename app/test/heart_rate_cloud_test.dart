import 'package:app/src/heart_rate_cloud.dart';
import 'package:app/src/heart_rate_summary.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

HeartRateDailySummary summary(int count, {double bpm = 72}) =>
    HeartRateSummary.build([
      for (var index = 0; index < count; index++)
        SignalReading(
          id: 'healthkit-$index',
          type: SignalType.heartRate,
          source: SignalSource.healthKit,
          value: bpm,
          timestamp: DateTime.utc(2026, 10, 24, 1, index),
        ),
    ]).single;

void main() {
  test(
    'v1 upgrades to context without changing raw proof or writer rules',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      HeartRateDailySummary day({double? hrv}) => HeartRateSummary.build([
        SignalReading(
          id: 'healthkit-pulse',
          type: SignalType.heartRate,
          source: SignalSource.healthKit,
          value: 72,
          timestamp: DateTime.utc(2026, 10, 24, 12),
        ),
        if (hrv != null)
          SignalReading(
            id: 'healthkit-hrv',
            type: SignalType.hrv,
            source: SignalSource.healthKit,
            value: hrv,
            timestamp: DateTime.utc(2026, 10, 24, 12),
          ),
      ]).single;
      final rawOnly = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: day(),
      );
      final withContext = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: day(hrv: 40),
        expectedDigest: rawOnly.summary.contentDigest,
      );
      expect(
        withContext.summary.rawContentDigest,
        rawOnly.summary.rawContentDigest,
      );
      expect(withContext.summary.sampleCount, rawOnly.summary.sampleCount);
      expect(withContext.summary.cardiacContext!.hrv!.mean, 40);
      expect(
        (await cloud.saveDay(
          'alice',
          writerId: 'phone-b',
          summary: day(hrv: 40),
        )).changed,
        isFalse,
      );
      await expectLater(
        cloud.saveDay(
          'alice',
          writerId: 'phone-b',
          summary: day(hrv: 50),
          expectedDigest: withContext.summary.contentDigest,
        ),
        throwsA(isA<HeartRateSummaryOwnershipConflict>()),
      );
      await expectLater(
        cloud.saveDay(
          'alice',
          writerId: 'phone-a',
          summary: day(hrv: 50),
          expectedDigest: rawOnly.summary.contentDigest,
        ),
        throwsA(isA<HeartRateSummaryRevisionConflict>()),
      );
      expect(cloud.writes, 2);
    },
  );

  test(
    'delete requires writer ownership and revision and is idempotent',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      final first = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: summary(2),
      );
      await expectLater(
        cloud.deleteDay(
          'alice',
          first.summary.day,
          writerId: 'phone-b',
          expectedDigest: first.summary.contentDigest,
        ),
        throwsA(isA<HeartRateSummaryOwnershipConflict>()),
      );
      await expectLater(
        cloud.deleteDay(
          'alice',
          first.summary.day,
          writerId: 'phone-a',
          expectedDigest: 'stale',
        ),
        throwsA(isA<HeartRateSummaryRevisionConflict>()),
      );
      expect(
        await cloud.deleteDay(
          'alice',
          first.summary.day,
          writerId: 'phone-a',
          expectedDigest: first.summary.contentDigest,
        ),
        isTrue,
      );
      expect(
        await cloud.deleteDay(
          'alice',
          first.summary.day,
          writerId: 'phone-a',
          expectedDigest: first.summary.contentDigest,
        ),
        isFalse,
      );
      expect(await cloud.readDays('alice'), isEmpty);
    },
  );

  test(
    'explicit clear removes all device writers only for the chosen account',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      await cloud.saveDay('alice', writerId: 'phone-a', summary: summary(2));
      await cloud.saveDay('bob', writerId: 'phone-b', summary: summary(2));
      await cloud.clearDays('alice');
      expect(await cloud.readDays('alice'), isEmpty);
      expect(await cloud.readDays('bob'), hasLength(1));
    },
  );

  test(
    'server acknowledgement is idempotent and scopes days by account',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      final first = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: summary(2),
      );
      final retry = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: summary(2),
      );
      expect(first.changed, isTrue);
      expect(retry.changed, isFalse);
      expect(cloud.writes, 1);
      expect((await cloud.readDays('alice')).single.summary.sampleCount, 2);
      expect(await cloud.readDays('bob'), isEmpty);
    },
  );

  test(
    'same writer needs expected revision for a changed complete snapshot',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      final first = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: summary(2),
      );
      await expectLater(
        cloud.saveDay('alice', writerId: 'phone-a', summary: summary(3)),
        throwsA(isA<HeartRateSummaryRevisionConflict>()),
      );
      final updated = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: summary(3),
        expectedDigest: first.summary.contentDigest,
      );
      expect(updated.summary.sampleCount, 3);
      expect(cloud.writes, 2);
      await expectLater(
        cloud.saveDay(
          'alice',
          writerId: 'phone-a',
          summary: summary(2),
          expectedDigest: first.summary.contentDigest,
        ),
        throwsA(isA<HeartRateSummaryRevisionConflict>()),
      );
      expect((await cloud.readDays('alice')).single.summary.sampleCount, 3);
    },
  );

  test(
    'other device never adds overlapping summaries or takes ownership',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      final first = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: summary(2),
      );
      final same = await cloud.saveDay(
        'alice',
        writerId: 'phone-b',
        summary: summary(2),
      );
      expect(same.changed, isFalse);
      expect(same.writerId, 'phone-a');
      for (final count in [1, 3]) {
        await expectLater(
          cloud.saveDay(
            'alice',
            writerId: 'phone-b',
            summary: summary(count),
            expectedDigest: first.summary.contentDigest,
          ),
          throwsA(isA<HeartRateSummaryOwnershipConflict>()),
        );
      }
      expect(cloud.writes, 1);
      expect((await cloud.readDays('alice')).single.summary.sampleCount, 2);
    },
  );

  test(
    'same sample IDs with corrected values require a new acknowledged write',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      final first = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: summary(2),
      );
      final corrected = await cloud.saveDay(
        'alice',
        writerId: 'phone-a',
        summary: summary(2, bpm: 80),
        expectedDigest: first.summary.contentDigest,
      );
      expect(corrected.changed, isTrue);
      expect(corrected.summary.sampleIdDigest, first.summary.sampleIdDigest);
      expect(
        corrected.summary.contentDigest,
        isNot(first.summary.contentDigest),
      );
      expect(corrected.summary.mean, 80);
    },
  );

  test(
    'a previously deleted day cannot be recreated by a stale upload',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      await expectLater(
        cloud.saveDay(
          'alice',
          writerId: 'phone-a',
          summary: summary(2),
          expectedDigest: 'previous-deleted-revision',
        ),
        throwsA(isA<HeartRateSummaryRevisionConflict>()),
      );
      expect(cloud.writes, 0);
    },
  );

  test(
    'matching digest with different saved statistics is not an ack',
    () async {
      final cloud = MemoryHeartRateCloudStore();
      final exact = HeartRateSummary.build([
        SignalReading(
          id: 'healthkit-a',
          type: SignalType.heartRate,
          source: SignalSource.healthKit,
          value: 70,
          timestamp: DateTime.utc(2026, 10, 24, 1),
        ),
        SignalReading(
          id: 'healthkit-b',
          type: SignalType.heartRate,
          source: SignalSource.healthKit,
          value: 80,
          timestamp: DateTime.utc(2026, 10, 24, 1, 30),
        ),
      ]).single;
      final corrupted = exact.toJson();
      corrupted['latestValue'] = 70.0;
      (corrupted['hours'] as List).single['latestValue'] = 70.0;
      cloud.values['alice'] = {
        exact.id: StoredHeartRateDay(
          writerId: 'phone-a',
          summary: HeartRateDailySummary.fromJson(corrupted),
        ),
      };
      await expectLater(
        cloud.saveDay('alice', writerId: 'phone-a', summary: exact),
        throwsFormatException,
      );
      expect(cloud.writes, 0);
    },
  );
}
