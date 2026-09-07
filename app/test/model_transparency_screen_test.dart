import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/energy_model_summary.dart';
import 'package:app/src/ml_prep_builder.dart';
import 'package:app/src/ml_prep_models.dart';
import 'package:app/src/ml_prep_service.dart';
import 'package:app/src/model_transparency_state.dart';
import 'package:app/src/models.dart';
import 'package:app/src/score_explanation.dart';
import 'package:app/src/screens/model_transparency_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

final _now = DateTime.utc(2026, 9, 7, 17);

ScoreSnapshot _score({bool legacy = false, bool empty = false}) =>
    ScoreSnapshot(
      energy: 72,
      cognitive: 64,
      confidence: .68,
      cognitiveConfidence: .44,
      inputCount: empty ? 0 : 5,
      cognitiveInputCount: 2,
      freshness: legacy ? null : .8,
      cognitiveFreshness: legacy ? null : .6,
      hasCognitiveScore: !legacy,
      calculatedAt: legacy ? null : _now.subtract(const Duration(hours: 2)),
      energyModelVersion: legacy ? null : 'energy-v2',
      cognitiveModelVersion: legacy ? null : 'cognitive-v2',
      drivers: legacy || empty
          ? const []
          : [
              ScoreDriver(
                'Hydration',
                2,
                '1.8 L logged today',
                explanation:
                    'Saved hydration explanation, not a new calculation.',
                source: SignalSource.manual,
                evidenceSources: const [SignalSource.manual],
                containsDemoEvidence: false,
                freshness: .7,
                evidenceAt: _now.subtract(const Duration(hours: 3)),
              ),
              ScoreDriver(
                'Sleep',
                -12,
                '6.2 hours in the selected night',
                explanation:
                    'The stored sleep adjustment reflects the model’s '
                    'sleep target and freshness at calculation.',
                source: SignalSource.healthKit,
                evidenceSources: const [SignalSource.healthKit],
                containsDemoEvidence: false,
                freshness: .9,
                evidenceAt: _now.subtract(const Duration(hours: 5)),
              ),
              const ScoreDriver(
                'Caffeine',
                -4,
                'Synthetic fixture caffeine detail',
                source: SignalSource.manual,
                evidenceSources: [SignalSource.manual],
                containsDemoEvidence: true,
              ),
              const ScoreDriver(
                'Mood',
                0,
                'Legacy source with unknown provenance',
                source: SignalSource.manual,
              ),
              const ScoreDriver(
                'Personalized Energy adjustment',
                1,
                'On-device correction',
                source: SignalSource.model,
              ),
            ],
      cognitiveDrivers: legacy
          ? const []
          : const [
              ScoreDriver(
                'Reaction time',
                -6,
                'Cognitive-only saved detail',
                source: SignalSource.manual,
                evidenceSources: [SignalSource.manual],
                containsDemoEvidence: false,
              ),
            ],
    );

EnergyModelSummary _summary() => EnergyModelSummary.tryParse({
  'modelVersion': 1,
  'schemaVersion': 1,
  'window': PrepWindow.endingOn(DateTime(2026, 9, 5), timezone: 'UTC').toJson(),
  'trainedAt': DateTime.utc(2026, 9, 6, 8).toIso8601String(),
  'labelCount': 22,
  'holdoutMae': 6.4,
  'deterministicMae': 8.1,
  'featureCoverage': {
    for (final key in MlPrepBuilder.energyFeatureNames) key: .9,
  },
})!;

class _GuideController extends AppController {
  _GuideController(this.state)
    : super(initialPrivacyConsent: testAdultPrivacyConsent) {
    isReady = true;
    onboardingComplete = true;
  }

  ModelTransparencyState state;
  int dataActions = 0;

  @override
  ModelTransparencyState get modelTransparency => state;
  @override
  ScoreSnapshot get score => state.snapshot;

  @override
  Future<PrepRun> prepareModelSnapshot({
    required PrepWindow window,
    bool refresh = false,
  }) async {
    dataActions++;
    throw StateError('Transparency must not prepare data');
  }

  @override
  Future<void> refreshPersonalizedModel({required PrepWindow window}) async {
    dataActions++;
  }

  @override
  Future<void> refreshScores({
    DateTime? day,
    bool notify = true,
    bool forceRecalculate = false,
  }) async {
    dataActions++;
  }

  void changeState(ModelTransparencyState next) {
    state = next;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _GuideController controller({bool legacy = false, bool empty = false}) =>
      _GuideController(
        ModelTransparencyState(
          snapshot: _score(legacy: legacy, empty: empty),
          viewedAt: _now,
        ),
      );

  Future<void> open(
    WidgetTester tester,
    _GuideController controller, {
    Size size = const Size(430, 1000),
    double textScale = 1,
    ScoreHead initialHead = ScoreHead.energy,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTonyoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ModelTransparencyScreen(
          controller: controller,
          initialHead: initialHead,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.descendant(
        of: find.byKey(const Key('model-transparency-scroll')),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 100,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opening and switching heads uses saved scores without actions', (
    tester,
  ) async {
    final owner = controller();
    await open(tester, owner);
    expect(find.text('72'), findsOneWidget);
    expect(find.text('Standard scoring on this device'), findsOneWidget);
    expect(find.text('energy-v2'), findsOneWidget);
    expect(find.textContaining(', 2026'), findsWidgets);
    await show(tester, find.byKey(const Key('transparency-confidence')));
    expect(find.text('68% confidence'), findsOneWidget);
    expect(find.textContaining('not the probability'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('model-transparency-scroll')),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transparency-head-cognitive')));
    await tester.pumpAndSettle();
    expect(find.text('64'), findsOneWidget);
    await show(tester, find.byKey(const Key('transparency-confidence')));
    expect(find.text('44% confidence'), findsOneWidget);
    await show(tester, find.byKey(const Key('transparency-driver-0')));
    expect(
      find.descendant(
        of: find.byKey(const Key('transparency-driver-0')),
        matching: find.text('Reaction time'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('transparency-driver-1')), findsNothing);
    expect(owner.dataActions, 0);
  });

  testWidgets('drivers retain exact details, ranked impact, and all entries', (
    tester,
  ) async {
    final owner = controller();
    await open(tester, owner);
    await show(tester, find.byKey(const Key('transparency-driver-0')));
    final first = tester.widget<ExpansionTile>(
      find.byKey(const Key('transparency-driver-0')),
    );
    expect((first.title as Text).data, 'Sleep');
    expect(find.text('−12 points'), findsOneWidget);
    await tester.tap(find.byKey(const Key('transparency-driver-0')));
    await tester.pumpAndSettle();
    expect(find.text('6.2 hours in the selected night'), findsOneWidget);
    expect(find.textContaining('The stored sleep adjustment'), findsOneWidget);
    await show(tester, find.text('Evidence observed').first);
    expect(find.textContaining('Apple Health'), findsWidgets);
    await show(tester, find.byKey(const Key('transparency-driver-4')));
    expect(find.text('0 points · neutral'), findsOneWidget);
    expect(owner.dataActions, 0);
  });

  testWidgets('inventory labels measured, manual, demo, unknown and missing', (
    tester,
  ) async {
    await open(tester, controller());
    await show(tester, find.byKey(const Key('transparency-input-inventory')));
    expect(find.text('Measured / imported'), findsWidgets);
    expect(find.text('Self-reported / app entry'), findsWidgets);
    expect(find.text('Demo / synthetic'), findsWidgets);
    expect(find.text('Unverified / mixed'), findsWidgets);
    expect(find.text('Missing'), findsWidgets);
    expect(find.textContaining('Missing does not mean zero'), findsWidgets);
  });

  testWidgets('legacy Cognitive remains absent, not a zero score', (
    tester,
  ) async {
    await open(
      tester,
      controller(legacy: true),
      initialHead: ScoreHead.cognitive,
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Not recorded in this saved snapshot'), findsOneWidget);
    expect(find.text('20% confidence'), findsNothing);
    expect(
      find.textContaining('Score calculated: Not recorded'),
      findsOneWidget,
    );
    await show(tester, find.byKey(const Key('transparency-no-drivers')));
    expect(
      find.textContaining('cannot be reconstructed reliably'),
      findsOneWidget,
    );
    await show(tester, find.byKey(const Key('transparency-model-details')));
    expect(find.text('No Cognitive score recorded'), findsOneWidget);
  });

  testWidgets('empty local model state is explicit without invented metadata', (
    tester,
  ) async {
    final owner = controller(empty: true);
    await open(tester, owner);
    await show(tester, find.byKey(const Key('transparency-no-drivers')));
    expect(find.textContaining('No factor details were saved'), findsOneWidget);
    await show(tester, find.byKey(const Key('transparency-model-details')));
    expect(find.text('Standard scoring on this device'), findsOneWidget);
    expect(find.textContaining('No usable personalized model'), findsOneWidget);
    expect(find.text('Not loaded'), findsOneWidget);
    expect(find.textContaining('No valid summary loaded'), findsOneWidget);
    expect(owner.dataActions, 0);
  });

  testWidgets(
    'Firebase summary cannot present itself as an active local model',
    (tester) async {
      final owner = _GuideController(
        ModelTransparencyState(
          snapshot: _score(),
          viewedAt: _now,
          signedIn: true,
          consentEnabled: true,
          offline: true,
          scoreFromCloud: true,
          cloudModel: _summary(),
          metadataFetchedAt: _now.subtract(const Duration(hours: 1)),
          accountUpdatedAt: _now.subtract(const Duration(days: 1)),
        ),
      );
      await open(tester, owner);
      expect(find.text('Saved Firebase score'), findsOneWidget);
      await show(tester, find.textContaining('Cloud sync is unavailable'));
      await show(tester, find.byKey(const Key('transparency-cloud-model')));
      expect(find.byKey(const Key('transparency-local-model')), findsNothing);
      expect(find.textContaining('Summary only'), findsOneWidget);
      expect(find.text('Model trained'), findsOneWidget);
      expect(find.text('Aug 7, 2026 – Sep 5, 2026 (Etc/UTC)'), findsOneWidget);
      expect(find.textContaining('21.0% lower error'), findsOneWidget);
      expect(
        find.textContaining('6.4 points, compared with 8.1'),
        findsOneWidget,
      );
      expect(owner.dataActions, 0);
    },
  );

  testWidgets(
    'controller changes update the screen and sign-out hides evidence',
    (tester) async {
      final owner = controller();
      await open(tester, owner);
      owner.changeState(
        ModelTransparencyState(
          snapshot: _score().withEnergyCorrection(5, 'energy-ridge-v1'),
          viewedAt: _now,
          signedIn: true,
          consentEnabled: true,
          localModel: _summary(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('77'), findsOneWidget);
      owner.isSignedOut = true;
      owner.changeState(owner.state);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transparency-signed-out')), findsOneWidget);
      expect(find.text('77'), findsNothing);
      expect(
        find.byKey(const Key('transparency-score-overview')),
        findsNothing,
      );
    },
  );

  testWidgets('320px and 2x text: complete guide and expanded details fit', (
    tester,
  ) async {
    final owner = _GuideController(
      ModelTransparencyState(
        snapshot: _score().withEnergyCorrection(5, 'energy-ridge-v1'),
        viewedAt: _now,
        signedIn: true,
        consentEnabled: true,
        localModel: _summary(),
        cloudModel: _summary(),
        metadataFetchedAt: _now,
      ),
    );
    await open(tester, owner, size: const Size(320, 844), textScale: 2);
    expect(tester.takeException(), isNull);
    await show(tester, find.byKey(const Key('transparency-driver-0')));
    await tester.tap(find.byKey(const Key('transparency-driver-0')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await show(tester, find.byKey(const Key('transparency-input-inventory')));
    expect(tester.takeException(), isNull);
    await show(tester, find.byKey(const Key('transparency-model-details')));
    expect(tester.takeException(), isNull);
    await show(tester, find.textContaining('This page only explains'));
    expect(tester.takeException(), isNull);
    expect(owner.dataActions, 0);
  });

  testWidgets('Today and Profile both open the read-only guide', (
    tester,
  ) async {
    final owner = controller();
    await tester.pumpWidget(TonyoApp(controller: owner));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('today-score-transparency')),
    );
    await tester.tap(find.byKey(const Key('today-score-transparency')));
    await tester.pumpAndSettle();
    expect(find.byType(ModelTransparencyScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('model-transparency-setting')),
      250,
    );
    await tester.tap(find.byKey(const Key('model-transparency-setting')));
    await tester.pumpAndSettle();
    expect(find.byType(ModelTransparencyScreen), findsOneWidget);
    expect(find.text('How your scores work'), findsOneWidget);
    expect(owner.dataActions, 0);
  });
}
