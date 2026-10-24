import 'dart:io';

import 'package:app/src/heart_rate_summary.dart';
import 'package:app/src/models.dart';
import 'package:app/src/raw_heart_rate_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SignalReading raw(String id, {double value = 72, int minute = 0}) =>
    SignalReading(
      id: id,
      type: SignalType.heartRate,
      source: SignalSource.healthKit,
      value: value,
      timestamp: DateTime.utc(2026, 10, 24, 1, minute, 0, 12, 345),
      quality: .75,
      note: 'Apple Health · Watch · 心率',
      groupId: 'original-source',
      syncedAt: DateTime.utc(2026, 10, 24, 2),
      recordedAt: DateTime.utc(2026, 10, 24, 1, 59),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final sqlite in [false, true]) {
    group(sqlite ? 'SQLite raw store' : 'memory raw store', () {
      late RawHeartRateStore store;
      Directory? directory;
      late String path;

      setUp(() async {
        if (sqlite) {
          directory = await Directory.systemTemp.createTemp('tonyo-raw-heart-');
          path = '${directory!.path}/samples.sqlite';
          store = SqliteRawHeartRateStore(
            databaseFactory: databaseFactoryFfi,
            path: path,
          );
        } else {
          store = MemoryRawHeartRateStore();
        }
      });
      tearDown(() async {
        await store.close();
        await directory?.delete(recursive: true);
      });

      test(
        'missing snapshot differs from saved empty and explicit erasure',
        () async {
          expect(await store.hasSnapshot('alice'), isFalse);
          expect(await store.load('alice'), isEmpty);
          await store.replace('alice', []);
          expect(await store.hasSnapshot('alice'), isTrue);
          expect(await store.load('alice'), isEmpty);
          if (sqlite) {
            await store.close();
            store = SqliteRawHeartRateStore(
              databaseFactory: databaseFactoryFfi,
              path: path,
            );
            expect(await store.hasSnapshot('alice'), isTrue);
          }
          expect(await store.hasSnapshot('bob'), isFalse);
          await store.clear('alice');
          expect(await store.hasSnapshot('alice'), isFalse);
        },
      );

      test(
        'legacy JSON migration round-trips exact raw fields per owner',
        () async {
          final original = raw('healthkit-a');
          await store.replace('alice', [
            original,
            original.copyWith(type: SignalType.hrv, id: 'hrv'),
            original.copyWith(source: SignalSource.manual, id: 'manual'),
          ]);
          await store.replace('bob', [raw('healthkit-b', value: 80)]);
          expect(
            (await store.load('alice')).single.toJson(),
            original.toJson(),
          );
          expect((await store.load('bob')).single.value, 80);
          expect(await store.loadProvenance('alice'), isEmpty);
          await store.clear('alice');
          expect(await store.load('alice'), isEmpty);
          expect(await store.load('bob'), hasLength(1));
        },
      );

      test(
        'snapshot replacement deduplicates and deletes only missing UUIDs',
        () async {
          final a = raw('healthkit-a');
          final b = raw('healthkit-b');
          await store.replace('alice', [a, b, a]);
          expect(await store.load('alice'), hasLength(2));
          await store.replace('alice', [a.copyWith(value: 81)]);
          expect((await store.load('alice')).single.value, 81);
          await store.replace('alice', []);
          expect(await store.load('alice'), isEmpty);
        },
      );

      test(
        'first import provenance survives subsequent travel and refresh',
        () async {
          final sample = raw('healthkit-a');
          await store.replace(
            'alice',
            [sample],
            provenance: {
              sample.id: const HeartRateSampleProvenance(
                offsetMinutes: -420,
                timezoneName: 'America/Los_Angeles',
              ),
            },
          );
          await store.replace(
            'alice',
            [sample],
            provenance: {
              sample.id: const HeartRateSampleProvenance(
                offsetMinutes: 60,
                timezoneName: 'Europe/London',
              ),
            },
          );
          final provenance = await store.loadProvenance('alice');
          expect(provenance[sample.id]!.offsetMinutes, -420);
          expect(provenance[sample.id]!.timezoneName, 'America/Los_Angeles');
        },
      );

      test(
        'invalid replacement never damages the prior complete snapshot',
        () async {
          final sample = raw('healthkit-a');
          await store.replace('alice', [sample]);
          await expectLater(
            Future<void>.sync(
              () =>
                  store.replace('alice', [sample.copyWith(value: double.nan)]),
            ),
            throwsFormatException,
          );
          expect((await store.load('alice')).single.toJson(), sample.toJson());
        },
      );

      if (sqlite) {
        test(
          'survives close and reopen without preferences or process cache',
          () async {
            final sample = raw('healthkit-a');
            await store.replace('alice', [sample]);
            await store.close();
            store = SqliteRawHeartRateStore(
              databaseFactory: databaseFactoryFfi,
              path: path,
            );
            expect(
              (await store.load('alice')).single.toJson(),
              sample.toJson(),
            );
          },
        );

        test(
          'unchanged snapshot does no row writes and one correction updates one',
          () async {
            final samples = List.generate(100, (i) => raw('healthkit-$i'));
            await store.replace('alice', samples);
            final db = await databaseFactoryFfi.openDatabase(path);
            final before = (await db.rawQuery(
              'SELECT total_changes() AS n',
            )).single['n'];
            await store.replace('alice', samples.reversed);
            expect(
              (await db.rawQuery('SELECT total_changes() AS n')).single['n'],
              before,
            );
            await store.replace('alice', [
              samples.first.copyWith(value: 83),
              ...samples.skip(1),
            ]);
            expect(
              (await db.rawQuery('SELECT total_changes() AS n')).single['n'],
              (before as int) + 1,
            );
          },
        );

        test(
          'SQLite write failure rolls back an earlier update in the batch',
          () async {
            final sample = raw('healthkit-a');
            await store.replace('alice', [sample]);
            final db = await databaseFactoryFfi.openDatabase(path);
            await db.execute('''
            CREATE TRIGGER fail_insert BEFORE INSERT ON raw_heart_rate
            WHEN NEW.sample_id = 'healthkit-fail'
            BEGIN SELECT RAISE(ABORT, 'injected disk-write failure'); END
          ''');
            await expectLater(
              store.replace('alice', [
                sample.copyWith(value: 90),
                raw('healthkit-fail', minute: 1),
              ]),
              throwsA(isA<DatabaseException>()),
            );
            expect(
              (await store.load('alice')).single.toJson(),
              sample.toJson(),
            );
          },
        );
      }
    });
  }
}
