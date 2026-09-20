part of 'app_controller.dart';

enum CloudSyncFailureKind {
  connection,
  authentication,
  permission,
  conflict,
  deviceStorage,
  unknown,
}

class _PendingRecommendationAction {
  const _PendingRecommendationAction({
    required this.record,
    this.status,
    this.helpful,
  });
  final Recommendation record;
  final RecommendationStatus? status;
  final bool? helpful;

  Map<String, Object?> toJson() => {
    'record': syncCanonical(recommendationToCloud(record)),
    if (status != null) 'status': status!.name,
    if (helpful != null) 'helpful': helpful,
  };

  factory _PendingRecommendationAction.fromJson(
    String id,
    Map<String, dynamic> json,
  ) {
    if (id.isEmpty || id.contains('/')) {
      throw const FormatException('Invalid Coach ID');
    }
    final record = recommendationFromCloud(
      id,
      Map<String, dynamic>.from(json['record'] as Map),
    );
    if (record.day == null) throw const FormatException('Missing Coach day');
    final status = json['status'] == null
        ? null
        : RecommendationStatus.values.byName(json['status'] as String);
    final helpful = json['helpful'] as bool?;
    if (status == null && helpful == null) {
      throw const FormatException('Missing Coach action');
    }
    return _PendingRecommendationAction(
      record: record,
      status: status,
      helpful: helpful,
    );
  }
}

extension _CoachSync on AppController {
  Object _beginCloudSyncActivity() {
    _cloudSyncActivities.removeWhere(
      (_, owner) => owner.uid != cloudUid || owner.revision != _sessionRevision,
    );
    final token = Object();
    _cloudSyncActivities[token] = (uid: cloudUid, revision: _sessionRevision);
    isCloudSyncing = true;
    return token;
  }

  void _endCloudSyncActivity(Object token) {
    final owner = _cloudSyncActivities.remove(token);
    if (owner == null ||
        owner.uid != cloudUid ||
        owner.revision != _sessionRevision ||
        _disposed) {
      return;
    }
    // Privacy generation controls which response can mutate data. Activity
    // ownership is separate: every completed request must release its spinner,
    // while a newer request keeps its own activity until it finishes.
    isCloudSyncing = _cloudSyncActivities.isNotEmpty;
    notifyListeners();
  }

  void _clearCoachSync() {
    _coachSyncGeneration++;
    _coachSyncOwnerUid = null;
    _pendingCoachWrites.clear();
    _pendingAlertWrites.clear();
  }

  void _reconcileCoachSync() {
    if (_coachSyncOwnerUid != null &&
        cloudUid != null &&
        _coachSyncOwnerUid != cloudUid) {
      _clearCoachSync();
      _recommendationStatuses.clear();
      _recommendationFeedback.clear();
      _dismissedRiskAlertIds.clear();
    }
  }

  void _queueRecommendationAction(
    Recommendation record, {
    RecommendationStatus? status,
    bool? helpful,
  }) {
    if (cloudUid == null || cloudRepository == null) return;
    _reconcileCoachSync();
    _coachSyncOwnerUid = cloudUid;
    final previous = _pendingCoachWrites[record.id];
    _pendingCoachWrites[record.id] = _PendingRecommendationAction(
      record: record,
      status: status ?? previous?.status,
      helpful: helpful ?? previous?.helpful,
    );
  }

  Map<String, Object?> _coachSyncJson() => {
    'version': 1,
    'uid': _coachSyncOwnerUid,
    'recommendations': {
      for (final entry in _pendingCoachWrites.entries)
        entry.key: entry.value.toJson(),
    },
    'alerts': {
      for (final entry in _pendingAlertWrites.entries)
        entry.key: syncCanonical(riskAlertToCloud(entry.value)),
    },
  };

  void _restoreCoachSync(Object? raw) {
    _clearCoachSync();
    if (raw is! Map || raw['version'] != 1 || raw['uid'] is! String) return;
    try {
      _coachSyncOwnerUid = raw['uid'] as String;
      for (final entry in (raw['recommendations'] as Map).entries) {
        final id = entry.key as String;
        _pendingCoachWrites[id] = _PendingRecommendationAction.fromJson(
          id,
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      for (final entry in (raw['alerts'] as Map).entries) {
        final id = entry.key as String;
        if (id.isEmpty || id.contains('/')) {
          throw const FormatException('Invalid alert ID');
        }
        final alert = riskAlertFromCloud(
          id,
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (alert.day == null || !alert.dismissed) {
          throw const FormatException('Invalid alert action');
        }
        _pendingAlertWrites[id] = alert;
      }
      if (!isSignedOut) _reconcileCoachSync();
    } on Object {
      _clearCoachSync();
    }
  }

  Future<void> _retryCoachSync() async {
    final uid = cloudUid;
    final revision = _sessionRevision;
    while (_pendingCoachPush != null || _pendingGuidanceWrite != null) {
      // A derived-plan replacement already in flight must finish before an
      // action writes its specific fields; otherwise it can undo the action.
      try {
        await _pendingGuidanceWrite;
      } on Object {
        /* retry the action */
      }
      await _pendingCoachPush;
    }
    if (uid != cloudUid || revision != _sessionRevision || !_canProcessData) {
      return;
    }
    _reconcileCoachSync();
    if (!hasPendingCoachChanges) return;
    final task = _flushCoachSync();
    _pendingCoachPush = task;
    try {
      await task;
    } finally {
      if (identical(_pendingCoachPush, task)) _pendingCoachPush = null;
      scheduleCloudRetry();
    }
  }

  Future<void> _flushCoachSync() async {
    final uid = cloudUid;
    final repository = cloudRepository;
    if (uid == null || repository == null) return;
    final revision = _sessionRevision;
    final generation = _coachSyncGeneration;
    bool current() =>
        revision == _sessionRevision &&
        generation == _coachSyncGeneration &&
        uid == cloudUid &&
        uid == _coachSyncOwnerUid &&
        _canProcessData;
    try {
      await _writeLocal();
      if (!current()) return;
      for (final entry in _pendingCoachWrites.entries.toList()) {
        if (!current()) return;
        if (!identical(_pendingCoachWrites[entry.key], entry.value)) continue;
        await repository.applyRecommendationAction(
          uid,
          entry.value.record,
          status: entry.value.status,
          helpful: entry.value.helpful,
        );
        if (!current()) return;
        if (identical(_pendingCoachWrites[entry.key], entry.value)) {
          _pendingCoachWrites.remove(entry.key);
        }
        _markCloudUploadSuccess();
        await _writeLocal();
      }
      for (final entry in _pendingAlertWrites.entries.toList()) {
        if (!current()) return;
        if (!identical(_pendingAlertWrites[entry.key], entry.value)) continue;
        await repository.applyRiskAlertDismissal(uid, entry.value);
        if (!current()) return;
        if (identical(_pendingAlertWrites[entry.key], entry.value)) {
          _pendingAlertWrites.remove(entry.key);
        }
        _markCloudUploadSuccess();
        await _writeLocal();
      }
      if (!current()) return;
      guidanceError = hasPendingCoachChanges
          ? 'Coach changes saved on this device · cloud update pending'
          : null;
    } on Object catch (error) {
      if (!current()) return;
      guidanceError =
          'Coach changes saved on this device · cloud update pending';
      _recordCloudFailure(error);
    }
  }

  void _markCloudUploadSuccess() {
    _lastCloudSyncOwnerUid = cloudUid;
    _lastCloudSyncAt = _now();
    if (!hasAnyPendingCloudChanges) {
      cloudSyncError = null;
      cloudSyncFailureKind = null;
      cloudSyncConflict = false;
      _cloudRetryDelay = const Duration(seconds: 5);
      _cloudRetryTimer?.cancel();
      _cloudRetryTimer = null;
    }
  }

  void _recordCloudFailure(Object error) {
    // A separate Coach/outcome failure cannot hide a still-unresolved input
    // conflict or turn foreground retries back on. The input push/resolution
    // path alone clears this blocking state.
    if (cloudSyncConflict && error is! InputSyncConflict) return;
    if (error is StateError &&
        error.message.contains(
          'belongs to another account and cannot be migrated',
        )) {
      cloudSyncFailureKind = CloudSyncFailureKind.authentication;
      cloudSyncError =
          '${error.message} Sign in to the original account to recover its device data.';
      return;
    }
    final code = error is FirebaseException ? error.code.toLowerCase() : '';
    final detail = error.toString().toLowerCase();
    cloudSyncFailureKind = error is InputSyncConflict
        ? CloudSyncFailureKind.conflict
        : {
            'unauthenticated',
            'user-token-expired',
            'invalid-user-token',
            'user-disabled',
          }.contains(code)
        ? CloudSyncFailureKind.authentication
        : code == 'permission-denied'
        ? CloudSyncFailureKind.permission
        : {
                'unavailable',
                'deadline-exceeded',
                'network-request-failed',
                'aborted',
                'resource-exhausted',
              }.contains(code) ||
              detail.contains('offline') ||
              detail.contains('disconnect') ||
              detail.contains('network') ||
              detail.contains('timeout')
        ? CloudSyncFailureKind.connection
        : detail.contains('could not save to this device')
        ? CloudSyncFailureKind.deviceStorage
        : CloudSyncFailureKind.unknown;
    cloudSyncConflict = cloudSyncFailureKind == CloudSyncFailureKind.conflict;
    cloudSyncError = switch (cloudSyncFailureKind!) {
      CloudSyncFailureKind.conflict =>
        'Another device changed the same data. Your edits are saved here. Review sync in Profile.',
      CloudSyncFailureKind.authentication =>
        'Your sign-in needs refreshing. Device changes are kept here. Sign in again to sync.',
      CloudSyncFailureKind.permission =>
        'Cloud access was denied. Device changes are kept here. Review account privacy or sign in again.',
      CloudSyncFailureKind.connection =>
        'Saved on this device. Waiting for a connection; sync retries while the app is open.',
      CloudSyncFailureKind.deviceStorage =>
        'This device could not save your changes. Keep the app open, free storage, and retry.',
      CloudSyncFailureKind.unknown =>
        'Saved on this device. Cloud sync could not finish; tap Retry sync in Profile.',
    };
  }
}

extension CloudRetry on AppController {
  bool get _retryEligible =>
      !_disposed &&
      _appInForeground &&
      isReady &&
      !isSignedOut &&
      !_isSigningOut &&
      !deletionPending &&
      !isPrivacyBusy &&
      cloudUid != null &&
      cloudRepository != null &&
      _privacyConsent?.validAt(_now()) == true &&
      guardianConsentBlocker == null &&
      hasAnyPendingCloudChanges &&
      !cloudSyncConflict &&
      cloudSyncFailureKind != CloudSyncFailureKind.authentication &&
      cloudSyncFailureKind != CloudSyncFailureKind.permission &&
      cloudSyncFailureKind != CloudSyncFailureKind.deviceStorage;

  void scheduleCloudRetry() {
    if (!_retryEligible) {
      _cloudRetryTimer?.cancel();
      _cloudRetryTimer = null;
      return;
    }
    if (_cloudRetryTimer != null) return;
    _cloudRetryTimer = Timer(_cloudRetryDelay, () async {
      _cloudRetryTimer = null;
      if (!_retryEligible) return;
      _cloudRetryDelay = Duration(
        seconds: (_cloudRetryDelay.inSeconds * 2).clamp(5, 60),
      );
      try {
        await syncPendingChanges();
      } on Object catch (error) {
        if (_retryEligible) _recordCloudFailure(error);
      } finally {
        scheduleCloudRetry();
      }
    });
  }

  /// Upload the durable journals without regenerating every derived view.
  Future<void> syncPendingChanges() async {
    if (_pendingSyncCycle != null) return _pendingSyncCycle;
    if (_disposed ||
        isSignedOut ||
        _isSigningOut ||
        deletionPending ||
        isPrivacyBusy ||
        cloudUid == null) {
      return;
    }
    final task = _syncPendingChangesNow();
    _pendingSyncCycle = task;
    try {
      await task;
    } finally {
      if (identical(_pendingSyncCycle, task)) _pendingSyncCycle = null;
      scheduleCloudRetry();
    }
  }

  Future<void> _syncPendingChangesNow() async {
    final revision = _sessionRevision;
    final uid = cloudUid;
    final generation = ++_privacyRefreshGeneration;
    var verifiedPrivacy = false;
    bool current() =>
        revision == _sessionRevision &&
        generation == _privacyRefreshGeneration &&
        uid == cloudUid &&
        !_disposed &&
        !isSignedOut &&
        !_isSigningOut &&
        !deletionPending &&
        !isPrivacyBusy;
    final syncActivity = _beginCloudSyncActivity();
    notifyListeners();
    try {
      if (!await _refreshCloudPrivacy(current)) return;
      verifiedPrivacy = true;
      if (!current() || !_canProcessData) return;
      if (hasPendingCloudChanges) await _pushCloud();
      if (!current()) return;
      await _retryOutcomeSync();
      if (!current()) return;
      await _retryCoachSync();
    } on Object catch (error) {
      if (current()) {
        if (!verifiedPrivacy) _cloudPrivacyVerified = false;
        _recordCloudFailure(error);
      }
    } finally {
      _endCloudSyncActivity(syncActivity);
    }
  }
}

/// Validate all backup actions before changing any device fields.
class _CoachBackupActions {
  _CoachBackupActions({
    required this.recommendations,
    required this.alerts,
    required this.statuses,
    required this.feedback,
    required this.dismissed,
  });
  final Map<String, _PendingRecommendationAction> recommendations;
  final Map<String, RiskAlert> alerts;
  final Map<String, RecommendationStatus> statuses;
  final Map<String, bool> feedback;
  final Set<String> dismissed;
  int get count =>
      {...recommendations.keys, ...statuses.keys, ...feedback.keys}.length +
      {...alerts.keys, ...dismissed}.length;

  factory _CoachBackupActions.parse(Map<String, dynamic> local) {
    String id(Object? value) {
      _backupId(value);
      return value as String;
    }

    void validateRecord(
      Map<String, dynamic> record,
      List<String> optionalDates,
    ) {
      _backupDate(record['day']);
      for (final field in optionalDates) {
        if (record[field] != null) _backupDate(record[field]);
      }
      for (final field in ['signalEvidenceIds', 'checkInEvidenceIds']) {
        final values = record[field];
        if (values != null) {
          if (values is! List) {
            throw const FormatException('Invalid Coach evidence list.');
          }
          for (final value in values) {
            _backupId(value);
          }
        }
      }
    }

    final recommendations = <String, _PendingRecommendationAction>{};
    final alerts = <String, RiskAlert>{};
    final statuses = <String, RecommendationStatus>{};
    final feedback = <String, bool>{};
    final dismissed = <String>{};
    for (final entry
        in ((local['recommendationStatuses'] as Map?) ?? {}).entries) {
      statuses[id(entry.key)] = RecommendationStatus.values.byName(
        entry.value as String,
      );
    }
    for (final entry
        in ((local['recommendationFeedback'] as Map?) ?? {}).entries) {
      feedback[id(entry.key)] = entry.value as bool;
    }
    for (final value in ((local['dismissedRiskAlertIds'] as List?) ?? [])) {
      dismissed.add(id(value));
    }
    final journal = local['coachSync'];
    if (journal != null) {
      if (journal is! Map ||
          journal['version'] != 1 ||
          journal['uid'] is! String) {
        throw const FormatException('Unsupported Coach backup.');
      }
      for (final entry in (journal['recommendations'] as Map).entries) {
        final key = id(entry.key);
        final action = _backupMap(entry.value);
        validateRecord(_backupMap(action['record']), [
          'scheduledAt',
          'generatedAt',
        ]);
        recommendations[key] = _PendingRecommendationAction.fromJson(
          key,
          action,
        );
      }
      for (final entry in (journal['alerts'] as Map).entries) {
        final key = id(entry.key);
        final record = _backupMap(entry.value);
        validateRecord(record, ['detectedAt']);
        final alert = riskAlertFromCloud(key, record);
        if (alert.day == null || !alert.dismissed) {
          throw const FormatException('Invalid Coach alert backup.');
        }
        alerts[key] = alert;
      }
    }
    return _CoachBackupActions(
      recommendations: Map.unmodifiable(recommendations),
      alerts: Map.unmodifiable(alerts),
      statuses: Map.unmodifiable(statuses),
      feedback: Map.unmodifiable(feedback),
      dismissed: Set.unmodifiable(dismissed),
    );
  }
}

extension _RestoreCoachBackup on AppController {
  void _restoreCoachBackupActions(
    _CoachBackupActions backup, {
    required bool replaceExisting,
  }) {
    _guidanceRefreshGeneration++;
    isGuidanceLoading = false;
    _reconcileCoachSync();
    final current = {for (final record in _recommendations) record.id: record};
    for (final id in {
      ...backup.recommendations.keys,
      ...backup.statuses.keys,
      ...backup.feedback.keys,
    }) {
      final pending = backup.recommendations[id];
      final record = pending?.record ?? current[id];
      if (record == null) continue;
      final status = pending?.status ?? backup.statuses[id];
      final helpful = pending?.helpful ?? backup.feedback[id];
      final existingStatus = _recommendationStatuses[id] ?? current[id]?.status;
      final existingHelpful =
          _recommendationFeedback[id] ?? current[id]?.helpful;
      final exists = existingStatus != null || existingHelpful != null;
      final statusDiffers = status != null && status != existingStatus;
      final feedbackDiffers = helpful != null && helpful != existingHelpful;
      // Preview compares each Coach record as a whole. "Keep existing" must
      // preserve all its fields even when another new record is being added.
      if (!replaceExisting && exists && (statusDiffers || feedbackDiffers)) {
        continue;
      }
      final useStatus = statusDiffers;
      final useFeedback = feedbackDiffers;
      if (useStatus) _recommendationStatuses[id] = status;
      if (useFeedback) _recommendationFeedback[id] = helpful;
      if (useStatus || useFeedback) {
        _queueRecommendationAction(
          record,
          status: useStatus ? status : null,
          helpful: useFeedback ? helpful : null,
        );
      }
    }
    for (final id in {...backup.alerts.keys, ...backup.dismissed}) {
      final current = _riskAlerts.where((item) => item.id == id).firstOrNull;
      final alreadyDismissed =
          _dismissedRiskAlertIds.contains(id) || current?.dismissed == true;
      if (alreadyDismissed || (!replaceExisting && current != null)) continue;
      final record = backup.alerts[id] ?? current;
      if (record == null) continue;
      _dismissedRiskAlertIds.add(id);
      if (cloudUid != null && cloudRepository != null) {
        _coachSyncOwnerUid = cloudUid;
        _pendingAlertWrites[id] = record.copyWith(dismissed: true);
      }
    }
    _recommendations = _recommendations
        .map(
          (record) => record.copyWith(
            status: _recommendationStatuses[record.id],
            helpful: _recommendationFeedback[record.id],
          ),
        )
        .toList();
    _riskAlerts = _riskAlerts
        .map(
          (record) => record.copyWith(
            dismissed: _dismissedRiskAlertIds.contains(record.id),
          ),
        )
        .toList();
  }
}
