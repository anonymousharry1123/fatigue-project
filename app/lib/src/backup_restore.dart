part of 'app_controller.dart';

/// An immutable preview bound to the account and device state that was reviewed.
class DeviceBackupPreview {
  DeviceBackupPreview._({
    required this.sourceLabels,
    required this.sourceIndex,
    required this.newRecords,
    required this.duplicates,
    required this.differingRecords,
    required this.skippedOutcomes,
    required this.profileDiffers,
    required this.profileName,
    required this.signalCount,
    required this.checkInCount,
    required this.outcomeCount,
    required this.coachCount,
    required this.skippedCoachActions,
    required this._owner,
    required this._revision,
    required this._fingerprint,
    required List<SignalReading> signals,
    required List<DailyCheckIn> checkIns,
    required List<OutcomeRecord> outcomes,
    required this._profile,
    required this._coach,
  }) : _signals = List.unmodifiable(signals),
       _checkIns = List.unmodifiable(checkIns),
       _outcomes = List.unmodifiable(outcomes);

  final List<String> sourceLabels;
  final int sourceIndex;
  final int newRecords;
  final int duplicates;
  final int differingRecords;
  final int skippedOutcomes;
  final bool profileDiffers;
  final String profileName;
  final int signalCount;
  final int checkInCount;
  final int outcomeCount;
  final int coachCount;
  final int skippedCoachActions;
  final String? _owner;
  final int _revision;
  final String _fingerprint;
  final List<SignalReading> _signals;
  final List<DailyCheckIn> _checkIns;
  final List<OutcomeRecord> _outcomes;
  final UserProfile _profile;
  final _CoachBackupActions _coach;
}

extension DeviceBackupRestoration on AppController {
  bool get canRestoreDeviceBackup => _canProcessData && !isPrivacyBusy;

  String _backupRestoreFingerprint() => jsonEncode(
    syncCanonical({
      'inputs': InputSyncSnapshot.fromState(
        _cloudState(migrationVersion: localMigrationVersion),
      ).toJson(),
      'outcomes': _outcomes.map((item) => item.toJson()).toList(),
      'pendingOutcomes': _pendingOutcomeWrites.map(
        (key, value) => MapEntry(key, value?.toJson()),
      ),
      'consent': outcomeConsent,
      'consentAt': outcomeConsentUpdatedAt,
      'coach': _coachSyncJson(),
      'statuses': _recommendationStatuses.map(
        (id, value) => MapEntry(id, value.name),
      ),
      'feedback': _recommendationFeedback,
      'dismissed': _dismissedRiskAlertIds.toList()..sort(),
      'availablePlans': _recommendations.map((item) => item.id).toList()
        ..sort(),
      'availableAlerts': _riskAlerts.map((item) => item.id).toList()..sort(),
    }),
  );

  DeviceBackupPreview previewDeviceBackup(String raw, {int sourceIndex = 0}) {
    if (!canRestoreDeviceBackup) {
      throw StateError(
        'Sign in and finish privacy review before restoring data.',
      );
    }
    if (utf8.encode(raw).length > 20 * 1024 * 1024) {
      throw const FormatException('The backup must be smaller than 20 MB.');
    }
    try {
      final file = _backupMap(jsonDecode(raw));
      if (file['backupVersion'] != 1 ||
          file['backupType'] != 'tonyoDeviceData') {
        throw const FormatException('Choose a Tonyo device backup JSON file.');
      }
      final owner = file['ownerUid'];
      if (owner != cloudUid || (owner != null && owner is! String)) {
        throw const FormatException(
          'This backup belongs to a different account. Open it in its original account.',
        );
      }
      final sources = <Map<String, dynamic>>[_backupMap(file['local'])];
      final labels = <String>['Saved device data'];
      final recovery = file['beforeCloudRestore'];
      if (recovery != null) {
        final saved = _backupMap(recovery);
        if (saved['ownerUid'] != owner) {
          throw const FormatException(
            'The recovery copy belongs to another account.',
          );
        }
        sources.add(_backupMap(saved['local']));
        labels.add('Recovery copy before cloud restore');
        final earlier = saved['earlierSnapshots'] ?? [];
        if (earlier is! List) {
          throw const FormatException('Invalid recovery copies.');
        }
        for (var index = 0; index < earlier.length; index++) {
          final item = _backupMap(earlier[index]);
          if (item['ownerUid'] != owner) {
            throw const FormatException(
              'A recovery copy belongs to another account.',
            );
          }
          sources.add(_backupMap(item['local']));
          labels.add('Earlier recovery copy ${index + 1}');
        }
      }
      if (sourceIndex < 0 || sourceIndex >= sources.length) {
        throw const FormatException('Choose an available recovery copy.');
      }
      final local = sources[sourceIndex];
      for (final candidate in [
        local['privacyOwnerUid'],
        (local['inputSync'] as Map?)?['uid'],
        (local['outcomeSync'] as Map?)?['uid'],
        (local['coachSync'] as Map?)?['uid'],
        (local['modelTransparencyCache'] as Map?)?['uid'],
      ]) {
        if (candidate != null && candidate != owner) {
          throw const FormatException(
            'The backup contains data from another account.',
          );
        }
      }
      final importedSignals = _backupRows(local['signals'], (data) {
        _backupId(data['id']);
        _backupDate(data['timestamp']);
        for (final key in ['recordedAt', 'syncedAt']) {
          if (data[key] != null) _backupDate(data[key]);
        }
        final signal = SignalReading.fromJson(data);
        if (!signal.value.isFinite ||
            signal.value < 0 ||
            signal.value > _backupSignalMaximum(signal.type) ||
            !signal.quality.isFinite ||
            signal.quality < 0 ||
            signal.quality > 1) {
          throw const FormatException('A signal has an invalid value.');
        }
        return signal;
      }, (item) => item.id);
      final importedCheckIns = _backupRows(local['checkIns'], (data) {
        _backupId(data['id']);
        _backupDate(data['timestamp']);
        if (data['recordedAt'] != null) _backupDate(data['recordedAt']);
        for (final key in ['energy', 'mood', 'stress']) {
          final rating = data[key];
          if (rating is! num || !rating.isFinite || rating < 1 || rating > 10) {
            throw const FormatException('A check-in has an invalid rating.');
          }
        }
        return DailyCheckIn.fromJson(data);
      }, (item) => item.id);
      OutcomeRecord parseOutcome(Map<String, dynamic> data) {
        _backupId(data['id']);
        _backupId(data['sourceId']);
        if (data['recommendationId'] != null) {
          _backupId(data['recommendationId']);
        }
        _backupDate(data['observedAt']);
        _backupDate(data['recordedAt']);
        final item = OutcomeRecord.fromJson(data);
        if (!item.value.isFinite ||
            (data['consentVersion'] ?? 1) != 1 ||
            (item.type == OutcomeType.observedEnergy
                ? !CheckInLogic.isValidRating(item.value)
                : item.value < ReactionTestLogic.minValidMs ||
                      item.value > ReactionTestLogic.maxValidMs)) {
          throw const FormatException('An outcome has an invalid value.');
        }
        return item;
      }

      final allOutcomes = _backupRows(
        local['outcomes'] ?? [],
        parseOutcome,
        (item) => item.id,
      );
      final consentAt = local['outcomeConsentUpdatedAt'];
      if (consentAt != null) _backupDate(consentAt);
      var journalConsentMatches = true;
      final journal = local['outcomeSync'];
      if (journal != null) {
        final pending = _backupMap(journal);
        if (pending['version'] != 1 || pending['uid'] != owner) {
          throw const FormatException('The pending outcome backup is invalid.');
        }
        final pendingConsent = pending['consentAt'];
        if (pendingConsent != null) _backupDate(pendingConsent);
        journalConsentMatches = _sameOutcomeConsentAt(
          consentAt == null ? null : DateTime.parse(consentAt as String),
          pendingConsent == null
              ? null
              : DateTime.parse(pendingConsent as String),
        );
        final merged = {for (final outcome in allOutcomes) outcome.id: outcome};
        for (final entry in _backupMap(pending['writes']).entries) {
          _backupId(entry.key);
          if (entry.value == null) {
            merged.remove(entry.key);
          } else {
            final outcome = parseOutcome(_backupMap(entry.value));
            if (outcome.id != entry.key) {
              throw const FormatException(
                'A pending outcome ID does not match its record.',
              );
            }
            merged[entry.key] = outcome;
          }
        }
        allOutcomes
          ..clear()
          ..addAll(merged.values);
      }
      final canRestoreOutcomes =
          outcomeConsent &&
          journalConsentMatches &&
          local['outcomeConsent'] == true &&
          _sameOutcomeConsentAt(
            outcomeConsentUpdatedAt,
            consentAt == null ? null : DateTime.parse(consentAt as String),
          );
      final importedOutcomes = canRestoreOutcomes
          ? allOutcomes
          : <OutcomeRecord>[];
      final allCoach = _CoachBackupActions.parse(local);
      final knownPlans = {
        ...allCoach.recommendations.keys,
        ..._recommendations.map((item) => item.id),
      };
      final knownAlerts = {
        ...allCoach.alerts.keys,
        ..._riskAlerts.map((item) => item.id),
      };
      final coach = _CoachBackupActions(
        recommendations: allCoach.recommendations,
        alerts: allCoach.alerts,
        statuses: Map.unmodifiable(
          Map.of(allCoach.statuses)
            ..removeWhere((id, _) => !knownPlans.contains(id)),
        ),
        feedback: Map.unmodifiable(
          Map.of(allCoach.feedback)
            ..removeWhere((id, _) => !knownPlans.contains(id)),
        ),
        dismissed: Set.unmodifiable(
          allCoach.dismissed.where(knownAlerts.contains),
        ),
      );
      final profileData = _backupMap(local['profile']);
      for (final field in ['name', 'ageRange', 'role', 'goal']) {
        if (profileData[field] is! String) {
          throw const FormatException('The saved profile is incomplete.');
        }
      }
      final importedProfile = UserProfile.fromJson(profileData);
      if (!importedProfile.wakeHour.isFinite ||
          importedProfile.wakeHour < 0 ||
          importedProfile.wakeHour >= 24 ||
          !importedProfile.bedHour.isFinite ||
          importedProfile.bedHour < 0 ||
          importedProfile.bedHour >= 24) {
        throw const FormatException('The saved profile has invalid times.');
      }
      var additions = 0;
      var duplicates = 0;
      var differences = 0;
      void count(Map<String, Object?> existing, Map<String, Object?> incoming) {
        for (final row in incoming.entries) {
          if (!existing.containsKey(row.key)) {
            additions++;
          } else if (sameSyncValue(existing[row.key], row.value)) {
            duplicates++;
          } else {
            differences++;
          }
        }
      }

      count(
        {for (final row in signals) row.id: row.toJson()},
        {for (final row in importedSignals) row.id: row.toJson()},
      );
      count(
        {for (final row in checkIns) row.id: row.toJson()},
        {for (final row in importedCheckIns) row.id: row.toJson()},
      );
      count(
        {for (final row in _outcomes) row.id: row.toJson()},
        {for (final row in importedOutcomes) row.id: row.toJson()},
      );
      for (final id in {
        ...coach.recommendations.keys,
        ...coach.statuses.keys,
        ...coach.feedback.keys,
      }) {
        final incoming = coach.recommendations[id];
        final status = incoming?.status ?? coach.statuses[id];
        final helpful = incoming?.helpful ?? coach.feedback[id];
        final record = _recommendations
            .where((item) => item.id == id)
            .firstOrNull;
        final currentStatus = _recommendationStatuses[id] ?? record?.status;
        final currentFeedback = _recommendationFeedback[id] ?? record?.helpful;
        final present = currentStatus != null || currentFeedback != null;
        count(
          {
            if (present)
              id: {
                if (status != null) 'status': currentStatus?.name,
                if (helpful != null) 'helpful': currentFeedback,
              },
          },
          {
            id: {
              if (status != null) 'status': status.name,
              'helpful': ?helpful,
            },
          },
        );
      }
      for (final id in {...coach.alerts.keys, ...coach.dismissed}) {
        final current = _riskAlerts.where((item) => item.id == id).firstOrNull;
        count(
          {
            if (current != null || _dismissedRiskAlertIds.contains(id))
              id:
                  _dismissedRiskAlertIds.contains(id) ||
                  current?.dismissed == true,
          },
          {id: true},
        );
      }
      return DeviceBackupPreview._(
        sourceLabels: List.unmodifiable(labels),
        sourceIndex: sourceIndex,
        newRecords: additions,
        duplicates: duplicates,
        differingRecords: differences,
        skippedOutcomes: allOutcomes.length - importedOutcomes.length,
        profileDiffers: !sameSyncValue(
          profile.toJson(),
          importedProfile.toJson(),
        ),
        profileName: importedProfile.name,
        signalCount: importedSignals.length,
        checkInCount: importedCheckIns.length,
        outcomeCount: importedOutcomes.length,
        coachCount: coach.count,
        skippedCoachActions: allCoach.count - coach.count,
        owner: cloudUid,
        revision: _sessionRevision,
        fingerprint: _backupRestoreFingerprint(),
        signals: importedSignals,
        checkIns: importedCheckIns,
        outcomes: importedOutcomes,
        profile: importedProfile,
        coach: coach,
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'The backup is damaged or contains invalid records.',
      );
    }
  }

  Future<void> restoreDeviceBackup(
    DeviceBackupPreview preview, {
    bool replaceExisting = false,
    bool restoreProfile = false,
  }) async {
    final ensureCurrent = _beginMutation();
    void ensurePreview() {
      ensureCurrent();
      if (isPrivacyBusy ||
          preview._owner != cloudUid ||
          preview._revision != _sessionRevision ||
          preview._fingerprint != _backupRestoreFingerprint()) {
        throw StateError(
          'Device data changed. Refresh the backup preview before restoring.',
        );
      }
    }

    ensurePreview();
    if (preview.newRecords == 0 &&
        (!replaceExisting || preview.differingRecords == 0) &&
        (!restoreProfile || !preview.profileDiffers)) {
      return;
    }
    while (_pendingCloudPush != null ||
        _pendingOutcomePush != null ||
        _pendingCoachPush != null ||
        _pendingGuidanceWrite != null) {
      await _pendingCloudPush;
      await _pendingOutcomePush;
      await _pendingCoachPush;
      await _pendingGuidanceWrite;
      ensurePreview();
    }
    final task = _restoreDeviceBackupNow(
      preview,
      ensurePreview,
      replaceExisting: replaceExisting,
      restoreProfile: restoreProfile,
    );
    _pendingCloudPush = task;
    try {
      await task;
    } finally {
      if (identical(_pendingCloudPush, task)) _pendingCloudPush = null;
    }
    ensureCurrent();
    // The device write is complete before a network attempt starts. The normal
    // sync journal owns retries, so a failed upload cannot undo the restore.
    await _commit(energyInputsChanged: true);
    ensureCurrent();
    if (hasPendingOutcomeChanges) await _retryOutcomeSync();
    if (hasPendingCoachChanges) await _retryCoachSync();
    notifyListeners();
  }

  Future<void> _restoreDeviceBackupNow(
    DeviceBackupPreview preview,
    void Function() ensurePreview, {
    required bool replaceExisting,
    required bool restoreProfile,
  }) async {
    await _discardPersonalizedModel();
    ensurePreview();
    final preferences = await SharedPreferences.getInstance();
    ensurePreview();
    // Stage the complete payload synchronously, then leave the visible state
    // untouched until durable storage confirms it. A failed write cannot roll
    // back unrelated edits that arrived while the write was pending.
    void Function() capture() {
      final savedSignals = [...signals];
      final savedCheckIns = [...checkIns];
      final savedOutcomes = [..._outcomes];
      final savedProfile = profile;
      final outcomeWrites = {..._pendingOutcomeWrites};
      final outcomeOwner = _outcomeSyncOwnerUid;
      final outcomeConsentAt = _outcomeSyncConsentAt;
      final outcomeGeneration = _outcomeSyncGeneration;
      final outcomeRefreshGeneration = _outcomeRefreshGeneration;
      final outcomeLoading = isOutcomeLoading;
      final savedOutcomeError = outcomeError;
      final coachOwner = _coachSyncOwnerUid;
      final coachWrites = {..._pendingCoachWrites};
      final alertWrites = {..._pendingAlertWrites};
      final coachGeneration = _coachSyncGeneration;
      final statuses = {..._recommendationStatuses};
      final feedback = {..._recommendationFeedback};
      final dismissed = {..._dismissedRiskAlertIds};
      final recommendations = [..._recommendations];
      final alerts = [..._riskAlerts];
      final guidanceGeneration = _guidanceRefreshGeneration;
      final guidanceLoading = isGuidanceLoading;
      return () {
        signals = savedSignals;
        checkIns = savedCheckIns;
        _outcomes = savedOutcomes;
        profile = savedProfile;
        _pendingOutcomeWrites
          ..clear()
          ..addAll(outcomeWrites);
        _outcomeSyncOwnerUid = outcomeOwner;
        _outcomeSyncConsentAt = outcomeConsentAt;
        _outcomeSyncGeneration = outcomeGeneration;
        _outcomeRefreshGeneration = outcomeRefreshGeneration;
        isOutcomeLoading = outcomeLoading;
        outcomeError = savedOutcomeError;
        _coachSyncOwnerUid = coachOwner;
        _pendingCoachWrites
          ..clear()
          ..addAll(coachWrites);
        _pendingAlertWrites
          ..clear()
          ..addAll(alertWrites);
        _coachSyncGeneration = coachGeneration;
        _recommendationStatuses
          ..clear()
          ..addAll(statuses);
        _recommendationFeedback
          ..clear()
          ..addAll(feedback);
        _dismissedRiskAlertIds
          ..clear()
          ..addAll(dismissed);
        _recommendations = recommendations;
        _riskAlerts = alerts;
        _guidanceRefreshGeneration = guidanceGeneration;
        isGuidanceLoading = guidanceLoading;
      };
    }

    final restoreOriginal = capture();
    late void Function() installRestored;
    late String encoded;
    List<T> merge<T>(List<T> current, List<T> incoming, String Function(T) id) {
      final merged = {for (final row in current) id(row): row};
      for (final row in incoming) {
        if (replaceExisting || !merged.containsKey(id(row))) {
          merged[id(row)] = row;
        }
      }
      return merged.values.toList();
    }

    final sourceCheckInIds = {
      ...preview._checkIns.map((item) => item.id),
      for (final outcome in preview._outcomes)
        if (outcome.source == OutcomeSource.checkIn &&
            checkIns.any((item) => item.id == outcome.sourceId))
          outcome.sourceId,
    };
    final sourceReactionIds = {
      for (final signal in preview._signals)
        if (signal.type == SignalType.reactionTime ||
            signals.any(
              (item) =>
                  item.id == signal.id && item.type == SignalType.reactionTime,
            ))
          signal.id,
      for (final outcome in preview._outcomes)
        if (outcome.source == OutcomeSource.reactionSignal &&
            signals.any((item) => item.id == outcome.sourceId))
          outcome.sourceId,
    };
    try {
      signals = merge(signals, preview._signals, (item) => item.id)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      checkIns = merge(checkIns, preview._checkIns, (item) => item.id)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      for (final outcome in preview._outcomes) {
        final current = _outcomes
            .where((item) => item.id == outcome.id)
            .firstOrNull;
        if (current == null ||
            (replaceExisting &&
                !sameSyncValue(current.toJson(), outcome.toJson()))) {
          _queueOutcomeWrite(outcome.id, outcome);
        }
      }
      _outcomes = merge(_outcomes, preview._outcomes, (item) => item.id);
      // Linked learning results follow the source value selected by the user,
      // including when the phone's version is kept over a differing backup.
      _reconcileSourceLinkedOutcomes(
        checkInIds: sourceCheckInIds,
        reactionSignalIds: sourceReactionIds,
      );
      if (restoreProfile) profile = preview._profile;
      _restoreCoachBackupActions(
        preview._coach,
        replaceExisting: replaceExisting,
      );
      installRestored = capture();
      encoded = jsonEncode(_json());
    } finally {
      restoreOriginal();
    }
    try {
      if (!await preferences.setString(AppController._storageKey, encoded)) {
        throw StateError(
          'Could not save restored data to this device. Please retry.',
        );
      }
      ensurePreview();
    } on Object {
      // A concurrent edit/session change supersedes the staged snapshot. Keep
      // its current cache too, so restart cannot adopt an unreviewed restore.
      // SharedPreferences also updates its in-memory cache before a failed
      // platform write, so repair that cache even when the first write failed.
      try {
        if (deletionPending ||
            (preview._revision != _sessionRevision &&
                !onboardingComplete &&
                _privacyConsent == null)) {
          await preferences.remove(AppController._storageKey);
        } else {
          await preferences.setString(
            AppController._storageKey,
            jsonEncode(_json()),
          );
        }
      } on Object {
        // The original storage error remains actionable; never install the
        // staged data or start its cloud upload when persistence is uncertain.
      }
      rethrow;
    }
    final latestGuidanceGeneration = _guidanceRefreshGeneration;
    final latestOutcomeGeneration = _outcomeRefreshGeneration;
    installRestored();
    if (_guidanceRefreshGeneration < latestGuidanceGeneration) {
      _guidanceRefreshGeneration = latestGuidanceGeneration;
    }
    if (_outcomeRefreshGeneration < latestOutcomeGeneration) {
      _outcomeRefreshGeneration = latestOutcomeGeneration;
    }
    // Supersede in-flight views which were calculated from pre-restore data.
    _scoreRefreshGeneration++;
    _forecastRefreshGeneration++;
    _guidanceRefreshGeneration++;
    _insightsRefreshGeneration++;
    _outcomeRefreshGeneration++;
    _scoreSnapshot = null;
    _todaySignals = [];
    _forecastsByDay.clear();
    _insightsSnapshot = null;
    notifyListeners();
  }
}

// Generous import bounds preserve valid Health/manual records while keeping
// duration conversion and chart arithmetic safe for untrusted JSON numbers.
double _backupSignalMaximum(SignalType type) => switch (type) {
  SignalType.sleep ||
  SignalType.nap ||
  SignalType.bedtime ||
  SignalType.study ||
  SignalType.exercise ||
  SignalType.screenTime ||
  SignalType.sleepAwake ||
  SignalType.sleepCore ||
  SignalType.sleepDeep ||
  SignalType.sleepRem ||
  SignalType.sleepUnspecified => 48,
  SignalType.hydration || SignalType.caffeine => 100,
  SignalType.steps => 1000000,
  SignalType.reactionTime || SignalType.hrv => 60000,
  SignalType.restingHeartRate => 400,
};

Map<String, dynamic> _backupMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('The backup structure is invalid.');
  }
  return Map<String, dynamic>.from(value);
}

void _backupId(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.contains('/') ||
      value == '.' ||
      value == '..' ||
      utf8.encode(value).length > 1500) {
    throw const FormatException('The backup contains an invalid record ID.');
  }
}

void _backupDate(Object? value) {
  if (value is! String) throw const FormatException('A saved date is invalid.');
  final parts = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):?(\d{2}))$',
  ).firstMatch(value);
  if (parts == null || DateTime.tryParse(value) == null) {
    throw const FormatException('A saved date is invalid.');
  }
  final year = int.parse(parts[1]!);
  final month = int.parse(parts[2]!);
  final day = int.parse(parts[3]!);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      int.parse(parts[4]!) > 23 ||
      int.parse(parts[5]!) > 59 ||
      int.parse(parts[6]!) > 59 ||
      (parts[7] != null &&
          (int.parse(parts[7]!) > 23 || int.parse(parts[8]!) > 59))) {
    throw const FormatException('A saved date is invalid.');
  }
}

List<T> _backupRows<T>(
  Object? source,
  T Function(Map<String, dynamic>) parse,
  String Function(T) id,
) {
  if (source is! List || source.length > 100000) {
    throw const FormatException(
      'The backup record list is invalid or too large.',
    );
  }
  final result = <T>[];
  final ids = <String>{};
  for (final raw in source) {
    final item = parse(_backupMap(raw));
    if (!ids.add(id(item))) {
      throw const FormatException('The backup contains repeated record IDs.');
    }
    result.add(item);
  }
  return result;
}
