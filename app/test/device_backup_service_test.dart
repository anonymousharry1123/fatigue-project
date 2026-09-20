import 'dart:async';

import 'package:app/src/device_backup_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = DeviceBackupService();
  const channel = MethodChannel('tonyo/device_backup');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'passes the exact snapshot to the device and awaits completed saving',
    () async {
      const json = '{"note":"未同步 ☀️","pending":[{"id":"local-only"}]}';
      final opened = Completer<void>();
      final completed = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'save');
        expect(call.arguments, {'json': json, 'filename': 'tonyo-backup.json'});
        opened.complete();
        return completed.future;
      });
      var reportedSaved = false;
      final saving = service
          .save(json: json, filename: 'tonyo-backup.json')
          .then((value) => reportedSaved = value);
      await opened.future;
      expect(reportedSaved, isFalse);
      completed.complete(true);
      expect(await saving, isTrue);
    },
  );

  test('a canceled picker does not report success', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(await service.save(json: '{}', filename: 'backup.json'), isFalse);
  });

  test('save failures remain distinguishable from canceling', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'backup_failed', message: 'Disk is full.');
    });
    await expectLater(
      service.save(json: '{}', filename: 'backup.json'),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'backup_failed'),
      ),
    );
  });

  test('an empty native reply never reports success', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      service.save(json: '{}', filename: 'backup.json'),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'backup_failed'),
      ),
    );
  });

  test(
    'an older build without the native bridge reports unsupported',
    () async {
      await expectLater(
        service.save(json: '{}', filename: 'backup.json'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'backup_unsupported',
          ),
        ),
      );
    },
  );

  test('supports only hosts with a save implementation', () async {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        service.isSupported,
        {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        }.contains(platform),
      );
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await expectLater(
      service.save(json: '{}', filename: 'backup.json'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'backup_unsupported',
        ),
      ),
    );
  });

  test(
    'rejects file paths before sending private data to the native bridge',
    () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (_) async {
        called = true;
        return true;
      });
      for (final filename in [
        '',
        '../backup.json',
        r'folder\backup.json',
        'backup.txt',
        'bad\n.json',
      ]) {
        await expectLater(
          service.save(json: '{}', filename: filename),
          throwsArgumentError,
        );
      }
      expect(called, isFalse);
    },
  );
}
