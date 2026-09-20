part of 'app_controller.dart';

/// A review is bound to the account and exact snapshots that were displayed.
/// Its private snapshots cannot be replaced by the caller before confirmation.
class InputConflictReview {
  InputConflictReview._(
    this._controller,
    this._uid,
    this._revision, {
    required InputSyncSnapshot baseline,
    required InputSyncSnapshot phone,
    required InputSyncSnapshot cloud,
  }) : _baseline = baseline,
       _phone = phone,
       _cloud = cloud,
       items = List.unmodifiable(_inputConflictItems(baseline, phone, cloud));

  final AppController _controller;
  final String _uid;
  final int _revision;
  final InputSyncSnapshot _baseline;
  final InputSyncSnapshot _phone;
  final InputSyncSnapshot _cloud;
  final List<InputConflictItem> items;
}

class InputConflictItem {
  const InputConflictItem._({
    required this.key,
    required this.title,
    required this.phoneDescription,
    required this.cloudDescription,
  });

  final String key;
  final String title;
  final String phoneDescription;
  final String cloudDescription;
}

extension InputConflictResolution on AppController {
  Future<InputConflictReview> reviewInputConflicts() async {
    _requirePrivacy();
    final uid = cloudUid;
    final repository = cloudRepository;
    final revision = _sessionRevision;
    if (uid == null || repository == null || isPrivacyBusy) {
      throw StateError('Finish signing in before reviewing cloud changes.');
    }
    final generation = ++_privacyRefreshGeneration;
    bool current() =>
        uid == cloudUid &&
        revision == _sessionRevision &&
        generation == _privacyRefreshGeneration &&
        _canProcessData &&
        !isPrivacyBusy;
    void ensureCurrent() {
      if (!current()) {
        throw StateError(
          'Account or privacy settings changed. Open review again.',
        );
      }
    }

    while (_pendingCloudPush != null) {
      await _pendingCloudPush;
      ensureCurrent();
    }
    if (_syncOwnerUid != uid || _syncBaseline == null) {
      throw StateError('Retry cloud sync before reviewing changes.');
    }
    final baseline = _syncBaseline!;
    final phone = _conflictInputSnapshot();
    if (!await _refreshCloudPrivacy(current)) ensureCurrent();
    ensureCurrent();
    final remote = await repository.readUser(uid);
    ensureCurrent();
    _requireReviewableRemote(remote);
    if (!_sameConflictSnapshot(phone, _conflictInputSnapshot()) ||
        !_sameConflictSnapshot(baseline, _syncBaseline)) {
      throw StateError(
        'New data was saved during review. Refresh and try again.',
      );
    }
    return InputConflictReview._(
      this,
      uid,
      revision,
      baseline: baseline,
      phone: phone,
      cloud: InputSyncSnapshot.fromState(remote!),
    );
  }

  /// True keeps the displayed phone version; false keeps the cloud version.
  /// Every conflict requires an explicit choice. Other local edits are retained.
  Future<void> resolveInputConflicts(
    InputConflictReview review,
    Map<String, bool> keepPhone,
  ) async {
    final choices = Map<String, bool>.unmodifiable(keepPhone);
    final expected = review.items.map((item) => item.key).toSet();
    if (choices.length != expected.length ||
        !expected.every(choices.containsKey)) {
      throw StateError('Choose a version for every conflicting item.');
    }
    _ensureConflictReviewCurrent(review);
    while (_pendingCloudPush != null || _pendingOutcomePush != null) {
      await _pendingCloudPush;
      await _pendingOutcomePush;
      _ensureConflictReviewCurrent(review);
    }
    final task = _resolveInputConflictsNow(review, choices);
    _pendingCloudPush = task;
    _pendingOutcomePush = task;
    try {
      await task;
    } finally {
      if (identical(_pendingCloudPush, task)) _pendingCloudPush = null;
      if (identical(_pendingOutcomePush, task)) _pendingOutcomePush = null;
      scheduleCloudRetry();
    }
    if (review._uid == cloudUid &&
        review._revision == _sessionRevision &&
        _canProcessData &&
        hasPendingOutcomeChanges) {
      await _retryOutcomeSync();
    }
  }

  InputSyncSnapshot _conflictInputSnapshot() => InputSyncSnapshot.fromState(
    _cloudState(migrationVersion: localMigrationVersion),
  );

  void _ensureConflictReviewCurrent(InputConflictReview review) {
    _requirePrivacy();
    if (!identical(review._controller, this) ||
        review._uid != cloudUid ||
        review._revision != _sessionRevision ||
        _syncOwnerUid != review._uid ||
        isPrivacyBusy) {
      throw StateError(
        'Account or privacy settings changed. Open review again.',
      );
    }
    if (!_sameConflictSnapshot(review._phone, _conflictInputSnapshot()) ||
        !_sameConflictSnapshot(review._baseline, _syncBaseline)) {
      throw StateError('Phone data changed. Refresh the review before saving.');
    }
  }

  void _requireReviewableRemote(CloudUserState? remote) {
    if (remote == null || remote.deletionPending) {
      throw StateError('Cloud data is unavailable. Retry from Profile.');
    }
    if (remote.privacyConsent?.validAt(_now()) != true) {
      throw StateError('Review your privacy choices before resolving changes.');
    }
  }

  Future<void> _resolveInputConflictsNow(
    InputConflictReview review,
    Map<String, bool> keepPhone,
  ) async {
    final uid = review._uid;
    final revision = review._revision;
    final generation = ++_privacyRefreshGeneration;
    bool current() =>
        uid == cloudUid &&
        revision == _sessionRevision &&
        generation == _privacyRefreshGeneration &&
        _canProcessData &&
        !isPrivacyBusy;
    void ensureReviewCurrent() {
      _ensureConflictReviewCurrent(review);
      if (!current()) {
        throw StateError(
          'Privacy settings changed. Refresh review before saving.',
        );
      }
    }

    final syncActivity = _beginCloudSyncActivity();
    notifyListeners();
    try {
      if (!await _refreshCloudPrivacy(current)) {
        ensureReviewCurrent();
        throw StateError('Privacy status could not be verified. Retry review.');
      }
      ensureReviewCurrent();
      final remote = await cloudRepository!.readUser(uid);
      ensureReviewCurrent();
      _requireReviewableRemote(remote);
      final cloud = InputSyncSnapshot.fromState(remote!);
      if (!_sameConflictSnapshot(review._cloud, cloud)) {
        throw StateError(
          'Cloud data changed. Refresh the review before saving.',
        );
      }

      final pending = InputSyncPatch(review._baseline, review._phone);
      pending.root.removeWhere((key, _) => keepPhone['profile:$key'] == false);
      pending.signals.removeWhere(
        (edit) => keepPhone['signal:${edit.id}'] == false,
      );
      pending.checkIns.removeWhere(
        (edit) => keepPhone['check-in:${edit.id}'] == false,
      );
      final merged = cloud.overlay(pending);
      await _discardPersonalizedModel();
      ensureReviewCurrent();
      // Consent comes from the current verified session, never the review or
      // the full cloud response, which may have been fetched before revocation.
      final authoritative = _cloudState(
        migrationVersion: localMigrationVersion,
      );
      final mergedState = merged.toState(authoritative);
      final deviceHealthAuthorized = healthAuthorized;
      final deviceBackgroundRefresh = healthBackgroundRefreshEnabled;
      _applyCloud(mergedState);
      healthAuthorized = deviceHealthAuthorized;
      healthBackgroundRefreshEnabled = deviceBackgroundRefresh;
      final selectedCheckIns = {
        for (final entry in keepPhone.entries)
          if (!entry.value && entry.key.startsWith('check-in:'))
            entry.key.substring('check-in:'.length),
      };
      final selectedReactions = {
        for (final entry in keepPhone.entries)
          if (!entry.value &&
              entry.key.startsWith('signal:') &&
              [review._baseline, review._phone, review._cloud].any(
                (snapshot) =>
                    snapshot.signals[entry.key.substring(
                      'signal:'.length,
                    )]?['type'] ==
                    SignalType.reactionTime.name,
              ))
            entry.key.substring('signal:'.length),
      };
      _reconcileSourceLinkedOutcomes(
        checkInIds: selectedCheckIns,
        reactionSignalIds: selectedReactions,
        ensureOutcomeIds: {
          ...selectedCheckIns.map((id) => 'energy-checkin-$id'),
          ...selectedReactions.map((id) => 'reaction-$id'),
        },
      );
      _syncBaseline = cloud;
      _syncOwnerUid = uid;
      cloudSyncConflict = false;
      cloudSyncError = null;
      cloudSyncFailureKind = null;
      try {
        await _writeLocal();
      } on Object catch (error) {
        if (current()) _recordCloudFailure(error);
        rethrow;
      }
      if (!current()) {
        throw StateError(
          'Account or privacy settings changed. Sync is paused.',
        );
      }
      notifyListeners();
      // The normal guarded transaction checks the freshly reviewed baseline
      // again. A third device editing now still produces a recoverable conflict.
      await _pushCloudNow();
      if (!current()) return;
      if (onboardingComplete) {
        await refreshScores(forceRecalculate: true);
        if (!current()) return;
        await refreshForecasts(forceRecalculate: true);
        if (!current()) return;
        await refreshGuidance();
        if (!current()) return;
        await refreshInsights();
      }
    } finally {
      _endCloudSyncActivity(syncActivity);
    }
  }

  /// Keep previously tracked learning results aligned with their selected
  /// source. Callers own the outcome-upload barrier and durable local write.
  void _reconcileSourceLinkedOutcomes({
    required Set<String> checkInIds,
    required Set<String> reactionSignalIds,
    Set<String> ensureOutcomeIds = const {},
  }) {
    if (checkInIds.isEmpty && reactionSignalIds.isEmpty) return;
    _reconcileOutcomeSync();
    void reconcile(
      String id,
      OutcomeRecord? selected, {
      required bool sourceDeleted,
    }) {
      final existing = _outcomes.where((item) => item.id == id).firstOrNull;
      if (existing == null &&
          !_pendingOutcomeWrites.containsKey(id) &&
          !ensureOutcomeIds.contains(id)) {
        return;
      }
      if (!outcomeConsent && !sourceDeleted) return;
      if (existing != null &&
          selected != null &&
          sameSyncValue(
            {...existing.toJson(), 'recordedAt': null},
            {...selected.toJson(), 'recordedAt': null},
          )) {
        selected = existing;
      }
      _outcomes.removeWhere((item) => item.id == id);
      if (selected != null && outcomeConsent) _outcomes.add(selected);
      // An opted-out account can delete a source-linked result, but never
      // creates or reconstructs learning data from restored inputs.
      _queueOutcomeWrite(id, outcomeConsent ? selected : null);
    }

    for (final id in checkInIds) {
      final source = checkIns.where((item) => item.id == id).firstOrNull;
      reconcile(
        'energy-checkin-$id',
        source == null || !outcomeConsent
            ? null
            : OutcomeRecord(
                id: 'energy-checkin-$id',
                type: OutcomeType.observedEnergy,
                value: source.energy,
                observedAt: source.timestamp,
                recordedAt: _now(),
                source: OutcomeSource.checkIn,
                sourceId: id,
              ),
        sourceDeleted: source == null,
      );
    }
    for (final id in reactionSignalIds) {
      final source = signals
          .where(
            (item) => item.id == id && item.type == SignalType.reactionTime,
          )
          .firstOrNull;
      reconcile(
        'reaction-$id',
        source == null || !outcomeConsent
            ? null
            : OutcomeRecord(
                id: 'reaction-$id',
                type: OutcomeType.cognitiveReaction,
                value: source.value,
                observedAt: source.timestamp,
                recordedAt: _now(),
                source: OutcomeSource.reactionSignal,
                sourceId: id,
              ),
        sourceDeleted: source == null,
      );
    }
    _outcomes.sort((a, b) => b.observedAt.compareTo(a.observedAt));
    _outcomeRefreshGeneration++;
    isOutcomeLoading = false;
    outcomeError = null;
  }
}

bool _sameConflictSnapshot(InputSyncSnapshot a, InputSyncSnapshot? b) =>
    b != null && sameSyncValue(a.toJson(), b.toJson());

Object? _conflictRootValue(Map<String, dynamic> root, String path) {
  Object? value = root;
  for (final key in path.split('.')) {
    if (value is! Map) return null;
    value = value[key];
  }
  return value;
}

List<InputConflictItem> _inputConflictItems(
  InputSyncSnapshot baseline,
  InputSyncSnapshot phone,
  InputSyncSnapshot cloud,
) {
  final pending = InputSyncPatch(baseline, phone);
  bool conflicts(Object? previous, Object? local, Object? remote) =>
      !sameSyncValue(remote, previous) && !sameSyncValue(remote, local);
  return [
    for (final entry in pending.root.entries)
      if (!_isDeviceRuntimeSyncPath(entry.key) &&
          conflicts(
            entry.value.before,
            entry.value.after,
            _conflictRootValue(cloud.root, entry.key),
          ))
        InputConflictItem._(
          key: 'profile:${entry.key}',
          title: _conflictFieldLabel(entry.key),
          phoneDescription: _conflictFieldValue(entry.key, entry.value.after),
          cloudDescription: _conflictFieldValue(
            entry.key,
            _conflictRootValue(cloud.root, entry.key),
          ),
        ),
    for (final edit in pending.signals)
      if (conflicts(edit.before, edit.after, cloud.signals[edit.id]))
        InputConflictItem._(
          key: 'signal:${edit.id}',
          title: _conflictRecordTitle(
            'signal',
            edit.after ?? cloud.signals[edit.id] ?? edit.before!,
          ),
          phoneDescription: _conflictRecordDescription(edit.after),
          cloudDescription: _conflictRecordDescription(cloud.signals[edit.id]),
        ),
    for (final edit in pending.checkIns)
      if (conflicts(edit.before, edit.after, cloud.checkIns[edit.id]))
        InputConflictItem._(
          key: 'check-in:${edit.id}',
          title: _conflictRecordTitle(
            'check-in',
            edit.after ?? cloud.checkIns[edit.id] ?? edit.before!,
          ),
          phoneDescription: _conflictRecordDescription(edit.after),
          cloudDescription: _conflictRecordDescription(cloud.checkIns[edit.id]),
        ),
  ];
}

// These values describe a device's importer, not user-authored records. Local
// importer progress is automatically rebased on the newly read cloud baseline;
// native Health permission and observer registration remain device-owned.
bool _isDeviceRuntimeSyncPath(String path) =>
    path.startsWith('healthSync.') ||
    path == 'lastHealthSync' ||
    path == 'prefs.healthAuthorized' ||
    path == 'localMigrationVersion' ||
    path == 'prefs.notificationPreferencesVersion';

String _conflictRecordTitle(String kind, Map<String, dynamic> data) {
  final type = SignalType.values
      .where((type) => type.name == data['type'])
      .firstOrNull;
  final label = kind == 'check-in'
      ? '${data['period'] == 'evening' ? 'Evening' : 'Morning'} check-in'
      : type?.label ?? 'Activity';
  return '$label · ${_conflictFieldValue('timestamp', data['timestamp'])}';
}

String _conflictRecordDescription(Map<String, dynamic>? data) => data == null
    ? 'Deleted'
    : data.entries
          .where(
            (entry) =>
                entry.value != null &&
                !const {'id', 'groupId', 'schemaVersion'}.contains(entry.key),
          )
          .map(
            (entry) =>
                '${_conflictFieldLabel(entry.key)}: ${_conflictFieldValue(entry.key, entry.value)}',
          )
          .join('\n');

String _conflictFieldLabel(String path) {
  final key = path.split('.').last;
  return const {
        'name': 'Name',
        'ageRange': 'Age range',
        'role': 'Role',
        'goal': 'Goal',
        'coachPriority': 'Coach priority',
        'wakeHour': 'Wake time',
        'bedHour': 'Bedtime',
        'accountEmail': 'Account email',
        'onboardingComplete': 'Setup complete',
        'notificationsEnabled': 'Notifications',
        'crashNotificationsEnabled': 'Low energy alerts',
        'recoveryNotificationsEnabled': 'Recovery alerts',
        'coachPlanNotificationsEnabled': 'Daily plan reminders',
        'healthAuthorized': 'Health access',
        'notificationPreferencesVersion': 'Notification settings version',
        'lastHealthSync': 'Last Health sync',
        'status': 'Health sync status',
        'reason': 'Health refresh reason',
        'lastAttemptAt': 'Last Health attempt',
        'lastSuccessAt': 'Last successful Health sync',
        'lastMeaningfulChangeAt': 'Last Health change',
        'backgroundRefreshEnabled': 'Health background refresh',
        'localMigrationVersion': 'Data version',
        'type': 'Activity',
        'value': 'Amount',
        'unit': 'Unit',
        'timestamp': 'Time',
        'recordedAt': 'Saved at',
        'syncedAt': 'Imported at',
        'source': 'Source',
        'quality': 'Data quality',
        'note': 'Note',
        'groupId': 'Linked record',
        'energy': 'Energy (1–10)',
        'mood': 'Mood (1–10)',
        'stress': 'Stress (1–10)',
        'period': 'Check-in period',
      }[key] ??
      key;
}

String _conflictFieldValue(String path, Object? value) {
  if (value == null || value == '') return 'Not set';
  if (value is bool) return value ? 'On' : 'Off';
  final key = path.split('.').last;
  if ((key == 'wakeHour' || key == 'bedHour') && value is num) {
    final minutes = (value * 60).round() % (24 * 60);
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
  }
  if (value is num) {
    return value == value.round() ? '${value.round()}' : '$value';
  }
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date != null && value.toString().contains('T')) {
    final local = date.toLocal();
    final fraction = local.millisecond == 0 && local.microsecond == 0
        ? ''
        : '.${(local.millisecond * 1000 + local.microsecond).toString().padLeft(6, '0')}';
    return '${local.month}/${local.day}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}$fraction ${local.timeZoneName}';
  }
  if (key == 'type') {
    return SignalType.values
            .where((type) => type.name == value)
            .firstOrNull
            ?.label ??
        '$value';
  }
  if (key == 'coachPriority') {
    return CoachPriority.values
            .where((priority) => priority.name == value)
            .firstOrNull
            ?.label ??
        '$value';
  }
  return const {
        'manual': 'Manual',
        'healthKit': 'Apple Health',
        'model': 'Model',
        'morning': 'Morning',
        'evening': 'Evening',
        'upToDate': 'Up to date',
        'partialFailure': 'Some sources need attention',
        'foreground': 'App opened',
        'background': 'Background refresh',
        'idle': 'Ready',
        'updated': 'Updated',
        'syncing': 'Refreshing',
        'failed': 'Needs attention',
        'disabled': 'Off',
        'initial': 'Initial import',
      }[value] ??
      '$value';
}
