import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import 'ai1_protocol.dart';
import 'timezone_database.dart';

/// Immutable synthetic fit metadata. This format is deliberately incompatible
/// with EnergyResidualModel's legacy 0–100 residual correction artifacts.
/// The synthetic factory records supplied fixture coefficients; it does not
/// certify how they were fitted or grant permission to use real records.
class AiModelArtifact {
  AiModelArtifact._({
    required this.artifactId,
    required this.candidateId,
    required this.protocol,
    required this.ownerScope,
    required this.participantKey,
    required this.timezone,
    required this.fittedAt,
    required this.dataCutoff,
    required this.dataGeneration,
    required List<String> trainingOpportunityIds,
    required this.constantPrediction,
    required this.intercept,
    required this.slope,
  }) : trainingOpportunityIds = List.unmodifiable(trainingOpportunityIds);

  factory AiModelArtifact.synthetic({
    required String artifactId,
    required String candidateId,
    required Ai1Protocol protocol,
    required String ownerScope,
    required String participantKey,
    required String timezone,
    required DateTime fittedAt,
    required DateTime dataCutoff,
    required List<String> trainingOpportunityIds,
    int dataGeneration = 0,
    double? constantPrediction,
    double? intercept,
    double? slope,
  }) {
    _text(artifactId);
    _text(ownerScope);
    _text(participantKey);
    _zone(timezone);
    if (!const {'B0', 'B1', 'M1'}.contains(candidateId) ||
        dataGeneration < 0 ||
        dataCutoff.isAfter(fittedAt) ||
        trainingOpportunityIds.isEmpty ||
        trainingOpportunityIds.length > 10000 ||
        trainingOpportunityIds.toSet().length !=
            trainingOpportunityIds.length ||
        (candidateId == 'B1' && trainingOpportunityIds.length != 1) ||
        (candidateId == 'M1' && trainingOpportunityIds.length < 2)) {
      throw const FormatException('Invalid synthetic model provenance.');
    }
    for (final id in trainingOpportunityIds) {
      _text(id, maximum: 2000);
    }
    if (candidateId == 'M1') {
      if (constantPrediction != null ||
          intercept == null ||
          !intercept.isFinite ||
          slope == null ||
          !slope.isFinite) {
        throw const FormatException('M1 requires finite intercept and slope.');
      }
    } else if (intercept != null ||
        slope != null ||
        constantPrediction == null ||
        !constantPrediction.isFinite ||
        constantPrediction < 1 ||
        constantPrediction > 10) {
      throw const FormatException(
        'A personal baseline requires a 1–10 constant.',
      );
    }
    final artifact = AiModelArtifact._(
      artifactId: artifactId,
      candidateId: candidateId,
      protocol: protocol,
      ownerScope: ownerScope,
      participantKey: participantKey,
      timezone: timezone,
      fittedAt: fittedAt.toUtc(),
      dataCutoff: dataCutoff.toUtc(),
      dataGeneration: dataGeneration,
      trainingOpportunityIds: trainingOpportunityIds,
      constantPrediction: constantPrediction,
      intercept: intercept,
      slope: slope,
    );
    if (utf8.encode(artifact.fingerprint).length > maximumBytes) {
      throw const FormatException(
        'Synthetic model artifact exceeds its size limit.',
      );
    }
    return artifact;
  }

  static const schemaVersion = 'tonyo-synthetic-personal-model-v1';
  static const evidenceKind = 'synthetic_software_fixture';
  static const maximumBytes = 256 * 1024;
  static const _outputRule = {'minimum': 1, 'maximum': 10, 'rounding': 'none'};
  static const _targetSchema = {
    'name': 'evening_energy',
    'unit': 'rating_1_10',
    'minimum': 1,
    'maximum': 10,
  };

  final String artifactId;
  final String candidateId;
  final Ai1Protocol protocol;
  final String ownerScope;
  final String participantKey;
  final String timezone;
  final DateTime fittedAt;
  final DateTime dataCutoff;
  final int dataGeneration;
  final List<String> trainingOpportunityIds;
  final double? constantPrediction;
  final double? intercept;
  final double? slope;
  bool get synthetic => true;
  bool get realDataTrainingAllowed => false;
  bool get appModelActivationAllowed => false;

  List<Map<String, String>> get featureSchema => candidateId == 'M1'
      ? const [
          {'name': 'main_sleep_duration_hours', 'unit': 'hours'},
        ]
      : const [];

  /// Canonical content identity, not a cryptographic signature or attestation.
  String get fingerprint => ai1CanonicalJson(toJson());

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'evidenceKind': evidenceKind,
    'synthetic': true,
    'realDataTrainingAllowed': false,
    'appModelActivationAllowed': false,
    'artifactId': artifactId,
    'candidateId': candidateId,
    'ownerScope': ownerScope,
    'participantKey': participantKey,
    'timezone': timezone,
    'dataGeneration': dataGeneration,
    'protocolId': protocol.id,
    'protocolVersion': protocol.version,
    'sleepSource': protocol.sleepSource.name,
    'measurement': jsonDecode(protocol.measurement),
    'featureSchema': [
      for (final feature in featureSchema) {...feature},
    ],
    'targetSchema': {..._targetSchema},
    'outputRule': {..._outputRule},
    'coefficients': candidateId == 'M1'
        ? {'intercept': intercept, 'slope': slope}
        : {'constantPrediction': constantPrediction},
    'fittedAt': fittedAt.toIso8601String(),
    'dataCutoff': dataCutoff.toIso8601String(),
    'historyPolicy': 'frozen_personal_fit_no_inference_updates',
    'trainingCount': trainingOpportunityIds.length,
    'trainingOpportunityIds': List<String>.of(trainingOpportunityIds),
  };

  factory AiModelArtifact.fromJson(Map<String, dynamic> json) {
    try {
      if (utf8.encode(jsonEncode(json)).length > maximumBytes ||
          !_keys(json, const {
            'schemaVersion',
            'evidenceKind',
            'synthetic',
            'realDataTrainingAllowed',
            'appModelActivationAllowed',
            'artifactId',
            'candidateId',
            'ownerScope',
            'participantKey',
            'timezone',
            'dataGeneration',
            'protocolId',
            'protocolVersion',
            'sleepSource',
            'measurement',
            'featureSchema',
            'targetSchema',
            'outputRule',
            'coefficients',
            'fittedAt',
            'dataCutoff',
            'historyPolicy',
            'trainingCount',
            'trainingOpportunityIds',
          }) ||
          json['schemaVersion'] != schemaVersion ||
          json['evidenceKind'] != evidenceKind ||
          json['synthetic'] != true ||
          json['realDataTrainingAllowed'] != false ||
          json['appModelActivationAllowed'] != false ||
          json['historyPolicy'] != 'frozen_personal_fit_no_inference_updates' ||
          json['dataGeneration'] is! int ||
          json['trainingCount'] is! int ||
          json['trainingOpportunityIds'] is! List) {
        throw const FormatException('Unsupported synthetic model artifact.');
      }
      final source = Ai1SleepSource.values.byName(
        json['sleepSource'] as String,
      );
      final protocol = Ai1Protocol.draft(sleepSource: source);
      if (json['protocolId'] != protocol.id ||
          json['protocolVersion'] != protocol.version ||
          ai1CanonicalJson(json['measurement']) != protocol.measurement ||
          ai1CanonicalJson(json['targetSchema']) !=
              ai1CanonicalJson(_targetSchema) ||
          ai1CanonicalJson(json['outputRule']) !=
              ai1CanonicalJson(_outputRule)) {
        throw const FormatException(
          'Incompatible model protocol or output schema.',
        );
      }
      final candidate = json['candidateId'] as String;
      final coefficients = json['coefficients'];
      if (coefficients is! Map ||
          !_keys(
            coefficients,
            candidate == 'M1'
                ? const {'intercept', 'slope'}
                : const {'constantPrediction'},
          )) {
        throw const FormatException('Incompatible model coefficient shape.');
      }
      double number(String key) {
        final value = coefficients[key];
        if (value is! num || !value.isFinite) {
          throw const FormatException('Invalid model coefficient.');
        }
        return value.toDouble();
      }

      final artifact = AiModelArtifact.synthetic(
        artifactId: json['artifactId'] as String,
        candidateId: candidate,
        protocol: protocol,
        ownerScope: json['ownerScope'] as String,
        participantKey: json['participantKey'] as String,
        timezone: json['timezone'] as String,
        fittedAt: _time(json['fittedAt']),
        dataCutoff: _time(json['dataCutoff']),
        dataGeneration: json['dataGeneration'] as int,
        trainingOpportunityIds: (json['trainingOpportunityIds'] as List)
            .cast<String>(),
        constantPrediction: candidate == 'M1'
            ? null
            : number('constantPrediction'),
        intercept: candidate == 'M1' ? number('intercept') : null,
        slope: candidate == 'M1' ? number('slope') : null,
      );
      if (json['trainingCount'] != artifact.trainingOpportunityIds.length ||
          ai1CanonicalJson(json['featureSchema']) !=
              ai1CanonicalJson(artifact.featureSchema)) {
        throw const FormatException('Incompatible feature or training schema.');
      }
      return artifact;
    } on Object catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('Invalid synthetic model artifact.');
    }
  }

  /// The caller still validates AI-1 source revisions and every source-selection
  /// dependency. This boundary checks the supplied selected value/receipt only.
  /// No prediction from this synthetic API is authorized for the live app.
  AiModelPrediction predict({
    required AiModelInferenceContext context,
    double? sleepHours,
    DateTime? sleepAvailableAt,
  }) {
    String? reason;
    if (!context.synthetic) {
      reason = 'synthetic_session_required';
    } else if (!context.signedIn) {
      reason = 'signed_out';
    } else if (!context.consentGranted) {
      reason = 'consent_withdrawn';
    } else if (context.ownerScope != ownerScope) {
      reason = 'owner_mismatch';
    } else if (context.participantKey != participantKey) {
      reason = 'participant_mismatch';
    } else if (context.dataGeneration != dataGeneration) {
      reason = 'stale_data_generation';
    } else if (context.timezone != timezone) {
      reason = 'timezone_mismatch';
    } else if (context.protocol.id != protocol.id ||
        context.protocol.measurement != protocol.measurement) {
      reason = 'incompatible_protocol';
    } else if (context.featureCutoff.isAfter(context.at)) {
      reason = 'invalid_feature_cutoff';
    } else if (fittedAt.isAfter(context.at) ||
        dataCutoff.isAfter(context.featureCutoff)) {
      reason = 'artifact_not_available_at_prediction';
    }
    if (reason != null) return AiModelPrediction.abstain(reason);
    double raw;
    if (candidateId == 'M1') {
      if (sleepHours == null) return AiModelPrediction.abstain('missing_sleep');
      if (!sleepHours.isFinite || sleepHours < 0.5 || sleepHours > 16) {
        return AiModelPrediction.abstain('invalid_sleep');
      }
      if (sleepAvailableAt == null) {
        return AiModelPrediction.abstain('unknown_sleep_availability');
      }
      if (sleepAvailableAt.isAfter(context.featureCutoff)) {
        return AiModelPrediction.abstain('sleep_after_cutoff');
      }
      raw = intercept! + slope! * sleepHours;
    } else {
      raw = constantPrediction!;
    }
    if (!raw.isFinite) {
      return AiModelPrediction.abstain('non_finite_prediction');
    }
    return AiModelPrediction._(raw, raw.clamp(1.0, 10.0).toDouble(), null);
  }
}

class AiModelInferenceContext {
  AiModelInferenceContext({
    required this.ownerScope,
    required this.participantKey,
    required this.protocol,
    required this.timezone,
    required DateTime at,
    DateTime? featureCutoff,
    this.dataGeneration = 0,
    this.synthetic = true,
    this.signedIn = true,
    this.consentGranted = true,
  }) : at = at.toUtc(),
       featureCutoff = (featureCutoff ?? at).toUtc();
  final String ownerScope;
  final String participantKey;
  final Ai1Protocol protocol;
  final String timezone;
  final DateTime at;
  final DateTime featureCutoff;
  final int dataGeneration;
  final bool synthetic;
  final bool signedIn;
  final bool consentGranted;
}

/// Abstention has no numeric substitute, including no invented neutral score.
class AiModelPrediction {
  const AiModelPrediction._(
    this.rawPrediction,
    this.prediction,
    this.abstentionReason,
  );
  factory AiModelPrediction.abstain(String reason) {
    _text(reason);
    return AiModelPrediction._(null, null, reason);
  }
  final double? rawPrediction;
  final double? prediction;
  final String? abstentionReason;
  bool get predicted => prediction != null;
  Map<String, Object?> toJson() => {
    'status': predicted ? 'predicted' : 'abstained',
    'rawPrediction': rawPrediction,
    'prediction': prediction,
    'abstentionReason': abstentionReason,
  };
}

/// Immutable in-memory synthetic lifecycle harness, not a durable deployment
/// registry. The caller replaces this value after transitions and supplies the
/// current session/generation on every inference. Older object references are
/// not globally revoked; this module owns no account, disk or app lifecycle.
class AiModelRegistry {
  AiModelRegistry._({
    required this.ownerScope,
    required this.timezone,
    required this.dataGeneration,
    required this.signedIn,
    required this.consentGranted,
    required Map<String, AiModelArtifact> artifacts,
    required List<String> activationHistory,
  }) : artifacts = Map.unmodifiable(artifacts),
       activationHistory = List.unmodifiable(activationHistory);

  factory AiModelRegistry.synthetic({
    required String ownerScope,
    required String timezone,
    int dataGeneration = 0,
  }) {
    _text(ownerScope);
    _zone(timezone);
    if (dataGeneration < 0) {
      throw const FormatException('Invalid data generation.');
    }
    return AiModelRegistry._(
      ownerScope: ownerScope,
      timezone: timezone,
      dataGeneration: dataGeneration,
      signedIn: true,
      consentGranted: true,
      artifacts: const {},
      activationHistory: const [],
    );
  }

  final String ownerScope;
  final String timezone;
  final int dataGeneration;
  final bool signedIn;
  final bool consentGranted;
  final Map<String, AiModelArtifact> artifacts;
  final List<String> activationHistory;
  String? get activeArtifactId => activationHistory.lastOrNull;
  AiModelArtifact? get activeArtifact => artifacts[activeArtifactId];

  void _checkArtifact(AiModelArtifact artifact) {
    if (!signedIn || !consentGranted) {
      throw StateError('The synthetic session is unavailable.');
    }
    if (artifact.ownerScope != ownerScope ||
        artifact.timezone != timezone ||
        artifact.dataGeneration != dataGeneration) {
      throw StateError(
        'The artifact is incompatible with this synthetic session.',
      );
    }
  }

  AiModelRegistry stage(AiModelArtifact artifact) {
    _checkArtifact(artifact);
    final existing = artifacts[artifact.artifactId];
    if (existing != null) {
      if (existing.fingerprint != artifact.fingerprint) {
        throw StateError(
          'Artifact identity conflicts with an existing version.',
        );
      }
      return this;
    }
    return _copy(artifacts: {...artifacts, artifact.artifactId: artifact});
  }

  AiModelRegistry activate(String artifactId) {
    final artifact = artifacts[artifactId];
    if (artifact == null) {
      throw StateError('Stage the synthetic artifact before activation.');
    }
    _checkArtifact(artifact);
    if (activeArtifactId == artifactId) return this;
    return _copy(activationHistory: [...activationHistory, artifactId]);
  }

  AiModelRegistry rollback() {
    if (!signedIn || !consentGranted || activationHistory.length < 2) {
      throw StateError('No compatible earlier activation is available.');
    }
    final history = activationHistory
        .take(activationHistory.length - 1)
        .toList();
    _checkArtifact(artifacts[history.last]!);
    return _copy(activationHistory: history);
  }

  AiModelRegistry invalidateCache() => _copy(
    dataGeneration: dataGeneration + 1,
    artifacts: const {},
    activationHistory: const [],
  );
  AiModelRegistry signOut() => invalidateCache()._copy(signedIn: false);
  AiModelRegistry withdrawConsent() =>
      invalidateCache()._copy(consentGranted: false);
  AiModelRegistry changeTimezone(String value) {
    _zone(value);
    return value == timezone ? this : invalidateCache()._copy(timezone: value);
  }

  AiModelPrediction predict({
    required AiModelInferenceContext context,
    double? sleepHours,
    DateTime? sleepAvailableAt,
  }) {
    if (!signedIn) return AiModelPrediction.abstain('signed_out');
    if (!consentGranted) return AiModelPrediction.abstain('consent_withdrawn');
    if (context.ownerScope != ownerScope) {
      return AiModelPrediction.abstain('owner_mismatch');
    }
    if (context.dataGeneration != dataGeneration) {
      return AiModelPrediction.abstain('stale_data_generation');
    }
    if (context.timezone != timezone) {
      return AiModelPrediction.abstain('timezone_mismatch');
    }
    final artifact = activeArtifact;
    if (artifact == null) {
      return AiModelPrediction.abstain('no_active_artifact');
    }
    return artifact.predict(
      context: context,
      sleepHours: sleepHours,
      sleepAvailableAt: sleepAvailableAt,
    );
  }

  AiModelRegistry _copy({
    String? timezone,
    int? dataGeneration,
    bool? signedIn,
    bool? consentGranted,
    Map<String, AiModelArtifact>? artifacts,
    List<String>? activationHistory,
  }) => AiModelRegistry._(
    ownerScope: ownerScope,
    timezone: timezone ?? this.timezone,
    dataGeneration: dataGeneration ?? this.dataGeneration,
    signedIn: signedIn ?? this.signedIn,
    consentGranted: consentGranted ?? this.consentGranted,
    artifacts: artifacts ?? this.artifacts,
    activationHistory: activationHistory ?? this.activationHistory,
  );
}

bool _keys(Map value, Set<String> expected) =>
    value.length == expected.length && expected.every(value.containsKey);

void _text(String value, {int maximum = 200}) {
  if (value.trim().isEmpty || value.length > maximum) {
    throw const FormatException('Invalid synthetic model text.');
  }
}

void _zone(String value) {
  _text(value, maximum: 100);
  initializeTimezoneDatabase();
  try {
    tz.getLocation(value);
  } on tz.LocationNotFoundException {
    throw const FormatException('Unknown model timezone.');
  }
}

DateTime _time(Object? value) {
  if (value is! String) throw const FormatException('Invalid model timestamp.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('Model timestamps require canonical UTC.');
  }
  return parsed;
}
