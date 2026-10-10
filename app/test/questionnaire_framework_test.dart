import 'dart:convert';

import 'package:app/src/privacy_consent.dart';
import 'package:app/src/questionnaire_framework.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic software fixtures only. These are not research instruments or
// evidence of biological, clinical, licensing, or participant approval.
final reviewTime = DateTime.utc(2026, 1, 1);
final completed = DateTime.utc(2026, 1, 2, 10);
final recorded = DateTime.utc(2026, 1, 2, 11);
final now = DateTime.utc(2026, 1, 3);

QuestionnaireReview approved({DateTime? at}) => QuestionnaireReview(
  status: QuestionnaireReviewStatus.approved,
  reviewedAt: at ?? reviewTime,
  reviewerRole: 'Synthetic test reviewer role',
  reference: 'synthetic-fixture-review-only',
);

QuestionnaireApproval approval({
  QuestionnaireReview? biological,
  QuestionnaireReview? youth,
  QuestionnaireReview? software,
  QuestionnaireReview? permissions,
  bool granted = true,
}) => QuestionnaireApproval(
  biological: biological ?? approved(),
  youthAppropriateness: youth ?? approved(),
  software: software ?? approved(),
  permissions: permissions ?? approved(),
  permissionsGranted: granted,
);

QuestionnaireItem item(String id, {bool required = true}) => QuestionnaireItem(
  id: id,
  prompt: 'Synthetic codec fixture $id; not a health question.',
  required: required,
  choices: [
    QuestionnaireChoice(id: 'zero', label: 'Fixture option zero', value: 0),
    QuestionnaireChoice(id: 'four', label: 'Fixture option four', value: 4),
  ],
);

InstrumentDefinition instrument({
  String id = 'synthetic-framework-fixture',
  String version = 'test-v1',
  String language = 'en',
  List<PrivacyAgeBand>? ages,
  List<QuestionnaireItem>? items,
  QuestionnaireApproval? review,
  QuestionnaireScoringSpec scoring = const QuestionnaireScoringSpec.none(),
}) => InstrumentDefinition(
  id: id,
  version: version,
  instrumentName: 'Synthetic implementation fixture, not an instrument',
  language: language,
  source: 'Synthetic test source',
  citation: 'Synthetic test citation',
  permissionReference: 'Synthetic digital-use permission fixture',
  intendedPopulation: 'Synthetic test cases only',
  recallPeriod: 'Synthetic test recall metadata',
  supportedPrivacyAgeBands: ages ?? [PrivacyAgeBand.adult],
  items: items ?? [item('required'), item('optional', required: false)],
  approval: review ?? approval(),
  scoring: scoring,
);

QuestionnaireScoringSpec scoring({QuestionnaireReview? review}) =>
    QuestionnaireScoringSpec.externalReviewed(
      id: 'synthetic-external-method',
      version: 'test-score-v1',
      reference: 'Synthetic scoring reference; no algorithm is implemented',
      review: review ?? approved(),
    );

QuestionnaireResponse response({
  InstrumentDefinition? definition,
  Map<String, String?> answers = const {'required': 'zero', 'optional': null},
  QuestionnaireScore? score,
  PrivacyAgeBand age = PrivacyAgeBand.adult,
  DateTime? completedAt,
  DateTime? recordedAt,
}) {
  final selected = definition ?? instrument();
  return QuestionnaireResponse.create(
    registry: QuestionnaireRegistry([selected]),
    id: 'synthetic-response',
    questionnaireId: selected.id,
    questionnaireVersion: selected.version,
    language: selected.language,
    ageBand: age,
    completedAt: completedAt ?? completed,
    recordedAt: recordedAt ?? recorded,
    now: now,
    responses: answers,
    score: score,
  );
}

QuestionnaireScore score({
  String id = 'synthetic-external-method',
  String version = 'test-score-v1',
  num? total = 0,
  DateTime? at,
}) => QuestionnaireScore(
  methodId: id,
  methodVersion: version,
  scoredAt: at ?? recorded,
  totalScore: total,
);

Map<String, dynamic> roundTrip(Map<String, Object?> json) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(json)) as Map);

void main() {
  test(
    'production catalog is empty and response input cannot install itself',
    () {
      expect(questionnaireCatalog, isEmpty);
      expect(QuestionnaireRegistry().definitions, isEmpty);
      expect(
        () => QuestionnaireResponse.fromJson(
          response().toJson(),
          registry: QuestionnaireRegistry(),
          now: now,
        ),
        throwsFormatException,
      );
    },
  );

  test('definition and partial response round-trip exact original choices', () {
    final original = instrument();
    final decoded = InstrumentDefinition.fromJson(roundTrip(original.toJson()));
    expect(decoded.toJson(), original.toJson());
    final raw = response(definition: decoded);
    final loaded = QuestionnaireResponse.fromJson(
      roundTrip(raw.toJson()),
      registry: QuestionnaireRegistry([decoded]),
      now: now,
    );
    expect(loaded.toJson(), raw.toJson());
    expect(loaded.responses, {'required': 'zero', 'optional': null});
    expect(loaded.definition.items.first.choices.first.value, 0);
    expect(loaded.score, isNull);
    expect(loaded.completionStatus, 'partial');
    expect(loaded.answeredItemCount, 1);
    expect(loaded.completedAt, completed);
    expect(loaded.recordedAt, recorded);
  });

  test(
    'missing keys stay absent and full response completeness is derived',
    () {
      final missing = response(answers: {'required': 'four'});
      expect(missing.responses.containsKey('optional'), isFalse);
      final full = response(answers: {'required': 'four', 'optional': 'zero'});
      expect(full.completionStatus, 'complete');
      expect(full.answeredItemCount, 2);
    },
  );

  test('definitions and responses deeply own immutable input and output', () {
    final choices = [
      QuestionnaireChoice(id: 'x', label: 'Fixture x', value: 0),
    ];
    final items = [
      QuestionnaireItem(
        id: 'x',
        prompt: 'Synthetic item',
        required: true,
        choices: choices,
      ),
    ];
    final ages = [PrivacyAgeBand.adult];
    final definition = instrument(items: items, ages: ages);
    final answers = <String, String?>{'x': 'x'};
    final saved = response(definition: definition, answers: answers);
    choices.clear();
    items.clear();
    ages.clear();
    answers.clear();
    expect(saved.responses, {'x': 'x'});
    expect(definition.items.single.choices.single.value, 0);
    expect(definition.supportedPrivacyAgeBands, {PrivacyAgeBand.adult});
    expect(() => saved.responses.clear(), throwsUnsupportedError);
    expect(() => definition.items.clear(), throwsUnsupportedError);
    expect(
      () => definition.items.first.choices.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => definition.supportedPrivacyAgeBands.clear(),
      throwsUnsupportedError,
    );
    final output = saved.toJson();
    (output['responses'] as Map).clear();
    ((output['definitionSnapshot'] as Map)['items'] as List).clear();
    expect(saved.responses, {'x': 'x'});
    expect(definition.items, hasLength(1));
  });

  test(
    'registry rejects duplicate identity but keeps languages and versions separate',
    () {
      expect(
        () => QuestionnaireRegistry([instrument(), instrument()]),
        throwsFormatException,
      );
      final registry = QuestionnaireRegistry([
        instrument(),
        instrument(language: 'es'),
        instrument(version: 'test-v2'),
      ]);
      expect(registry.definitions, hasLength(3));
      expect(
        registry.find('synthetic-framework-fixture', 'test-v1', 'es')!.language,
        'es',
      );
      expect(() => registry.definitions.clear(), throwsUnsupportedError);
    },
  );

  test(
    'unreviewed domains and absent permission independently close availability',
    () {
      for (final review in [
        approval(biological: QuestionnaireReview()),
        approval(software: QuestionnaireReview()),
        approval(permissions: QuestionnaireReview()),
        approval(granted: false),
        approval(
          biological: QuestionnaireReview(
            status: QuestionnaireReviewStatus.rejected,
          ),
        ),
      ]) {
        final definition = instrument(review: review);
        expect(
          definition.isAvailable(ageBand: PrivacyAgeBand.adult, now: now),
          isFalse,
        );
        expect(() => response(definition: definition), throwsFormatException);
      }
    },
  );

  test(
    'youth support requires youth review and under-13 is never supported',
    () {
      final adult = instrument(review: approval(youth: QuestionnaireReview()));
      expect(
        adult.isAvailable(ageBand: PrivacyAgeBand.adult, now: now),
        isTrue,
      );
      final youth = instrument(
        ages: [PrivacyAgeBand.adult, PrivacyAgeBand.age13to15],
        review: approval(youth: QuestionnaireReview()),
      );
      expect(
        youth.isAvailable(ageBand: PrivacyAgeBand.age13to15, now: now),
        isFalse,
      );
      expect(
        youth.isAvailable(ageBand: PrivacyAgeBand.adult, now: now),
        isFalse,
      );
      expect(
        () => response(definition: adult, age: PrivacyAgeBand.age16to17),
        throwsFormatException,
      );
      expect(
        () => instrument(ages: [PrivacyAgeBand.under13]),
        throwsFormatException,
      );
      expect(() => instrument(ages: []), throwsFormatException);
    },
  );

  test(
    'future reviews and reviews after submission cannot enable intake retroactively',
    () {
      for (final at in [DateTime.utc(2026, 2), recorded]) {
        expect(
          () => response(
            definition: instrument(
              review: approval(permissions: approved(at: at)),
            ),
          ),
          throwsFormatException,
        );
      }
      expect(
        instrument().isAvailable(
          ageBand: PrivacyAgeBand.adult,
          now: DateTime(2026, 1, 3),
        ),
        isFalse,
      );
    },
  );

  test('approved metadata requires actual non-placeholder review records', () {
    for (final text in ['', '  ', 'TBD', 'pending', 'unknown']) {
      expect(
        () => QuestionnaireReview(
          status: QuestionnaireReviewStatus.approved,
          reviewedAt: reviewTime,
          reviewerRole: text,
          reference: 'Synthetic reference',
        ),
        throwsFormatException,
      );
    }
    expect(
      () => QuestionnaireReview(status: QuestionnaireReviewStatus.approved),
      throwsFormatException,
    );
    final json = instrument().toJson()..['permissionReference'] = 'TBD';
    expect(
      InstrumentDefinition.fromJson(
        json,
      ).isAvailable(ageBand: PrivacyAgeBand.adult, now: now),
      isFalse,
    );
  });

  test(
    'invalid item identities, repeated values and non-finite options fail',
    () {
      expect(() => instrument(items: []), throwsFormatException);
      expect(
        () => instrument(items: [item('x'), item('x')]),
        throwsFormatException,
      );
      for (final choices in [
        <QuestionnaireChoice>[],
        [
          QuestionnaireChoice(id: 'x', label: 'A', value: 0),
          QuestionnaireChoice(id: 'x', label: 'B', value: 1),
        ],
        [
          QuestionnaireChoice(id: 'x', label: 'A', value: 0),
          QuestionnaireChoice(id: 'y', label: 'B', value: 0.0),
        ],
      ]) {
        expect(
          () => QuestionnaireItem(
            id: 'x',
            prompt: 'Synthetic fixture',
            required: true,
            choices: choices,
          ),
          throwsFormatException,
        );
      }
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => QuestionnaireChoice(id: 'x', label: 'Fixture', value: value),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'unknown items, choices and empty submissions fail without coercion',
    () {
      for (final answers in <Map<String, String?>>[
        {},
        {'required': null},
        {'required': '0'},
        {'unknown': 'zero'},
      ]) {
        expect(() => response(answers: answers), throwsFormatException);
      }
      expect(
        response(answers: {'optional': 'zero'}).completionStatus,
        'partial',
      );
      final raw = response().toJson()..['responses'] = {'required': 0};
      expect(
        () => QuestionnaireResponse.fromJson(
          raw,
          registry: QuestionnaireRegistry([instrument()]),
          now: now,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'intake rejects timezone-free times, future records and reversed timing',
    () {
      for (final date in [DateTime(2026, 1, 2), DateTime.utc(2026, 2)]) {
        expect(() => response(completedAt: date), throwsFormatException);
      }
      expect(() => response(recordedAt: reviewTime), throwsFormatException);
      expect(
        () => response(recordedAt: DateTime.utc(2026, 2)),
        throwsFormatException,
      );
      for (final value in ['2026-01-02T10:00:00', '2026-02-30T10:00:00.000Z']) {
        final raw = response().toJson()..['completedAt'] = value;
        expect(
          () => QuestionnaireResponse.fromJson(
            raw,
            registry: QuestionnaireRegistry([instrument()]),
            now: now,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'original snapshot and definition identity cannot be silently replaced',
    () {
      final registry = QuestionnaireRegistry([instrument()]);
      for (final patch in <Map<String, Object?>>[
        {'questionnaireVersion': 'test-v2'},
        {'language': 'es'},
        {'questionnaireId': 'other'},
        {'source': 'model'},
        {'completionStatus': 'complete'},
        {'answeredItemCount': 2},
        {'schemaVersion': 2},
      ]) {
        expect(
          () => QuestionnaireResponse.fromJson(
            {...response().toJson(), ...patch},
            registry: registry,
            now: now,
          ),
          throwsFormatException,
        );
      }
      final raw = roundTrip(response().toJson());
      ((raw['definitionSnapshot'] as Map)['items'] as List).first['prompt'] =
          'Changed synthetic fixture';
      expect(
        () => QuestionnaireResponse.fromJson(raw, registry: registry, now: now),
        throwsFormatException,
      );
    },
  );

  test('decoding ignores map order but preserves item and option order', () {
    final raw = roundTrip(response().toJson());
    final snapshot = raw['definitionSnapshot'] as Map<String, dynamic>;
    raw['definitionSnapshot'] = Map.fromEntries(
      snapshot.entries.toList().reversed,
    );
    expect(
      QuestionnaireResponse.fromJson(
        raw,
        registry: QuestionnaireRegistry([instrument()]),
        now: now,
      ).responses['required'],
      'zero',
    );
    (raw['definitionSnapshot'] as Map)['items'] = (snapshot['items'] as List)
        .reversed
        .toList();
    expect(
      () => QuestionnaireResponse.fromJson(
        raw,
        registry: QuestionnaireRegistry([instrument()]),
        now: now,
      ),
      throwsFormatException,
    );
  });

  test(
    'scoring is absent by default and needs the exact reviewed external method',
    () {
      expect(() => response(score: score()), throwsFormatException);
      final definition = instrument(scoring: scoring());
      for (final invalid in [
        score(id: 'other'),
        score(version: 'other'),
        score(at: reviewTime),
        score(at: DateTime.utc(2026, 2)),
      ]) {
        expect(
          () => response(definition: definition, score: invalid),
          throwsFormatException,
        );
      }
      expect(
        () => response(
          definition: instrument(
            scoring: scoring(review: QuestionnaireReview()),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => response(
          definition: definition,
          answers: {'optional': 'four'},
          score: score(),
        ),
        throwsFormatException,
      );
      final scored = response(definition: definition, score: score());
      expect(scored.score!.totalScore, 0);
      expect(scored.responses['required'], 'zero');
      expect(scored.responses['optional'], isNull);
      expect(
        QuestionnaireResponse.fromJson(
          roundTrip(scored.toJson()),
          registry: QuestionnaireRegistry([definition]),
          now: now,
        ).toJson(),
        scored.toJson(),
      );
    },
  );

  test(
    'scores preserve finite totals and subscales without defaults or mutation',
    () {
      final subscales = <String, num>{'fixture-subscale': 2.5};
      final value = QuestionnaireScore(
        methodId: 'synthetic-external-method',
        methodVersion: 'test-score-v1',
        scoredAt: recorded,
        subscaleScores: subscales,
      );
      subscales.clear();
      expect(value.totalScore, isNull);
      expect(value.subscaleScores, {'fixture-subscale': 2.5});
      expect(() => value.subscaleScores.clear(), throwsUnsupportedError);
      (value.toJson()['subscaleScores'] as Map).clear();
      expect(value.subscaleScores, isNotEmpty);
      expect(() => score(total: null), throwsFormatException);
      for (final invalid in [double.nan, double.infinity]) {
        expect(() => score(total: invalid), throwsFormatException);
        expect(
          () => QuestionnaireScore(
            methodId: 'x',
            methodVersion: 'v1',
            scoredAt: recorded,
            subscaleScores: {'x': invalid},
          ),
          throwsFormatException,
        );
      }
    },
  );
}
