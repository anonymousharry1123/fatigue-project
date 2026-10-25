import 'package:app/src/app.dart';
import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/oura_service.dart';
import 'package:app/src/screens/oura_connection_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

class _ConfiguredOura extends OuraService {
  @override
  bool get supported => true;
  @override
  bool get configured => true;
  @override
  Future<void> cancel() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> pump(WidgetTester tester, AppController controller) async {
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: buildTonyoTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.7)),
            child: child!,
          ),
          home: const OuraConnectionScreen(),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(
        Key(
          controller.ouraConnected ? 'oura-sync-button' : 'oura-connect-button',
        ),
      ),
      250,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unconfigured build explains availability and disables connection',
    (tester) async {
      await pump(tester, AppController(ouraService: OuraService(endpoint: '')));
      expect(
        find.text('Oura connection is not available in this build yet.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('oura-connect-button')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('signed out users see sign-in requirement', (tester) async {
    await pump(tester, AppController(ouraService: _ConfiguredOura()));
    expect(
      find.text('Sign in to your Tonyo account to connect Oura.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('oura-connect-button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('connected screen keeps disconnect available during a sync', (
    tester,
  ) async {
    final controller =
        AppController(
            ouraService: _ConfiguredOura(),
            initialPrivacyConsent: testAdultPrivacyConsent,
            accountAuth: MemoryAccountAuth(
              session: const AccountSession(
                uid: 'owner',
                email: 'owner@example.test',
              ),
            ),
          )
          ..ouraConnected = true
          ..isOuraBusy = true;
    await pump(tester, controller);
    expect(find.byKey(const Key('oura-connected')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('oura-sync-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('oura-disconnect-button')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
