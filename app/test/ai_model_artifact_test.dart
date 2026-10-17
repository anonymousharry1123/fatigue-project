import 'dart:convert';

import 'package:app/src/ai1_protocol.dart';
import 'package:app/src/ai_model_artifact.dart';
import 'package:flutter_test/flutter_test.dart';

final _protocol = Ai1Protocol.draft();
final _fit = DateTime.utc(2026, 10, 6, 10);
final _at = DateTime.utc(2026, 10, 7, 10, 3);
final _cutoff = DateTime.utc(2026, 10, 7, 10);

AiModelArtifact _model({
  String id = 'fixture-model-v1',
  String candidate = 'M1',
  String owner = 'fixture-owner',
  String participant = 'fixture-person',
  String timezone = 'Etc/UTC',
  int generation = 0,
  double constant = 6.25,
  double intercept = 1,
  double slope = 0.5,
  Ai1Protocol? protocol,
  List<String>? training,
}) => AiModelArtifact.synthetic(
  artifactId: id,
  candidateId: candidate,
  protocol: protocol ?? _protocol,
  ownerScope: owner,
  participantKey: participant,
  timezone: timezone,
  fittedAt: _fit,
  dataCutoff: _fit,
  dataGeneration: generation,
  trainingOpportunityIds:
      training ?? (candidate == 'B1' ? ['day-1'] : ['day-1', 'day-2']),
  constantPrediction: candidate == 'M1' ? null : constant,
  intercept: candidate == 'M1' ? intercept : null,
  slope: candidate == 'M1' ? slope : null,
);

AiModelInferenceContext _context({
  String owner = 'fixture-owner',
  String participant = 'fixture-person',
  String timezone = 'Etc/UTC',
  int generation = 0,
  bool synthetic = true,
  bool signedIn = true,
  bool consent = true,
  Ai1Protocol? protocol,
  DateTime? at,
  DateTime? featureCutoff,
}) => AiModelInferenceContext(
  ownerScope: owner,
  participantKey: participant,
  protocol: protocol ?? _protocol,
  timezone: timezone,
  at: at ?? _at,
  featureCutoff: featureCutoff ?? _cutoff,
  dataGeneration: generation,
  synthetic: synthetic,
  signedIn: signedIn,
  consentGranted: consent,
);

AiModelRegistry _registry() =>
    AiModelRegistry.synthetic(ownerScope: 'fixture-owner', timezone: 'Etc/UTC');

void _absent(AiModelPrediction result, String reason) {
  expect(result.predicted, isFalse);
  expect(result.prediction, isNull);
  expect(result.rawPrediction, isNull);
  expect(result.abstentionReason, reason);
  expect(result.toJson()['status'], 'abstained');
}

void main() {
  for (final candidate in ['B0', 'B1', 'M1']) {
    test(
      '$candidate round trip preserves exact versioned synthetic contract',
      () {
        final model = _model(candidate: candidate);
        final restored = AiModelArtifact.fromJson(model.toJson());
        expect(restored.fingerprint, model.fingerprint);
        expect(restored.trainingOpportunityIds, model.trainingOpportunityIds);
        expect(restored.protocol.id, _protocol.id);
        expect(restored.protocol.measurement, _protocol.measurement);
        expect(
          restored.featureSchema,
          candidate == 'M1'
              ? [
                  {'name': 'main_sleep_duration_hours', 'unit': 'hours'},
                ]
              : isEmpty,
        );
        expect(restored.synthetic, isTrue);
        expect(restored.realDataTrainingAllowed, isFalse);
        expect(restored.appModelActivationAllowed, isFalse);
        expect(
          restored.toJson()['historyPolicy'],
          'frozen_personal_fit_no_inference_updates',
        );
      },
    );
  }

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'legacy schema': (json) => json['schemaVersion'] = 1,
    'new unknown schema': (json) => json['schemaVersion'] = 'model-v999',
    'real evidence': (json) => json['evidenceKind'] = 'captured_local_history',
    'non synthetic': (json) => json['synthetic'] = false,
    'real training permission': (json) =>
        json['realDataTrainingAllowed'] = true,
    'live activation permission': (json) =>
        json['appModelActivationAllowed'] = true,
    'unknown field': (json) => json['referenceRulesVersion'] = 1,
    'missing field': (json) => json.remove('timezone'),
    'source change': (json) => json['sleepSource'] = 'appleHealth',
    'protocol change': (json) => json['protocolId'] = 'old-protocol',
    'wording change': (json) =>
        (json['measurement'] as Map)['sharedHeading'] = 'Different wording',
    'target scale change': (json) =>
        (json['targetSchema'] as Map)['maximum'] = 100,
    'clipping change': (json) => (json['outputRule'] as Map)['minimum'] = 0,
    'rounding change': (json) =>
        (json['outputRule'] as Map)['rounding'] = 'integer',
    'feature name change': (json) =>
        ((json['featureSchema'] as List).single as Map)['name'] =
            'sleepDeviation',
    'feature unit change': (json) =>
        ((json['featureSchema'] as List).single as Map)['unit'] = 'minutes',
    'extra feature': (json) => (json['featureSchema'] as List).add({
      'name': 'energy',
      'unit': 'rating',
    }),
    'missing slope': (json) => (json['coefficients'] as Map).remove('slope'),
    'extra coefficient': (json) =>
        (json['coefficients'] as Map)['constantPrediction'] = 5,
    'infinite coefficient': (json) =>
        (json['coefficients'] as Map)['slope'] = double.infinity,
    'NaN coefficient': (json) =>
        (json['coefficients'] as Map)['intercept'] = double.nan,
    'string coefficient': (json) =>
        (json['coefficients'] as Map)['slope'] = '0.5',
    'duplicate training IDs': (json) =>
        json['trainingOpportunityIds'] = ['same', 'same'],
    'wrong training count': (json) => json['trainingCount'] = 10,
    'fractional generation': (json) => json['dataGeneration'] = 0.5,
    'negative generation': (json) => json['dataGeneration'] = -1,
    'unknown zone': (json) => json['timezone'] = 'Unknown/Nowhere',
    'noncanonical time': (json) =>
        json['fittedAt'] = '2026-10-06T10:00:00+00:00',
    'impossible time': (json) => json['fittedAt'] = '2026-10-32T10:00:00.000Z',
    'cutoff after fit': (json) => json['dataCutoff'] = _fit
        .add(const Duration(microseconds: 1))
        .toIso8601String(),
    'updating model': (json) => json['historyPolicy'] = 'update_on_inference',
  };
  for (final entry in corruptions.entries) {
    test('deserialization rejects ${entry.key}', () {
      final json =
          jsonDecode(jsonEncode(_model().toJson())) as Map<String, dynamic>;
      entry.value(json);
      expect(() => AiModelArtifact.fromJson(json), throwsFormatException);
    });
  }

  test('legacy residual payload cannot be interpreted as an evening model', () {
    expect(
      () => AiModelArtifact.fromJson({
        'modelVersion': 1,
        'schemaVersion': 1,
        'weights': [0.5],
        'intercept': 1,
        'referenceRulesVersion': 1,
      }),
      throwsFormatException,
    );
  });

  test(
    'factory enforces candidate, personal history and finite parameters',
    () {
      expect(() => _model(candidate: 'M2'), throwsFormatException);
      expect(
        () => _model(candidate: 'B0', training: []),
        throwsFormatException,
      );
      expect(
        () => _model(candidate: 'B1', training: ['a', 'b']),
        throwsFormatException,
      );
      expect(() => _model(training: ['a']), throwsFormatException);
      expect(() => _model(training: ['a', 'a']), throwsFormatException);
      expect(
        () => _model(candidate: 'B0', constant: 11),
        throwsFormatException,
      );
      expect(() => _model(intercept: double.infinity), throwsFormatException);
      expect(() => _model(owner: ''), throwsFormatException);
    },
  );

  test('training identities and returned JSON cannot mutate an artifact', () {
    final training = ['day-1', 'day-2'];
    final artifact = _model(training: training);
    final fingerprint = artifact.fingerprint;
    training[0] = 'changed';
    expect(
      () => artifact.trainingOpportunityIds.add('extra'),
      throwsUnsupportedError,
    );
    final json = artifact.toJson();
    (json['coefficients'] as Map)['slope'] = 99.0;
    (json['trainingOpportunityIds'] as List).clear();
    (json['measurement'] as Map).clear();
    expect(artifact.fingerprint, fingerprint);
  });

  test(
    'M1 keeps fractional predictions and preserves a negative coefficient',
    () {
      final result = _model(intercept: 10, slope: -0.5).predict(
        context: _context(),
        sleepHours: 7.5,
        sleepAvailableAt: _cutoff,
      );
      expect(result.predicted, isTrue);
      expect(result.rawPrediction, 6.25);
      expect(result.prediction, 6.25);
      expect(result.abstentionReason, isNull);
    },
  );

  test('clipping retains the underlying raw output at both scale ends', () {
    final low = _model(
      intercept: -10,
      slope: 1,
    ).predict(context: _context(), sleepHours: 8, sleepAvailableAt: _cutoff);
    final high = _model(
      intercept: 10,
      slope: 1,
    ).predict(context: _context(), sleepHours: 8, sleepAvailableAt: _cutoff);
    expect(low.rawPrediction, -2);
    expect(low.prediction, 1);
    expect(high.rawPrediction, 18);
    expect(high.prediction, 10);
  });

  test('finite coefficients that overflow at inference produce abstention', () {
    _absent(
      _model(
        intercept: 1e308,
        slope: 1e308,
      ).predict(context: _context(), sleepHours: 8, sleepAvailableAt: _cutoff),
      'non_finite_prediction',
    );
  });

  for (final candidate in ['B0', 'B1']) {
    test(
      '$candidate frozen baseline needs no sleep and never updates from it',
      () {
        final model = _model(candidate: candidate);
        expect(model.predict(context: _context()).prediction, 6.25);
        expect(
          model.predict(context: _context(), sleepHours: 9).prediction,
          6.25,
        );
        expect(model.featureSchema, isEmpty);
      },
    );
  }

  final contexts = <String, AiModelInferenceContext Function()>{
    'synthetic_session_required': () => _context(synthetic: false),
    'signed_out': () => _context(signedIn: false),
    'consent_withdrawn': () => _context(consent: false),
    'owner_mismatch': () => _context(owner: 'another-owner'),
    'participant_mismatch': () => _context(participant: 'another-person'),
    'stale_data_generation': () => _context(generation: 1),
    'timezone_mismatch': () => _context(timezone: 'Europe/London'),
    'incompatible_protocol': () => _context(
      protocol: Ai1Protocol.draft(sleepSource: Ai1SleepSource.appleHealth),
    ),
    'invalid_feature_cutoff': () =>
        _context(featureCutoff: _at.add(const Duration(microseconds: 1))),
    'artifact_not_available_at_prediction': () => _context(
      at: _fit.subtract(const Duration(microseconds: 1)),
      featureCutoff: _fit.subtract(const Duration(microseconds: 1)),
    ),
  };
  for (final entry in contexts.entries) {
    test('inference fails closed for ${entry.key}', () {
      _absent(
        _model().predict(
          context: entry.value(),
          sleepHours: 8,
          sleepAvailableAt: _cutoff,
        ),
        entry.key,
      );
    });
  }

  test('training cutoff cannot exceed prediction feature cutoff', () {
    _absent(
      _model().predict(
        context: _context(
          featureCutoff: _fit.subtract(const Duration(microseconds: 1)),
        ),
        sleepHours: 8,
        sleepAvailableAt: _fit.subtract(const Duration(hours: 1)),
      ),
      'artifact_not_available_at_prediction',
    );
  });

  test('M1 missing sleep or unproven availability has no neutral fallback', () {
    _absent(_model().predict(context: _context()), 'missing_sleep');
    _absent(
      _model().predict(context: _context(), sleepHours: 8),
      'unknown_sleep_availability',
    );
  });

  test('M1 rejects nonfinite and out-of-range sleep', () {
    for (final hours in [double.nan, double.infinity, 0.49, 16.01]) {
      _absent(
        _model().predict(
          context: _context(),
          sleepHours: hours,
          sleepAvailableAt: _cutoff,
        ),
        'invalid_sleep',
      );
    }
  });

  test(
    'sleep availability includes exact cutoff and excludes one microsecond later',
    () {
      final model = _model();
      expect(
        model
            .predict(
              context: _context(),
              sleepHours: 8,
              sleepAvailableAt: _cutoff,
            )
            .predicted,
        isTrue,
      );
      _absent(
        model.predict(
          context: _context(),
          sleepHours: 8,
          sleepAvailableAt: _cutoff.add(const Duration(microseconds: 1)),
        ),
        'sleep_after_cutoff',
      );
    },
  );

  test('staging and activation are separate immutable transitions', () {
    final original = _registry();
    final staged = original.stage(_model(candidate: 'B0'));
    expect(original.artifacts, isEmpty);
    expect(staged.activeArtifact, isNull);
    _absent(staged.predict(context: _context()), 'no_active_artifact');
    final active = staged.activate('fixture-model-v1');
    expect(active.predict(context: _context()).prediction, 6.25);
    expect(staged.activeArtifact, isNull);
    expect(() => active.artifacts.clear(), throwsUnsupportedError);
    expect(() => active.activationHistory.add('other'), throwsUnsupportedError);
    expect(() => original.activate('unknown'), throwsStateError);
  });

  test(
    'conflicting artifact identity is rejected; identical retry is idempotent',
    () {
      final model = _model(candidate: 'B0');
      final staged = _registry().stage(model);
      expect(
        staged.stage(AiModelArtifact.fromJson(model.toJson())),
        same(staged),
      );
      expect(
        () => staged.stage(_model(candidate: 'B0', constant: 7)),
        throwsStateError,
      );
    },
  );

  test('registry staging rejects owner, timezone and generation mismatch', () {
    final registry = _registry();
    expect(() => registry.stage(_model(owner: 'other')), throwsStateError);
    expect(
      () => registry.stage(_model(timezone: 'Europe/London')),
      throwsStateError,
    );
    expect(() => registry.stage(_model(generation: 1)), throwsStateError);
  });

  test('rollback explicitly restores the previously active frozen version', () {
    final staged = _registry()
        .stage(_model(candidate: 'B0'))
        .stage(_model(id: 'second', candidate: 'B1', constant: 4));
    final first = staged.activate('fixture-model-v1');
    final second = first.activate('second');
    expect(second.predict(context: _context()).prediction, 4);
    final rolledBack = second.rollback();
    expect(rolledBack.activeArtifactId, 'fixture-model-v1');
    expect(rolledBack.predict(context: _context()).prediction, 6.25);
    expect(second.activeArtifactId, 'second');
    expect(() => rolledBack.rollback(), throwsStateError);
  });

  test('incompatible active source abstains until explicit rollback', () {
    final manual = _model(candidate: 'B0');
    final health = _model(
      id: 'health',
      candidate: 'B0',
      constant: 4,
      protocol: Ai1Protocol.draft(sleepSource: Ai1SleepSource.appleHealth),
    );
    final active = _registry()
        .stage(manual)
        .activate(manual.artifactId)
        .stage(health)
        .activate(health.artifactId);
    _absent(active.predict(context: _context()), 'incompatible_protocol');
    expect(active.rollback().predict(context: _context()).prediction, 6.25);
  });

  test('missing M1 input never silently falls back to a staged baseline', () {
    final active = _registry()
        .stage(_model(id: 'baseline', candidate: 'B0'))
        .activate('baseline')
        .stage(_model())
        .activate('fixture-model-v1');
    _absent(active.predict(context: _context()), 'missing_sleep');
  });

  test(
    'erasure invalidates active, staged and rollback caches through generation',
    () {
      final model = _model(candidate: 'B0');
      final active = _registry().stage(model).activate(model.artifactId);
      final cleared = active.invalidateCache();
      expect(cleared.dataGeneration, 1);
      expect(cleared.artifacts, isEmpty);
      expect(cleared.activationHistory, isEmpty);
      _absent(
        cleared.predict(context: _context(generation: 1)),
        'no_active_artifact',
      );
      _absent(
        model.predict(context: _context(generation: 1)),
        'stale_data_generation',
      );
      expect(() => cleared.stage(model), throwsStateError);
      expect(() => cleared.rollback(), throwsStateError);
      final refreshed = cleared
          .stage(_model(candidate: 'B0', generation: 1))
          .activate(model.artifactId);
      expect(
        refreshed.predict(context: _context(generation: 1)).predicted,
        isTrue,
      );
    },
  );

  test(
    'sign-out and consent withdrawal erase registry and prevent restaging',
    () {
      final active = _registry()
          .stage(_model(candidate: 'B0'))
          .activate('fixture-model-v1');
      final signedOut = active.signOut();
      final withdrawn = active.withdrawConsent();
      _absent(signedOut.predict(context: _context()), 'signed_out');
      _absent(withdrawn.predict(context: _context()), 'consent_withdrawn');
      for (final stopped in [signedOut, withdrawn]) {
        expect(stopped.artifacts, isEmpty);
        expect(stopped.activationHistory, isEmpty);
        expect(
          () => stopped.stage(_model(generation: stopped.dataGeneration)),
          throwsStateError,
        );
        expect(() => stopped.rollback(), throwsStateError);
      }
    },
  );

  test(
    'timezone transition clears old versions and invalidates pending context',
    () {
      final active = _registry()
          .stage(_model(candidate: 'B0'))
          .activate('fixture-model-v1');
      expect(active.changeTimezone('Etc/UTC'), same(active));
      final moved = active.changeTimezone('Europe/London');
      expect(moved.artifacts, isEmpty);
      expect(moved.dataGeneration, 1);
      _absent(moved.predict(context: _context()), 'stale_data_generation');
      _absent(
        moved.predict(context: _context(generation: 1)),
        'timezone_mismatch',
      );
      expect(() => moved.stage(_model(generation: 1)), throwsStateError);
      expect(
        () => active.changeTimezone('Unknown/Nowhere'),
        throwsFormatException,
      );
    },
  );
}
