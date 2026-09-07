import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_repository.dart';
import 'ml_prep_builder.dart';
import 'ml_prep_models.dart';

/// Private on-device model/throttle envelopes, never part of cloud app state.
abstract interface class EnergyModelStore {
  Future<String?> read(String uid);
  Future<void> write(String uid, String value);
  Future<void> clear();
}

const energyModelEnvelopeMaximumBytes = 16 * 1024;

String _ownerKey(String uid) {
  if (uid.isEmpty || uid.length > 128 || uid.contains('/')) {
    throw ArgumentError.value(uid, 'uid', 'Expected one account identifier.');
  }
  return base64Url.encode(utf8.encode(uid));
}

void _checkEnvelope(String value) {
  if (utf8.encode(value).length > energyModelEnvelopeMaximumBytes) {
    throw const FormatException('The local model envelope exceeds 16 KiB.');
  }
}

class MemoryEnergyModelStore implements EnergyModelStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String uid) async {
    _ownerKey(uid);
    final value = values[uid];
    if (value == null ||
        utf8.encode(value).length > energyModelEnvelopeMaximumBytes) {
      return null;
    }
    return value;
  }

  @override
  Future<void> write(String uid, String value) async {
    _ownerKey(uid);
    _checkEnvelope(value);
    values[uid] = value;
  }

  @override
  Future<void> clear() async => values.clear();
}

/// One bounded envelope per owner. Retaining throttle state across sign-out
/// prevents account switching or app restart from bypassing the daily budget.
/// Clearing model storage cannot erase check-ins or the separate prep snapshot.
class SharedPreferencesEnergyModelStore implements EnergyModelStore {
  static const _prefix = 'tonyo_energy_model_v1_';

  @override
  Future<String?> read(String uid) async {
    final key = '$_prefix${_ownerKey(uid)}';
    final value = (await SharedPreferences.getInstance()).get(key);
    if (value is! String ||
        utf8.encode(value).length > energyModelEnvelopeMaximumBytes) {
      return null;
    }
    return value;
  }

  @override
  Future<void> write(String uid, String value) async {
    final key = '$_prefix${_ownerKey(uid)}';
    _checkEnvelope(value);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, value)) {
      throw StateError('Could not save the private Energy model.');
    }
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith(_prefix),
    )) {
      if (!await preferences.remove(key)) {
        throw StateError('Could not clear the private Energy model.');
      }
    }
  }
}

/// Uploads accepted-model summaries only: no training rows, weights, or reads.
abstract interface class EnergyModelMetadataWriter {
  Future<void> writeAccepted(String uid, Map<String, Object?> metadata);
}

/// Whitelisting is intentionally independent of the artifact format. Adding a
/// private model field must never silently add that field to a cloud payload.
abstract final class EnergyModelMetadata {
  static const maximumBytes = 4096;
  static const fields = {
    'modelVersion',
    'schemaVersion',
    'window',
    'trainedAt',
    'labelCount',
    'holdoutMae',
    'deterministicMae',
    'featureCoverage',
  };

  static Map<String, Object?> validate(Map<String, Object?> metadata) {
    if (!_exactKeys(metadata, fields) ||
        metadata['modelVersion'] != 1 ||
        metadata['modelVersion'] is! int ||
        metadata['schemaVersion'] != 1 ||
        metadata['schemaVersion'] is! int) {
      throw const FormatException('Unsupported Energy model metadata schema.');
    }
    final window = metadata['window'];
    final coverage = metadata['featureCoverage'];
    final labelCount = metadata['labelCount'];
    final holdoutMae = metadata['holdoutMae'];
    final deterministicMae = metadata['deterministicMae'];
    if (window is! Map ||
        !_exactKeys(window, const {'start', 'end', 'timezone'}) ||
        !_utcTime(window['start']) ||
        !_utcTime(window['end']) ||
        window['timezone'] is! String ||
        (window['timezone'] as String).length > 100 ||
        !_utcTime(metadata['trainedAt']) ||
        labelCount is! int ||
        labelCount < 14 ||
        labelCount > 100 ||
        !_fraction(holdoutMae, maximum: 100) ||
        !_fraction(deterministicMae, maximum: 100) ||
        (deterministicMae as num) <= 0 ||
        (holdoutMae as num) > deterministicMae * 0.95 ||
        coverage is! Map ||
        !_exactKeys(coverage, MlPrepBuilder.energyFeatureNames.toSet()) ||
        !coverage.values.every(_fraction)) {
      throw const FormatException('Invalid accepted Energy model metadata.');
    }
    try {
      PrepWindow.fromJson(window.cast<String, dynamic>());
    } catch (_) {
      throw const FormatException('Invalid Energy model training window.');
    }
    final encoded = jsonEncode(metadata);
    if (utf8.encode(encoded).length > maximumBytes) {
      throw const FormatException('Energy model metadata exceeds 4 KiB.');
    }
    // A detached JSON-only copy prevents later caller mutation and rejects
    // unsupported values before any database operation is issued.
    return (jsonDecode(encoded) as Map).cast<String, Object?>();
  }

  static bool _exactKeys(Map value, Set<String> keys) =>
      value.length == keys.length && keys.every(value.containsKey);

  static bool _fraction(Object? value, {double maximum = 1}) =>
      value is num && value.isFinite && value >= 0 && value <= maximum;

  static bool _utcTime(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
        ).hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null &&
        parsed.isUtc &&
        parsed.toIso8601String().substring(0, 19) == value.substring(0, 19);
  }
}

class MemoryEnergyModelMetadataWriter implements EnergyModelMetadataWriter {
  MemoryEnergyModelMetadataWriter({this.auth});

  final AccountAuth? auth;
  final values = <String, Map<String, Object?>>{};
  int writes = 0;

  @override
  Future<void> writeAccepted(String uid, Map<String, Object?> metadata) async {
    _authorize(uid, auth, requireConfigured: auth != null);
    final validated = EnergyModelMetadata.validate(metadata);
    values[uid] = validated;
    writes++;
  }
}

class FirestoreEnergyModelMetadataWriter implements EnergyModelMetadataWriter {
  FirestoreEnergyModelMetadataWriter({
    required FirebaseFirestore firestore,
    required AccountAuth auth,
  }) : this._(firestore, auth);

  FirestoreEnergyModelMetadataWriter._(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final AccountAuth _auth;

  @override
  Future<void> writeAccepted(String uid, Map<String, Object?> metadata) async {
    _authorize(uid, _auth);
    final validated = EnergyModelMetadata.validate(metadata);
    await _firestore.collection('users').doc(uid).set({
      'personalizedEnergyModel': validated,
    }, SetOptions(merge: true));
  }
}

void _authorize(
  String uid,
  AccountAuth? auth, {
  bool requireConfigured = true,
}) {
  if (uid.isEmpty ||
      uid.length > 128 ||
      uid.contains('/') ||
      (requireConfigured &&
          (auth?.isConfigured != true || auth?.currentSession?.uid != uid))) {
    throw StateError('Energy models require the authenticated owner account.');
  }
}
