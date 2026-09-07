import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../privacy_consent.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// Account controls are explicit user actions. Merely opening this route never
/// exports, changes consent, imports Health data, or starts a deletion.
class PrivacyCenterScreen extends StatefulWidget {
  const PrivacyCenterScreen({
    super.key,
    required this.controller,
    this.requireReview = false,
  });

  final AppController controller;
  final bool requireReview;

  @override
  State<PrivacyCenterScreen> createState() => _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends State<PrivacyCenterScreen> {
  PrivacyAgeBand? _ageBand;
  PrivacyRegion? _region;
  bool _acknowledged = false;
  bool _ageLocked = false;
  bool _working = false;
  String? _error;
  String? _export;
  String? _exportOwner;
  bool _exportWasCloud = false;
  bool _copied = false;

  AppController get _controller => widget.controller;
  bool get _busy => _working || _controller.isPrivacyBusy;

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
            title: const Text('Privacy center'),
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
                    color: TonyoColors.coral,
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
                      label: const Text('Sign in to finish deletion'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('privacy-clear-device-only'),
                      onPressed: _busy
                          ? null
                          : () => _deleteData(clearDeviceOnly: true),
                      icon: const Icon(Icons.phone_iphone_rounded),
                      label: const Text('Erase only this device’s Tonyo cache'),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                if (review && !_controller.deletionPending) ...[
                  const _PrivacyNotice(
                    icon: Icons.fact_check_outlined,
                    color: TonyoColors.amber,
                    title: 'A quick review before you continue',
                    text:
                        'Your existing records stay in place. Review your age '
                        'band, region, and data use before new tracking, Health '
                        'imports, or optional learning can start.',
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
                          '${consent.ageBand.label} · ${consent.region.label}',
                          key: const Key('privacy-saved-age-region'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Acknowledged ${_date(consent.acceptedAt)} · '
                          'Policy version ${consent.policyVersion}',
                          key: const Key('privacy-consent-receipt'),
                          style: const TextStyle(color: TonyoColors.muted),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Age and region are saved with your consent record. '
                          'They cannot be changed here to bypass a protection.',
                          style: TextStyle(color: TonyoColors.muted),
                        ),
                      ],
                      if (review &&
                          !_controller.deletionPending &&
                          _controller.guardianConsentBlocker == null) ...[
                        const SizedBox(height: 10),
                        if (_ageLocked && consent == null)
                          Text(
                            'Selected age band: ${_ageBand!.label}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
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
                                ? 'Guardian setup unavailable'
                                : _busy
                                ? 'Saving…'
                                : 'Save privacy choices',
                          ),
                        ),
                      ],
                      if (_controller.guardianConsentBlocker
                          case final blocker?) ...[
                        const SizedBox(height: 14),
                        _PrivacyNotice(
                          key: const Key('privacy-guardian-required'),
                          icon: Icons.family_restroom_rounded,
                          color: TonyoColors.amber,
                          title: 'Verified guardian setup required',
                          text: blocker,
                        ),
                      ] else if (_controller.guardianConsentVerified) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Guardian authorization verified by the account service.',
                          key: Key('privacy-guardian-verified'),
                          style: TextStyle(color: TonyoColors.mint),
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
                          label: const Text('Check account status'),
                        ),
                        const Text(
                          'Checks the account service without changing your '
                          'saved choices or opting you into outcome learning.',
                          style: TextStyle(color: TonyoColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _optionalLearning(),
                const SizedBox(height: 22),
                _heading(context, 'Take your data with you'),
                const SizedBox(height: 8),
                TonyoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _controller.isCloudAuthenticated
                            ? 'Generate a fresh export of your private Tonyo account '
                                  'and this device’s available app data.'
                            : 'Generate an export of Tonyo data stored on this '
                                  'device. This does not fetch another account.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Includes sensitive wellness information. Nothing is '
                        'copied or shared until you explicitly choose to do so.',
                        style: TextStyle(color: TonyoColors.muted),
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
                              ? 'Preparing export…'
                              : 'Generate data export',
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
                          label: Text(_copied ? 'Copied' : 'Copy JSON export'),
                        ),
                        TextButton(
                          key: const Key('privacy-dismiss-export'),
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _export = null;
                                  _copied = false;
                                }),
                          child: const Text('Dismiss export from this screen'),
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
                      const Text(
                        'Reset clears tracking records while keeping your '
                        'account and profile. Deletion removes your Tonyo '
                        'account data and this device’s Tonyo cache.',
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Neither action deletes the original data in Apple '
                        'Health, files you exported, or copies cached on other '
                        'devices. Manage Apple Health access in iOS Settings.',
                        style: TextStyle(color: TonyoColors.muted),
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
                          label: const Text('Reset tracking data'),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('privacy-delete-data'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TonyoColors.coral,
                        ),
                        onPressed: _busy || needsDeletionSignIn
                            ? null
                            : _deleteData,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          _controller.deletionPending
                              ? 'Retry unfinished deletion'
                              : _controller.isCloudAuthenticated
                              ? 'Delete account and data'
                              : 'Delete local data',
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
                      color: TonyoColors.coral,
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
                    label: const Text('Return to welcome without continuing'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _dataUse() => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(context, 'A clear view of your data'),
        const SizedBox(height: 14),
        _DataUseRow(
          icon: Icons.phone_iphone_rounded,
          title: 'On this device',
          text:
              'Your entries and imported Health summaries support wellness '
              'scores and forecasts. An offline cache, preparation snapshot, '
              'and any personalized model weights stay on this device.',
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
        const _DataUseRow(
          icon: Icons.tune_rounded,
          title: 'Separate, optional controls',
          text:
              'Health access, notifications, and outcome learning are separate '
              'choices. Agreeing to this notice does not enable them. '
              'Personalized Energy training runs only when you request it.',
        ),
        const SizedBox(height: 16),
        const _DataUseRow(
          icon: Icons.favorite_border_rounded,
          title: 'Wellness estimates, not a diagnosis',
          text:
              'Tonyo can be incomplete or wrong. It does not diagnose, treat, '
              'or replace medical care. Do not rely on its scores for '
              'medical or safety-critical decisions.',
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
        const Text(
          'Link future check-ins, reaction tests, and optional Coach ratings '
          'to private outcome records. Energy personalization uses eligible '
          'records only after a separate model refresh.',
          style: TextStyle(color: TonyoColors.muted),
        ),
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            key: const Key('privacy-outcome-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow outcome learning'),
            subtitle: Text(
              _controller.outcomeConsent
                  ? 'On · turn off to stop new outcomes and remove this '
                        'device’s personalized model from use.'
                  : 'Off · not required to use ordinary wellness tracking.',
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
        const Text(
          'Turning this off does not delete previously saved outcomes. '
          'Reset tracking or delete data below to remove those records.',
          style: TextStyle(color: TonyoColors.muted),
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

  Future<void> _setOutcomeConsent(bool value) async {
    if (_busy) return;
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow optional outcome learning?'),
          scrollable: true,
          content: const Text(
            'Future Energy check-ins, reaction tests, and optional completed '
            'Coach ratings will be saved as private outcome records. '
            'Eligible outcomes can support a small on-device Energy model '
            'when you separately choose Refresh Energy model. Model weights '
            'are not uploaded. You can turn this off at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              key: const Key('privacy-confirm-outcomes'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow future outcomes'),
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
        title: const Text('Copy sensitive data?'),
        scrollable: true,
        content: const Text(
          'This export contains private wellness and account information. '
          'Your clipboard may be readable by other apps or synced to other '
          'devices. Copy only on a device you trust. Tonyo cannot erase '
          'copies after you share them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('privacy-confirm-copy'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copy to clipboard'),
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
          const SnackBar(content: Text('Tracking data cleared. Account kept.')),
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
            content: Text(_error!),
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
      Text(text, style: Theme.of(context).textTheme.titleLarge);

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
        const Text(
          'Choose your age band and region. We ask before account details '
          'so age-appropriate protections can apply. No date of birth is needed.',
          style: TextStyle(color: TonyoColors.muted),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<PrivacyAgeBand>(
          key: const Key('privacy-age-band'),
          initialValue: ageBand,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          decoration: const InputDecoration(labelText: 'Age band'),
          hint: const Text('Choose your age band'),
          items: PrivacyAgeBand.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
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
          decoration: const InputDecoration(labelText: 'Region'),
          hint: const Text('Choose your region'),
          items: PrivacyRegion.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: enabled ? onRegionChanged : null,
        ),
      ],
      if (ageBand != null && ageBand != PrivacyAgeBand.adult) ...[
        const SizedBox(height: 14),
        const _PrivacyNotice(
          key: Key('privacy-age-protection'),
          icon: Icons.family_restroom_rounded,
          color: TonyoColors.amber,
          title: 'A guardian step is needed',
          text:
              'This build requires verified guardian authorization before '
              'under-18 tracking or account setup. A checkbox is not '
              'verification. New guardian setup is not available in this '
              'build; no name, email, or health data is needed to stop here.',
        ),
      ],
      const SizedBox(height: 16),
      Text(
        cloudEnabled
            ? 'Tonyo uses your wellness entries and any Health summaries you '
                  'choose to import for scores and forecasts. Signed-in data '
                  'syncs to your private Firebase account, with an offline '
                  'cache on this device. Firebase handles passwords.'
            : 'Tonyo uses your wellness entries for scores and forecasts. '
                  'This build stores app data on this device. Passwords '
                  'are never saved by Tonyo.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Health access and outcome learning are separate opt-ins. '
        'You can export your data or request deletion in Privacy center.',
        style: TextStyle(color: TonyoColors.muted),
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
          title: const Text(
            'I have read this data-use notice and understand Tonyo provides '
            'wellness estimates, not medical advice or a diagnosis.',
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
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF252141), Color(0xFF122D2B)],
      ),
      border: Border.all(color: TonyoColors.border),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, color: TonyoColors.mint, size: 32),
        const SizedBox(height: 14),
        Text(
          'Your data. Your choices.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Know what Tonyo uses. Decide what comes next.',
          style: TextStyle(color: TonyoColors.muted, height: 1.5),
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
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(text, style: const TextStyle(height: 1.5)),
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
      Icon(icon, color: TonyoColors.mint, size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(color: TonyoColors.muted)),
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
          const Text(
            'Export ready',
            style: TextStyle(
              color: TonyoColors.mint,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text('${utf8.encode(data).length} bytes · JSON format'),
          Text(
            decoded['cloud'] == null
                ? 'Scope: this device’s Tonyo data'
                : 'Scope: your Tonyo cloud records and this device’s data',
          ),
          if (counts.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final count in counts.entries)
              Text('${count.key}: ${count.value}'),
          ],
          const SizedBox(height: 10),
          const Text(
            'Tonyo records only—not a complete Apple Health archive, Firebase '
            'password, or files from another device. Keep the export somewhere '
            'private; this preview is held only while this screen is open.',
            style: TextStyle(color: TonyoColors.muted),
          ),
          if (decoded['cloud'] != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Cloud collections are read in sequence, not as one atomic '
              'snapshot. Nested subcollections are not included. Local and '
              'cloud counts may overlap or differ while syncing.',
              style: TextStyle(color: TonyoColors.amber),
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
            ? 'Erase only this device?'
            : widget.reset
            ? 'Reset tracking data?'
            : widget.retry
            ? 'Retry account deletion?'
            : widget.cloud
            ? 'Delete account and data?'
            : 'Delete local data?',
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.clearDeviceOnly
                ? 'This erases only this device’s Tonyo cache. It does not '
                      'confirm deletion of the cloud account or any remaining '
                      'cloud data. Sign in again to finish cloud deletion.'
                : widget.reset
                ? 'This permanently clears tracking signals, check-ins, outcomes, '
                      'scores, guidance, and the personalized model. Your account '
                      'and profile stay. Connected Apple Health can import '
                      'records again; disconnect it first if you want to stop imports.'
                : widget.cloud
                ? 'This permanently deletes your Tonyo data in Firestore, '
                      'your Firebase sign-in account, and this device’s Tonyo '
                      'cache. Your password is verified before deletion starts.'
                : 'This permanently deletes the Tonyo profile, tracking records, '
                      'settings, and cache on this device.',
          ),
          const SizedBox(height: 12),
          const Text(
            'This cannot be undone. Original Apple Health data, exported '
            'files, and other devices’ cached copies are not erased.',
            style: TextStyle(color: TonyoColors.coral),
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
              decoration: const InputDecoration(labelText: 'Current password'),
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
            decoration: InputDecoration(labelText: 'Type $word to confirm'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('privacy-confirm-deletion'),
          style: FilledButton.styleFrom(backgroundColor: TonyoColors.coral),
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
                ? 'Erase this device only'
                : widget.reset
                ? 'Reset tracking'
                : 'Delete permanently',
          ),
        ),
      ],
    );
  }
}
