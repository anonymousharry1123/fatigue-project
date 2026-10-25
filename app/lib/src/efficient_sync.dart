part of 'app_controller.dart';

extension _EfficientSync on AppController {
  bool get _cloudInputsPullDue =>
      _syncBaseline == null ||
      _syncOwnerUid != cloudUid ||
      _lastInputHydrationOwner != cloudUid ||
      ContinuousRefreshLogic.shouldRefresh(
        now: _now(),
        lastAttempt: _lastInputHydrationAt,
        minimumInterval: ContinuousRefreshLogic.cloudInputRefreshInterval,
      );

  bool get _heartSummaryPushDue =>
      _lastHeartSummaryUploadAt == null ||
      _lastHeartSummaryUploadAt!.isAfter(_now()) ||
      localDay(_lastHeartSummaryUploadAt!.toLocal()) !=
          localDay(_now().toLocal());

  bool get _onlyDeferredHeartSummaries =>
      !_heartSummaryPushDue &&
      _pendingHeartRateDays.isNotEmpty &&
      _deletedHeartRateDays.isEmpty &&
      _legacyHeartRateCloud.isEmpty &&
      !hasPendingOutcomeChanges &&
      !hasPendingCoachChanges &&
      _syncBaseline != null &&
      _syncOwnerUid == cloudUid &&
      InputSyncPatch(
        _syncBaseline!,
        _inputSnapshot(_cloudState(migrationVersion: localMigrationVersion)),
      ).isEmpty;

  bool get _heartRateSummaryEnabled => _rawHeartRateStore != null;
  CloudQuotaGate? get _quotaGate =>
      (cloudRepository as QuotaCloudRepository?)?.gate;
  EfficientInputRepository? get _efficientInputRepository {
    final repository = (cloudRepository as QuotaCloudRepository?)?.inner;
    return repository is EfficientInputRepository
        ? repository as EfficientInputRepository
        : null;
  }

  InputSyncSnapshot _withoutRawHeartRate(InputSyncSnapshot snapshot) =>
      InputSyncSnapshot(
        root: snapshot.root,
        signals: {
          for (final entry in snapshot.signals.entries)
            if (!(entry.value['type'] == 'heartRate' &&
                entry.value['source'] == 'healthKit'))
              entry.key: entry.value,
        },
        checkIns: snapshot.checkIns,
      );

  InputSyncSnapshot _inputSnapshot(CloudUserState state) {
    final snapshot = InputSyncSnapshot.fromState(state);
    return _heartRateSummaryEnabled ? _withoutRawHeartRate(snapshot) : snapshot;
  }

  List<HeartRateDailySummary> get _localHeartRateDays {
    if (!identical(_heartRateSummarySource, signals) ||
        _heartRateSummarySourceLength != signals.length) {
      _heartRateSummaryCache = HeartRateSummary.build(
        signals,
        sampleProvenance: _heartRateProvenance,
      );
      _heartRateSummarySource = signals;
      _heartRateSummarySourceLength = signals.length;
    }
    return _heartRateSummaryCache;
  }

  Set<String> get _deletedHeartRateDays {
    if (!_heartRateSummaryEnabled ||
        _heartRateCloudStore == null ||
        cloudUid == null ||
        _rawHeartRateOwner != cloudUid) {
      return const {};
    }
    return _ownedHeartRateDays.difference(
      _localHeartRateDays.map((day) => day.day).toSet(),
    );
  }

  List<HeartRateDailySummary> get _pendingHeartRateDays {
    if (!_heartRateSummaryEnabled ||
        _heartRateCloudStore == null ||
        cloudUid == null ||
        _rawHeartRateOwner != cloudUid) {
      return const [];
    }
    return _localHeartRateDays
        .where((day) => _heartRateAcknowledged[day.day] != day.contentDigest)
        .toList();
  }

  Future<void> _loadRawHeartRate(
    String owner, {
    required bool mergeCurrent,
  }) async {
    final store = _rawHeartRateStore;
    if (store == null) return;
    final revision = _sessionRevision;
    if (_rawHeartRateSnapshotExpected &&
        _rawHeartRateOwner == owner &&
        !await store.hasSnapshot(owner)) {
      throw StateError(
        'Could not load device heart-rate history. The local database is missing.',
      );
    }
    final raw = await store.load(owner);
    final provenance = await store.loadProvenance(owner);
    if (revision != _sessionRevision) return;
    final combined = HeartRateSummary.uniqueRawReadings([
      ...raw,
      if (mergeCurrent) ...signals.where(isRawHeartRate),
    ]);
    // Write before removing the legacy preferences copy. A failed transaction
    // leaves both the original preferences and the old database intact.
    await store.replace(owner, combined, provenance: provenance);
    if (revision != _sessionRevision) return;
    if (_rawHeartRateOwner != owner) {
      _lastHeartSummaryUploadAt = null;
      _lastInputHydrationOwner = null;
      _lastInputHydrationAt = null;
      _heartRateAcknowledged.clear();
      _ownedHeartRateDays.clear();
      _blockedHeartRateDays.clear();
      _explicitRawHeartRateDeletes.clear();
      _cloudHeartRateDays.clear();
      _legacyHeartRateCloud.clear();
    }
    _rawHeartRateOwner = owner;
    _rawHeartRateLoaded = true;
    _rawHeartRateSnapshotExpected = true;
    _heartRateProvenance = provenance;
    signals = [...signals.where((item) => !isRawHeartRate(item)), ...combined]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final prefs = await SharedPreferences.getInstance();
    if (revision != _sessionRevision) return;
    const key = 'tonyo_heart_rate_writer_v1';
    _heartRateWriterId = prefs.getString(key);
    if (_heartRateWriterId == null) {
      final random = math.Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      if (!await prefs.setString(key, id)) {
        throw StateError('Could not save to this device. Retry.');
      }
      if (revision != _sessionRevision) return;
      _heartRateWriterId = id;
    }
  }

  Map<String, Object?> _efficientSyncJson() => {
    'version': 1,
    'rawOwner': _rawHeartRateOwner,
    'lastInputHydrationOwner': _lastInputHydrationOwner,
    'lastInputHydrationAt': _lastInputHydrationAt?.toUtc().toIso8601String(),
    'lastHeartSummaryUploadAt': _lastHeartSummaryUploadAt
        ?.toUtc()
        .toIso8601String(),
    'heartRateStorageVersion': _heartRateStorageVersion,
    'ownedHeartRateDays': _ownedHeartRateDays.toList(),
    'blockedHeartRateDays': _blockedHeartRateDays.toList(),
    'explicitRawDeletes': _explicitRawHeartRateDeletes.toList(),
    'heartRateAcknowledged': _heartRateAcknowledged,
    'heartRateDays': {
      for (final entry in _cloudHeartRateDays.entries)
        entry.key: entry.value.toJson(),
    },
    // Kept only during migration; removal follows a verified server summary.
    'legacyHeartRateCloud': _legacyHeartRateCloud,
    if (_remoteInputOwner != null &&
        _remoteInputSnapshot != null &&
        _remoteInputRevision != null)
      'remoteInputs': {
        'uid': _remoteInputOwner,
        'revision': _remoteInputRevision,
        'snapshot': _remoteInputSnapshot!.toJson(),
      },
  };

  void _restoreEfficientSync(Object? value) {
    if (!_heartRateSummaryEnabled || value is! Map || value['version'] != 1) {
      return;
    }
    try {
      _rawHeartRateOwner = value['rawOwner'] as String?;
      _lastInputHydrationOwner = value['lastInputHydrationOwner'] as String?;
      _lastInputHydrationAt = DateTime.tryParse(
        value['lastInputHydrationAt'] as String? ?? '',
      );
      _lastHeartSummaryUploadAt = DateTime.tryParse(
        value['lastHeartSummaryUploadAt'] as String? ?? '',
      );
      _heartRateStorageVersion =
          (value['heartRateStorageVersion'] as num?)?.toInt() ?? 0;
      _rawHeartRateSnapshotExpected = _rawHeartRateOwner != null;
      _explicitRawHeartRateDeletes.addAll(
        (value['explicitRawDeletes'] as List? ?? []).cast<String>(),
      );
      _blockedHeartRateDays.addAll(
        (value['blockedHeartRateDays'] as List? ?? []).cast<String>(),
      );
      _ownedHeartRateDays.addAll(
        (value['ownedHeartRateDays'] as List? ?? []).cast<String>(),
      );
      _heartRateAcknowledged = Map<String, String>.from(
        value['heartRateAcknowledged'] as Map? ?? {},
      );
      _cloudHeartRateDays = {
        for (final entry in (value['heartRateDays'] as Map? ?? {}).entries)
          entry.key as String: HeartRateDailySummary.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      };
      _legacyHeartRateCloud = {
        for (final entry
            in (value['legacyHeartRateCloud'] as Map? ?? {}).entries)
          entry.key as String: Map<String, dynamic>.from(entry.value as Map),
      };
      final remote = value['remoteInputs'];
      if (remote is Map &&
          remote['uid'] is String &&
          remote['revision'] is int) {
        _remoteInputOwner = remote['uid'] as String;
        _remoteInputRevision = remote['revision'] as int;
        _remoteInputSnapshot = _withoutRawHeartRate(
          InputSyncSnapshot.fromJson(
            Map<String, dynamic>.from(remote['snapshot'] as Map),
          ),
        );
      }
    } on Object {
      // A missing/corrupt cursor triggers a fresh authoritative bootstrap;
      // it never advances the cursor or discards raw database history.
      _remoteInputOwner = null;
      _lastInputHydrationOwner = null;
      _lastInputHydrationAt = null;
      _lastHeartSummaryUploadAt = null;
      _remoteInputRevision = null;
      _remoteInputSnapshot = null;
      _heartRateAcknowledged.clear();
      _cloudHeartRateDays.clear();
      _legacyHeartRateCloud.clear();
      _heartRateStorageVersion = 0;
    }
  }

  Future<CloudUserState?> _readCloudInputs(String uid) async {
    final efficient = _efficientInputRepository;
    if (efficient != null && _heartRateSummaryEnabled) {
      await _quotaGate!.run(uid, () => efficient.activateInputSync(uid));
    }
    if (efficient != null &&
        _remoteInputOwner == uid &&
        _remoteInputSnapshot != null &&
        _remoteInputRevision != null) {
      return _quotaGate!.run(
        uid,
        () => efficient.readUserSince(
          uid,
          baseline: _remoteInputSnapshot!,
          revision: _remoteInputRevision!,
        ),
      );
    }
    return cloudRepository!.readUser(uid);
  }

  Future<void> _readHeartRateCloud(String uid) async {
    final store = _heartRateCloudStore;
    if (store == null) return;
    final revision = _sessionRevision;
    final days = await _quotaGate!.run(uid, () => store.readDays(uid));
    if (revision != _sessionRevision || uid != cloudUid) return;
    _ownedHeartRateDays.clear();
    _ownedHeartRateDays.addAll(
      days
          .where((day) => day.writerId == _heartRateWriterId)
          .map((day) => day.summary.day),
    );
    _cloudHeartRateDays = {
      for (final day in days) day.summary.day: day.summary,
    };
    final local = {for (final day in _localHeartRateDays) day.day: day};
    _heartRateAcknowledged = {
      for (final day in days)
        if (local[day.summary.day] == null ||
            local[day.summary.day]!.contentDigest !=
                day.summary.contentDigest ||
            sameHeartRateSummaryStatistics(
              local[day.summary.day]!,
              day.summary,
            ))
          day.summary.day: day.summary.contentDigest,
    };
  }

  Future<void> _pushHeartRateCloud(
    String uid,
    bool Function() current, {
    bool force = false,
  }) async {
    final store = _heartRateCloudStore;
    if (store == null ||
        _heartRateWriterId == null ||
        _rawHeartRateOwner != uid) {
      return;
    }
    // A second edit may arrive while the preferences write is awaiting disk.
    // Summarize only the database's committed snapshot, never newer mutable
    // in-memory rows. Those newer rows remain pending for the next commit.
    final rawStore = _rawHeartRateStore!;
    final durableRaw = await rawStore.load(uid);
    final durableProvenance = await rawStore.loadProvenance(uid);
    if (!current()) return;
    // Related native/estimated values must also come from a committed snapshot.
    // A newer in-memory correction cannot enter a summary ahead of its save.
    final preferences = await SharedPreferences.getInstance();
    if (!current()) return;
    final encoded = preferences.getString(AppController._storageKey);
    final saved = encoded == null
        ? null
        : jsonDecode(encoded) as Map<String, dynamic>;
    final related = saved?['privacyOwnerUid'] == uid
        ? (saved?['signals'] as List? ?? const [])
              .map(
                (row) => SignalReading.fromJson(
                  Map<String, dynamic>.from(row as Map),
                ),
              )
              .where((row) => !isRawHeartRate(row))
              .toList()
        : <SignalReading>[];
    final durableDays = HeartRateSummary.build([
      ...durableRaw,
      ...related,
    ], sampleProvenance: durableProvenance);
    final durableDayIds = durableDays.map((day) => day.day).toSet();
    for (final day in _ownedHeartRateDays.difference(durableDayIds)) {
      final digest = _heartRateAcknowledged[day];
      if (digest == null) continue;
      await _quotaGate!.run(
        uid,
        () => store.deleteDay(
          uid,
          day,
          writerId: _heartRateWriterId!,
          expectedDigest: digest,
        ),
      );
      if (!current()) return;
      _ownedHeartRateDays.remove(day);
      _cloudHeartRateDays.remove(day);
      _heartRateAcknowledged.remove(day);
      _markCloudUploadSuccess();
      await _writeLocal();
      if (!current()) return;
    }
    var acknowledgedBatch = false;
    final summariesDue = force || _heartSummaryPushDue;
    var summaryUploads = 0;
    for (final summary in durableDays.where(
      (day) =>
          summariesDue && _heartRateAcknowledged[day.day] != day.contentDigest,
    )) {
      if (_blockedHeartRateDays.contains(summary.day)) continue;
      if (summaryUploads >=
          ContinuousRefreshLogic.maxHeartSummaryDaysPerSync) {
        break;
      }
      final HeartRateSummaryAcknowledgement ack;
      try {
        ack = await _quotaGate!.run(
          uid,
          () => store.saveDay(
            uid,
            writerId: _heartRateWriterId!,
            summary: summary,
            expectedDigest: _heartRateAcknowledged[summary.day],
          ),
        );
      } on HeartRateSummaryOwnershipConflict {
        if (!current()) return;
        _blockedHeartRateDays.add(summary.day);
        continue;
      } on HeartRateSummaryRevisionConflict {
        if (!current()) return;
        _blockedHeartRateDays.add(summary.day);
        continue;
      }
      if (!current()) return;
      if (!sameHeartRateSummaryStatistics(summary, ack.summary) ||
          ack.summary.contentDigest != summary.contentDigest ||
          ack.summary.sampleIdDigest != summary.sampleIdDigest ||
          ack.summary.sampleCount != summary.sampleCount ||
          ack.summary.latestAt != summary.latestAt ||
          ack.summary.latestValue != summary.latestValue) {
        throw StateError(
          'Cloud heart-rate summary verification failed. Raw history is kept on this device.',
        );
      }
      if (ack.writerId == _heartRateWriterId) {
        _ownedHeartRateDays.add(summary.day);
      }
      _cloudHeartRateDays[summary.day] = ack.summary;
      _heartRateAcknowledged[summary.day] = ack.summary.contentDigest;
      acknowledgedBatch = true;
      summaryUploads++;
      _markCloudUploadSuccess();
      await _writeLocal();
      if (!current()) return;
    }
    if (acknowledgedBatch) {
      _lastHeartSummaryUploadAt = _now();
      await _writeLocal();
      if (!current()) return;
    }
    // Only exact, durably stored legacy samples covered by an acknowledged
    // complete daily snapshot may be retired. Conflict-aware deletes preserve
    // a concurrently edited server sample; partial retries are idempotent.
    final localById = {for (final sample in durableRaw) sample.id: sample};
    final summaries = {for (final day in durableDays) day.day: day};
    final removable = <String, Map<String, dynamic>>{};
    for (final entry in _legacyHeartRateCloud.entries) {
      if (_explicitRawHeartRateDeletes.contains(entry.key) &&
          !localById.containsKey(entry.key)) {
        removable[entry.key] = entry.value;
        continue;
      }
      final sample = localById[entry.key];
      if (sample == null ||
          HeartRateSummary.contentDigest([sample]) !=
              HeartRateSummary.contentDigest([
                signalFromCloud(entry.key, entry.value),
              ])) {
        final previous = signalFromCloud(entry.key, entry.value);
        _blockedHeartRateDays.add(HeartRateSummary.dayId(previous.timestamp));
        continue;
      }
      final day = summaries[HeartRateSummary.dayId(sample.timestamp)];
      if (day != null && _heartRateAcknowledged[day.day] == day.contentDigest) {
        removable[entry.key] = entry.value;
      }
    }
    if (removable.isNotEmpty) {
      final batch = Map<String, Map<String, dynamic>>.fromEntries(
        removable.entries.take(
          ContinuousRefreshLogic.maxLegacyHeartRateDeletesPerSync,
        ),
      );
      await cloudRepository!.applyInputPatch(
        uid,
        InputSyncPatch(
          InputSyncSnapshot(root: {}, signals: batch, checkIns: {}),
          InputSyncSnapshot(root: {}, signals: {}, checkIns: {}),
        ),
      );
      if (!current()) return;
      for (final id in batch.keys) {
        _legacyHeartRateCloud.remove(id);
        _explicitRawHeartRateDeletes.remove(id);
      }
      await _writeLocal();
      if (!current()) return;
    }
    final efficient = _efficientInputRepository;
    if (efficient != null &&
        _legacyHeartRateCloud.isEmpty &&
        _pendingHeartRateDays.isEmpty) {
      await _quotaGate!.run(uid, () => efficient.finishHeartRateMigration(uid));
      if (!current()) return;
      _heartRateStorageVersion = 1;
      await _writeLocal();
    }
  }
}
