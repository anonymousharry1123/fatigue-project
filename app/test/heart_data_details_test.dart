import 'package:app/src/heart_derivation_logic.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/widgets/heart_data_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime(2026, 10, 24);
  final now = DateTime(2026, 10, 24, 12);

  SignalReading heart(int minute, double value) => SignalReading(
    id: 'healthkit-heart-$minute',
    type: SignalType.heartRate,
    value: value,
    timestamp: day.add(Duration(minutes: minute)),
    source: SignalSource.healthKit,
  );

  Future<void> pumpDetails(WidgetTester tester, List<SignalReading> readings) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HeartDataDetails(readings: readings, now: now),
            ),
          ),
        ),
      );

  testWidgets('estimates and bpm variation remain distinct from native HRV', (
    tester,
  ) async {
    final readings = HeartDerivationLogic.reconcile(
      readings: [
        heart(60, 60),
        heart(90, 58),
        heart(120, 62),
        for (var i = 0; i < 6; i++) heart(480 + i * 30, i.isEven ? 60 : 64),
      ],
      now: now,
    ).readings;
    await pumpDetails(tester, readings);
    expect(
      find.textContaining('Latest estimated resting HR: 60.0 bpm'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Sampled heart-rate variation: 4.0 bpm'),
      findsOneWidget,
    );
    expect(find.textContaining('No native HRV imported.'), findsOneWidget);
    expect(find.textContaining('not used in your score'), findsOneWidget);
    expect(
      find.textContaining('do not affect your score or measured baselines'),
      findsOneWidget,
    );
    expect(find.textContaining('Latest HRV from Apple Health:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native measurements are labelled with their source and units', (
    tester,
  ) async {
    await pumpDetails(tester, [
      SignalReading(
        id: 'healthkit-native-resting',
        type: SignalType.restingHeartRate,
        value: 58,
        timestamp: day.add(const Duration(hours: 7)),
        source: SignalSource.healthKit,
      ),
      SignalReading(
        id: 'healthkit-native-hrv',
        type: SignalType.hrv,
        value: 42,
        timestamp: day.add(const Duration(hours: 7)),
        source: SignalSource.healthKit,
      ),
    ]);
    expect(
      find.textContaining('Latest resting HR from Apple Health: 58.0 bpm'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Latest HRV from Apple Health: 42.0 ms'),
      findsOneWidget,
    );
    expect(find.textContaining('Latest estimated resting HR:'), findsNothing);
    expect(find.textContaining('No native HRV imported.'), findsNothing);
  });

  testWidgets('sparse data gives guidance without inventing HRV', (
    tester,
  ) async {
    await pumpDetails(tester, [heart(60, 60)]);
    expect(
      find.byKey(const Key('heart-data-resting-guidance')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('heart-data-variation-guidance')),
      findsOneWidget,
    );
    expect(find.textContaining('beat-to-beat intervals'), findsOneWidget);
    expect(find.textContaining('take a heart-rate reading'), findsNothing);
    expect(find.byKey(const Key('heart-data-sampled-variation')), findsNothing);
    expect(find.byKey(const Key('heart-data-resting')), findsNothing);
  });

  testWidgets('future availability never appears as a current native value', (
    tester,
  ) async {
    await pumpDetails(tester, [
      SignalReading(
        id: 'healthkit-future-hrv',
        type: SignalType.hrv,
        value: 42,
        timestamp: day.add(const Duration(hours: 7)),
        syncedAt: now.add(const Duration(hours: 1)),
        source: SignalSource.healthKit,
      ),
    ]);
    expect(find.textContaining('No native HRV imported.'), findsOneWidget);
    expect(find.textContaining('42.0 ms'), findsNothing);
  });

  test('heart details have complete authored translations and unit templates', () {
    const templates = [
      'Resting HR estimates are informational and do not affect your score or measured baselines.',
      'Latest estimated resting HR: {value} bpm · {date}',
      'Latest resting HR from Apple Health: {value} bpm · {date}',
      'Latest logged resting HR: {value} bpm · {date}',
      'Latest HRV from Apple Health: {value} ms · {date}',
      'Sampled heart-rate variation: {value} bpm · {date}',
      'Variation between sampled bpm readings; separate from HRV and not used in your score.',
      'Daytime variation needs at least 6 readings across 2 hours, no more than 45 minutes apart.',
      'No native HRV imported. HRV needs beat-to-beat intervals; ordinary heart-rate samples cannot supply it. Check whether your device shares HRV with Apple Health.',
      'A resting HR estimate needs at least 3 overnight readings (midnight–8 am). Wear your device overnight, sync its app to Apple Health, then tap Sync now.',
    ];
    for (final language in ['es', 'zh-Hans', 'zh-Hant']) {
      final localizations = AppLocalizations(language);
      for (final template in templates) {
        expect(AppLocalizations.translations[template]?[language], isNotEmpty);
        final translated = localizations.text(
          template,
          args: {'value': '58.0', 'date': '2026-10-24'},
        );
        expect(translated, isNot(contains('{value}')));
        expect(translated, isNot(contains('{date}')));
      }
    }
  });
}
