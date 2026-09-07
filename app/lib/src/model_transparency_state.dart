import 'energy_model_summary.dart';
import 'models.dart';
import 'score_explanation.dart';

/// Read-only presentation of an already loaded score and account metadata.
/// This object cannot query Firebase, train a model, or change consent.
class ModelTransparencyState {
  const ModelTransparencyState({
    required this.snapshot,
    required this.viewedAt,
    this.scoreFromCloud = false,
    this.offline = false,
    this.signedIn = false,
    this.consentEnabled = false,
    this.loading = false,
    this.localModel,
    this.cloudModel,
    this.metadataFetchedAt,
    this.accountUpdatedAt,
    this.localModelStatus = '',
  });

  final ScoreSnapshot snapshot;
  final DateTime viewedAt;
  final bool scoreFromCloud;
  final bool offline;
  final bool signedIn;
  final bool consentEnabled;
  final bool loading;
  final EnergyModelSummary? localModel;
  final EnergyModelSummary? cloudModel;
  final DateTime? metadataFetchedAt;
  final DateTime? accountUpdatedAt;
  final String localModelStatus;

  bool get personalizedEnergyApplied =>
      signedIn &&
      consentEnabled &&
      localModel != null &&
      snapshot.deterministicEnergy != null &&
      snapshot.personalizedModelVersion == 'energy-ridge-v1';

  String get scoreSourceLabel => scoreFromCloud
      ? personalizedEnergyApplied
            ? 'Saved Firebase score · on-device adjustment'
            : 'Saved Firebase score'
      : offline
      ? 'Calculated from cached inputs'
      : 'Calculated on this device';

  String get energyModelVersion =>
      snapshot.energyModelVersion ?? 'Not recorded in this snapshot';
  String get cognitiveModelVersion => snapshot.hasCognitiveScore
      ? snapshot.cognitiveModelVersion ?? 'Not recorded in this snapshot'
      : 'No Cognitive score recorded';

  String get modelStatusTitle => personalizedEnergyApplied
      ? 'Personalized Energy'
      : localModel != null && signedIn && consentEnabled
      ? 'Model ready · baseline used'
      : 'Standard scoring on this device';

  String get modelStatusDetail {
    if (personalizedEnergyApplied) {
      final delta = snapshot.energy - snapshot.deterministicEnergy!;
      final sign = delta > 0 ? '+' : '−';
      return 'The standard Energy estimate is ${snapshot.deterministicEnergy}. '
          'Your on-device model contributes $sign${delta.abs()} points to this '
          'score. The adjustment is limited to ±10; Cognitive and confidence '
          'are unchanged.';
    }
    if (localModel != null && signedIn && consentEnabled) {
      return 'An accepted Energy model is stored on this phone, but no learned '
          'adjustment is applied to this score. A correction can round to zero, '
          'or fall back when inputs are unavailable or safety checks fail.';
    }
    if (!consentEnabled) {
      return 'Outcome learning is off. Both scores use the standard rules; '
          'no learned Energy correction is applied. This screen never changes '
          'your consent.';
    }
    if (cloudModel != null) {
      return 'Firebase contains a model summary, not its weights. Without an '
          'accepted local model, this device uses the standard rules. A model '
          'trained on another device is not automatically installed here.';
    }
    return 'There is no accepted Energy model available on this device. '
        'Personalization needs at least 14 genuine, consented labeled days '
        'and must improve held-out predictions. Preparation and training are '
        'separate, explicit actions.';
  }

  ScoreExplanation explanation(ScoreHead head) =>
      ScoreExplanation.build(snapshot: snapshot, head: head, now: viewedAt);

  List<String> get notices => List.unmodifiable([
    if (loading)
      'A score refresh is in progress. These details describe the currently '
          'displayed estimate until that refresh finishes.',
    if (offline)
      'Cloud sync is unavailable. Cached inputs and previously loaded metadata '
          'may not include changes made on another device.',
    if (!signedIn)
      'Local view: no Firebase model metadata is loaded for an active account.',
    if (signedIn && metadataFetchedAt == null)
      'Account model metadata has not been loaded. Missing metadata does not '
          'prove that no model summary exists in Firebase.',
    if (metadataFetchedAt != null)
      'Firebase metadata is a saved view from the last account load, not a '
          'live connection. Account update time is not model training time.',
    if (localModel != null &&
        cloudModel != null &&
        localModel!.trainedAt.isAfter(cloudModel!.trainedAt))
      'The local model is newer than the last loaded Firebase summary. '
          'This screen does not fetch or retry a metadata write.',
    if (localModel != null && cloudModel == null)
      'A local model is available, but no supported Firebase summary has been '
          'loaded for comparison. Metadata sync status cannot be inferred '
          'from that absence.',
    if (localModel != null && localModelStatus.contains('sync unavailable'))
      'The Energy model was accepted locally, but its metadata could not be '
          'synced. The local model remains usable.',
  ]);
}
