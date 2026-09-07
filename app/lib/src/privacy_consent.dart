/// Versioned product safeguards, not a declaration of legal compliance.
/// Until jurisdiction-specific rules and a verification provider are reviewed,
/// this build conservatively requires verified guardian consent for minors.
const privacyPolicyVersion = 1;

enum PrivacyAgeBand { under13, age13to15, age16to17, adult }

extension PrivacyAgeBandInfo on PrivacyAgeBand {
  String get storageValue => switch (this) {
    PrivacyAgeBand.under13 => 'under13',
    PrivacyAgeBand.age13to15 => '13to15',
    PrivacyAgeBand.age16to17 => '16to17',
    PrivacyAgeBand.adult => '18plus',
  };

  String get label => switch (this) {
    PrivacyAgeBand.under13 => 'Under 13',
    PrivacyAgeBand.age13to15 => '13–15',
    PrivacyAgeBand.age16to17 => '16–17',
    PrivacyAgeBand.adult => '18 or older',
  };
}

enum PrivacyRegion { us, other, unknown }

extension PrivacyRegionInfo on PrivacyRegion {
  String get label => switch (this) {
    PrivacyRegion.us => 'United States',
    PrivacyRegion.other => 'Outside the United States',
    PrivacyRegion.unknown => 'Prefer not to say / not sure',
  };
}

/// An explicit acknowledgement. Missing legacy values never become consent.
/// No exact date of birth, parent contact details, or passwords are collected.
class PrivacyConsent {
  const PrivacyConsent({
    required this.ageBand,
    required this.region,
    required this.acceptedAt,
    this.policyVersion = privacyPolicyVersion,
    this.wellnessAcknowledged = true,
  });

  final PrivacyAgeBand ageBand;
  final PrivacyRegion region;
  final DateTime acceptedAt;
  final int policyVersion;
  final bool wellnessAcknowledged;

  bool get guardianRequired => ageBand != PrivacyAgeBand.adult;
  bool validAt(DateTime now) =>
      policyVersion == privacyPolicyVersion &&
      wellnessAcknowledged &&
      !acceptedAt.isAfter(now);

  bool sameIdentity(PrivacyConsent other) =>
      ageBand == other.ageBand && region == other.region;

  Map<String, Object?> toJson() => {
    'policyVersion': policyVersion,
    'ageBand': ageBand.storageValue,
    'region': region.name,
    'acceptedAt': acceptedAt.toUtc().toIso8601String(),
    'wellnessAcknowledged': wellnessAcknowledged,
  };

  Map<String, Object?> toCloud() => {
    ...toJson(),
    'acceptedAt': acceptedAt.toUtc(),
  };

  static PrivacyConsent? tryParse(Object? value) {
    if (value is! Map ||
        value.length != 5 ||
        value['policyVersion'] != privacyPolicyVersion ||
        value['policyVersion'] is! int ||
        value['wellnessAcknowledged'] != true) {
      return null;
    }
    final age = PrivacyAgeBand.values
        .where((band) => band.storageValue == value['ageBand'])
        .firstOrNull;
    final region = PrivacyRegion.values
        .where((region) => region.name == value['region'])
        .firstOrNull;
    final rawTime = value['acceptedAt'];
    final at = rawTime is DateTime
        ? rawTime.toUtc()
        : rawTime is String &&
              RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(rawTime)
        ? DateTime.tryParse(rawTime)?.toUtc()
        : null;
    if (age == null || region == null || at == null) return null;
    return PrivacyConsent(ageBand: age, region: region, acceptedAt: at);
  }
}
