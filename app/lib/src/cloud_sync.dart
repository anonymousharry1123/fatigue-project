import 'dart:convert';

import 'cloud_schema.dart';
import 'models.dart';

Object? syncCanonical(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Map) {
    final keys =
        value.keys
            .cast<String>()
            .where((key) => key != 'schemaVersion')
            .toList()
          ..sort();
    return {
      for (final key in keys)
        if (value[key] != null) key: syncCanonical(value[key]),
    };
  }
  if (value is Iterable) return value.map(syncCanonical).toList();
  return value;
}

bool sameSyncValue(Object? a, Object? b) =>
    jsonEncode(syncCanonical(a)) == jsonEncode(syncCanonical(b));
Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

/// Only ordinary profile fields are synchronized here. Consent, deletion and
/// model metadata retain their separate protected APIs.
class InputSyncSnapshot {
  InputSyncSnapshot({
    required this.root,
    required this.signals,
    required this.checkIns,
  });
  final Map<String, dynamic> root;
  final Map<String, Map<String, dynamic>> signals;
  final Map<String, Map<String, dynamic>> checkIns;

  factory InputSyncSnapshot.fromState(CloudUserState state) {
    final root =
        profileToCloud(
            profile: state.profile,
            email: state.accountEmail,
            onboardingComplete: state.onboardingComplete,
            notificationsEnabled: state.notificationsEnabled,
            crashNotificationsEnabled: state.crashNotificationsEnabled,
            recoveryNotificationsEnabled: state.recoveryNotificationsEnabled,
            notificationPrefsVersion: state.notificationPrefsVersion,
            outcomeConsent: state.outcomeConsent,
            healthAuthorized: state.healthAuthorized,
            lastSync: state.lastSync,
            healthSyncStatus: state.healthSyncStatus,
            lastHealthRefreshReason: state.lastHealthRefreshReason,
            lastHealthSyncAttempt: state.lastHealthSyncAttempt,
            lastHealthChangeAt: state.lastHealthChangeAt,
            healthBackgroundRefreshEnabled:
                state.healthBackgroundRefreshEnabled,
            migrationVersion: state.migrationVersion,
          )
          ..remove('consentFlags')
          ..remove('updatedAt');
    return InputSyncSnapshot(
      root: _map(syncCanonical(root)),
      signals: {
        for (final item in state.signals)
          item.id: _map(syncCanonical(signalToCloud(item))),
      },
      checkIns: {
        for (final item in state.checkIns)
          item.id: _map(syncCanonical(checkInToCloud(item))),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'root': root,
    'signals': signals,
    'checkIns': checkIns,
  };
  factory InputSyncSnapshot.fromJson(Map<String, dynamic> json) =>
      InputSyncSnapshot(
        root: _map(json['root']),
        signals: _map(
          json['signals'],
        ).map((key, value) => MapEntry(key, _map(value))),
        checkIns: _map(
          json['checkIns'],
        ).map((key, value) => MapEntry(key, _map(value))),
      );

  /// Overlay only local differences on freshly loaded remote state.
  InputSyncSnapshot overlay(InputSyncPatch patch, {bool useBefore = false}) {
    final nextRoot = {...root};
    for (final item in patch.root.entries) {
      _setRootPath(
        nextRoot,
        item.key,
        useBefore ? item.value.before : item.value.after,
      );
    }
    Map<String, Map<String, dynamic>> apply(
      Map<String, Map<String, dynamic>> source,
      List<InputDocumentEdit> edits,
    ) {
      final result = {...source};
      for (final edit in edits) {
        final value = useBefore ? edit.before : edit.after;
        if (value == null) {
          result.remove(edit.id);
        } else {
          result[edit.id] = value;
        }
      }
      return result;
    }

    return InputSyncSnapshot(
      root: nextRoot,
      signals: apply(signals, patch.signals),
      checkIns: apply(checkIns, patch.checkIns),
    );
  }

  CloudUserState toState(CloudUserState authoritative) {
    final prefs = _map(root['prefs'] ?? {});
    final health = _map(root['healthSync'] ?? {});
    DateTime? date(Object? value) =>
        value == null ? null : cloudDateTime(value, field: 'sync time');
    return CloudUserState(
      profile: UserProfile.fromJson(_map(root['profile'])),
      accountEmail:
          root['accountEmail'] as String? ?? authoritative.accountEmail,
      onboardingComplete: root['onboardingComplete'] == true,
      notificationsEnabled: prefs['notificationsEnabled'] == true,
      crashNotificationsEnabled: prefs['crashNotificationsEnabled'] != false,
      recoveryNotificationsEnabled:
          prefs['recoveryNotificationsEnabled'] != false,
      notificationPrefsVersion:
          (prefs['notificationPreferencesVersion'] as num?)?.toInt() ?? 0,
      healthAuthorized: prefs['healthAuthorized'] == true,
      lastSync: date(root['lastHealthSync']),
      healthSyncStatus: HealthSyncStatus.values.byName(
        health['status'] as String? ?? 'idle',
      ),
      lastHealthRefreshReason: health['reason'] == null
          ? null
          : HealthRefreshReason.values.byName(health['reason'] as String),
      lastHealthSyncAttempt: date(health['lastAttemptAt']),
      lastHealthChangeAt: date(health['lastMeaningfulChangeAt']),
      healthBackgroundRefreshEnabled:
          health['backgroundRefreshEnabled'] == true,
      migrationVersion: (root['localMigrationVersion'] as num?)?.toInt() ?? 0,
      signals: signals.entries
          .map((item) => signalFromCloud(item.key, item.value))
          .toList(),
      checkIns: checkIns.entries
          .map((item) => checkInFromCloud(item.key, item.value))
          .toList(),
      outcomeConsent: authoritative.outcomeConsent,
      privacyConsent: authoritative.privacyConsent,
      outcomeConsentUpdatedAt: authoritative.outcomeConsentUpdatedAt,
      deletionPending: authoritative.deletionPending,
      personalizedEnergyModel: authoritative.personalizedEnergyModel,
      userUpdatedAt: authoritative.userUpdatedAt,
    );
  }
}

class SyncValueEdit {
  const SyncValueEdit(this.before, this.after);
  final Object? before;
  final Object? after;
}

class InputDocumentEdit {
  const InputDocumentEdit(this.id, this.before, this.after);
  final String id;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
}

class InputSyncPatch {
  InputSyncPatch(InputSyncSnapshot before, InputSyncSnapshot after)
    : root = _rootEdits(before.root, after.root),
      signals = _edits(before.signals, after.signals),
      checkIns = _edits(before.checkIns, after.checkIns);

  /// Dotted paths refer to individual known profile/preferences fields. The
  /// durable journal still stores full snapshots, so older journals retain
  /// their meaning while unrelated edits from another device can merge.
  final Map<String, SyncValueEdit> root;
  final List<InputDocumentEdit> signals;
  final List<InputDocumentEdit> checkIns;
  bool get isEmpty => root.isEmpty && signals.isEmpty && checkIns.isEmpty;
  static List<InputDocumentEdit> _edits(
    Map<String, Map<String, dynamic>> before,
    Map<String, Map<String, dynamic>> after,
  ) => [
    for (final id in {...before.keys, ...after.keys})
      if (!sameSyncValue(before[id], after[id]))
        InputDocumentEdit(id, before[id], after[id]),
  ];

  Map<String, dynamic> rootData({bool useBefore = false}) {
    final data = <String, dynamic>{};
    for (final item in root.entries) {
      _setRootPath(
        data,
        item.key,
        useBefore ? item.value.before : item.value.after,
      );
    }
    return data;
  }

  void checkRootAgainst(InputSyncSnapshot actual) {
    for (final item in root.entries) {
      checkSyncValue(
        'profile',
        _rootPathValue(actual.root, item.key),
        item.value.before,
        item.value.after,
      );
    }
  }

  void checkAgainst(InputSyncSnapshot actual) {
    checkRootAgainst(actual);
    for (final item in signals) {
      checkSyncValue(
        'signal',
        actual.signals[item.id],
        item.before,
        item.after,
      );
    }
    for (final item in checkIns) {
      checkSyncValue(
        'check-in',
        actual.checkIns[item.id],
        item.before,
        item.after,
      );
    }
  }
}

Map<String, SyncValueEdit> _rootEdits(
  Map<String, dynamic> before,
  Map<String, dynamic> after, [
  String prefix = '',
]) {
  final edits = <String, SyncValueEdit>{};
  for (final key in {...before.keys, ...after.keys}) {
    final previous = before[key];
    final next = after[key];
    if (sameSyncValue(previous, next)) continue;
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if ((previous is Map || previous == null) &&
        (next is Map || next == null) &&
        (previous is Map || next is Map)) {
      final nested = _rootEdits(
        previous is Map ? _map(previous) : {},
        next is Map ? _map(next) : {},
        path,
      );
      // Clearing a known map clears only its known leaves. Unknown fields from
      // newer clients or server writers remain untouched by merged writes.
      edits.addAll(nested);
    } else {
      edits[path] = SyncValueEdit(previous, next);
    }
  }
  return edits;
}

Object? _rootPathValue(Map<String, dynamic> root, String path) {
  Object? value = root;
  for (final key in path.split('.')) {
    if (value is! Map) return null;
    value = value[key];
  }
  return value;
}

void _setRootPath(Map<String, dynamic> root, String path, Object? value) {
  final keys = path.split('.');
  var parent = root;
  for (final key in keys.take(keys.length - 1)) {
    final existing = parent[key];
    final child = existing is Map ? _map(existing) : <String, dynamic>{};
    parent[key] = child;
    parent = child;
  }
  parent[keys.last] = value;
}

class InputSyncConflict implements Exception {
  const InputSyncConflict(this.kind);
  final String kind;
  @override
  String toString() =>
      'A $kind was changed on another device. Your edits remain saved here.';
}

void checkSyncValue(
  String kind,
  Object? actual,
  Object? before,
  Object? after,
) {
  if (!sameSyncValue(actual, before) && !sameSyncValue(actual, after)) {
    throw InputSyncConflict(kind);
  }
}

/// Firestore timestamp fields must remain timestamps, not strings, after a
/// journal round-trip. Other strings (including notes) are untouched.
Map<String, dynamic> syncFirestoreData(Map<String, dynamic> data) =>
    data.map((key, value) {
      const timeFields = {
        'timestamp',
        'recordedAt',
        'syncedAt',
        'lastHealthSync',
        'lastAttemptAt',
        'lastSuccessAt',
        'lastMeaningfulChangeAt',
      };
      return MapEntry(
        key,
        value is Map
            ? syncFirestoreData(_map(value))
            : timeFields.contains(key) && value is String
            ? DateTime.parse(value).toUtc()
            : value,
      );
    });

/// Include explicit nulls for cleared known fields when using Firestore merge.
/// Fields absent from both snapshots belong to another writer and are preserved.
Map<String, dynamic> syncMergedData(
  Map<String, dynamic>? before,
  Map<String, dynamic> after,
) => syncFirestoreData({
  for (final key in {...?before?.keys, ...after.keys})
    key: after[key] is Map
        ? syncMergedData(
            before?[key] is Map ? _map(before![key]) : null,
            _map(after[key]),
          )
        : after[key],
});
