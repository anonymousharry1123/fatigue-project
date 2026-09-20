import 'dart:convert';

import 'package:app/src/app_controller.dart';
import 'package:app/src/cloud_repository.dart';
import 'package:app/src/cloud_schema.dart';
import 'package:app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

final _now = DateTime.utc(2026, 9, 20, 12);
final _receipt = DateTime.utc(2026, 9, 1, 12);
const _session = AccountSession(uid: 'owner', email: 'owner@example.com');

Map<String, Object?> _signal() => SignalReading(
  id: 'backup-signal',
  type: SignalType.study,
  value: 2,
  timestamp: _now,
).toJson();

Map<String, Object?> _checkIn() => DailyCheckIn(
  id: 'backup-check-in',
  timestamp: _now,
  energy: 6,
  mood: 7,
  stress: 4,
).toJson();

Map<String, Object?> _outcome() => OutcomeRecord(
  id: 'backup-outcome',
  type: OutcomeType.observedEnergy,
  value: 7,
  observedAt: _now,
  recordedAt: _now,
  source: OutcomeSource.coach,
  sourceId: 'backup-source',
).toJson();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryCloudRepository repository;
  late AppController app;
  late Map<String, dynamic> backup;

  Map<String, dynamic> copy() =>
      jsonDecode(jsonEncode(backup)) as Map<String, dynamic>;

  void rejects(Map<String, dynamic> value) {
    expect(
      () => app.previewDeviceBackup(jsonEncode(value)),
      throwsFormatException,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = MemoryCloudRepository(signedInUid: 'owner')
      ..seed(
        'owner',
        CloudUserState(
          privacyConsent: testAdultPrivacyConsent,
          profile: const UserProfile(name: 'Owner'),
          accountEmail: _session.email,
          onboardingComplete: false,
          notificationsEnabled: false,
          outcomeConsent: true,
          outcomeConsentUpdatedAt: _receipt,
          healthAuthorized: false,
          migrationVersion: localMigrationVersion,
          signals: const [],
          checkIns: const [],
        ),
      );
    app = AppController(
      accountAuth: MemoryAccountAuth(session: _session),
      cloudRepository: repository,
      clock: () => _now,
    );
    await app.load();
    backup = jsonDecode(await app.exportDeviceBackup()) as Map<String, dynamic>;
  });

  tearDown(() => app.dispose());

  test('rejects malformed JSON and unsupported envelopes without writes', () {
    final before = app.exportJson();
    for (final raw in ['{', 'null', '[]', '{}', '{"backupVersion":2}']) {
      expect(() => app.previewDeviceBackup(raw), throwsFormatException);
    }
    for (final field in ['backupVersion', 'backupType', 'local']) {
      final invalid = copy()..remove(field);
      rejects(invalid);
    }
    expect(app.exportJson(), before);
  });

  test('rejects oversized pasted data before attempting JSON parsing', () {
    expect(
      () => app.previewDeviceBackup(' ' * (20 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
    expect(app.signals, isEmpty);
    expect(app.hasAnyPendingCloudChanges, isFalse);
  });

  test('rejects invalid collection shapes and incomplete profile', () {
    for (final field in ['signals', 'checkIns', 'outcomes']) {
      final invalid = copy();
      invalid['local'][field] = {'record': {}};
      rejects(invalid);
    }
    final invalidProfile = copy();
    (invalidProfile['local']['profile'] as Map).remove('name');
    rejects(invalidProfile);
  });

  test('rejects duplicate IDs within each record collection', () {
    for (final entry in {
      'signals': _signal(),
      'checkIns': _checkIn(),
      'outcomes': _outcome(),
    }.entries) {
      final invalid = copy();
      invalid['local'][entry.key] = [entry.value, entry.value];
      rejects(invalid);
    }
    expect(app.signals, isEmpty);
    expect(app.checkIns, isEmpty);
    expect(app.outcomes, isEmpty);
  });

  test('rejects another account in envelope and every ownership marker', () {
    final wrongOwner = copy()..['ownerUid'] = 'other';
    rejects(wrongOwner);
    final wrongPrivacyOwner = copy();
    wrongPrivacyOwner['local']['privacyOwnerUid'] = 'other';
    rejects(wrongPrivacyOwner);
    for (final field in [
      'inputSync',
      'outcomeSync',
      'coachSync',
      'modelTransparencyCache',
    ]) {
      final invalid = copy();
      invalid['local'][field] = {'uid': 'other'};
      rejects(invalid);
    }
    final wrongRecoveryOwner = copy();
    wrongRecoveryOwner['beforeCloudRestore'] = {
      'ownerUid': 'other',
      'local': wrongRecoveryOwner['local'],
    };
    rejects(wrongRecoveryOwner);
    expect(app.hasAnyPendingCloudChanges, isFalse);
  });

  test(
    'rejects invalid IDs and dates rather than normalizing saved records',
    () {
      for (final id in ['', '../record', '.', '..', 'x' * 1501]) {
        final invalid = copy();
        invalid['local']['signals'] = [
          {..._signal(), 'id': id},
        ];
        rejects(invalid);
      }
      for (final timestamp in [
        '2026-02-30T12:00:00Z',
        '2026-09-20T25:00:00Z',
        '2026-09-20T12:61:00Z',
        '2026-09-20T12:00:61Z',
        '2026-09-20T12:00:00+26:00',
        '2026-09-20T12:00:00',
      ]) {
        final invalid = copy();
        invalid['local']['signals'] = [
          {..._signal(), 'timestamp': timestamp},
        ];
        rejects(invalid);
      }
    },
  );

  test('rejects a fractional outcome consent version before truncation', () {
    final invalid = copy();
    invalid['local']['outcomes'] = [
      {..._outcome(), 'consentVersion': 1.5},
    ];
    rejects(invalid);
  });

  test('rejects signal values that would overflow history calculations', () {
    final invalid = copy();
    invalid['local']['signals'] = [
      {..._signal(), 'type': 'nap', 'groupId': 'sleep-bad', 'value': 1e308},
    ];
    rejects(invalid);
    expect(app.signals, isEmpty);
  });

  test(
    'outcome receipt mismatch skips outcomes but restores other data',
    () async {
      final saved = copy();
      saved['local']['signals'] = [_signal()];
      saved['local']['outcomes'] = [_outcome()];
      saved['local']['outcomeConsentUpdatedAt'] = _receipt
          .subtract(const Duration(days: 1))
          .toIso8601String();
      final preview = app.previewDeviceBackup(jsonEncode(saved));
      expect(preview.newRecords, 1);
      expect(preview.outcomeCount, 0);
      expect(preview.skippedOutcomes, 1);
      await app.restoreDeviceBackup(preview);
      expect(app.signals.single.id, 'backup-signal');
      expect(app.outcomes, isEmpty);
      expect(app.outcomeConsent, isTrue);
      expect(app.outcomeConsentUpdatedAt!.isAtSameMomentAs(_receipt), isTrue);
      expect(
        await repository.outcomesByRange(
          'owner',
          start: _now.subtract(const Duration(days: 1)),
          end: _now.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
    },
  );

  test('a backup cannot re-enable revoked outcome consent', () async {
    final saved = copy();
    saved['local']['outcomes'] = [_outcome()];
    await app.setOutcomeConsent(false);
    final preview = app.previewDeviceBackup(jsonEncode(saved));
    expect(preview.outcomeCount, 0);
    expect(preview.skippedOutcomes, 1);
    await app.restoreDeviceBackup(preview);
    expect(app.outcomeConsent, isFalse);
    expect(app.outcomes, isEmpty);
    expect(app.hasPendingOutcomeChanges, isFalse);
  });

  test('a later local edit makes an earlier preview unsafe to apply', () async {
    final saved = copy();
    saved['local']['signals'] = [_signal()];
    final preview = app.previewDeviceBackup(jsonEncode(saved));
    await app.addSignal(SignalType.hydration, 1);
    await expectLater(app.restoreDeviceBackup(preview), throwsStateError);
    expect(app.signals.single.type, SignalType.hydration);
  });

  test(
    'restores queued outcomes absent from the visible history cache',
    () async {
      final saved = copy();
      final outcome = _outcome()
        ..['observedAt'] = _now
            .subtract(const Duration(days: 500))
            .toIso8601String();
      saved['local']['outcomes'] = [];
      saved['local']['outcomeSync'] = {
        'version': 1,
        'uid': 'owner',
        'consentAt': _receipt.toIso8601String(),
        'writes': {'backup-outcome': outcome},
      };
      final preview = app.previewDeviceBackup(jsonEncode(saved));
      expect(preview.outcomeCount, 1);
      expect(preview.newRecords, 1);
      await app.restoreDeviceBackup(preview);
      expect(
        (await repository.outcomesByRange(
          'owner',
          start: _now.subtract(const Duration(days: 501)),
          end: _now,
        )).single.id,
        'backup-outcome',
      );
    },
  );

  test(
    'the queued outcome value takes precedence over its older cache',
    () async {
      final saved = copy();
      saved['local']['outcomes'] = [
        {..._outcome(), 'value': 4},
      ];
      saved['local']['outcomeSync'] = {
        'version': 1,
        'uid': 'owner',
        'consentAt': _receipt.toIso8601String(),
        'writes': {'backup-outcome': _outcome()},
      };
      final preview = app.previewDeviceBackup(jsonEncode(saved));
      expect(preview.outcomeCount, 1);
      await app.restoreDeviceBackup(preview);
      expect(app.outcomes.single.value, 7);
      expect(
        (await repository.outcomesByRange(
          'owner',
          start: _now.subtract(const Duration(days: 1)),
          end: _now.add(const Duration(days: 1)),
        )).single.value,
        7,
      );
    },
  );

  test('saved deletion requests never delete current outcomes', () async {
    await app.recordObservedEnergy(8, observedAt: _now);
    final current = app.outcomes.single;
    final saved = copy();
    saved['local']['signals'] = [_signal()];
    saved['local']['outcomes'] = [
      {...current.toJson(), 'value': 4},
    ];
    saved['local']['outcomeSync'] = {
      'version': 1,
      'uid': 'owner',
      'consentAt': _receipt.toIso8601String(),
      'writes': {current.id: null},
    };
    final preview = app.previewDeviceBackup(jsonEncode(saved));
    expect(preview.outcomeCount, 0);
    await app.restoreDeviceBackup(preview, replaceExisting: true);
    expect(app.outcomes.single.id, current.id);
    expect(app.outcomes.single.value, 8);
    expect(app.hasPendingOutcomeChanges, isFalse);
  });

  test('rejects mismatched pending record identity and journal version', () {
    for (final invalidJournal in [
      {
        'version': 1,
        'uid': 'owner',
        'consentAt': _receipt.toIso8601String(),
        'writes': {'wrong-id': _outcome()},
      },
      {
        'version': 2,
        'uid': 'owner',
        'consentAt': _receipt.toIso8601String(),
        'writes': {'backup-outcome': _outcome()},
      },
    ]) {
      final invalid = copy();
      invalid['local']['outcomeSync'] = invalidJournal;
      rejects(invalid);
    }
  });

  test('an old journal consent cannot authorize its queued outcomes', () {
    final saved = copy();
    saved['local']['outcomeSync'] = {
      'version': 1,
      'uid': 'owner',
      'consentAt': _receipt.subtract(const Duration(days: 1)).toIso8601String(),
      'writes': {'backup-outcome': _outcome()},
    };
    final preview = app.previewDeviceBackup(jsonEncode(saved));
    expect(preview.outcomeCount, 0);
    expect(preview.skippedOutcomes, 1);
    expect(app.outcomes, isEmpty);
  });
}
