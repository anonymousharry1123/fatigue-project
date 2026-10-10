import 'dart:convert';

import 'privacy_consent.dart';

/// No instrument has been selected, licensed, or approved for this application.
const List<InstrumentDefinition> questionnaireCatalog = [];

enum QuestionnaireReviewStatus { pending, approved, rejected }

enum QuestionnaireScoringMethod { none, externalReviewed }

/// Records a review; it does not authenticate a reviewer or grant user consent.
class QuestionnaireReview {
  QuestionnaireReview({
    this.status = QuestionnaireReviewStatus.pending,
    this.reviewedAt,
    this.reviewerRole,
    this.reference,
  }) {
    if (reviewedAt != null) _requireUtc(reviewedAt!);
    if (status == QuestionnaireReviewStatus.approved &&
        (reviewedAt == null ||
            !_reviewText(reviewerRole) ||
            !_reviewText(reference))) {
      throw const FormatException(
        'An approved review needs its review record.',
      );
    }
  }

  final QuestionnaireReviewStatus status;
  final DateTime? reviewedAt;
  final String? reviewerRole;
  final String? reference;

  bool approvedAt(DateTime now) =>
      status == QuestionnaireReviewStatus.approved &&
      reviewedAt != null &&
      !reviewedAt!.isAfter(now) &&
      _reviewText(reviewerRole) &&
      _reviewText(reference);

  Map<String, Object?> toJson() => {
    'status': status.name,
    'reviewedAt': reviewedAt?.toIso8601String(),
    'reviewerRole': reviewerRole,
    'reference': reference,
  };

  factory QuestionnaireReview.fromJson(Map<String, dynamic> json) =>
      QuestionnaireReview(
        status: _enum(QuestionnaireReviewStatus.values, json['status']),
        reviewedAt: json['reviewedAt'] == null
            ? null
            : _date(json['reviewedAt']),
        reviewerRole: _nullableString(json['reviewerRole']),
        reference: _nullableString(json['reference']),
      );
}

class QuestionnaireApproval {
  const QuestionnaireApproval({
    required this.biological,
    required this.youthAppropriateness,
    required this.software,
    required this.permissions,
    this.permissionsGranted = false,
  });

  final QuestionnaireReview biological;
  final QuestionnaireReview youthAppropriateness;
  final QuestionnaireReview software;
  final QuestionnaireReview permissions;
  final bool permissionsGranted;

  bool approvedAt(DateTime now, {required bool includesYouth}) =>
      permissionsGranted &&
      biological.approvedAt(now) &&
      software.approvedAt(now) &&
      permissions.approvedAt(now) &&
      (!includesYouth || youthAppropriateness.approvedAt(now));

  Map<String, Object?> toJson() => {
    'biological': biological.toJson(),
    'youthAppropriateness': youthAppropriateness.toJson(),
    'software': software.toJson(),
    'permissions': permissions.toJson(),
    'permissionsGranted': permissionsGranted,
  };

  factory QuestionnaireApproval.fromJson(Map<String, dynamic> json) =>
      QuestionnaireApproval(
        biological: QuestionnaireReview.fromJson(_map(json['biological'])),
        youthAppropriateness: QuestionnaireReview.fromJson(
          _map(json['youthAppropriateness']),
        ),
        software: QuestionnaireReview.fromJson(_map(json['software'])),
        permissions: QuestionnaireReview.fromJson(_map(json['permissions'])),
        permissionsGranted: _bool(json['permissionsGranted']),
      );
}

/// Original option values are retained; no common 1–10 scale is imposed.
class QuestionnaireChoice {
  QuestionnaireChoice({
    required this.id,
    required this.label,
    required this.value,
  }) {
    _text(id);
    _text(label);
    _finite(value);
  }

  final String id;
  final String label;
  final num value;

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'value': value};

  factory QuestionnaireChoice.fromJson(Map<String, dynamic> json) =>
      QuestionnaireChoice(
        id: _string(json['id']),
        label: _string(json['label']),
        value: _number(json['value']),
      );
}

class QuestionnaireItem {
  QuestionnaireItem({
    required this.id,
    required this.prompt,
    required this.required,
    required Iterable<QuestionnaireChoice> choices,
  }) : choices = List.unmodifiable(choices) {
    _text(id);
    _text(prompt);
    if (this.choices.isEmpty ||
        this.choices.map((value) => value.id).toSet().length !=
            this.choices.length ||
        this.choices.map((value) => value.value).toSet().length !=
            this.choices.length) {
      throw const FormatException(
        'Each item needs unique option IDs and values.',
      );
    }
  }

  final String id;
  final String prompt;
  final bool required;
  final List<QuestionnaireChoice> choices;

  Map<String, Object?> toJson() => {
    'id': id,
    'prompt': prompt,
    'required': required,
    'choices': choices.map((choice) => choice.toJson()).toList(),
  };

  factory QuestionnaireItem.fromJson(Map<String, dynamic> json) =>
      QuestionnaireItem(
        id: _string(json['id']),
        prompt: _string(json['prompt']),
        required: _bool(json['required']),
        choices: _list(
          json['choices'],
        ).map((value) => QuestionnaireChoice.fromJson(_map(value))),
      );
}

/// A method identifier and a review are metadata, never an executable formula.
class QuestionnaireScoringSpec {
  const QuestionnaireScoringSpec.none()
    : method = QuestionnaireScoringMethod.none,
      id = null,
      version = null,
      reference = null,
      review = null;

  QuestionnaireScoringSpec.externalReviewed({
    required String id,
    required String version,
    required String reference,
    required QuestionnaireReview this.review,
  }) : method = QuestionnaireScoringMethod.externalReviewed,
       id = id,
       version = version,
       reference = reference {
    _text(id);
    _text(version);
    _text(reference);
  }

  final QuestionnaireScoringMethod method;
  final String? id;
  final String? version;
  final String? reference;
  final QuestionnaireReview? review;

  bool approvedAt(DateTime now) =>
      method == QuestionnaireScoringMethod.none ||
      (_reviewText(id) &&
          _reviewText(version) &&
          _reviewText(reference) &&
          review!.approvedAt(now));

  Map<String, Object?> toJson() => {
    'method': method.name,
    'id': id,
    'version': version,
    'reference': reference,
    'review': review?.toJson(),
  };

  factory QuestionnaireScoringSpec.fromJson(Map<String, dynamic> json) {
    final method = _enum(QuestionnaireScoringMethod.values, json['method']);
    if (method == QuestionnaireScoringMethod.none) {
      if ([
        'id',
        'version',
        'reference',
        'review',
      ].any((key) => json[key] != null)) {
        throw const FormatException(
          'An unscored instrument cannot declare a scorer.',
        );
      }
      return const QuestionnaireScoringSpec.none();
    }
    return QuestionnaireScoringSpec.externalReviewed(
      id: _string(json['id']),
      version: _string(json['version']),
      reference: _string(json['reference']),
      review: QuestionnaireReview.fromJson(_map(json['review'])),
    );
  }
}

class InstrumentDefinition {
  InstrumentDefinition({
    required this.id,
    required this.version,
    required this.instrumentName,
    required this.language,
    required this.source,
    required this.citation,
    required this.permissionReference,
    required this.intendedPopulation,
    required this.recallPeriod,
    required Iterable<PrivacyAgeBand> supportedPrivacyAgeBands,
    required Iterable<QuestionnaireItem> items,
    required this.approval,
    this.scoring = const QuestionnaireScoringSpec.none(),
  }) : supportedPrivacyAgeBands = Set.unmodifiable(supportedPrivacyAgeBands),
       items = List.unmodifiable(items) {
    for (final value in [
      id,
      version,
      instrumentName,
      language,
      source,
      citation,
      permissionReference,
      intendedPopulation,
      recallPeriod,
    ]) {
      _text(value);
    }
    if (this.supportedPrivacyAgeBands.isEmpty ||
        this.supportedPrivacyAgeBands.contains(PrivacyAgeBand.under13) ||
        this.items.isEmpty ||
        this.items.map((item) => item.id).toSet().length != this.items.length) {
      throw const FormatException(
        'Unsupported population or invalid questionnaire items.',
      );
    }
  }

  final String id;
  final String version;
  final String instrumentName;
  final String language;
  final String source;
  final String citation;
  final String permissionReference;
  final String intendedPopulation;
  final String recallPeriod;
  final Set<PrivacyAgeBand> supportedPrivacyAgeBands;
  final List<QuestionnaireItem> items;
  final QuestionnaireApproval approval;
  final QuestionnaireScoringSpec scoring;

  /// Necessary metadata checks only. Privacy, consent, deployment and research
  /// authorization remain separate gates before any future collection UI.
  bool isAvailable({required PrivacyAgeBand ageBand, required DateTime now}) =>
      now.isUtc &&
      ageBand != PrivacyAgeBand.under13 &&
      supportedPrivacyAgeBands.contains(ageBand) &&
      [
        source,
        citation,
        permissionReference,
        intendedPopulation,
        recallPeriod,
      ].every(_reviewText) &&
      approval.approvedAt(
        now,
        includesYouth: supportedPrivacyAgeBands.any(
          (band) => band != PrivacyAgeBand.adult,
        ),
      ) &&
      scoring.approvedAt(now);

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'version': version,
    'instrumentName': instrumentName,
    'language': language,
    'source': source,
    'citation': citation,
    'permissionReference': permissionReference,
    'intendedPopulation': intendedPopulation,
    'recallPeriod': recallPeriod,
    'supportedPrivacyAgeBands': PrivacyAgeBand.values
        .where(supportedPrivacyAgeBands.contains)
        .map((band) => band.name)
        .toList(),
    'items': items.map((item) => item.toJson()).toList(),
    'approval': approval.toJson(),
    'scoring': scoring.toJson(),
  };

  factory InstrumentDefinition.fromJson(Map<String, dynamic> json) {
    _version(json);
    return InstrumentDefinition(
      id: _string(json['id']),
      version: _string(json['version']),
      instrumentName: _string(json['instrumentName']),
      language: _string(json['language']),
      source: _string(json['source']),
      citation: _string(json['citation']),
      permissionReference: _string(json['permissionReference']),
      intendedPopulation: _string(json['intendedPopulation']),
      recallPeriod: _string(json['recallPeriod']),
      supportedPrivacyAgeBands: _list(
        json['supportedPrivacyAgeBands'],
      ).map((value) => _enum(PrivacyAgeBand.values, value)),
      items: _list(
        json['items'],
      ).map((value) => QuestionnaireItem.fromJson(_map(value))),
      approval: QuestionnaireApproval.fromJson(_map(json['approval'])),
      scoring: QuestionnaireScoringSpec.fromJson(_map(json['scoring'])),
    );
  }
}

/// Explicitly provided, trusted definitions only; decoded response snapshots
/// cannot install instruments or approve their own intake.
class QuestionnaireRegistry {
  QuestionnaireRegistry([
    Iterable<InstrumentDefinition> definitions = questionnaireCatalog,
  ]) : definitions = List.unmodifiable(definitions) {
    final identities = <String>{};
    for (final definition in this.definitions) {
      if (!identities.add(
        _identity(definition.id, definition.version, definition.language),
      )) {
        throw const FormatException('Duplicate questionnaire identity.');
      }
    }
  }

  final List<InstrumentDefinition> definitions;

  InstrumentDefinition? find(String id, String version, String language) =>
      definitions
          .where(
            (definition) =>
                definition.id == id &&
                definition.version == version &&
                definition.language == language,
          )
          .firstOrNull;
}

class QuestionnaireScore {
  QuestionnaireScore({
    required this.methodId,
    required this.methodVersion,
    required this.scoredAt,
    this.totalScore,
    Map<String, num> subscaleScores = const {},
  }) : subscaleScores = Map.unmodifiable(subscaleScores) {
    _text(methodId);
    _text(methodVersion);
    _requireUtc(scoredAt);
    if (totalScore == null && subscaleScores.isEmpty) {
      throw const FormatException('An absent score must remain absent.');
    }
    if (totalScore != null) _finite(totalScore!);
    for (final entry in subscaleScores.entries) {
      _text(entry.key);
      _finite(entry.value);
    }
  }

  final String methodId;
  final String methodVersion;
  final DateTime scoredAt;
  final num? totalScore;
  final Map<String, num> subscaleScores;

  Map<String, Object?> toJson() => {
    'methodId': methodId,
    'methodVersion': methodVersion,
    'scoredAt': scoredAt.toIso8601String(),
    'totalScore': totalScore,
    'subscaleScores': Map<String, num>.from(subscaleScores),
  };

  factory QuestionnaireScore.fromJson(Map<String, dynamic> json) =>
      QuestionnaireScore(
        methodId: _string(json['methodId']),
        methodVersion: _string(json['methodVersion']),
        scoredAt: _date(json['scoredAt']),
        totalScore: json['totalScore'] == null
            ? null
            : _number(json['totalScore']),
        subscaleScores: _map(
          json['subscaleScores'],
        ).map((key, value) => MapEntry(key, _number(value))),
      );
}

class QuestionnaireResponse {
  QuestionnaireResponse._({
    required this.id,
    required this.definition,
    required this.ageBand,
    required this.completedAt,
    required this.recordedAt,
    required Map<String, String?> responses,
    required this.score,
  }) : responses = Map.unmodifiable(responses);

  final String id;
  final InstrumentDefinition definition;
  final PrivacyAgeBand ageBand;
  final DateTime completedAt;
  final DateTime recordedAt;
  final Map<String, String?> responses;
  final QuestionnaireScore? score;
  String get source => 'selfReport';
  String get questionnaireId => definition.id;
  String get questionnaireVersion => definition.version;
  String get language => definition.language;
  int get answeredItemCount =>
      responses.values.where((value) => value != null).length;
  String get completionStatus =>
      answeredItemCount == definition.items.length ? 'complete' : 'partial';

  /// No implicit approval, coercion, automatic score, or missing-value fill.
  factory QuestionnaireResponse.create({
    required QuestionnaireRegistry registry,
    required String id,
    required String questionnaireId,
    required String questionnaireVersion,
    required String language,
    required PrivacyAgeBand ageBand,
    required DateTime completedAt,
    required DateTime recordedAt,
    required DateTime now,
    required Map<String, String?> responses,
    QuestionnaireScore? score,
  }) {
    _text(id);
    for (final date in [completedAt, recordedAt, now]) {
      _requireUtc(date);
    }
    final definition = registry.find(
      questionnaireId,
      questionnaireVersion,
      language,
    );
    if (definition == null ||
        !definition.isAvailable(ageBand: ageBand, now: completedAt) ||
        !definition.isAvailable(ageBand: ageBand, now: now) ||
        recordedAt.isBefore(completedAt) ||
        recordedAt.isAfter(now)) {
      throw const FormatException(
        'Questionnaire intake is unavailable or its timing is invalid.',
      );
    }
    final items = {for (final item in definition.items) item.id: item};
    for (final entry in responses.entries) {
      final item = items[entry.key];
      if (item == null ||
          (entry.value != null &&
              !item.choices.any((choice) => choice.id == entry.value))) {
        throw const FormatException(
          'Response does not match the original options.',
        );
      }
    }
    if (responses.values.every((value) => value == null)) {
      throw const FormatException(
        'An empty questionnaire is not a submission.',
      );
    }
    if (score != null) {
      final spec = definition.scoring;
      if (spec.method != QuestionnaireScoringMethod.externalReviewed ||
          !spec.approvedAt(score.scoredAt) ||
          score.methodId != spec.id ||
          score.methodVersion != spec.version ||
          score.scoredAt.isBefore(completedAt) ||
          score.scoredAt.isAfter(now) ||
          definition.items.any(
            (item) => item.required && responses[item.id] == null,
          )) {
        throw const FormatException(
          'Scores require the reviewed method and all required answers.',
        );
      }
    }
    return QuestionnaireResponse._(
      id: id,
      definition: definition,
      ageBand: ageBand,
      completedAt: completedAt,
      recordedAt: recordedAt,
      responses: responses,
      score: score,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'questionnaireId': questionnaireId,
    'questionnaireVersion': questionnaireVersion,
    'language': language,
    'source': source,
    'ageBand': ageBand.name,
    'completedAt': completedAt.toIso8601String(),
    'recordedAt': recordedAt.toIso8601String(),
    'responses': Map<String, String?>.from(responses),
    'completionStatus': completionStatus,
    'answeredItemCount': answeredItemCount,
    'definitionSnapshot': definition.toJson(),
    'score': score?.toJson(),
  };

  factory QuestionnaireResponse.fromJson(
    Map<String, dynamic> json, {
    required QuestionnaireRegistry registry,
    required DateTime now,
  }) {
    _version(json);
    final result = QuestionnaireResponse.create(
      registry: registry,
      id: _string(json['id']),
      questionnaireId: _string(json['questionnaireId']),
      questionnaireVersion: _string(json['questionnaireVersion']),
      language: _string(json['language']),
      ageBand: _enum(PrivacyAgeBand.values, json['ageBand']),
      completedAt: _date(json['completedAt']),
      recordedAt: _date(json['recordedAt']),
      now: now,
      responses: _map(
        json['responses'],
      ).map((key, value) => MapEntry(key, _nullableString(value))),
      score: json['score'] == null
          ? null
          : QuestionnaireScore.fromJson(_map(json['score'])),
    );
    if (json['source'] != 'selfReport' ||
        json['completionStatus'] != result.completionStatus ||
        json['answeredItemCount'] is! int ||
        json['answeredItemCount'] != result.answeredItemCount ||
        _canonical(json['definitionSnapshot']) !=
            _canonical(result.definition.toJson())) {
      throw const FormatException(
        'Response metadata differs from its trusted definition or answers.',
      );
    }
    return result;
  }
}

void _version(Map<String, dynamic> json) {
  if (json['schemaVersion'] is! int || json['schemaVersion'] != 1) {
    throw const FormatException('Unsupported questionnaire schema version.');
  }
}

void _text(String value) {
  if (value.trim().isEmpty || value.length > 10000) {
    throw const FormatException(
      'Questionnaire metadata must contain bounded text.',
    );
  }
}

bool _reviewText(String? value) =>
    value != null &&
    value.trim().isNotEmpty &&
    value.length <= 10000 &&
    !const {
      'unknown',
      'pending',
      'not reviewed',
      'not selected',
      'tbd',
      'todo',
      'none',
      'n/a',
    }.contains(value.trim().toLowerCase());

void _finite(num value) {
  if (!value.isFinite) {
    throw const FormatException('A numeric value must be finite.');
  }
}

void _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw const FormatException('Use an explicit UTC timestamp.');
  }
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected text.');
  return value;
}

String? _nullableString(Object? value) => value == null ? null : _string(value);
num _number(Object? value) {
  if (value is! num) throw const FormatException('Expected a number.');
  _finite(value);
  return value;
}

bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('Expected a boolean.');
  return value;
}

List<dynamic> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected a list.');
  return value;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a string-keyed object.');
  }
  return Map<String, dynamic>.from(value);
}

T _enum<T extends Enum>(List<T> values, Object? raw) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw const FormatException('Unknown questionnaire enum value.');
}

DateTime _date(Object? value) {
  if (value is! String) {
    throw const FormatException('Expected a UTC timestamp.');
  }
  final parsed = DateTime.tryParse(value);
  // Canonical UTC also rejects normalized invalid dates and timezone-free input.
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('Invalid UTC timestamp.');
  }
  return parsed;
}

String _identity(String id, String version, String language) =>
    jsonEncode([id, version, language]);
String _canonical(Object? value) {
  Object? sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(value[key])};
    }
    if (value is List) return value.map(sorted).toList();
    return value;
  }

  return jsonEncode(sorted(value));
}
