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

  test(
    'opening awaits selection and returns the exact UTF-8 contents',
    () async {
      const json = '{"note":"未同步 ☀️","pending":[{"id":"local-only"}]}';
      final opened = Completer<void>();
      final completed = Completer<String?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'open');
        expect(call.arguments, isNull);
        opened.complete();
        return completed.future;
      });
      var returned = false;
      final opening = service.open().then((value) {
        returned = true;
        return value;
      });
      await opened.future;
      expect(returned, isFalse);
      completed.complete(json);
      expect(await opening, json);
    },
  );

  test('canceling open returns null without reporting a failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await service.open(), isNull);
  });

  test('opening distinguishes unreadable files from cancellation', () async {
    for (final code in [
      'backup_failed',
      'backup_too_large',
      'backup_invalid_encoding',
      'backup_busy',
      'backup_interrupted',
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: code,
          message: 'Cannot open this backup.',
        );
      });
      await expectLater(
        service.open(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    }
  });

  test('a build without the open bridge reports unsupported', () async {
    await expectLater(
      service.open(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'backup_unsupported',
        ),
      ),
    );
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

  test('supports only hosts with a backup implementation', () async {
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
    await expectLater(
      service.open(),
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
