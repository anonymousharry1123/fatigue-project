import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/check_in_measurement.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:app/src/research_export.dart';
import 'package:app/src/screens/add_data_screen.dart';
import 'package:app/src/screens/daily_checkin_screen.dart';
import 'package:app/src/screens/daily_history_screen.dart';
import 'package:app/src/screens/forecast_insights_screen.dart';
import 'package:app/src/screens/insights_screen.dart';
import 'package:app/src/screens/profile_screen.dart';
import 'package:app/src/screens/questionnaire_library_screen.dart';
import 'package:app/src/screens/research_export_screen.dart';
import 'package:app/src/screens/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// This marker identifies an isolated, fictional UI submission. It is not a
// production observation and never establishes measurement or model validity.
const uiMeasurementNote = 'native-ui-measurement-walkthrough';
const _spanish = AppLocalizations('es');

/// Uses the actual mounted TonyoApp and its live native-backed controller.
/// Call before seeding the reference history so its final current report wins
/// Today selection. No account, consent, storage, or platform API is mocked.
Future<void> exerciseMeasurementEntryUi(
  WidgetTester tester,
  AppController controller,
) async {
  // Controller-only setup can finish before the live test binding renders the
  // authenticated shell and its new locale. Flush that frame before locating it.
  await tester.pumpAndSettle();
  expect(controller.effectiveLanguage, 'es');
  final originalEnglish = controller.checkIns.singleWhere(
    (row) => row.id == 'checkin-measurement-complete',
  );
  final englishBefore = jsonEncode(originalEnglish.toJson());
  final initialCount = controller.checkIns.length;
  await _tab(tester, 'Add');
  await _tap(
    tester,
    find.text(_spanish.text('Daily check-in')),
    within: find.byType(AddDataScreen),
  );
  expect(find.byType(DailyCheckInScreen), findsOneWidget);
  final form = find.byType(DailyCheckInScreen);
  for (final id in DailyCheckIn.measurementIds) {
    final value = find.byKey(Key('rating-$id-value'));
    await _reveal(tester, value, within: form);
    expect(tester.widget<Text>(value).data, _spanish.text('Not answered'));
  }
  await _tap(tester, find.byKey(const Key('save-checkin')), within: form);
  await _reveal(
    tester,
    find.byKey(const Key('checkin-validation')),
    within: form,
  );
  expect(
    find.text(_spanish.text('Choose Morning or Evening before saving.')),
    findsWidgets,
  );
  expect(controller.checkIns.length, initialCount);
  await _tap(
    tester,
    find.byKey(const Key('checkin-period-morning')),
    within: form,
  );
  await _tap(tester, find.byKey(const Key('save-checkin')), within: form);
  await _reveal(
    tester,
    find.byKey(const Key('checkin-validation')),
    within: form,
  );
  expect(
    find.text(_spanish.text('Select at least one rating before saving.')),
    findsWidgets,
  );
  expect(controller.checkIns.length, initialCount);
  await _tap(tester, find.byKey(const Key('rating-focus-6')), within: form);
  final note = find.byKey(const Key('checkin-note'));
  await _reveal(tester, note, within: form);
  await tester.enterText(note, uiMeasurementNote);
  await _tap(tester, find.byKey(const Key('save-checkin')), within: form);
  await _waitUntil(
    tester,
    () => find.byType(DailyCheckInScreen).evaluate().isEmpty,
  );
  expect(controller.cloudSyncError, isNull);
  expect(controller.checkIns.length, initialCount + 1);
  expectUiMeasurementState(controller.checkIns);
  final saved = controller.checkIns.singleWhere(
    (row) => row.note == uiMeasurementNote,
  );
  final captured = (
    saved.timestamp,
    saved.localDate,
    saved.timezone,
    saved.utcOffsetMinutes,
    jsonEncode(saved.questionnaireSnapshot),
  );

  // The normal history edit affordance leads back to the same form.
  await _tap(
    tester,
    find.text(_spanish.text('Daily history')),
    within: find.byType(AddDataScreen),
  );
  await _editHistory(tester, saved.id);
  await _tap(tester, find.byKey(const Key('rating-energy-5')), within: form);
  await _tap(tester, find.byKey(const Key('save-checkin')), within: form);
  await _waitUntil(
    tester,
    () => find.byType(DailyCheckInScreen).evaluate().isEmpty,
  );
  expect(
    controller.checkIns.singleWhere((row) => row.id == saved.id).energy,
    5,
  );
  expect(controller.cloudSyncError, isNull);
  await _editHistory(tester, saved.id);
  await _tap(tester, find.byKey(const Key('skip-energy')), within: form);
  expect(
    tester.widget<Text>(find.byKey(const Key('rating-energy-value'))).data,
    _spanish.text('Skipped'),
  );
  await _tap(tester, find.byKey(const Key('save-checkin')), within: form);
  await _waitUntil(
    tester,
    () => find.byType(DailyCheckInScreen).evaluate().isEmpty,
  );
  expect(controller.cloudSyncError, isNull);
  expectUiMeasurementState(controller.checkIns);
  final edited = controller.checkIns.singleWhere((row) => row.id == saved.id);
  expect((
    edited.timestamp,
    edited.localDate,
    edited.timezone,
    edited.utcOffsetMinutes,
    jsonEncode(edited.questionnaireSnapshot),
  ), captured);

  // Enter an English record's editor under Spanish presentation. Change a
  // control, then leave without saving: the existing restart fixture is exact.
  await _editHistory(tester, originalEnglish.id);
  final fatigueQuestion =
      (originalEnglish.questionnaireSnapshot!['items'] as List)[1]['prompt']
          as String;
  await _reveal(tester, find.text(fatigueQuestion), within: form);
  expect(find.text(fatigueQuestion), findsOneWidget);
  expect(find.text(_spanish.text('Edit Check-in')), findsOneWidget);
  await _tap(tester, find.byKey(const Key('rating-focus-9')), within: form);
  expect(
    tester.widget<Text>(find.byKey(const Key('rating-focus-value'))).data,
    _spanish.text('{value} out of 10', args: {'value': 9}),
  );
  await _back(tester);
  await tester.pumpAndSettle();
  expect(
    jsonEncode(
      controller.checkIns
          .singleWhere((row) => row.id == originalEnglish.id)
          .toJson(),
    ),
    englishBefore,
  );
  await _back(tester);
  await tester.pumpAndSettle();
  expect(find.byType(AddDataScreen), findsOneWidget);
  expect(controller.effectiveLanguage, 'es');
  expect(controller.outcomes, isEmpty);
  expect(controller.healthAuthorized, isFalse);
}

/// Reused for native preferences before hydration, server reads and controller
/// reconstruction. The generated ID is intentionally found by the test note.
void expectUiMeasurementState(List<DailyCheckIn> rows) {
  final entry = rows.singleWhere((row) => row.note == uiMeasurementNote);
  expect(entry.ratings, {
    'energy': null,
    'fatigue': null,
    'sleepiness': null,
    'focus': 6.0,
    'mood': null,
    'stress': null,
  });
  expect(entry.period, CheckInPeriod.morning);
  expect(entry.completionStatus, 'partial');
  expect(entry.answeredItemCount, 1);
  expect(entry.questionnaireLanguage, 'es');
  expect(entry.questionnaireVersion, CheckInMeasurement.currentVersion);
  expect(
    entry.questionnaireSnapshot,
    CheckInMeasurement.snapshot(language: 'es', translate: _spanish.text),
  );
  expect(entry.source, 'selfReport');
  expect(entry.isValidResearchResponse, isTrue);
}

/// Runs after the independent process restart with history fixtures hydrated.
/// Exercises Flutter controls on the native app and the real OS clipboard;
/// system file-picker/VoiceOver/physical-device acceptance remains separate.
Future<void> exerciseMeasurementReviewUi(
  WidgetTester tester,
  AppController controller,
) async {
  expect(controller.effectiveLanguage, 'es');
  expectUiMeasurementState(controller.checkIns);
  final beforeInputs = _inputs(controller);
  await _tab(tester, 'Today');
  final today = find.byType(TodayScreen);
  final reference = find.byKey(
    const PageStorageKey('self-report-reference-acceptance-current-morning'),
  );
  await _tap(tester, reference, within: today);
  final energy = find.byKey(
    const Key('self-report-reference-acceptance-current-morning-energy'),
  );
  await _reveal(tester, energy, within: today);
  expect(
    find.descendant(
      of: energy,
      matching: find.text(
        _spanish.text(
          '{measure} average: {value} / 10',
          args: {'measure': _spanish.text('Energy'), 'value': '5,5'},
        ),
      ),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: energy,
      matching: find.text(
        _spanish.text('{count} days with an answer', args: {'count': 8}),
      ),
    ),
    findsOneWidget,
  );

  await _tab(tester, 'Forecast');
  await _tap(
    tester,
    find.descendant(
      of: find.byType(SegmentedButton<int>),
      matching: find.text(_spanish.text('Insights')),
    ),
    within: find.byType(ForecastInsightsScreen),
  );
  final insights = find.byType(InsightsScreen);
  await _tap(
    tester,
    find.byKey(const Key('self-report-trend-language-en')),
    within: insights,
  );
  await _reveal(
    tester,
    find.byKey(const Key('self-report-rating-chart')),
    within: insights,
  );
  expect(find.byKey(const Key('self-report-rating-chart')), findsOneWidget);
  await _reveal(
    tester,
    find.byKey(const Key('self-report-sleep-chart')),
    within: insights,
  );
  expect(find.byKey(const Key('self-report-sleep-chart')), findsOneWidget);
  await _tap(
    tester,
    find.byKey(const Key('self-report-trend-measure-sleepiness')),
    within: insights,
  );
  expect(find.byKey(const Key('self-report-rating-chart')), findsNothing);
  expect(find.byKey(const Key('self-report-sleep-chart')), findsNothing);
  await _tap(
    tester,
    find.byKey(const Key('self-report-trend-measure-focus')),
    within: insights,
  );
  final records = find.byKey(
    const PageStorageKey('self-report-trend-records-focus-morning-en'),
  );
  await _tap(tester, records, within: insights);
  final currentDate = controller.checkIns
      .singleWhere((row) => row.id == 'acceptance-current-morning')
      .localDate!;
  final dateRow = find.byKey(Key('self-report-trend-record-$currentDate'));
  await _reveal(tester, dateRow, within: insights);
  expect(
    find.descendant(
      of: dateRow,
      matching: find.text(
        _spanish.text(
          '{measure}: {value}',
          args: {
            'measure': _spanish.text('Focus'),
            'value': _spanish.text('Not answered'),
          },
        ),
      ),
    ),
    findsOneWidget,
  );
  await _tap(
    tester,
    find.byKey(const Key('self-report-trend-period-evening')),
    within: insights,
  );
  expect(find.byKey(const Key('self-report-rating-chart')), findsNothing);
  await _tap(
    tester,
    find.byKey(const Key('self-report-trend-language-es')),
    within: insights,
  );
  expect(
    find.text(_spanish.text('No matching self-reports in this window.')),
    findsOneWidget,
  );
  await _tap(
    tester,
    find.byKey(const Key('self-report-trend-period-morning')),
    within: insights,
  );
  expect(
    find.text(_spanish.text('No matching self-reports in this window.')),
    findsNothing,
  );

  await _tab(tester, 'Profile');
  final profile = find.byType(ProfileScreen);
  await _tap(
    tester,
    find.byKey(const Key('research-export-setting')),
    within: profile,
  );
  final export = find.byType(ResearchExportScreen);
  expect(export, findsOneWidget);
  expect(find.byKey(const Key('research-export-summary')), findsNothing);
  expect(find.byKey(const Key('research-copy-json')), findsNothing);
  final code = find.byKey(const Key('research-study-code'));
  await _reveal(tester, code, within: export);
  await tester.enterText(code, 'NATIVE001');
  await _tap(tester, find.byKey(const Key('research-prepare')), within: export);
  final expected = ResearchExport.build(
    checkIns: controller.checkIns,
    signals: controller.signals,
    studyCode: 'NATIVE001',
    generatedAt: controller.currentTime,
  );
  await _reveal(
    tester,
    find.byKey(const Key('research-export-summary')),
    within: export,
  );
  expect(
    find.text(
      _spanish.text(
        '{rows} responses · {partial} partial · {pairs} sleep pairs · {excluded} excluded',
        args: {
          'rows': expected.responseCount,
          'partial': expected.partialCount,
          'pairs': expected.pairedCount,
          'excluded': expected.excludedCount,
        },
      ),
    ),
    findsOneWidget,
  );

  // Clipboard content is exclusively generated fixture data and is cleared,
  // even if a verification fails. No file picker is invoked by this scenario.
  await Clipboard.setData(
    const ClipboardData(text: 'native-integration-empty'),
  );
  try {
    await _tap(
      tester,
      find.byKey(const Key('research-copy-json')),
      within: export,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(_spanish.text('Cancel')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      (await Clipboard.getData(Clipboard.kTextPlain))?.text,
      'native-integration-empty',
    );
    await _tap(
      tester,
      find.byKey(const Key('research-copy-json')),
      within: export,
    );
    await tester.tap(find.byKey(const Key('research-copy-confirm')));
    await _waitUntil(
      tester,
      () =>
          find.byKey(const Key('research-export-status')).evaluate().isNotEmpty,
    );
    final json = (await Clipboard.getData(Clipboard.kTextPlain))!.text!;
    final actual = jsonDecode(json) as Map<String, dynamic>;
    final expectedJson = jsonDecode(expected.json) as Map<String, dynamic>;
    // Generation instants differ; the response/definition/sleep tables do not.
    for (final key in [
      'responses',
      'sleepObservations',
      'questionnaireDefinitions',
    ]) {
      expect(
        actual.containsKey(key),
        isTrue,
        reason: 'Export must include $key.',
      );
      expect(actual[key], expectedJson[key]);
    }
    expect(json, isNot(contains(uiMeasurementNote)));
    expect(json, isNot(contains(controller.cloudUid!)));
    expect(json, isNot(contains(controller.accountEmail!)));
    await _tap(
      tester,
      find.byKey(const Key('research-copy-csv')),
      within: export,
    );
    await tester.tap(find.byKey(const Key('research-copy-confirm')));
    await _waitUntil(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
    await tester.pumpAndSettle();
    await _expectClipboard(tester, expected.csv);
  } finally {
    await Clipboard.setData(const ClipboardData(text: ''));
  }
  await _back(tester);
  await tester.pumpAndSettle();
  await _tap(
    tester,
    find.byKey(const Key('questionnaire-library-setting')),
    within: profile,
  );
  expect(find.byType(QuestionnaireLibraryScreen), findsOneWidget);
  expect(
    find.text(
      _spanish.text('Installed instruments: {count}', args: {'count': 0}),
    ),
    findsOneWidget,
  );
  expect(find.byType(FilledButton), findsNothing);
  expect(find.byType(TextField), findsNothing);
  await _back(tester);
  await tester.pumpAndSettle();
  expect(_inputs(controller), beforeInputs);
  expect(controller.effectiveLanguage, 'es');
  expect(controller.outcomes, isEmpty);
  expect(controller.outcomeConsent, isFalse);
  expect(controller.healthAuthorized, isFalse);
}

String _inputs(AppController controller) => jsonEncode({
  'checkIns': controller.checkIns.map((row) => row.toJson()).toList(),
  'signals': controller.signals.map((row) => row.toJson()).toList(),
});

Future<void> _editHistory(WidgetTester tester, String id) async {
  final row = find.byKey(Key('history-item-$id'));
  final edit = find.descendant(
    of: row,
    matching: find.byIcon(Icons.edit_outlined),
  );
  await _tap(tester, edit, within: find.byType(DailyHistoryScreen));
  expect(find.byType(DailyCheckInScreen), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  // WidgetTester.pageBack searches the English "Back" tooltip; this app is
  // intentionally running with Spanish Material localizations on iOS.
  final button = find.byType(BackButton).hitTestable();
  expect(button, findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label) async {
  final target = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(_spanish.text(label)),
  );
  expect(target, findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tap(
  WidgetTester tester,
  Finder target, {
  required Finder within,
}) async {
  await _reveal(tester, target, within: within);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  required Finder within,
}) async {
  if (target.evaluate().isEmpty) {
    final scroll = find
        .descendant(of: within, matching: find.byType(Scrollable))
        .first;
    expect(scroll, findsOneWidget);
    // Returning to an earlier lazy child needs an actual bounded upward scroll.
    for (
      var attempt = 0;
      attempt < 40 && target.evaluate().isEmpty;
      attempt++
    ) {
      final position = tester.state<ScrollableState>(scroll).position;
      if (position.pixels <= position.minScrollExtent) break;
      await tester.drag(scroll, const Offset(0, 600));
      await tester.pumpAndSettle();
    }
    for (
      var attempt = 0;
      attempt < 80 && target.evaluate().isEmpty;
      attempt++
    ) {
      final position = tester.state<ScrollableState>(scroll).position;
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(scroll, const Offset(0, -350));
      await tester.pumpAndSettle();
    }
  }
  expect(target, findsOneWidget);
  if (target.hitTestable().evaluate().isEmpty) {
    final element = tester.element(target);
    // Scroll only the containing vertical list. tester.ensureVisible also
    // scrolls the outer horizontal PageView and can switch the selected tab.
    final scroll = Scrollable.maybeOf(element, axis: Axis.vertical);
    if (scroll != null) {
      await scroll.position.ensureVisible(
        element.renderObject!,
        alignment: .15,
      );
    }
  }
  await tester.pumpAndSettle();
  // Display-only Columns do not necessarily hit-test in their blank center.
  // Require visible geometry here; actual tap targets are checked in _tap.
  final bounds = tester.getRect(target);
  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  expect(bounds.overlaps(screen), isTrue);
  final vertical = Scrollable.maybeOf(
    tester.element(target),
    axis: Axis.vertical,
  );
  if (vertical != null) {
    expect(
      bounds.overlaps(tester.getRect(find.byWidget(vertical.widget))),
      isTrue,
    );
  }
}

Future<void> _waitUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 120 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(
    condition(),
    isTrue,
    reason: 'The native UI action did not finish within 30 seconds.',
  );
  await tester.pumpAndSettle();
}

Future<void> _expectClipboard(WidgetTester tester, String expected) async {
  String? actual;
  for (var attempt = 0; attempt < 60; attempt++) {
    actual = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (actual == expected) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    actual,
    expected,
    reason: 'The native clipboard must contain the confirmed prepared CSV.',
  );
}
