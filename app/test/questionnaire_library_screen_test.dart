import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/screens/questionnaire_library_screen.dart';
import 'package:app/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in ['en', 'es', 'zh-Hans', 'zh-Hant']) {
    testWidgets(
      'empty library stays read-only at narrow width and 2× text: $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tr = AppLocalizations(language).text;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTonyoTheme(),
            locale: localeForLanguage(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const QuestionnaireLibraryScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(tr('No periodic questionnaire is available')),
          findsOneWidget,
        );
        expect(
          find.text(tr('Installed instruments: {count}', args: {'count': 0})),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.byType(Switch), findsNothing);
        final end = find.byKey(
          const Key('questionnaire-library-daily-check-ins'),
        );
        await tester.scrollUntilVisible(
          end,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(end);
        await tester.pumpAndSettle();
        expect(find.text(tr('Daily check-ins stay separate')), findsOneWidget);
        expect(
          find.text(
            tr(
              'Tonyo’s daily 1–10 questions remain custom research check-ins in draft form, not a clinical assessment. Their original answers are not converted into questionnaire scores.',
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (language != 'en') {
          expect(tr('Questionnaire library'), isNot('Questionnaire library'));
          expect(
            tr('No periodic questionnaire is available'),
            isNot('No periodic questionnaire is available'),
          );
        }
      },
    );
  }
}
