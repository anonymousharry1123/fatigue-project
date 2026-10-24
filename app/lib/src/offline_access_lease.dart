import 'dart:convert';

import 'privacy_consent.dart';

/// Device-only continuity after a verified account/consent check. Never grants
/// cloud authorization, and never renews itself after a failed request.
class OfflineAccessLease {
  const OfflineAccessLease({
    required this.uid,
    required this.verifiedAt,
    required this.consent,
  });
  static const lifetime = Duration(hours: 72);
  final String uid;
  final DateTime verifiedAt;
  final PrivacyConsent consent;
  DateTime get expiresAt => verifiedAt.add(lifetime);

  bool allows({
    required String? owner,
    required PrivacyConsent? currentConsent,
    required DateTime now,
  }) =>
      owner == uid &&
      currentConsent?.ageBand == PrivacyAgeBand.adult &&
      currentConsent?.validAt(now) == true &&
      !verifiedAt.isAfter(now) &&
      now.isBefore(expiresAt) &&
      jsonEncode(currentConsent?.toJson()) == jsonEncode(consent.toJson());

  Map<String, Object?> toJson() => {
    'uid': uid,
    'verifiedAt': verifiedAt.toUtc().toIso8601String(),
    'consent': consent.toJson(),
  };
  static OfflineAccessLease? tryParse(Object? value) {
    if (value is! Map ||
        value['uid'] is! String ||
        (value['uid'] as String).isEmpty) {
      return null;
    }
    final at = value['verifiedAt'] is String
        ? DateTime.tryParse(value['verifiedAt'] as String)
        : null;
    final receipt = PrivacyConsent.tryParse(value['consent']);
    if (at == null ||
        receipt == null ||
        receipt.ageBand != PrivacyAgeBand.adult) {
      return null;
    }
    return OfflineAccessLease(
      uid: value['uid'] as String,
      verifiedAt: at,
      consent: receipt,
    );
  }
}
