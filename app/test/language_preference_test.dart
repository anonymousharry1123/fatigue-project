import 'package:app/src/language_preference.dart';
import 'package:app/src/l10n/app_localizations.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy, unsupported and malformed language choices fall back to English',
    () {
      expect(const UserProfile().preferredLanguage, 'en');
      expect(UserProfile.fromJson({}).preferredLanguage, 'en');
      for (final value in <Object?>[
        null,
        7,
        true,
        const [],
        const {},
        '',
        ' ',
        'fr',
        'english',
        'zh-Hans-extra-unknown',
        'es/../../',
        'en-US\n<script>',
        'zh--TW',
      ]) {
        expect(normalizeLanguagePreference(value), 'en', reason: '$value');
        expect(
          UserProfile.fromJson({'preferredLanguage': value}).preferredLanguage,
          'en',
        );
      }
    },
  );

  test('supported aliases normalize to stable language tags', () {
    const aliases = {
      'EN': 'en',
      'en-US': 'en',
      ' en_GB ': 'en',
      'es': 'es',
      'ES-mx': 'es',
      'es_419': 'es',
      'zh': 'zh-Hans',
      'zh_CN': 'zh-Hans',
      'zh-SG': 'zh-Hans',
      'ZH-hANS-cn': 'zh-Hans',
      'zh-TW': 'zh-Hant',
      'zh-HK': 'zh-Hant',
      'zh_MO': 'zh-Hant',
      'zh-hant-TW': 'zh-Hant',
    };
    for (final entry in aliases.entries) {
      expect(
        normalizeLanguagePreference(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test(
    'profile serialization and edits preserve language without changing schedule',
    () {
      const original = UserProfile(
        name: 'Synthetic profile',
        wakeHour: 9.5,
        bedHour: 22.25,
      );
      for (final language in supportedLanguagePreferences) {
        final changed = original.copyWith(preferredLanguage: language);
        final restored = UserProfile.fromJson(changed.toJson());
        expect(restored.preferredLanguage, language);
        expect(restored.toJson(), changed.toJson());
        expect(restored.copyWith(name: 'Renamed').preferredLanguage, language);
        expect(restored.wakeHour, original.wakeHour);
        expect(restored.bedHour, original.bedHour);
        expect(restored.goal, original.goal);
        expect(restored.coachPriority, original.coachPriority);
      }
      expect(
        original.copyWith(preferredLanguage: 'zh_TW').preferredLanguage,
        'zh-Hant',
      );
      expect(
        const UserProfile(
          preferredLanguage: 'unsupported',
        ).toJson()['preferredLanguage'],
        'en',
      );
    },
  );

  test(
    'locale mapping retains both Chinese scripts and native language labels',
    () {
      expect(localeForLanguage('en').toLanguageTag(), 'en');
      expect(localeForLanguage('es-MX').toLanguageTag(), 'es');
      expect(localeForLanguage('zh-CN').toLanguageTag(), 'zh-Hans');
      expect(localeForLanguage('zh-TW').toLanguageTag(), 'zh-Hant');
      expect(supportedLanguagePreferences.map(languageDisplayName), [
        'English',
        'Español',
        '简体中文',
        '繁體中文',
      ]);
    },
  );

  test('all authored translations retain exactly the source placeholders', () {
    Set<String> placeholders(String value) => RegExp(
      r'\{([A-Za-z][A-Za-z0-9_]*)\}',
    ).allMatches(value).map((match) => match.group(1)!).toSet();
    expect(AppLocalizations.translations, isNotEmpty);
    for (final entry in AppLocalizations.translations.entries) {
      for (final language in supportedLanguagePreferences.where(
        (value) => value != 'en',
      )) {
        final translated = entry.value[language];
        expect(
          translated,
          isNotNull,
          reason: '$language missing: ${entry.key}',
        );
        expect(
          translated!.trim(),
          isNotEmpty,
          reason: '$language empty: ${entry.key}',
        );
        expect(
          placeholders(translated),
          placeholders(entry.key),
          reason: '$language placeholders: ${entry.key}',
        );
      }
    }
  });

  test(
    'authored templates translate numbers without translating observations',
    () {
      const spanish = AppLocalizations('es');
      expect(
        spanish.text('No forecast available'),
        'No hay previsión disponible',
      );
      expect(
        spanish.text('Energy 6/10 · mood 8/10 · stress 3/10'),
        'Energía 6/10 · ánimo 8/10 · estrés 3/10',
      );
      expect(
        spanish.text('Curve high {time}', args: {'time': '13:25'}),
        'Máximo de la curva 13:25',
      );
      expect(spanish.text('Original note: café 中文'), 'Original note: café 中文');
      expect(
        const AppLocalizations(
          'en',
        ).text('Curve high {time}', args: {'time': '1:25 PM'}),
        'Curve high 1:25 PM',
      );
      expect(
        const AppLocalizations('zh-Hans').text('No forecast available'),
        '暂无预测',
      );
      expect(
        const AppLocalizations('zh-Hant').text('No forecast available'),
        '暫無預測',
      );
    },
  );

  test(
    'unknown text remains readable and replacements are not evaluated recursively',
    () {
      const spanish = AppLocalizations('es');
      expect(
        spanish.text('Untranslated diagnostic {code}', args: {'code': 42}),
        'Untranslated diagnostic 42',
      );
      expect(
        spanish.text('Curve high {time}', args: {'time': '{value}\n\$literal'}),
        'Máximo de la curva {value}\n\$literal',
      );
      expect(spanish.text('Curve high {time}'), 'Máximo de la curva {time}');
    },
  );
}
