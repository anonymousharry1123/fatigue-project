import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../device_backup_service.dart';
import '../privacy_consent.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'device_backup_flow.dart';
import 'backup_restore_screen.dart';
import 'study_tools_screen.dart';

/// Account controls are explicit user actions. Merely opening this route never
/// exports, changes consent, imports Health data, or starts a deletion.
class PrivacyCenterScreen extends StatefulWidget {
  const PrivacyCenterScreen({
    super.key,
    required this.controller,
    this.requireReview = false,
    this.backupService = const DeviceBackupService(),
  });

  final AppController controller;
  final bool requireReview;
  final DeviceBackupService backupService;

  @override
  State<PrivacyCenterScreen> createState() => _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends State<PrivacyCenterScreen> {
  PrivacyAgeBand? _ageBand;
  PrivacyRegion? _region;
  bool _acknowledged = false;
  bool _ageLocked = false;
  bool _working = false;
  bool _savingBackup = false;
  bool _retryingConnection = false;
  bool _changingCapture = false;
  String? _captureError;
  int? _captureErrorRevision;
  String? _connectionError;
  String? _error;
  String? _export;
  String? _exportOwner;
  bool _exportWasCloud = false;
  bool _copied = false;

  AppController get _controller => widget.controller;
  bool get _busy =>
      _working ||
      _savingBackup ||
      _retryingConnection ||
      _changingCapture ||
      _controller.ai1CaptureBusy ||
      _controller.isPrivacyBusy;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final consent = _controller.privacyConsent;
      final review = _controller.privacyReviewRequired;
      final needsDeletionSignIn =
          _controller.deletionPending &&
          _controller.cloudEnabled &&
          !_controller.isCloudAuthenticated;
      final showExport =
          _export != null &&
          _exportOwner == _controller.cloudUid &&
          _exportWasCloud == _controller.isCloudAuthenticated &&
          !_controller.isSignedOut;
      return PopScope(
        canPop: !_busy && !widget.requireReview,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.requireReview && !_busy,
            title: Text(context.tr('Privacy center')),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              key: const Key('privacy-center-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                const _PrivacyHero(),
                const SizedBox(height: 18),
                if (_controller.deletionPending) ...[
                  _PrivacyNotice(
                    key: Key('privacy-deletion-pending'),
                    icon: Icons.pause_circle_outline_rounded,
                    color: TonyoPalette.of(context).error,
                    title: 'Deletion needs your attention',
                    text: needsDeletionSignIn
                        ? 'Cloud account deletion could not be confirmed. Sign '
                              'in to finish, or erase only this device’s Tonyo '
                              'cache. Clearing this device does not confirm '
                              'deletion of your cloud account.'
                        : 'Deletion did not finish. Some data may already be removed. '
                              'New collection and syncing are paused. Retry deletion '
                              'below; this is not a completed deletion.',
                  ),
                  if (needsDeletionSignIn) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('privacy-resume-deletion-sign-in'),
                      onPressed: _busy ? null : _signOut,
                      icon: const Icon(Icons.login_rounded),
                      label: Text(context.tr('Sign in to finish deletion')),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('privacy-clear-device-only'),
                      onPressed: _busy
                          ? null
                          : () => _deleteData(clearDeviceOnly: true),
                      icon: const Icon(Icons.phone_iphone_rounded),
                      label: Text(
                        context.tr('Erase only this device’s Tonyo cache'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                if (review && !_controller.deletionPending) ...[
                  _PrivacyNotice(
                    icon: Icons.fact_check_outlined,
                    color: TonyoPalette.of(context).warning,
                    title: 'A quick review before you continue',
                    text: context.tr(
                      'Your existing records stay in place. Review your age '
                      'band, region, and data use before new tracking, Health '
                      'imports, or optional learning can start.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TonyoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _backupControls(),
                        if (_controller.isCloudAuthenticated) ...[
                          const SizedBox(height: 12),
                          Text(
                            context.tr(
                              'If the account could not be verified while offline, '
                              'retry when connected to check it and sync pending changes.',
                            ),
                            style: TextStyle(
                              color: TonyoPalette.of(context).muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const Key('privacy-retry-connection'),
                            onPressed: _busy || _controller.isCloudSyncing
                                ? null
                                : _retryConnection,
                            icon: const Icon(Icons.sync_rounded),
                            label: Text(
                              _retryingConnection
                                  ? context.tr('Checking connection…')
                                  : context.tr('Retry connection'),
                            ),
                          ),
                          if (_connectionError case final error?) ...[
                            const SizedBox(height: 8),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                context.tr(error),
                                style: TextStyle(
                                  color: TonyoPalette.of(context).warning,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _dataUse(),
                const SizedBox(height: 16),
                TonyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heading(context, 'Your privacy choices'),
                      const SizedBox(height: 8),
                      if (consent != null) ...[
                        Text(
                          context.tr(
                            "{value0} · {value1}",
                            args: {
                              'value0': context.tr(consent.ageBand.label),
                              'value1': context.tr(consent.region.label),
                            },
                          ),
                          key: const Key('privacy-saved-age-region'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr(
                            "Acknowledged {value0} · Policy version {value1}",
                            args: {
                              'value0': _date(consent.acceptedAt),
                              'value1': consent.policyVersion,
                            },
                          ),
                          key: const Key('privacy-consent-receipt'),
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            'Age and region are saved with your consent record. '
                            'They cannot be changed here to bypass a protection.',
                          ),
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                          ),
                        ),
                      ],
                      if (review &&
                          !_controller.deletionPending &&
                          _controller.guardianConsentBlocker == null) ...[
                        const SizedBox(height: 10),
                        if (_ageLocked && consent == null)
                          Text(
                            context.tr(
                              "Selected age band: {value0}",
                              args: {'value0': context.tr(_ageBand!.label)},
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        PrivacyChoicesForm(
                          ageBand: consent?.ageBand ?? _ageBand,
                          region: consent?.region ?? _region,
                          acknowledged: _acknowledged,
                          locked: consent != null || _ageLocked,
                          enabled: !_busy && !_ageLocked,
                          cloudEnabled: _controller.cloudEnabled,
                          onAgeChanged: (value) => setState(() {
                            _ageBand = value;
                            _acknowledged = false;
                            _ageLocked =
                                value != null &&
                                value != PrivacyAgeBand.adult &&
                                !_controller.guardianConsentVerified;
                          }),
                          onRegionChanged: (value) => setState(() {
                            _region = value;
                            _acknowledged = false;
                          }),
                          onAcknowledged: (value) =>
                              setState(() => _acknowledged = value),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          key: const Key('privacy-accept-button'),
                          onPressed:
                              !_busy &&
                                  !_ageLocked &&
                                  (consent?.ageBand ?? _ageBand) != null &&
                                  (consent?.region ?? _region) != null &&
                                  _acknowledged
                              ? _accept
                              : null,
                          icon: const Icon(Icons.check_rounded),
                          label: Text(
                            _ageLocked
                                ? context.tr('Guardian setup unavailable')
                                : _busy
                                ? context.tr('Saving…')
                                : context.tr('Save privacy choices'),
                          ),
                        ),
                      ],
                      if (_controller.guardianConsentBlocker
                          case final blocker?) ...[
                        const SizedBox(height: 14),
                        _PrivacyNotice(
                          key: const Key('privacy-guardian-required'),
                          icon: Icons.family_restroom_rounded,
                          color: TonyoPalette.of(context).warning,
                          title: 'Verified guardian setup required',
                          text: blocker,
                        ),
                      ] else if (_controller.guardianConsentVerified) ...[
                        const SizedBox(height: 12),
                        Text(
                          context.tr(
                            'Guardian authorization verified by the account service.',
                          ),
                          key: Key('privacy-guardian-verified'),
                          style: TextStyle(
                            color: TonyoPalette.of(context).success,
                          ),
                        ),
                      ],
                      if (consent != null &&
                          review &&
                          _controller.isCloudAuthenticated &&
                          !_controller.deletionPending) ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          key: const Key('privacy-check-account-status'),
                          onPressed: _busy
                              ? null
                              : () => _run(_controller.handleAppResumed),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(context.tr('Check account status')),
                        ),
                        Text(
                          context.tr(
                            'Checks the account service without changing your '
                            'saved choices or opting you into outcome learning.',
                          ),
                          style: TextStyle(
                            color: TonyoPalette.of(context).muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _optionalLearning(),
                const SizedBox(height: 16),
                _localStudyHistory(),
                const SizedBox(height: 22),
                _heading(context, 'Take your data with you'),
                const SizedBox(height: 8),
                TonyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!review) ...[
                        _backupControls(),
                        const Divider(height: 28),
                      ],
                      Text(
                        _controller.isCloudAuthenticated
                            ? context.tr(
                                'Generate a fresh export of your private Tonyo account '
                                'and this device’s available app data.',
                              )
                            : context.tr(
                                'Generate an export of Tonyo data stored on this '
                                'device. This does not fetch another account.',
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr(
                          'Includes sensitive wellness information. Nothing is '
                          'copied or shared until you explicitly choose to do so.',
                        ),
                        style: TextStyle(color: TonyoPalette.of(context).muted),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        key: const Key('privacy-generate-export'),
                        onPressed: _busy || _controller.deletionPending
                            ? null
                            : _generateExport,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          _controller.isExportingData
                              ? context.tr('Preparing export…')
                              : context.tr('Generate data export'),
                        ),
                      ),
                      if (showExport) ...[
                        const Divider(height: 28),
                        _ExportSummary(data: _export!),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('privacy-copy-export'),
                          onPressed: _busy ? null : _copyExport,
                          icon: Icon(
                            _copied ? Icons.check_rounded : Icons.copy_outlined,
                          ),
                          label: Text(
                            _copied
                                ? context.tr('Copied')
                                : context.tr('Copy JSON export'),
                          ),
                        ),
                        TextButton(
                          key: const Key('privacy-dismiss-export'),
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _export = null;
                                  _copied = false;
                                }),
                          child: Text(
                            context.tr('Dismiss export from this screen'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _heading(context, 'Reset or leave Tonyo'),
                const SizedBox(height: 8),
                TonyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'Reset clears tracking records while keeping your '
                          'account and profile. Deletion removes your Tonyo '
                          'account data and this device’s Tonyo cache.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr(
                          'Neither action deletes the original data in Apple '
                          'Health, files you exported, or copies cached on other '
                          'devices. Manage Apple Health access in iOS Settings.',
                        ),
                        style: TextStyle(color: TonyoPalette.of(context).muted),
                      ),
                      const SizedBox(height: 14),
                      if (!_controller.deletionPending)
                        OutlinedButton.icon(
                          key: const Key('privacy-reset-tracking'),
                          onPressed:
                              _busy || !_controller.privacyFeaturesAllowed
                              ? null
                              : _resetTracking,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: Text(context.tr('Reset tracking data')),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('privacy-delete-data'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TonyoPalette.of(context).error,
                        ),
                        onPressed: _busy || needsDeletionSignIn
                            ? null
                            : _deleteData,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          _controller.deletionPending
                              ? context.tr('Retry unfinished deletion')
                              : _controller.isCloudAuthenticated
                              ? context.tr('Delete account and data')
                              : context.tr('Delete local data'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error ?? _controller.privacyOperationError
                    case final error?) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: _PrivacyNotice(
                      key: const Key('privacy-operation-error'),
                      icon: Icons.error_outline_rounded,
                      color: TonyoPalette.of(context).error,
                      title: 'Action not completed',
                      text: error,
                    ),
                  ),
                ],
                if (widget.requireReview && !_controller.deletionPending) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    key: const Key('privacy-review-sign-out'),
                    onPressed: _busy ? null : _signOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(
                      context.tr('Return to welcome without continuing'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _backupControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr(
          'Save the data on this device, including unsynced changes, as a JSON '
          'backup. No internet is needed.',
        ),
        style: TextStyle(color: TonyoPalette.of(context).muted),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const Key('privacy-save-backup'),
        onPressed: _savingBackup || !_controller.canExportDeviceBackup
            ? null
            : _saveBackup,
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        icon: const Icon(Icons.save_alt_rounded),
        label: Text(
          _savingBackup
              ? context.tr('Saving backup…')
              : context.tr('Save device backup'),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('privacy-restore-backup'),
        onPressed: _busy || !_controller.canRestoreDeviceBackup
            ? null
            : _restoreBackup,
        icon: const Icon(Icons.restore_rounded),
        label: Text(context.tr('Restore from backup')),
      ),
      if (!_controller.canRestoreDeviceBackup && !_controller.deletionPending)
        Text(
          context.tr('Finish privacy review before restoring records.'),
          style: TextStyle(color: TonyoPalette.of(context).muted),
        ),
    ],
  );

  Future<void> _saveBackup() async {
    if (_savingBackup || !_controller.canExportDeviceBackup) return;
    setState(() => _savingBackup = true);
    try {
      await saveDeviceBackup(context, _controller, widget.backupService);
    } finally {
      if (mounted) setState(() => _savingBackup = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy || !_controller.canRestoreDeviceBackup) return;
    setState(() => _working = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BackupRestoreScreen(
            controller: _controller,
            service: widget.backupService,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _retryConnection() async {
    if (_busy || _controller.isCloudSyncing) return;
    final revision = _controller.sessionRevision;
    setState(() {
      _retryingConnection = true;
      _connectionError = null;
    });
    try {
      await _controller.retryCloudSync();
      if (!mounted || revision != _controller.sessionRevision) return;
      setState(() {
        _connectionError =
            _controller.cloudSyncError ??
            _controller.outcomeError ??
            (_controller.privacyReviewRequired
                ? 'Connection checked. Review your privacy choices to continue.'
                : null);
      });
    } on Object {
      if (mounted && revision == _controller.sessionRevision) {
        setState(
          () => _connectionError = 'Could not connect. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _retryingConnection = false);
    }
  }

  Widget _dataUse() => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'A clear view of your data'),
        const SizedBox(height: 14),
        _DataUseRow(
          icon: Icons.phone_iphone_rounded,
          title: 'On this device',
          text: context.tr(
            'Your entries and imported Health summaries support wellness '
            'scores and forecasts. An offline cache, preparation snapshot, '
            'and any personalized model weights stay on this device.',
          ),
        ),
        const SizedBox(height: 16),
        _DataUseRow(
          icon: _controller.isCloudAuthenticated
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          title: _controller.isCloudAuthenticated
              ? 'Your private Firebase account'
              : 'No signed-in cloud account',
          text: _controller.isCloudAuthenticated
              ? 'Your profile, settings, entries, imported summaries, scores, '
                    'and optional outcomes sync under your account. Other '
                    'users do not have access through Tonyo’s account rules.'
              : 'This session uses local storage. Signing in restores that '
                    'account’s cloud data; it does not automatically migrate '
                    'this local profile. Export local data first if you want '
                    'a copy.',
        ),
        const SizedBox(height: 16),
        _DataUseRow(
          icon: Icons.tune_rounded,
          title: 'Separate, optional controls',
          text: context.tr(
            'Health access, notifications, and outcome learning are separate '
            'choices. Agreeing to this notice does not enable them. '
            'Personalized Energy training runs only when you request it.',
          ),
        ),
        const SizedBox(height: 16),
        _DataUseRow(
          icon: Icons.favorite_border_rounded,
          title: 'Wellness estimates, not a diagnosis',
          text: context.tr(
            'Tonyo can be incomplete or wrong. It does not diagnose, treat, '
            'or replace medical care. Do not rely on its scores for '
            'medical or safety-critical decisions.',
          ),
        ),
      ],
    ),
  );

  Widget _optionalLearning() => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'Optional outcome learning'),
        const SizedBox(height: 8),
        Text(
          context.tr(
            'Link future check-ins, reaction tests, and optional Coach ratings '
            'to private outcome records. Energy personalization uses eligible '
            'records only after a separate model refresh.',
          ),
          style: TextStyle(color: TonyoPalette.of(context).muted),
        ),
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            key: const Key('privacy-outcome-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('Allow outcome learning')),
            subtitle: Text(
              _controller.outcomeConsent
                  ? context.tr(
                      'On · turn off to stop new outcomes and remove this '
                      'device’s personalized model from use.',
                    )
                  : context.tr(
                      'Off · not required to use ordinary wellness tracking.',
                    ),
            ),
            value: _controller.outcomeConsent,
            onChanged:
                _busy ||
                    _controller.isOutcomeLoading ||
                    (!_controller.privacyFeaturesAllowed &&
                        !_controller.outcomeConsent)
                ? null
                : _setOutcomeConsent,
          ),
        ),
        Text(
          context.tr(
            'Turning this off does not delete previously saved outcomes. '
            'Reset tracking or delete data below to remove those records.',
          ),
          style: TextStyle(color: TonyoPalette.of(context).muted),
        ),
      ],
    ),
  );

  Future<void> _accept() async {
    final existing = _controller.privacyConsent;
    await _run(
      () => _controller.acceptPrivacy(
        ageBand: existing?.ageBand ?? _ageBand!,
        region: existing?.region ?? _region!,
        acknowledged: _acknowledged,
      ),
    );
  }

  Widget _localStudyHistory() {
    final available = _controller.ai1CaptureAvailable;
    final enabled = _controller.ai1CaptureEnabled;
    final error =
        (_captureErrorRevision == _controller.sessionRevision
            ? _captureError
            : null) ??
        _controller.ai1CaptureError;
    return TonyoCard(
      key: const Key('privacy-local-study-history'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context, 'Local study history'),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'Save new manual sleep logs and check-in revisions on this '
              'device, including earlier answers after edits. This history '
              'is not used for model training or uploaded to the cloud.',
            ),
            style: TextStyle(color: TonyoPalette.of(context).muted),
          ),
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              key: const Key('privacy-study-history-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Keep local study history')),
              subtitle: Text(
                !available
                    ? context.tr('Available in the iPhone app.')
                    : _changingCapture || _controller.ai1CaptureBusy
                    ? context.tr('Updating study history…')
                    : enabled
                    ? context.tr('On · starts with new records only.')
                    : context.tr('Off · no study history is being saved.'),
              ),
              value: enabled,
              onChanged:
                  !available ||
                      _busy ||
                      (!_controller.privacyFeaturesAllowed && !enabled)
                  ? null
                  : _setAi1CaptureEnabled,
            ),
          ),
          if (available) ...[
            Text(
              context.tr(
                'Saved revisions: {count}',
                args: {'count': _controller.ai1CapturedRevisionCount},
              ),
              key: const Key('privacy-study-history-count'),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            context.tr(
              'Turning this off clears this study history. Your ordinary '
              'sleep logs and check-ins stay. Any earlier fixed-schedule plan '
              'keeps its original timing rules. Review or export its retained '
              'history in Study tools. This history is excluded from ordinary '
              'backups and exports.',
            ),
            style: TextStyle(color: TonyoPalette.of(context).muted),
          ),
          if (enabled)
            TextButton.icon(
              key: const Key('privacy-study-tools'),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StudyToolsScreen(
                          controller: _controller,
                          backupService: widget.backupService,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.science_outlined),
              label: Text(context.tr('Study tools')),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                context.tr(error),
                key: const Key('privacy-study-history-error'),
                style: TextStyle(color: TonyoPalette.of(context).error),
              ),
            ),
          ],
          if (available &&
              (error != null || !_controller.privacyFeaturesAllowed))
            TextButton.icon(
              key: const Key('privacy-clear-study-history'),
              onPressed: _busy ? null : () => _setAi1CaptureEnabled(false),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(context.tr('Clear local history')),
            ),
        ],
      ),
    );
  }

  Future<void> _setAi1CaptureEnabled(bool value) async {
    if (_busy || !_controller.ai1CaptureAvailable) return;
    final revision = _controller.sessionRevision;
    setState(() {
      _changingCapture = true;
      _captureError = null;
      _captureErrorRevision = revision;
    });
    try {
      await _controller.setAi1CaptureEnabled(value);
    } on Object {
      if (mounted && revision == _controller.sessionRevision) {
        setState(() {
          _captureError =
              _controller.ai1CaptureError ??
              'Could not update local study history. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _changingCapture = false);
    }
  }

  Future<void> _setOutcomeConsent(bool value) async {
    if (_busy) return;
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Allow optional outcome learning?')),
          scrollable: true,
          content: Text(
            context.tr(
              'Future Energy check-ins, reaction tests, and optional completed '
              'Coach ratings will be saved as private outcome records. '
              'Eligible outcomes can support a small on-device Energy model '
              'when you separately choose Refresh Energy model. Model weights '
              'are not uploaded. You can turn this off at any time.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Not now')),
            ),
            FilledButton(
              key: const Key('privacy-confirm-outcomes'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Allow future outcomes')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run(() => _controller.setOutcomeConsent(value));
  }

  Future<void> _generateExport() async {
    if (_busy) return;
    final owner = _controller.cloudUid;
    final cloud = _controller.isCloudAuthenticated;
    setState(() {
      _export = null;
      _copied = false;
    });
    await _run(() async {
      final data = await _controller.exportAllData();
      if (!mounted ||
          owner != _controller.cloudUid ||
          cloud != _controller.isCloudAuthenticated ||
          _controller.isSignedOut) {
        return;
      }
      // Validate the export before labeling it ready; never present a malformed
      // or partial result as a completed download.
      if (jsonDecode(data) is! Map<String, dynamic>) {
        throw const FormatException('Invalid export');
      }
      setState(() {
        _export = data;
        _exportOwner = owner;
        _exportWasCloud = cloud;
      });
    });
  }

  Future<void> _copyExport() async {
    final data = _export;
    if (data == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Copy sensitive data?')),
        scrollable: true,
        content: Text(
          context.tr(
            'This export contains private wellness and account information. '
            'Your clipboard may be readable by other apps or synced to other '
            'devices. Copy only on a device you trust. Tonyo cannot erase '
            'copies after you share them.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            key: const Key('privacy-confirm-copy'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Copy to clipboard')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_exportOwner != _controller.cloudUid || _controller.isSignedOut) {
      setState(() => _export = null);
      return;
    }
    await _run(() async {
      await Clipboard.setData(ClipboardData(text: data));
      if (mounted) setState(() => _copied = true);
    });
  }

  Future<void> _resetTracking() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DestructiveConfirmation(reset: true),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _controller.clearTrackingData();
      if (mounted) {
        setState(() => _export = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('Tracking data cleared. Account kept.')),
          ),
        );
      }
    });
  }

  Future<void> _deleteData({bool clearDeviceOnly = false}) async {
    if (_busy) return;
    // The dialog owns and clears the password controller. Only an explicit
    // typed confirmation can return credentials to this operation.
    final confirmation = await showDialog<_DeletionConfirmation>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DestructiveConfirmation(
        cloud: _controller.isCloudAuthenticated,
        retry: _controller.deletionPending,
        clearDeviceOnly: clearDeviceOnly,
      ),
    );
    if (confirmation == null || !mounted) return;
    final success = await _run(() async {
      setState(() => _export = null);
      if (clearDeviceOnly) {
        await _controller.clearDeviceAfterInterruptedDeletion();
      } else {
        await _controller.deleteAccountData(password: confirmation.password);
      }
    });
    if (success && mounted && !widget.requireReview) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _signOut() async {
    await _run(_controller.signOut);
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } on Object {
      if (mounted) {
        setState(() {
          _error =
              _controller.privacyOperationError ??
              'This action could not finish. Your data has not been reported '
                  'as deleted or exported. Check your connection and retry.';
        });
        // Keep an error visible at the point of action even when the permanent
        // error panel is outside this long, accessible scroll view.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr(_error!)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  static Widget _heading(BuildContext context, String text) =>
      Text(context.tr(text), style: Theme.of(context).textTheme.titleLarge);

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')} (device time)';
  }
}

/// Shared neutral age/region screen. No inferred adult age and no prechecked
/// acknowledgement; guardian authorization cannot be self-attested here.
class PrivacyChoicesForm extends StatelessWidget {
  const PrivacyChoicesForm({
    super.key,
    required this.ageBand,
    required this.region,
    required this.acknowledged,
    required this.onAgeChanged,
    required this.onRegionChanged,
    required this.onAcknowledged,
    required this.cloudEnabled,
    this.enabled = true,
    this.locked = false,
  });

  final PrivacyAgeBand? ageBand;
  final PrivacyRegion? region;
  final bool acknowledged;
  final bool enabled;
  final bool locked;
  final bool cloudEnabled;
  final ValueChanged<PrivacyAgeBand?> onAgeChanged;
  final ValueChanged<PrivacyRegion?> onRegionChanged;
  final ValueChanged<bool> onAcknowledged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!locked) ...[
        Text(
          context.tr(
            'Choose your age band and region. We ask before account details '
            'so age-appropriate protections can apply. No date of birth is needed.',
          ),
          style: TextStyle(color: TonyoPalette.of(context).muted),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<PrivacyAgeBand>(
          key: const Key('privacy-age-band'),
          initialValue: ageBand,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          decoration: InputDecoration(labelText: context.tr('Age band')),
          hint: Text(context.tr('Choose your age band')),
          items: PrivacyAgeBand.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(context.tr(value.label)),
                ),
              )
              .toList(),
          onChanged: enabled ? onAgeChanged : null,
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<PrivacyRegion>(
          key: const Key('privacy-region'),
          initialValue: region,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          decoration: InputDecoration(labelText: context.tr('Region')),
          hint: Text(context.tr('Choose your region')),
          items: PrivacyRegion.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(context.tr(value.label)),
                ),
              )
              .toList(),
          onChanged: enabled ? onRegionChanged : null,
        ),
      ],
      if (ageBand != null && ageBand != PrivacyAgeBand.adult) ...[
        const SizedBox(height: 14),
        _PrivacyNotice(
          key: Key('privacy-age-protection'),
          icon: Icons.family_restroom_rounded,
          color: TonyoPalette.of(context).warning,
          title: 'A guardian step is needed',
          text: context.tr(
            'This build requires verified guardian authorization before '
            'under-18 tracking or account setup. A checkbox is not '
            'verification. New guardian setup is not available in this '
            'build; no name, email, or health data is needed to stop here.',
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        cloudEnabled
            ? context.tr(
                'Tonyo uses your wellness entries and any Health summaries you '
                'choose to import for scores and forecasts. Signed-in data '
                'syncs to your private Firebase account, with an offline '
                'cache on this device. Firebase handles passwords.',
              )
            : context.tr(
                'Tonyo uses your wellness entries for scores and forecasts. '
                'This build stores app data on this device. Passwords '
                'are never saved by Tonyo.',
              ),
      ),
      const SizedBox(height: 12),
      Text(
        context.tr(
          'Health access and outcome learning are separate opt-ins. '
          'You can export your data or request deletion in Privacy center.',
        ),
        style: TextStyle(color: TonyoPalette.of(context).muted),
      ),
      const SizedBox(height: 10),
      Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          key: const Key('privacy-acknowledgement'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: acknowledged,
          onChanged: enabled ? (value) => onAcknowledged(value ?? false) : null,
          title: Text(
            context.tr(
              'I have read this data-use notice and understand Tonyo provides '
              'wellness estimates, not medical advice or a diagnosis.',
            ),
          ),
        ),
      ),
    ],
  );
}

class _PrivacyHero extends StatelessWidget {
  const _PrivacyHero();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: TonyoPalette.of(context).surface,
      border: Border.all(color: TonyoPalette.of(context).border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.shield_outlined,
          color: TonyoPalette.of(context).secondary,
          size: 32,
        ),
        const SizedBox(height: 14),
        Text(
          context.tr('Your data. Your choices.'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('Know what Tonyo uses. Decide what comes next.'),
          style: TextStyle(color: TonyoPalette.of(context).muted, height: 1.5),
        ),
      ],
    ),
  );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      border: Border.all(color: color.withValues(alpha: .28)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 8),
        Text(
          context.tr(title),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(context.tr(text), style: const TextStyle(height: 1.5)),
      ],
    ),
  );
}

class _DataUseRow extends StatelessWidget {
  const _DataUseRow({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: TonyoPalette.of(context).secondary, size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(title),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(text),
              style: TextStyle(color: TonyoPalette.of(context).muted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ExportSummary extends StatelessWidget {
  const _ExportSummary({required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    final decoded = jsonDecode(data) as Map<String, dynamic>;
    final counts = <String, int>{};
    void count(Map<String, dynamic> section, [String prefix = '']) {
      for (final entry in section.entries) {
        if (entry.value is List) {
          counts['$prefix${entry.key}'] = (entry.value as List).length;
        } else if (entry.key == 'collections' &&
            entry.value is Map<String, dynamic>) {
          for (final collection
              in (entry.value as Map<String, dynamic>).entries) {
            if (collection.value is Map) {
              counts['$prefix${collection.key}'] =
                  (collection.value as Map).length;
            }
          }
        } else if (entry.value is Map<String, dynamic> &&
            ['local', 'cloud', 'data'].contains(entry.key)) {
          count(entry.value as Map<String, dynamic>, '$prefix${entry.key} · ');
        }
      }
    }

    count(decoded);
    return Semantics(
      liveRegion: true,
      child: Column(
        key: const Key('privacy-export-summary'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Export ready'),
            style: TextStyle(
              color: TonyoPalette.of(context).success,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              "{value0} bytes · JSON format",
              args: {'value0': utf8.encode(data).length},
            ),
          ),
          Text(
            decoded['cloud'] == null
                ? context.tr('Scope: this device’s Tonyo data')
                : context.tr(
                    'Scope: your Tonyo cloud records and this device’s data',
                  ),
          ),
          if (counts.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final count in counts.entries)
              Text(
                context.tr(
                  "{value0}: {value1}",
                  args: {'value0': count.key, 'value1': count.value},
                ),
              ),
          ],
          const SizedBox(height: 10),
          Text(
            context.tr(
              'Tonyo records only—not a complete Apple Health archive, Firebase '
              'password, or files from another device. Keep the export somewhere '
              'private; this preview is held only while this screen is open.',
            ),
            style: TextStyle(color: TonyoPalette.of(context).muted),
          ),
          if (decoded['cloud'] != null) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Cloud collections are read in sequence, not as one atomic '
                'snapshot. Nested subcollections are not included. Local and '
                'cloud counts may overlap or differ while syncing.',
              ),
              style: TextStyle(color: TonyoPalette.of(context).warning),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeletionConfirmation {
  const _DeletionConfirmation(this.password);
  final String? password;
}

class _DestructiveConfirmation extends StatefulWidget {
  const _DestructiveConfirmation({
    this.cloud = false,
    this.reset = false,
    this.retry = false,
    this.clearDeviceOnly = false,
  });
  final bool cloud;
  final bool reset;
  final bool retry;
  final bool clearDeviceOnly;

  @override
  State<_DestructiveConfirmation> createState() =>
      _DestructiveConfirmationState();
}

class _DestructiveConfirmationState extends State<_DestructiveConfirmation> {
  final _confirmation = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.reset ? 'RESET' : 'DELETE';
    final ready =
        _confirmation.text == word &&
        (!widget.cloud || _password.text.isNotEmpty);
    return AlertDialog(
      title: Text(
        widget.clearDeviceOnly
            ? context.tr('Erase only this device?')
            : widget.reset
            ? context.tr('Reset tracking data?')
            : widget.retry
            ? context.tr('Retry account deletion?')
            : widget.cloud
            ? context.tr('Delete account and data?')
            : context.tr('Delete local data?'),
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.clearDeviceOnly
                ? context.tr(
                    'This erases only this device’s Tonyo cache. It does not '
                    'confirm deletion of the cloud account or any remaining '
                    'cloud data. Sign in again to finish cloud deletion.',
                  )
                : widget.reset
                ? context.tr(
                    'This permanently clears tracking signals, check-ins, outcomes, '
                    'scores, guidance, and the personalized model. Your account '
                    'and profile stay. Connected Apple Health can import '
                    'records again; disconnect it first if you want to stop imports.',
                  )
                : widget.cloud
                ? context.tr(
                    'This permanently deletes your Tonyo data in Firestore, '
                    'your Firebase sign-in account, and this device’s Tonyo '
                    'cache. Your password is verified before deletion starts.',
                  )
                : context.tr(
                    'This permanently deletes the Tonyo profile, tracking records, '
                    'settings, and cache on this device.',
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'This cannot be undone. Original Apple Health data, exported '
              'files, and other devices’ cached copies are not erased.',
            ),
            style: TextStyle(color: TonyoPalette.of(context).error),
          ),
          const SizedBox(height: 18),
          if (widget.cloud) ...[
            TextField(
              key: const Key('privacy-delete-password'),
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: context.tr('Current password'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            key: const Key('privacy-delete-confirmation'),
            controller: _confirmation,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: context.tr(
                "Type {value0} to confirm",
                args: {'value0': word},
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          key: const Key('privacy-confirm-deletion'),
          style: FilledButton.styleFrom(
            backgroundColor: TonyoPalette.of(context).error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: ready
              ? () {
                  if (widget.reset) {
                    Navigator.pop(context, true);
                  } else {
                    final password = widget.cloud ? _password.text : null;
                    _password.clear();
                    Navigator.pop(context, _DeletionConfirmation(password));
                  }
                }
              : null,
          child: Text(
            widget.clearDeviceOnly
                ? context.tr('Erase this device only')
                : widget.reset
                ? context.tr('Reset tracking')
                : context.tr('Delete permanently'),
          ),
        ),
      ],
    );
  }
}
