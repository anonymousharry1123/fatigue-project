import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../questionnaire_framework.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// Read-only catalog status. There is no questionnaire collection, installation,
/// approval, or storage action on this route.
class QuestionnaireLibraryScreen extends StatelessWidget {
  const QuestionnaireLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Questionnaire library'))),
    body: SafeArea(
      top: false,
      child: ListView(
        key: const Key('questionnaire-library-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          TonyoCard(
            key: const Key('questionnaire-library-status'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.assignment_outlined,
                  color: TonyoPalette.of(context).primary,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('No periodic questionnaire is available'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    'Installed instruments: {count}',
                    args: {'count': questionnaireCatalog.length},
                  ),
                  key: const Key('questionnaire-library-count'),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    'No published questionnaire has been selected or approved for Tonyo.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TonyoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Before an instrument can be added'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    'An instrument needs documented review of its intended age group, language, recall period, permissions for digital use and scoring instructions.',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    'Biological, youth-appropriateness and software reviews are separate. An app screen or software test does not establish clinical validation.',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    'Any future collection also needs the applicable privacy, consent and research approvals.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TonyoCard(
            key: const Key('questionnaire-library-daily-check-ins'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Daily check-ins stay separate'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    'Tonyo’s daily 1–10 questions remain custom research check-ins in draft form, not a clinical assessment. Their original answers are not converted into questionnaire scores.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
