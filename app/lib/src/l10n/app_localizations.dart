import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../language_preference.dart';
import 'account_translations.dart';
import 'core_translations.dart';
import 'forecast_translations.dart';
import 'logging_translations.dart';
import 'measurement_translations.dart';

Locale localeForLanguage(String code) => switch (normalizeLanguagePreference(
  code,
)) {
  'es' => const Locale('es'),
  'zh-Hans' => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  'zh-Hant' => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  _ => const Locale('en'),
};

class AppLocalizations {
  const AppLocalizations(this.language);

  final String language;
  static const supportedLocales = [
    Locale('en'),
    Locale('es'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];
  static const delegate = _AppLocalizationsDelegate();
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations('en');

  static final translations = Map<String, Map<String, String>>.unmodifiable({
    ...coreTranslations,
    ...accountTranslations,
    ...forecastTranslations,
    ...loggingTranslations,
    ...measurementTranslations,
  });

  // Only known, authored templates are recognized. Observations and account
  // data remain in their original language; callers translate presentation.
  static final _templates = [
    for (final entry in translations.entries)
      if (RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}').hasMatch(entry.key))
        _TranslationTemplate(entry.key, entry.value),
  ]..sort((a, b) => b.literalLength.compareTo(a.literalLength));

  String text(String source, {Map<String, Object?> args = const {}}) {
    if (language == 'en') return _fill(source, args);
    final exact = translations[source]?[language];
    if (exact != null) return _fill(exact, args);
    if (args.isEmpty && source.length <= 5000) {
      for (final template in _templates) {
        final match = template.pattern.firstMatch(source);
        final translated = template.values[language];
        if (match == null || translated == null) continue;
        return _fill(translated, {
          for (var index = 0; index < template.names.length; index++)
            template.names[index]: match.group(index + 1)!,
        });
      }
    }
    // New or diagnostic text remains readable until an authored translation
    // exists. Never send private health/account text to a translation service.
    return _fill(source, args);
  }

  static String _fill(String value, Map<String, Object?> args) =>
      value.replaceAllMapped(RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}'), (match) {
        final name = match.group(1)!;
        return args.containsKey(name) ? '${args[name] ?? ''}' : match.group(0)!;
      });
}

class _TranslationTemplate {
  _TranslationTemplate(String source, this.values) {
    literalLength = source
        .replaceAll(RegExp(r'\{[A-Za-z][A-Za-z0-9_]*\}'), '')
        .length;
    final markers = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}').allMatches(source);
    final expression = StringBuffer('^');
    var offset = 0;
    for (final marker in markers) {
      expression.write(RegExp.escape(source.substring(offset, marker.start)));
      expression.write('(.*?)');
      names.add(marker.group(1)!);
      offset = marker.end;
    }
    expression.write(RegExp.escape(source.substring(offset)));
    expression.write(r'$');
    pattern = RegExp(expression.toString(), dotAll: true);
  }
  final Map<String, String> values;
  final names = <String>[];
  late final RegExp pattern;
  late final int literalLength;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      ['en', 'es', 'zh'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(
    AppLocalizations(normalizeLanguagePreference(locale.toLanguageTag())),
  );
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension TonyoTranslations on BuildContext {
  String tr(String source, {Map<String, Object?> args = const {}}) =>
      AppLocalizations.of(this).text(source, args: args);
}
