import 'dart:async';

import 'package:app/src/notification_service.dart';
import 'package:app/src/timezone_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('serialized local notification delivery', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late Map<int, Map<String, Object?>> pending;
    late Set<int> failedIds;
    late LocalNotificationService service;
    Completer<void>? initializeGate;
    Completer<void>? initializeStarted;
    Completer<void>? scheduleGate;
    Completer<void>? scheduleStarted;
    Map<String, Object?>? launchDetails;

    GuidanceNotification reminder(
      int id, {
      GuidanceNotificationKind kind = GuidanceNotificationKind.coachPlan,
    }) => GuidanceNotification(
      id: 'reminder-$id',
      platformId: id,
      kind: kind,
      scheduledAt: DateTime.utc(2030, 11, 3, 5, 30),
      title: 'Focus block',
      body: '35 min · Open Coach for your daily plan.',
      sourceRecommendationId: kind == GuidanceNotificationKind.coachPlan
          ? 'plan-$id'
          : null,
    );

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      calls = [];
      pending = {
        99: {
          'id': 99,
          'title': 'Other app feature',
          'body': 'Unrelated',
          'payload': 'unrelated:keep',
        },
      };
      failedIds = {};
      initializeGate = null;
      initializeStarted = null;
      scheduleGate = null;
      scheduleStarted = null;
      launchDetails = null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'initialize':
            initializeStarted?.complete();
            initializeStarted = null;
            final gate = initializeGate;
            initializeGate = null;
            if (gate != null) await gate.future;
            return true;
          case 'areNotificationsEnabled':
            return true;
          case 'getNotificationAppLaunchDetails':
            return launchDetails;
          case 'pendingNotificationRequests':
            return pending.values.toList();
          case 'cancel':
            pending.remove((call.arguments as Map)['id']);
            return null;
          case 'zonedSchedule':
            final arguments = Map<String, Object?>.from(call.arguments as Map);
            final gate = scheduleGate;
            scheduleGate = null;
            scheduleStarted?.complete();
            scheduleStarted = null;
            if (gate != null) await gate.future;
            final id = arguments['id']! as int;
            if (failedIds.contains(id)) {
              throw PlatformException(
                code: 'schedule-failed',
                message: 'Native scheduling failed',
              );
            }
            pending[id] = {
              for (final field in ['id', 'title', 'body', 'payload'])
                field: arguments[field],
            };
            return null;
          default:
            return null;
        }
      });
      service = LocalNotificationService();
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'an idle service can run native work outside its creation zone',
      (tester) async {
        try {
          final createdInWidgetZone = LocalNotificationService();
          await tester.runAsync(() async {
            await createdInWidgetZone
                .reconcile([reminder(1)])
                .timeout(const Duration(seconds: 2));
            await createdInWidgetZone.cancelGuidance().timeout(
              const Duration(seconds: 2),
            );
          });
          expect(pending.keys, [99]);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test(
      'latest plan wins after older scheduling and cancellation finish',
      () async {
        final gate = scheduleGate = Completer<void>();
        final started = scheduleStarted = Completer<void>();
        final older = service.reconcile([reminder(1)]);
        await started.future;
        final cancel = service.cancelGuidance();
        final desired = [reminder(2)];
        final newest = service.reconcile(desired);
        desired.clear(); // The queued plan owns an immutable snapshot.
        gate.complete();
        await Future.wait([older, cancel, newest]);
        expect(pending.keys.toSet(), {99, 2});
        expect(pending[99]!['payload'], 'unrelated:keep');
        expect(pending[2]!['payload'], 'tonyo-guidance:coach:plan-2');
        expect(
          calls.where((call) => call.method == 'initialize'),
          hasLength(1),
        );
      },
    );

    test(
      'disabling reminders waits for and cancels an issued older schedule',
      () async {
        final gate = scheduleGate = Completer<void>();
        final started = scheduleStarted = Completer<void>();
        final old = service.reconcile([reminder(1), reminder(2)]);
        await started.future;
        final cancel = service.cancelGuidance();
        gate.complete();
        await Future.wait([old, cancel]);
        expect(pending.keys, [99]);
      },
    );

    test(
      'partial native failure cleans the plan and does not poison later retries',
      () async {
        failedIds.add(2);
        await expectLater(
          service.reconcile([reminder(1), reminder(2)]),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'schedule-failed',
            ),
          ),
        );
        expect(pending.keys, [99]);
        await service.reconcile([reminder(3)]);
        expect(pending.keys.toSet(), {99, 3});
      },
    );

    test(
      'does not overwrite unrelated notifications even if an ID collides',
      () async {
        await expectLater(service.reconcile([reminder(99)]), throwsStateError);
        expect(pending.keys, [99]);
        expect(pending[99]!['payload'], 'unrelated:keep');
        expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
      },
    );

    test(
      'rejects duplicate platform IDs before replacing the existing plan',
      () async {
        await service.reconcile([reminder(1)]);
        await expectLater(
          service.reconcile([reminder(2), reminder(2)]),
          throwsArgumentError,
        );
        expect(pending.keys.toSet(), {99, 1});
      },
    );

    test(
      'Coach scheduling is one-shot UTC with a separate channel and source route',
      () async {
        await service.reconcile([reminder(1)]);
        final arguments =
            calls
                    .singleWhere((call) => call.method == 'zonedSchedule')
                    .arguments
                as Map;
        expect(arguments['timeZoneName'], timezone.UTC.name);
        expect(arguments.containsKey('matchDateTimeComponents'), false);
        expect(arguments['payload'], 'tonyo-guidance:coach:plan-1');
        expect(
          (arguments['platformSpecifics'] as Map)['channelId'],
          'tonyo_coach_plan',
        );
      },
    );

    test(
      'permission and response initialization share one native initialization',
      () async {
        final gate = initializeGate = Completer<void>();
        final started = initializeStarted = Completer<void>();
        final permission = service.permissionStatus();
        await started.future;
        final responses = service.initializeResponses((_) {});
        gate.complete();
        await Future.wait<Object?>([permission, responses]);
        expect(
          calls.where((call) => call.method == 'initialize'),
          hasLength(1),
        );
        expect(
          calls.where(
            (call) => call.method == 'getNotificationAppLaunchDetails',
          ),
          hasLength(1),
        );
        expect(calls.where((call) => call.method.contains('request')), isEmpty);
      },
    );

    test(
      'cold launch is delivered once and warm taps route after permission-first initialization',
      () async {
        launchDetails = {
          'notificationLaunchedApp': true,
          'notificationResponse': {
            'notificationId': 1,
            'notificationResponseType': 0,
            'payload': 'tonyo-guidance:coach:cold',
          },
        };
        await service.permissionStatus();
        expect(
          calls.where(
            (call) => call.method == 'getNotificationAppLaunchDetails',
          ),
          isEmpty,
        );
        final first = <String>[];
        await service.initializeResponses(first.add);
        expect(first, ['tonyo-guidance:coach:cold']);
        final second = <String>[];
        await service.initializeResponses(second.add);
        expect(second, isEmpty);
        final delivered = Completer<void>();
        ServicesBinding.instance.channelBuffers.push(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('didReceiveNotificationResponse', {
              'notificationId': 2,
              'notificationResponseType': 0,
              'payload': 'tonyo-guidance:coach:warm',
            }),
          ),
          (_) => delivered.complete(),
        );
        await delivered.future;
        expect(second, ['tonyo-guidance:coach:warm']);
        expect(
          calls.where(
            (call) => call.method == 'getNotificationAppLaunchDetails',
          ),
          hasLength(1),
        );
      },
    );
  });

  testWidgets('unsupported cancellation does not depend on its creation zone', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final service = LocalNotificationService();
      expect(service.supportsScheduling, false);
      await tester.runAsync(() async {
        await service.cancelGuidance().timeout(const Duration(seconds: 2));
        await service.reconcile([]).timeout(const Duration(seconds: 2));
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

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
