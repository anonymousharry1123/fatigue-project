/// A saved language choice uses a language tag, never a translated label.
/// Existing profiles retain English until the user makes an explicit choice.
const defaultLanguagePreference = 'en';

const supportedLanguagePreferences = ['en', 'es', 'zh-Hans', 'zh-Hant'];

String languageDisplayName(String value) => switch (value) {
  'es' => 'Español',
  'zh-Hans' => '简体中文',
  'zh-Hant' => '繁體中文',
  _ => 'English',
};

String normalizeLanguagePreference(Object? value) {
  if (value is! String) return defaultLanguagePreference;
  final tag = value.trim().replaceAll('_', '-');
  if (!RegExp(
    r'^[A-Za-z]{2,3}(?:-[A-Za-z]{4})?(?:-[A-Za-z]{2}|-[0-9]{3})?$',
  ).hasMatch(tag)) {
    return defaultLanguagePreference;
  }
  final parts = tag.split('-');
  final normalized = [
    parts.first.toLowerCase(),
    for (final part in parts.skip(1))
      part.length == 4
          ? '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}'
          : part.toUpperCase(),
  ].join('-');
  if (normalized == 'zh' || normalized == 'zh-CN' || normalized == 'zh-SG') {
    return 'zh-Hans';
  }
  if (normalized == 'zh-TW' || normalized == 'zh-HK' || normalized == 'zh-MO') {
    return 'zh-Hant';
  }
  if (normalized.startsWith('zh-Hans')) return 'zh-Hans';
  if (normalized.startsWith('zh-Hant')) return 'zh-Hant';
  if (normalized.split('-').first == 'es') return 'es';
  return supportedLanguagePreferences.contains(normalized)
      ? normalized
      : defaultLanguagePreference;
}
