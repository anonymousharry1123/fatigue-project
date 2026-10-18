import 'package:app/src/health_service.dart';
import 'package:app/src/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tonyo/health');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native Heart Rate payload stays distinct and uses requested read window',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return [
          for (final type in ['heartRate', 'hrv', 'restingHeartRate'])
            {
              'id': 'healthkit-$type-sample',
              'type': type,
              'value': 72.0,
              'timestamp': '2026-10-18T20:00:00.000Z',
              'source': 'healthKit',
              'quality': 1.0,
            },
        ];
      });
      const service = HealthService();
      final readings = await service.sync();
      expect(readings.map((reading) => reading.type), [
        SignalType.heartRate,
        SignalType.hrv,
        SignalType.restingHeartRate,
      ]);
      expect(readings.first.timestamp.toUtc(), DateTime.utc(2026, 10, 18, 20));
      expect(readings.first.type.unit, 'bpm');
      await service.sync(recentOnly: true);
      expect(calls.map((call) => call.method), ['sync', 'sync']);
      expect(calls.map((call) => call.arguments), [
        {'recentOnly': false},
        {'recentOnly': true},
      ]);
    },
  );
}
