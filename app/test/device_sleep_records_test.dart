import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/daily_history_logic.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/screens/daily_checkin_screen.dart';
import 'package:app/src/screens/daily_history_screen.dart';
import 'package:app/src/screens/sleep_log_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 10, 4, 21);
  const healthId = 'healthkit-sleep-2026-10-04';
  AppController controller() => AppController(
    initialPrivacyConsent: testAdultPrivacyConsent,
    clock: () => now,
  )..isReady = true;

  test('preferred Health sleep and naps are records without copying IDs', () {
    final app = controller();
    addTearDown(app.dispose);
    app.signals.addAll([
      ..._night(healthId, now, duration: 7.5, staged: 7.5),
      SignalReading(
        id: 'healthkit-nap-1-duration',
        groupId: 'healthkit-nap-1',
        type: SignalType.nap,
        value: .5,
        timestamp: DateTime(2026, 10, 4, 15),
        source: SignalSource.healthKit,
      ),
    ]);
    final originalIds = app.signals.map((s) => s.id).toSet();
    final logs = app.sleepLogs;
    expect(logs, hasLength(2));
    expect(logs.first.id, 'healthkit-nap-1');
    expect(logs.first.isNap, isTrue);
    expect(logs.first.bedtime, DateTime(2026, 10, 4, 14, 30));
    final main = logs.last;
    expect(main.id, healthId);
    expect(main.source, SignalSource.healthKit);
    expect(main.durationHours, 7.5); // Excludes awake time, unlike the span.
    expect(main.wakeTime.difference(main.bedtime).inHours, 8);
    expect(app.signals.map((s) => s.id).toSet(), originalIds);
    final history = app.dailyHistory.single;
    expect(history.items, hasLength(2));
    expect(
      history.items.every((s) => s.kind == DailyHistoryItemKind.sleep),
      isTrue,
    );
    expect(
      history.items.every((s) => !s.isManual && s.canEdit && s.canDelete),
      isTrue,
    );
    expect(history.isCompleted(DailyCompletionCategory.sleep), isTrue);
  });

  test(
    'records follow the existing duration and detailed-stage preference gate',
    () async {
      final app = controller();
      addTearDown(app.dispose);
      await app.addSleep(
        id: 'sleep-manual',
        bedtime: DateTime(2026, 10, 3, 23),
        wakeTime: DateTime(2026, 10, 4, 7),
        quality: 3,
      );
      for (final scenario in [
        (hours: 7.0, stages: 2.0, selected: 'sleep-manual'),
        (hours: 6.0, stages: 6.0, selected: 'sleep-manual'),
        (hours: 7.0, stages: 4.0, selected: healthId),
      ]) {
        app.signals.removeWhere((s) => s.groupId == healthId);
        app.signals.addAll(
          _night(
            healthId,
            now,
            duration: scenario.hours,
            staged: scenario.stages,
          ),
        );
        expect(app.sleepLogs.single.id, scenario.selected);
        expect(app.dailyHistory.single.items.single.id, scenario.selected);
      }
    },
  );

  test(
    'stage-only and incomplete Health groups do not become empty sleep logs',
    () {
      final app = controller();
      addTearDown(app.dispose);
      app.signals.addAll([
        ..._night(
          healthId,
          now,
          duration: 7,
          staged: 7,
        ).where((s) => s.type != SignalType.sleep),
        SignalReading(
          id: 'healthkit-sleep-incomplete-duration',
          groupId: 'healthkit-sleep-incomplete',
          type: SignalType.sleep,
          value: 8,
          timestamp: DateTime(2026, 10, 3, 7),
          source: SignalSource.healthKit,
        ),
      ]);
      expect(app.sleepLogs, isEmpty);
      expect(app.dailyHistory, isEmpty);
    },
  );

  test(
    'review correction preserves device group and uses a stable manual ID',
    () async {
      final app = controller();
      addTearDown(app.dispose);
      app.signals.addAll(_night(healthId, now, duration: 7.5, staged: 7));
      final before = app.signals.map((s) => s.toJson()).toList();
      for (var attempt = 0; attempt < 2; attempt++) {
        await app.addSleep(
          id: healthId,
          bedtime: DateTime(2026, 10, 3, 23),
          wakeTime: DateTime(2026, 10, 4, 7),
          quality: 3,
        );
      }
      expect(
        app.signals.where((s) => s.groupId == healthId).map((s) => s.toJson()),
        before,
      );
      final correction = app.signals.where(
        (s) => s.groupId == 'sleep-correction-$healthId',
      );
      expect(correction, hasLength(2));
      expect(correction.every((s) => s.source == SignalSource.manual), isTrue);
      expect(
        app.sleepLogs.single.id,
        healthId,
      ); // Complete device staging still wins.
      await app.deleteSleepLog(healthId);
      expect(app.signals.any((s) => s.groupId == healthId), isFalse);
      expect(app.sleepLogs.single.id, 'sleep-correction-$healthId');
    },
  );

  test(
    'deleting Health nap removes its group without touching the main sleep',
    () async {
      final app = controller();
      addTearDown(app.dispose);
      app.signals.addAll([
        ..._night(healthId, now, duration: 7.5, staged: 7.5),
        SignalReading(
          id: 'healthkit-nap-1-duration',
          groupId: 'healthkit-nap-1',
          type: SignalType.nap,
          value: .5,
          timestamp: DateTime(2026, 10, 4, 15),
          source: SignalSource.healthKit,
        ),
      ]);
      await app.deleteSleepLog('healthkit-nap-1');
      expect(app.sleepLogs.single.id, healthId);
      expect(app.signals.where((s) => s.groupId == healthId), hasLength(4));
    },
  );

  testWidgets('evening card shows device sleep and opens its recorded times', (
    tester,
  ) async {
    final app = controller();
    addTearDown(app.dispose);
    app.signals.addAll(_night(healthId, now, duration: 7.5, staged: 7.5));
    await tester.pumpWidget(
      _screen(
        app,
        const DailyCheckInScreen(initialPeriod: CheckInPeriod.evening),
      ),
    );
    expect(find.text('7h 30m · Apple Health · Saved'), findsOneWidget);
    expect(find.text('Review sleep'), findsOneWidget);
    expect(find.text('Log or review sleep'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('checkin-log-sleep')));
    await tester.tap(find.byKey(const Key('checkin-log-sleep')));
    await tester.pumpAndSettle();
    final screen = tester.widget<SleepLogScreen>(find.byType(SleepLogScreen));
    expect(screen.initialLog!.id, healthId);
    expect(screen.initialLog!.bedtime, DateTime(2026, 10, 3, 23));
    expect(screen.initialLog!.wakeTime, DateTime(2026, 10, 4, 7));
    expect(find.byKey(const Key('review-health-sleep')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale or future device sleep never seeds an evening check-in', (
    tester,
  ) async {
    for (final day in [DateTime(2026, 10, 3), DateTime(2026, 10, 5)]) {
      final app = controller();
      app.signals.addAll(_night(healthId, day, duration: 7.5, staged: 7.5));
      await tester.pumpWidget(
        _screen(
          app,
          const DailyCheckInScreen(initialPeriod: CheckInPeriod.evening),
        ),
      );
      expect(find.byKey(const Key('evening-sleep-record')), findsNothing);
      expect(find.text('Log or review sleep'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    }
  });

  testWidgets(
    'daily history reviews and deletes the whole Health sleep group',
    (tester) async {
      final app = controller();
      addTearDown(app.dispose);
      app.signals.addAll(_night(healthId, now, duration: 7.5, staged: 7.5));
      await tester.pumpWidget(_screen(app, const DailyHistoryScreen()));
      expect(find.text('Main sleep'), findsOneWidget);
      expect(find.byTooltip('Review Main sleep'), findsOneWidget);
      await tester.tap(find.byTooltip('Review Main sleep'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SleepLogScreen>(find.byType(SleepLogScreen))
            .initialLog!
            .id,
        healthId,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete Main sleep'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The original stays in Apple Health'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(app.signals, isEmpty);
      expect(app.dailyHistory, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test('new sleep review copy is authored in every supported language', () {
    for (final language in ['es', 'zh-Hans', 'zh-Hant']) {
      final localization = AppLocalizations(language);
      for (final source in [
        'Review sleep',
        'Review nap',
        'Review {item}',
        '{duration} · {source} · Saved',
        '{hours}h {minutes}m',
        'Your main sleep is already logged. Review it if needed. Sleep and Energy are saved separately.',
        'Device sleep excludes awake time. Saving these times creates a manual correction; imported sleep stages stay available.',
        'This removes the sleep record and its stages from Tonyo. The original stays in Apple Health and may be imported again on a later sync.',
      ]) {
        expect(
          localization.text(source),
          isNot(source),
          reason: '$language: $source',
        );
      }
    }
  });
}

Widget _screen(AppController controller, Widget child) => AppScope(
  controller: controller,
  child: MaterialApp(theme: buildTonyoTheme(), home: child),
);

List<SignalReading> _night(
  String groupId,
  DateTime day, {
  required double duration,
  required double staged,
}) {
  final wake = DateTime(day.year, day.month, day.day, 7);
  return [
    SignalReading(
      id: '$groupId-duration',
      groupId: groupId,
      type: SignalType.sleep,
      value: duration,
      timestamp: wake,
      source: SignalSource.healthKit,
    ),
    SignalReading(
      id: '$groupId-bedtime',
      groupId: groupId,
      type: SignalType.bedtime,
      value: 23,
      timestamp: DateTime(day.year, day.month, day.day - 1, 23),
      source: SignalSource.healthKit,
    ),
    SignalReading(
      id: '$groupId-sleepCore',
      groupId: groupId,
      type: SignalType.sleepCore,
      value: staged,
      timestamp: wake,
      source: SignalSource.healthKit,
    ),
    SignalReading(
      id: '$groupId-sleepAwake',
      groupId: groupId,
      type: SignalType.sleepAwake,
      value: 8 - duration,
      timestamp: wake,
      source: SignalSource.healthKit,
    ),
  ];
}
