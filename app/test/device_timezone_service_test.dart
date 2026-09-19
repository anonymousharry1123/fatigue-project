import 'package:app/src/device_timezone_service.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'detects regional travel even when both zones have the same offset',
    () async {
      var identifier = 'Europe/London';
      final service = DeviceTimezoneService(
        readIdentifier: () async => identifier,
        clock: () => DateTime.utc(2026, 7, 1),
      );
      expect(await service.refresh(), isTrue);
      expect(service.identifier, 'Europe/London');
      expect(service.utcOffset, const Duration(hours: 1));
      expect(await service.refresh(), isFalse);
      identifier = 'Africa/Lagos';
      expect(await service.refresh(), isTrue);
      expect(service.utcOffset, const Duration(hours: 1));
      expect(service.identifier, 'Africa/Lagos');
    },
  );

  test('detects DST changes without a region change', () async {
    var now = DateTime.utc(2026, 3, 8, 6, 30);
    final service = DeviceTimezoneService(
      readIdentifier: () async => 'America/New_York',
      clock: () => now,
    );
    await service.refresh();
    expect(service.localTime(now).hour, 1);
    expect(service.utcOffset, const Duration(hours: -5));
    now = now.add(const Duration(hours: 1));
    expect(await service.refresh(), isTrue);
    expect(service.localTime(now).hour, 3);
    expect(service.utcOffset, const Duration(hours: -4));
  });

  test(
    'supports fractional offsets and OS aliases in historical prep',
    () async {
      final service = DeviceTimezoneService(
        readIdentifier: () async => 'Asia/Calcutta',
        clock: () => DateTime.utc(2026, 7, 1),
      );
      await service.refresh();
      expect(service.utcOffset, const Duration(hours: 5, minutes: 30));
      expect(service.label, 'Asia/Calcutta · UTC+05:30');
      final window = PrepWindow.endingOn(
        DateTime(2026, 7, 1),
        timezone: service.identifier!,
      );
      expect(window.start, DateTime.utc(2026, 6, 1, 18, 30));
    },
  );

  test(
    'unknown regions and read errors retain the local clock without guessing',
    () async {
      var fails = false;
      final service = DeviceTimezoneService(
        readIdentifier: () async {
          if (fails) throw PlatformException(code: 'unavailable');
          return 'Not/A_Region';
        },
      );
      await service.refresh();
      expect(service.identifier, isNull);
      final instant = DateTime.utc(2026, 7, 1, 18);
      expect(service.localTime(instant), instant.toLocal());
      fails = true;
      expect(await service.refresh(), isFalse);
      expect(service.identifier, isNull);
    },
  );

  test('reads an IANA name from the native bridge', () async {
    const channel = MethodChannel('tonyo/timezone');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getTimezone');
      return 'Pacific/Auckland';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = DeviceTimezoneService();
    await service.refresh();
    expect(service.identifier, 'Pacific/Auckland');
  });

  test('unsupported hosts do not silently use a US region or UTC', () async {
    final service = DeviceTimezoneService();
    await service.refresh();
    expect(service.identifier, isNull);
    expect(service.label, startsWith('Device local time'));
  });
}
