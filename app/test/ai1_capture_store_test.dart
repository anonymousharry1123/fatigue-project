import 'dart:async';
import 'dart:convert';

import 'package:app/src/ai1_capture_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = MethodChannelAi1CaptureStore();
  const channel = MethodChannel('tonyo/ai1_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('unsupported platforms never call the native journal channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      throw StateError('Unsupported platforms must not call native storage.');
    });
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.iOS) continue;
      debugDefaultTargetPlatformOverride = platform;
      expect(await store.isAvailable(), isFalse);
      await store.clear('owner');
      await store.clearAll();
      final unsupported = throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'capture_unsupported',
        ),
      );
      await expectLater(store.read('owner'), unsupported);
      await expectLater(store.write('owner', '{}'), unsupported);
    }
    expect(calls, 0);
  });

  test(
    'missing native plugin reports unavailable but does not fake reads',
    () async {
      expect(await store.isAvailable(), isFalse);
      await expectLater(
        store.read('owner'),
        throwsA(isA<MissingPluginException>()),
      );
      await expectLater(
        store.write('owner', '{}'),
        throwsA(isA<MissingPluginException>()),
      );
      await store.clear('owner');
      await store.clearAll();
    },
  );

  test('availability errors remain actionable', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'storage_unavailable');
    });
    await expectLater(store.isAvailable(), throwsA(isA<PlatformException>()));
  });

  test('real native deletion failures remain actionable', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'capture_storage_failed');
    });
    await expectLater(store.clear('owner'), throwsA(isA<PlatformException>()));
    await expectLater(store.clearAll(), throwsA(isA<PlatformException>()));
  });

  test('passes exact owner and JSON and awaits native completion', () async {
    const payload = '{"version":1,"synthetic":"未保存"}';
    final started = Completer<void>();
    final completed = Completer<String>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'write');
      expect(call.arguments, {'owner': 'synthetic-owner', 'value': payload});
      started.complete();
      return completed.future;
    });
    var done = false;
    final saving = store.write('synthetic-owner', payload).then((value) {
      done = true;
      return value;
    });
    await started.future;
    expect(done, isFalse);
    completed.complete('2026-10-11T17:00:00.123Z');
    expect(await saving, DateTime.utc(2026, 10, 11, 17, 0, 0, 123));
  });

  test('rejects absent malformed and non-UTC completion receipts', () async {
    for (final receipt in [
      null,
      'invalid',
      '2026-10-11T17:00:00.000',
      '2026-02-31T17:00:00.000Z',
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => receipt);
      await expectLater(store.write('owner', '{}'), throwsStateError);
    }
  });

  test(
    'reads exact JSON without creating an empty journal for missing data',
    () async {
      const payload = '{"synthetic":true,"revisions":[]}';
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'read');
        expect(call.arguments, {'owner': 'owner'});
        return payload;
      });
      expect(await store.read('owner'), payload);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await store.read('owner'), isNull);
    },
  );

  test(
    'rejects invalid and oversized data received from native storage',
    () async {
      for (final payload in [
        '[]',
        'not-json',
        '{"value":"${'x' * ai1CaptureMaximumBytes}"}',
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => payload);
        await expectLater(store.read('owner'), throwsFormatException);
      }
    },
  );

  test(
    'bounds encoded bytes and requires an object before native writes',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return '2026-10-11T17:00:00.000Z';
      });
      for (final payload in [
        '[]',
        'null',
        'not-json',
        jsonEncode({'value': '☀' * (ai1CaptureMaximumBytes ~/ 3)}),
      ]) {
        await expectLater(store.write('owner', payload), throwsFormatException);
      }
      expect(calls, 0);
    },
  );

  test('accepts an object exactly at the byte limit', () async {
    final payload = '{"v":"${'x' * (ai1CaptureMaximumBytes - 8)}"}';
    expect(utf8.encode(payload).length, ai1CaptureMaximumBytes);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => '2026-10-11T17:00:00.000Z',
    );
    await store.write('owner', payload);
  });

  test(
    'validates owner before any operation can reach native storage',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });
      for (final owner in ['', '  ', 'x' * 201]) {
        await expectLater(store.read(owner), throwsFormatException);
        await expectLater(store.write(owner, '{}'), throwsFormatException);
        await expectLater(store.clear(owner), throwsFormatException);
      }
      expect(calls, 0);
    },
  );

  test(
    'clears only the requested owner or explicitly all capture storage',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await store.clear('synthetic-owner');
      await store.clearAll();
      expect(calls.map((call) => call.method), ['clear', 'clearAll']);
      expect(calls.first.arguments, {'owner': 'synthetic-owner'});
      expect(calls.last.arguments, isNull);
    },
  );
}
