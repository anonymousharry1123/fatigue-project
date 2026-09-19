import 'package:app/src/notification_service.dart';
import 'package:app/src/timezone_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'one-shot guidance preserves both instants in a repeated DST hour',
    () async {
      initializeTimezoneDatabase();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'initialize' => true,
          'pendingNotificationRequests' => <Map<String, Object>>[],
          _ => null,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });

      final newYork = timezone.getLocation('America/New_York');
      final instants = [
        DateTime.utc(2030, 11, 3, 5, 30),
        DateTime.utc(2030, 11, 3, 6, 30),
      ];
      final local = instants
          .map((time) => timezone.TZDateTime.from(time, newYork))
          .toList();
      expect(local.map((time) => time.hour), everyElement(1));
      await LocalNotificationService().reconcile([
        for (var index = 0; index < local.length; index++)
          GuidanceNotification(
            id: 'dst-$index',
            platformId: index + 1,
            kind: GuidanceNotificationKind.recovery,
            scheduledAt: local[index],
            title: 'Recovery',
            body: 'Test',
          ),
      ]);

      final scheduled = calls
          .where((call) => call.method == 'zonedSchedule')
          .toList();
      expect(scheduled.length, 2);
      for (var index = 0; index < scheduled.length; index++) {
        final arguments = scheduled[index].arguments as Map;
        expect(arguments['timeZoneName'], timezone.UTC.name);
        expect(
          DateTime.parse(arguments['scheduledDateTimeISO8601'] as String),
          instants[index],
        );
      }
    },
  );
}
