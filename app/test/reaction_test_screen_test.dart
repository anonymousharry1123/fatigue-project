import 'dart:async';

import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/screens/reaction_test_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'privacy_test_support.dart';

class _TestStopwatch extends Stopwatch {
  int milliseconds = 0;
  bool running = false;

  @override
  bool get isRunning => running;
  @override
  int get elapsedMilliseconds => milliseconds;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
  @override
  void reset() => milliseconds = 0;
}

class _SaveAttempt {
  _SaveAttempt(this.average, this.resultId, this.observedAt);
  final double average;
  final String? resultId;
  final DateTime? observedAt;
  final completion = Completer<void>();
}

class _ReactionController extends AppController {
  _ReactionController() : super(initialPrivacyConsent: testAdultPrivacyConsent);

  final attempts = <_SaveAttempt>[];
  int revision = 0;
  double? baseline;

  @override
  double? get reactionBaseline => baseline;

  @override
  int get sessionRevision => revision;

  void changeAccount() {
    revision++;
    notifyListeners();
  }

  @override
  Future<void> addReactionResult(
    double averageMs, {
    String? note,
    String? resultId,
    DateTime? observedAt,
  }) {
    final attempt = _SaveAttempt(averageMs, resultId, observedAt);
    attempts.add(attempt);
    return attempt.completion.future;
  }
}

void main() {
  final panel = find.byKey(const Key('reaction-test-panel'));
  late _ReactionController controller;
  late _TestStopwatch stopwatch;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    controller = _ReactionController();
    stopwatch = _TestStopwatch();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  Future<void> mount(WidgetTester tester, {double textScale = 1}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: buildTonyoTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ReactionTestScreen(
            waitDuration: const Duration(seconds: 1),
            stopwatch: stopwatch,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> round(WidgetTester tester, {int milliseconds = 250}) async {
    await tester.tap(panel);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('TAP NOW'), findsOneWidget);
    expect(stopwatch.isRunning, isTrue);
    stopwatch.milliseconds = milliseconds;
    await tester.tap(panel);
    await tester.pump();
  }

  testWidgets('backgrounding a ready test discards all partial rounds', (
    tester,
  ) async {
    await mount(tester);
    await round(tester);
    await tester.tap(panel);
    await tester.pump(const Duration(seconds: 1));
    stopwatch.milliseconds = 200;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('TAP TO RESTART'), findsOneWidget);
    expect(find.text('1 valid round'), findsNothing);
    expect(stopwatch.isRunning, isFalse);
    expect(controller.attempts, isEmpty);

    await round(tester);
    await round(tester);
    expect(controller.attempts, isEmpty);
    await round(tester);
    expect(controller.attempts.single.average, 250);
    controller.attempts.single.completion.complete();
    await tester.pump();
    expect(find.text('TEST COMPLETE'), findsOneWidget);
  });

  testWidgets('cancelled timer cannot turn an interrupted test green', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(panel);
    await tester.pump(const Duration(milliseconds: 700));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(panel);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('WAIT FOR GREEN'), findsOneWidget);
    expect(stopwatch.isRunning, isFalse);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('TAP NOW'), findsOneWidget);
    expect(controller.attempts, isEmpty);
  });

  testWidgets('instructions and covering routes require a fresh test', (
    tester,
  ) async {
    await mount(tester);
    await round(tester);
    await tester.tap(find.byTooltip('Reaction test instructions'));
    await tester.pumpAndSettle();
    expect(stopwatch.isRunning, isFalse);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('TAP TO RESTART'), findsOneWidget);

    await tester.tap(panel);
    await tester.pump(const Duration(seconds: 1));
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Other page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(stopwatch.isRunning, isFalse);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('TAP TO RESTART'), findsOneWidget);
    expect(controller.attempts, isEmpty);
  });

  testWidgets(
    'a queued green-frame callback cannot resume an interrupted round',
    (tester) async {
      await mount(tester);
      await tester.tap(panel);
      tester.binding.addPostFrameCallback((_) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('TAP TO RESTART'), findsOneWidget);
      expect(stopwatch.isRunning, isFalse);
      expect(controller.attempts, isEmpty);
      await round(tester);
      expect(find.text('1 valid round'), findsOneWidget);
    },
  );

  testWidgets(
    'save waits, ignores repeated taps, and retries the same result',
    (tester) async {
      await mount(tester);
      await round(tester, milliseconds: 220);
      await round(tester, milliseconds: 250);
      await round(tester, milliseconds: 280);
      expect(find.text('SAVING RESULT'), findsOneWidget);
      expect(find.text('TEST COMPLETE'), findsNothing);
      await tester.tap(panel);
      await tester.tap(panel);
      expect(controller.attempts, hasLength(1));

      final first = controller.attempts.single;
      first.completion.completeError(StateError('Storage unavailable'));
      await tester.pump();
      expect(find.text('RETRY SAVING'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(panel);
      await tester.pump();
      expect(controller.attempts, hasLength(2));
      final retry = controller.attempts.last;
      expect(retry.resultId, isNotNull);
      expect(retry.resultId, first.resultId);
      expect(retry.observedAt, first.observedAt);
      expect(retry.average, 250);
      controller.baseline = 250;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      retry.completion.complete();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('TEST COMPLETE'), findsOneWidget);
      expect(find.text('Personal baseline'), findsNothing);
      expect(find.text('250'), findsOneWidget);
    },
  );

  testWidgets('account changes discard partial rounds and ignore old save', (
    tester,
  ) async {
    await mount(tester);
    await round(tester);
    controller.changeAccount();
    await tester.pump();
    expect(find.text('TAP TO RESTART'), findsOneWidget);
    expect(find.text('1 valid round'), findsNothing);

    await round(tester);
    await round(tester);
    await round(tester);
    final oldSave = controller.attempts.single;
    controller.changeAccount();
    await tester.pump();
    oldSave.completion.complete();
    await tester.pump();
    expect(find.text('TEST COMPLETE'), findsNothing);
    expect(find.text('TAP TO RESTART'), findsOneWidget);
    expect(find.text('3 valid rounds'), findsNothing);
  });

  testWidgets('leaving a waiting route cancels timers without saving', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(panel);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(controller.attempts, isEmpty);
    expect(stopwatch.isRunning, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'panel remains accessible at triple text size on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester, textScale: 3);
        expect(tester.getSemantics(panel).label, contains('TAP TO BEGIN'));
        await round(tester, milliseconds: 1500);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Reaction test instructions'));
        await tester.pumpAndSettle();
        expect(find.text('How it works'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
