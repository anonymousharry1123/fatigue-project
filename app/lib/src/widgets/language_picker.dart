import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../language_preference.dart';
import '../l10n/app_localizations.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey(normalizeLanguagePreference(value)),
    initialValue: normalizeLanguagePreference(value),
    isExpanded: true,
    decoration: InputDecoration(
      labelText: context.tr('Language'),
      prefixIcon: const Icon(Icons.language_rounded),
    ),
    items: [
      for (final code in supportedLanguagePreferences)
        DropdownMenuItem(value: code, child: Text(languageDisplayName(code))),
    ],
    onChanged: onChanged == null
        ? null
        : (selection) {
            if (selection != null) onChanged!(selection);
          },
  );
}

Future<void> showLanguagePreferenceDialog(
  BuildContext context,
  AppController controller,
) async {
  var saving = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(context.tr('Language')),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    context.tr(
                      'Some technical details and notifications are still in English.',
                    ),
                  ),
                ),
                for (final code in supportedLanguagePreferences)
                  ListTile(
                    key: ValueKey('language-choice-$code'),
                    title: Text(languageDisplayName(code)),
                    selected: controller.profile.preferredLanguage == code,
                    trailing: controller.profile.preferredLanguage == code
                        ? const Icon(Icons.check_rounded)
                        : null,
                    enabled: !saving,
                    onTap: () async {
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await controller.setPreferredLanguage(code);
                      } on Object {
                        if (context.mounted) {
                          update(
                            () => error =
                                'Could not save your language. Please try again.',
                          );
                        }
                      } finally {
                        if (context.mounted) update(() => saving = false);
                      }
                    },
                  ),
                if (saving) const LinearProgressIndicator(),
                if (error != null)
                  Text(
                    context.tr(error!),
                    key: const Key('language-save-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('language-close'),
            onPressed: saving ? null : () => Navigator.of(context).pop(),
            child: Text(context.tr('Close')),
          ),
        ],
      ),
    ),
  );
}
