import 'dart:async';

import 'package:app/src/app_controller.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/ml_prep_service.dart';
import 'package:app/src/screens/ml_prep_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This screen only consumes readiness. Real provenance, consent and training
/// validation are exercised independently by the builder/controller tests.
class _ScreenReport implements PrepReport {
  _ScreenReport({required this.energyReady});

  @override
  final bool energyReady;
  @override
  bool get cognitiveReady => false;
  @override
  List<TrainingExample> get examples => const [];
  @override
  Map<String, Object?> get identity => const {};

  @override
  Map<String, Object?> toJson() => {
    'readiness': {
      'energy': {
        'ready': energyReady,
        'reasons': energyReady ? [] : ['insufficient_genuine_labeled_days'],
      },
      'cognitive': {
        'ready': false,
        'reasons': ['report_only'],
      },
    },
  };
}

class _ScreenController extends AppController {
  final selectedWindow = PrepWindow.endingOn(
    DateTime(2026, 7, 31),
    timezone: 'UTC',
  );
  String? accountUid = 'screen-user';
  int revision = 0;
  bool ready = true;
  bool refreshing = false;
  String status = 'Deterministic Energy scoring active';
  String? blocker;
  int preparationCalls = 0;
  int trainingCalls = 0;
  PrepWindow? trainedWindow;
  Completer<void>? pendingTraining;

  @override
  String? get cloudUid => accountUid;
  @override
  String? get modelPreparationBlocker => null;
  @override
  int get modelPreparationRevision => revision;
  @override
  PrepWindow? get lastModelPreparationWindow => selectedWindow;
  @override
  bool get isRefreshingPersonalizedModel => refreshing;
  @override
  String get personalizedModelStatus => status;
  @override
  String? get personalizedModelBlocker => blocker;

  @override
  Future<PrepRun> prepareModelSnapshot({
    required PrepWindow window,
    bool refresh = false,
  }) async {
    preparationCalls++;
    return PrepRun(
      snapshot: PrepSnapshot(
        uid: accountUid!,
        window: window,
        consent: const PrepConsent(
          collection: true,
          trainingUse: true,
          version: 1,
        ),
        fetchedAt: DateTime.utc(2026, 8, 1),
        signals: [],
        checkIns: [],
        outcomes: [],
        schemaVersion: 11,
      ),
      report: _ScreenReport(energyReady: ready),
      cacheHit: true,
      collectionQueries: 0,
      metadataReads: 0,
      returnedDocuments: const {},
    );
  }

  @override
  Future<void> refreshPersonalizedModel({required PrepWindow window}) async {
    trainingCalls++;
    trainedWindow = window;
    refreshing = true;
    notifyListeners();
    try {
      await pendingTraining?.future;
      status = 'Personalized Energy model accepted';
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  void changeState() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const prepareKey = Key('prepare-model-snapshot');
  const refreshKey = Key('refresh-personalized-energy-model');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, _ScreenController controller) async {
    // Keep the long instructional and coverage content deterministic in tests.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTonyoTheme(),
        home: MlPrepScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> prepare(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(prepareKey));
    await tester.tap(find.byKey(prepareKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(refreshKey));
  }

  FilledButton refreshButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(refreshKey));

  testWidgets('opening and reopening the screen never prepares or trains', (
    tester,
  ) async {
    final controller = _ScreenController();
    await open(tester, controller);
    expect(controller.preparationCalls, 0);
    expect(controller.trainingCalls, 0);
    expect(refreshButton(tester).onPressed, isNull);
    expect(
      find.textContaining('14 genuine, consented labeled days'),
      findsOneWidget,
    );
    expect(find.textContaining('at least 5%'), findsOneWidget);
    expect(
      find.textContaining('Cognitive is not personalized'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await open(tester, controller);
    expect(controller.preparationCalls, 0);
    expect(controller.trainingCalls, 0);
    expect(refreshButton(tester).onPressed, isNull);
  });

  testWidgets('read-only preparation enables a separate explicit refresh', (
    tester,
  ) async {
    final controller = _ScreenController();
    await open(tester, controller);
    await prepare(tester);
    expect(controller.preparationCalls, 1);
    expect(controller.trainingCalls, 0);
    expect(refreshButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(refreshKey));
    await tester.pumpAndSettle();
    expect(controller.trainingCalls, 1);
    expect(
      controller.trainedWindow?.toJson(),
      controller.selectedWindow.toJson(),
    );
    expect(find.text('Personalized Energy model accepted'), findsOneWidget);
    expect(controller.preparationCalls, 1);
  });

  testWidgets('refresh blocks duplicate taps and all snapshot/window actions', (
    tester,
  ) async {
    final controller = _ScreenController()..pendingTraining = Completer<void>();
    await open(tester, controller);
    await prepare(tester);
    final action = refreshButton(tester).onPressed!;
    action();
    action();
    await tester.pump();

    expect(controller.trainingCalls, 1);
    expect(refreshButton(tester).onPressed, isNull);
    expect(
      tester.widget<FilledButton>(find.byKey(prepareKey)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('refresh-model-snapshot')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('prep-window-end')))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('prep-timezone'))).enabled,
      isFalse,
    );
    expect(find.text('Refreshing Energy model…'), findsOneWidget);

    controller.pendingTraining!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Personalized Energy model accepted'), findsOneWidget);
    expect(controller.trainingCalls, 1);
    expect(controller.preparationCalls, 1);
  });

  testWidgets('a snapshot without eligible Energy days cannot train', (
    tester,
  ) async {
    final controller = _ScreenController()..ready = false;
    await open(tester, controller);
    await prepare(tester);
    expect(refreshButton(tester).onPressed, isNull);
    expect(
      find.textContaining('not ready for Energy training'),
      findsOneWidget,
    );
    expect(controller.trainingCalls, 0);
  });

  testWidgets(
    'account changes and data revisions invalidate the refresh action',
    (tester) async {
      final controller = _ScreenController();
      await open(tester, controller);
      await prepare(tester);
      final oldAction = refreshButton(tester).onPressed!;
      controller.revision++;
      controller.changeState();
      oldAction();
      await tester.pumpAndSettle();
      expect(refreshButton(tester).onPressed, isNull);
      expect(controller.trainingCalls, 0);

      await prepare(tester);
      expect(refreshButton(tester).onPressed, isNotNull);
      controller.accountUid = 'other-user';
      controller.changeState();
      await tester.pumpAndSettle();
      expect(refreshButton(tester).onPressed, isNull);
      expect(controller.trainingCalls, 0);
    },
  );

  testWidgets('consent or daily/new-outcome blocker prevents model refresh', (
    tester,
  ) async {
    final controller = _ScreenController();
    await open(tester, controller);
    await prepare(tester);
    final oldAction = refreshButton(tester).onPressed!;
    controller.blocker = 'A new eligible outcome is required before refresh.';
    controller.changeState();
    oldAction();
    await tester.pumpAndSettle();
    expect(refreshButton(tester).onPressed, isNull);
    expect(find.text(controller.blocker!), findsOneWidget);
    expect(controller.trainingCalls, 0);
  });

  testWidgets('editing the selected window requires a new inspection', (
    tester,
  ) async {
    final controller = _ScreenController();
    await open(tester, controller);
    await prepare(tester);
    await tester.enterText(
      find.byKey(const Key('prep-timezone')),
      'Europe/London',
    );
    await tester.pumpAndSettle();
    expect(refreshButton(tester).onPressed, isNull);
    expect(controller.trainingCalls, 0);
    expect(controller.preparationCalls, 1);
  });

  testWidgets('failed refresh shows a safe error and restores controls', (
    tester,
  ) async {
    final controller = _ScreenController()..pendingTraining = Completer<void>();
    await open(tester, controller);
    await prepare(tester);
    await tester.tap(find.byKey(refreshKey));
    await tester.pump();
    controller.pendingTraining!.completeError(
      StateError('private account or database detail'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be refreshed'), findsOneWidget);
    expect(
      find.textContaining('private account or database detail'),
      findsNothing,
    );
    expect(refreshButton(tester).onPressed, isNotNull);
    expect(controller.trainingCalls, 1);
    expect(controller.preparationCalls, 1);
  });
}
