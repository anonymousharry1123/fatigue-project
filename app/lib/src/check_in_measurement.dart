/// Technical definition of Tonyo's draft custom self-report items.
///
/// This version identifies stored wording, not an approved research protocol or
/// a validated questionnaire. Changing prompts/anchors requires a new version.
abstract final class CheckInMeasurement {
  static const currentVersion = 'tonyo-self-report-draft-v1';
  static const recallPeriod = 'right now';
  static const disclosure =
      'Tonyo research check-in — not a clinical assessment';
  static const items = <CheckInMeasurementItem>[
    CheckInMeasurementItem(
      id: 'energy',
      label: 'Energy',
      low: 'extremely low energy',
      middle: 'about average',
      high: 'extremely high energy',
    ),
    CheckInMeasurementItem(
      id: 'fatigue',
      label: 'Fatigue',
      prompt: 'How fatigued or drained do you feel right now?',
      low: 'not fatigued at all',
      middle: 'moderately fatigued',
      high: 'extremely fatigued',
    ),
    CheckInMeasurementItem(
      id: 'sleepiness',
      label: 'Sleepiness',
      prompt: 'How sleepy do you feel right now?',
      low: 'fully alert',
      middle: 'moderately sleepy',
      high: 'extremely sleepy',
    ),
    CheckInMeasurementItem(
      id: 'focus',
      label: 'Focus',
      prompt: 'How easy is it for you to focus right now?',
      low: 'extremely difficult to focus',
      middle: 'average',
      high: 'extremely easy to focus',
    ),
    CheckInMeasurementItem(
      id: 'mood',
      label: 'Mood',
      low: 'Low',
      middle: 'Steady',
      high: 'Great',
    ),
    CheckInMeasurementItem(
      id: 'stress',
      label: 'Stress',
      low: 'Calm',
      middle: 'Moderate',
      high: 'Maxed',
    ),
  ];

  static Map<String, dynamic> snapshot({
    required String language,
    required String Function(String) translate,
  }) => {
    'version': currentVersion,
    'language': language,
    'kind': 'customSelfReport',
    'status': 'draftNotClinicallyValidated',
    'recallPeriod': recallPeriod,
    'recallPeriodText': translate(recallPeriod),
    'items': [
      for (final item in items)
        {
          'id': item.id,
          'label': translate(item.label),
          'prompt': item.prompt.isEmpty ? '' : translate(item.prompt),
          'anchors': {
            '1': translate(item.low),
            '5': translate(item.middle),
            '10': translate(item.high),
          },
          'optional': true,
        },
    ],
  };
}

class CheckInMeasurementItem {
  const CheckInMeasurementItem({
    required this.id,
    required this.label,
    this.prompt = '',
    required this.low,
    required this.middle,
    required this.high,
  });
  final String id;
  final String label;
  final String prompt;
  final String low;
  final String middle;
  final String high;
}
