import 'package:app/src/app_controller.dart';
import 'package:app/src/screens/admin/admin_cohort_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Cohort Lab overview renders empty state and load control', (
    tester,
  ) async {
    final controller = AppController();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTonyoTheme(),
        home: AdminCohortScreen(controller: controller),
      ),
    );

    expect(find.text('Cohort Lab'), findsOneWidget);
    expect(find.text('Load CSV'), findsOneWidget);
    expect(
      find.text('Load the synthetic CSV to see score distributions.'),
      findsOneWidget,
    );
  });
}
