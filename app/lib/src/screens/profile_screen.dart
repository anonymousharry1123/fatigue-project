import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../app.dart';
import '../app_controller.dart';
import '../device_backup_service.dart';
import '../health_service.dart';
import '../models.dart';
import '../language_preference.dart';
import '../widgets/language_picker.dart';
import '../notification_logic.dart';
import '../screen_time_service.dart';
import '../schedule_logic.dart';
import '../sleep_sync_logic.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/heart_data_details.dart';
import 'account_sign_in_dialog.dart';
import 'appearance_screen.dart';
import 'change_password_dialog.dart';
import 'admin/admin_cohort_screen.dart';
import 'device_backup_flow.dart';
import 'backup_restore_screen.dart';
import 'sync_conflict_screen.dart';
import 'ml_prep_screen.dart';
import 'model_transparency_screen.dart';
import 'privacy_center_screen.dart';
import 'research_export_screen.dart';
import 'questionnaire_library_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.backupService = const DeviceBackupService(),
  });

  final DeviceBackupService backupService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isSigningOut = false;
  bool _isSavingDeviceBackup = false;
  bool _isRestoringDeviceBackup = false;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final profile = controller.profile;
    final backupAvailable =
        !_isSigningOut &&
        !_isSavingDeviceBackup &&
        !_isRestoringDeviceBackup &&
        controller.canExportDeviceBackup;
    final syncNeedsAttention =
        controller.hasPendingCloudChanges ||
        controller.hasPendingOutcomeChanges ||
        controller.hasPendingCoachChanges ||
        controller.cloudSyncConflict ||
        controller.cloudSyncError != null ||
        controller.outcomeError != null;
    return SafeArea(
      bottom: false,
      child: ListView(
        key: const PageStorageKey('profile-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: TonyoPalette.of(
                  context,
                ).primary.withValues(alpha: .22),
                child: Text(
                  profile.name.trim().isEmpty
                      ? 'T'
                      : profile.name.trim().characters.first.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      context.tr(
                        "{value0} · {value1}",
                        args: {
                          'value0': context.tr(profile.role),
                          'value1': context.tr(profile.ageRange),
                        },
                      ),
                      style: TextStyle(
                        color: TonyoPalette.of(context).muted,
                        fontSize: 11,
                      ),
                    ),
                    if (controller.accountEmail != null)
                      Text(
                        controller.accountEmail!,
                        style: TextStyle(
                          color: TonyoPalette.of(context).muted,
                          fontSize: 10,
                        ),
                      ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (syncNeedsAttention
                                    ? TonyoPalette.of(context).warning
                                    : TonyoPalette.of(context).success)
                                .withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        context.tr(controller.cloudBackupLabel),
                        key: const Key('profile-backup-status'),
                        style: TextStyle(
                          color: syncNeedsAttention
                              ? TonyoPalette.of(context).warning
                              : TonyoPalette.of(context).success,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('Edit profile'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => _editProfile(context, controller),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          if (!controller.isSignedOut &&
              (controller.onboardingComplete ||
                  controller.isCloudAuthenticated)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('profile-sign-out-button'),
              onPressed:
                  _isSigningOut ||
                      _isSavingDeviceBackup ||
                      _isRestoringDeviceBackup
                  ? null
                  : () => _signOut(context, controller),
              icon: _isSigningOut
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
              label: Text(
                _isSigningOut
                    ? context.tr('Signing out…')
                    : context.tr('Sign out'),
              ),
            ),
          ],
          if (controller.isCloudAuthenticated && !controller.isSignedOut) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('profile-change-password-button'),
              onPressed:
                  _isSigningOut ||
                      _isSavingDeviceBackup ||
                      _isRestoringDeviceBackup
                  ? null
                  : () => _changePassword(context, controller),
              icon: const Icon(Icons.lock_reset_rounded),
              label: Text(context.tr('Change password')),
            ),
          ],
          if (controller.isCloudAuthenticated) ...[
            const SizedBox(height: 14),
            TonyoCard(
              key: const Key('cloud-sync-status'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('Cloud backup'),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(controller.cloudBackupLabel),
                    key: const Key('cloud-backup-label'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    context.tr(
                      'Health imports and cloud backup are separate. A pending backup does not mean your entry failed to save.',
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(context.tr(controller.cloudSyncStatusMessage)),
                  ),
                  Text(
                    context.tr(
                      "{value0} pending changes",
                      args: {'value0': controller.pendingCloudRecordCount},
                    ),
                    key: const Key('cloud-sync-pending-count'),
                    style: TextStyle(color: TonyoPalette.of(context).muted),
                  ),
                  Text(
                    controller.lastCloudSyncAt == null
                        ? context.tr(
                            'No completed upload recorded on this device yet.',
                          )
                        : context.tr(
                            "Last upload: {value0}",
                            args: {
                              'value0': _cloudSyncTime(
                                controller.lastCloudSyncAt!,
                              ),
                            },
                          ),
                    key: const Key('cloud-sync-last-success'),
                    style: TextStyle(color: TonyoPalette.of(context).muted),
                  ),
                ],
              ),
            ),
          ],
          if (controller.isCloudAuthenticated && syncNeedsAttention) ...[
            const SizedBox(height: 14),
            _CloudSyncRecoveryCard(
              controller: controller,
              savingBackup: _isSavingDeviceBackup,
              onSaveBackup: backupAvailable
                  ? () => _saveDeviceBackup(controller)
                  : null,
            ),
          ],
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >=
                      280 * MediaQuery.textScalerOf(context).scale(1)
                  ? 3
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              final stats = [
                _ProfileStat(
                  controller.score.canEstimateEnergy
                      ? '${controller.score.energy}'
                      : '—',
                  'Experimental energy',
                  TonyoPalette.of(context).secondary,
                ),
                _ProfileStat(
                  '${_latestSleep(controller)}h',
                  'Last main sleep',
                  TonyoPalette.of(context).primary,
                ),
                _ProfileStat(
                  '${(controller.score.confidence * 100).round()}%',
                  'Data coverage',
                  TonyoPalette.of(context).secondary,
                ),
              ];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final stat in stats) SizedBox(width: width, child: stat),
                ],
              );
            },
          ),
          SectionHeader(context.tr('Connected data sources')),
          _SourceCard(
            key: const Key('health-source-card'),
            icon: Icons.health_and_safety_rounded,
            color: TonyoPalette.of(context).primary,
            title: 'Apple Health',
            detail: _healthSourceDetail(controller),
            status: _healthSourceStatus(controller),
            onTap: () => _healthPermissions(context),
          ),
          const SizedBox(height: 9),
          _SourceCard(
            key: const Key('screen-time-source-card'),
            icon: Icons.smartphone_rounded,
            color: TonyoPalette.of(context).secondary,
            title: 'Screen Time',
            detail: _screenTimeSourceDetail(controller),
            status: _screenTimeSourceStatus(controller),
            onTap: () => _screenTimeReport(context),
          ),
          const SizedBox(height: 9),
          _SourceCard(
            icon: Icons.storage_rounded,
            color: TonyoPalette.of(context).secondary,
            title: controller.isCloudAuthenticated
                ? 'Firebase Cloud Firestore'
                : 'Local app storage',
            detail: controller.isCloudAuthenticated
                ? controller.isCloudSyncing
                      ? 'Syncing private account data'
                      : controller.cloudSyncConflict
                      ? 'Saved on this device · review sync above'
                      : syncNeedsAttention
                      ? 'Saved on this device · sync pending'
                      : controller.cloudSyncError == null
                      ? 'Offline cache enabled'
                      : 'Offline cache active · sync will retry'
                : controller.cloudEnabled
                ? 'Sign in to migrate local data'
                : 'Offline demo mode',
            status: controller.isCloudAuthenticated ? 'On' : 'Local',
          ),
          SectionHeader(context.tr('Settings')),
          _SettingTile(
            key: const Key('language-preference-setting'),
            icon: Icons.language_rounded,
            title: 'Language',
            subtitle: languageDisplayName(controller.effectiveLanguage),
            onTap: () => showLanguagePreferenceDialog(context, controller),
          ),
          _SettingTile(
            key: const Key('sleep-schedule-setting'),
            icon: Icons.bedtime_outlined,
            title: 'Wake and bed schedule',
            subtitle: context.tr(
              "{value0} wake · {value1} bed",
              args: {
                'value0': _scheduleClock(profile.wakeHour),
                'value1': _scheduleClock(profile.bedHour),
              },
            ),
            onTap: () => _editSchedule(context, controller),
          ),
          _SettingTile(
            key: const Key('appearance-setting'),
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Light, dark, colors, and fonts',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppearanceScreen()),
            ),
          ),
          if (!controller.isSignedOut)
            ListTile(
              key: const Key('device-backup-setting'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              leading: Icon(
                Icons.save_alt_rounded,
                color: TonyoPalette.of(context).muted,
              ),
              title: Text(
                _isSavingDeviceBackup
                    ? context.tr('Saving backup…')
                    : context.tr('Save device backup'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                context.tr(
                  'Save the data on this device, including unsynced changes, as JSON. Works offline.',
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              enabled: backupAvailable,
              onTap: backupAvailable
                  ? () => _saveDeviceBackup(controller)
                  : null,
            ),
          if (controller.cloudEnabled && !controller.isCloudAuthenticated)
            _SettingTile(
              icon: Icons.cloud_outlined,
              title: 'Cloud account',
              subtitle: 'Sign in and migrate this device’s data',
              onTap: () => _signIn(context, controller),
            ),
          if (!controller.isSignedOut)
            ListTile(
              key: const Key('device-restore-setting'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
              leading: Icon(
                Icons.restore_rounded,
                color: TonyoPalette.of(context).muted,
              ),
              title: Text(
                context.tr('Restore from backup'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                context.tr('Preview saved records and choose what to restore.'),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              enabled:
                  !_isRestoringDeviceBackup &&
                  !_isSavingDeviceBackup &&
                  !_isSigningOut &&
                  controller.canRestoreDeviceBackup,
              onTap:
                  !_isRestoringDeviceBackup &&
                      !_isSavingDeviceBackup &&
                      !_isSigningOut &&
                      controller.canRestoreDeviceBackup
                  ? () => _restoreDeviceBackup(controller)
                  : null,
            ),
          _SettingTile(
            icon: Icons.track_changes_rounded,
            title: 'Goals & schedule',
            subtitle: context.tr(
              "{value0} · {value1}",
              args: {
                'value0': context.tr(profile.goal),
                'value1': context.tr(profile.coachPriority.label),
              },
            ),
            onTap: () => _editProfile(context, controller),
          ),
          ListTile(
            key: const Key('automatic-timezone'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 2),
            leading: Icon(
              Icons.public_rounded,
              color: TonyoPalette.of(context).muted,
            ),
            title: Text(
              context.tr('Automatic time zone'),
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              context.tr(
                "{value0} · Follows your device for daily records and reminders.",
                args: {'value0': controller.deviceTimezoneLabel},
              ),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 10,
              ),
            ),
            trailing: Icon(
              Icons.check_rounded,
              color: TonyoPalette.of(context).success,
            ),
          ),
          _SettingTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: _notificationSubtitle(controller),
            onTap: () => _notifications(context),
          ),
          _SettingTile(
            key: const Key('model-transparency-setting'),
            icon: Icons.insights_rounded,
            title: 'How your scores work',
            subtitle: 'Evidence, data quality & the model on this device',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ModelTransparencyScreen(controller: controller),
              ),
            ),
          ),
          _SettingTile(
            key: const Key('outcome-learning-setting'),
            icon: Icons.fact_check_outlined,
            title: 'Outcome learning',
            subtitle: controller.outcomeConsent
                ? 'On · ${controller.outcomes.length} private outcome ${controller.outcomes.length == 1 ? 'record' : 'records'}'
                : 'Off · no training records are created',
            onTap: () => _outcomeLearning(context),
          ),
          _SettingTile(
            key: const Key('model-preparation-setting'),
            icon: Icons.dataset_outlined,
            title: 'Model preparation',
            subtitle: 'Inspect 30 days · refresh Energy model separately',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MlPrepScreen(controller: controller),
              ),
            ),
          ),
          _SettingTile(
            key: const Key('privacy-center-setting'),
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy center',
            subtitle: 'Data choices, youth protections, export & deletion',
            onTap: () => _privacy(context, controller),
          ),
          _SettingTile(
            key: const Key('research-export-setting'),
            icon: Icons.table_view_outlined,
            title: 'Research export',
            subtitle: 'Private response table and data dictionary',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ResearchExportScreen(
                  controller: controller,
                  service: widget.backupService,
                ),
              ),
            ),
          ),
          _SettingTile(
            key: const Key('questionnaire-library-setting'),
            icon: Icons.assignment_outlined,
            title: 'Questionnaire library',
            subtitle: 'Instrument availability and review requirements',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QuestionnaireLibraryScreen(),
              ),
            ),
          ),
          _SettingTile(
            icon: Icons.help_outline_rounded,
            title: 'Help & support',
            subtitle: 'Tonyo is a wellness tool',
            onTap: () => _preview(
              context,
              'Tonyo provides wellness estimates, not medical advice.',
            ),
          ),
          SectionHeader(context.tr('Developer')),
          _SettingTile(
            icon: Icons.science_outlined,
            title: 'Cohort Lab',
            subtitle: 'Synthetic students · score debug dashboard',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AdminCohortScreen(controller: controller),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _latestSleep(AppController controller) {
    final matches = SleepSyncLogic.preferredSleepReadings(controller.signals);
    return matches.isEmpty ? '—' : matches.first.value.toStringAsFixed(1);
  }

  static String _cloudSyncTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _restoreDeviceBackup(AppController controller) async {
    if (_isRestoringDeviceBackup || !controller.canRestoreDeviceBackup) return;
    setState(() => _isRestoringDeviceBackup = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BackupRestoreScreen(
            controller: controller,
            service: widget.backupService,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRestoringDeviceBackup = false);
    }
  }

  static String _notificationSubtitle(AppController controller) {
    if (!controller.notificationSchedulingSupported) {
      return 'Unavailable on this platform';
    }
    if (!controller.notificationsEnabled) return 'Off · explicit opt-in';
    if (controller.isNotificationSyncing) return 'Updating schedule…';
    if (controller.notificationError != null) {
      return controller.notificationError!;
    }
    final count = controller.scheduledNotificationCount;
    return count == 0
        ? 'On · no upcoming reminders'
        : 'On · $count ${count == 1 ? 'notification' : 'notifications'} scheduled';
  }

  static String _healthSourceDetail(AppController controller) {
    if (!controller.healthAvailable) {
      return 'Unavailable here · manual logs stay available';
    }
    if (controller.healthError != null) {
      return 'Permission status needs attention';
    }
    if (controller.isSyncing) return 'Syncing health data…';
    if (controller.healthSyncError != null ||
        controller.sleepSyncError != null ||
        controller.activitySyncError != null) {
      return 'Health sync needs attention';
    }
    return switch (controller.healthAuthorization) {
      HealthAuthorizationState.authorized when controller.healthAuthorized =>
        controller.lastSync == null
            ? 'Read-only access · health sync ready'
            : '${controller.healthKitHeartSignalCount} heart · ${controller.healthKitSleepNightCount} sleep nights · ${controller.healthKitWorkoutSignalCount + controller.healthKitHydrationSignalCount + controller.healthKitStepSignalCount} activity signals',
      HealthAuthorizationState.authorized =>
        'Permission choices saved · connect to sync',
      HealthAuthorizationState.revoked =>
        'Connection stopped · saved entries remain',
      HealthAuthorizationState.denied => 'Permission request not completed',
      HealthAuthorizationState.error => 'Permission status needs attention',
      _ => 'Review four read-only permissions',
    };
  }

  static String _healthSourceStatus(AppController controller) {
    if (!controller.healthAvailable) return 'Unavailable';
    if (controller.healthError != null) return 'Check';
    if (controller.isSyncing) return 'Syncing';
    if (controller.healthSyncError != null ||
        controller.sleepSyncError != null ||
        controller.activitySyncError != null) {
      return 'Check';
    }
    return switch (controller.healthAuthorization) {
      HealthAuthorizationState.authorized when controller.healthAuthorized =>
        'On',
      HealthAuthorizationState.denied ||
      HealthAuthorizationState.revoked => 'Off',
      HealthAuthorizationState.error => 'Check',
      _ => 'Set up',
    };
  }

  static String _screenTimeSourceDetail(AppController controller) =>
      controller.screenTimeAutoSyncEnabled
      ? (controller.screenTimeSyncError != null
            ? 'Automatic sync needs attention · manual entry available'
            : 'Apple daily totals · automatic sync on')
      : switch (controller.screenTimeAuthorization) {
          ScreenTimeAuthorizationState.authorized =>
            'Private daily-total report · manual model input',
          ScreenTimeAuthorizationState.notDetermined =>
            'Optional private report · manual logging active',
          ScreenTimeAuthorizationState.denied =>
            'Report off · manual logging active',
          ScreenTimeAuthorizationState.entitlementRequired =>
            'Awaiting Apple entitlement · manual logging active',
          ScreenTimeAuthorizationState.error =>
            'Report needs attention · manual logging active',
          ScreenTimeAuthorizationState.unavailable =>
            'Unavailable here · manual logging active',
        };

  static String _screenTimeSourceStatus(AppController controller) =>
      controller.screenTimeAutoSyncEnabled
      ? (controller.screenTimeSyncError != null ? 'Check' : 'Auto')
      : switch (controller.screenTimeAuthorization) {
          ScreenTimeAuthorizationState.authorized => 'View',
          ScreenTimeAuthorizationState.notDetermined => 'Set up',
          ScreenTimeAuthorizationState.error => 'Check',
          _ => 'Manual',
        };

  static void _healthPermissions(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TonyoPalette.of(context).surface,
        builder: (_) => const _HealthPermissionSheet(),
      );

  static void _screenTimeReport(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TonyoPalette.of(context).surface,
        builder: (_) => const _ScreenTimeReportSheet(),
      );

  static void _notifications(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TonyoPalette.of(context).surface,
        builder: (_) => const _NotificationSheet(),
      );

  static String _scheduleClock(double hour) {
    if (!hour.isFinite || hour < 0 || hour >= 24) return 'Not set';
    final minutes = (hour * 60).round() % (24 * 60);
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  }

  static double? _parseScheduleClock(String text) {
    final parts = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (parts == null) return null;
    final hours = int.parse(parts.group(1)!);
    final minutes = int.parse(parts.group(2)!);
    if (hours > 23 || minutes > 59) return null;
    return hours + minutes / 60;
  }

  static Future<void> _editSchedule(
    BuildContext context,
    AppController controller,
  ) async {
    final previous = controller.profile;
    var wakeText = _scheduleClock(previous.wakeHour);
    var bedText = _scheduleClock(previous.bedHour);
    String? error;
    final updated = await showDialog<UserProfile>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(context.tr('Wake and bed schedule')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    'Use local 24-hour times. Suggested blocks stay within your waking window. This is your chosen sleep opportunity, not a sleep recommendation or measured sleep.',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('schedule-wake-field'),
                  initialValue: wakeText,
                  onChanged: (value) => wakeText = value,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: context.tr('Wake time (HH:mm)'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('schedule-bed-field'),
                  initialValue: bedText,
                  onChanged: (value) => bedText = value,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: context.tr('Bed time (HH:mm)'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.tr(error!),
                    key: const Key('schedule-validation-error'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              key: const Key('schedule-save'),
              onPressed: () {
                final wakeHour = _parseScheduleClock(wakeText);
                final bedHour = _parseScheduleClock(bedText);
                if (wakeHour == null || bedHour == null) {
                  setState(
                    () => error = 'Enter valid times from 00:00 to 23:59.',
                  );
                  return;
                }
                final proposed = previous.copyWith(
                  wakeHour: wakeHour,
                  bedHour: bedHour,
                );
                final problem = ScheduleLogic.validationError(
                  previous,
                  proposed,
                );
                if (problem != null) {
                  setState(() => error = problem);
                  return;
                }
                Navigator.pop(dialogContext, proposed);
              },
              child: Text(context.tr('Save schedule')),
            ),
          ],
        ),
      ),
    );
    if (updated == null) return;
    try {
      await controller.updateProfile(updated);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Could not save the schedule. Please try again.'),
            ),
          ),
        );
      }
    }
  }

  static Future<void> _editProfile(
    BuildContext context,
    AppController controller,
  ) async {
    final name = TextEditingController(text: controller.profile.name);
    var role = controller.profile.role;
    var goal = controller.profile.goal;
    var coachPriority = controller.profile.coachPriority;
    final updated = await showDialog<UserProfile>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.tr('Edit profile')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: context.tr('First name'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: context.tr('Role')),
                  items: ['Student', 'Athlete', 'Student athlete']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(context.tr(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => role = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: goal,
                  decoration: InputDecoration(labelText: context.tr('Goal')),
                  items:
                      [
                            'Improve focus',
                            'Improve recovery',
                            'Balance focus and training',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(context.tr(value)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() => goal = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CoachPriority>(
                  key: const Key('coach-priority-field'),
                  initialValue: coachPriority,
                  decoration: InputDecoration(
                    labelText: context.tr('AI Coach priority'),
                  ),
                  items: CoachPriority.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(context.tr(value.label)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => coachPriority = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                controller.profile.copyWith(
                  name: name.text.trim().isEmpty
                      ? controller.profile.name
                      : name.text.trim(),
                  role: role,
                  goal: goal,
                  coachPriority: coachPriority,
                ),
              ),
              child: Text(context.tr('Save')),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (updated != null) await controller.updateProfile(updated);
  }

  static void _preview(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Version 0.5 preview')),
          content: Text(context.tr(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Close')),
            ),
          ],
        ),
      );

  static Future<void> _signIn(BuildContext context, AppController controller) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AccountSignInDialog(controller: controller),
      );

  static Future<void> _changePassword(
    BuildContext context,
    AppController controller,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangePasswordDialog(controller: controller),
    );
    if (changed != true || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr('Password updated.'))));
  }

  Future<void> _saveDeviceBackup(AppController controller) async {
    if (_isSavingDeviceBackup ||
        _isSigningOut ||
        !controller.canExportDeviceBackup) {
      return;
    }
    setState(() => _isSavingDeviceBackup = true);
    try {
      await saveDeviceBackup(context, controller, widget.backupService);
    } finally {
      if (mounted) setState(() => _isSavingDeviceBackup = false);
    }
  }

  Future<void> _signOut(BuildContext context, AppController controller) async {
    if (_isSigningOut ||
        _isSavingDeviceBackup ||
        controller.isSignedOut ||
        !(controller.onboardingComplete || controller.isCloudAuthenticated)) {
      return;
    }
    setState(() => _isSigningOut = true);
    try {
      await controller.signOut();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Signed out. Your saved data is kept on this device.'),
            ),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('Could not sign out. Please try again.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  static void _privacy(BuildContext context, AppController controller) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivacyCenterScreen(controller: controller),
      ),
    );
  }

  static void _outcomeLearning(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TonyoPalette.of(context).surface,
        builder: (_) => const _OutcomeLearningSheet(),
      );
}

class _OutcomeLearningSheet extends StatelessWidget {
  const _OutcomeLearningSheet();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Outcome learning'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              context.tr(
                'Optional outcome records can support an on-device Energy model. Training starts only when you separately choose Refresh Energy model.',
              ),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            const _ScreenTimePrivacyRow(
              icon: Icons.bolt_rounded,
              title: 'Observed energy',
              detail:
                  'Future check-in energy and optional ratings after completed Coach blocks become linked private outcomes.',
            ),
            const _ScreenTimePrivacyRow(
              icon: Icons.timer_outlined,
              title: 'Cognitive outcomes',
              detail:
                  'Future reaction-test results remain signals and are linked as cognitive outcome records.',
            ),
            const _ScreenTimePrivacyRow(
              icon: Icons.lock_outline_rounded,
              title: 'Explicit and owner-only',
              detail:
                  'Firestore rejects new outcome records unless both consent flags are on. Other users cannot read your records.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('outcome-consent-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.tr('Allow private outcome records'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                context.tr(
                  'Applies only to future check-ins, reaction tests, and optional Coach ratings.',
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              value: controller.outcomeConsent,
              onChanged:
                  controller.isOutcomeLoading ||
                      controller.isPrivacyBusy ||
                      (!controller.privacyFeaturesAllowed &&
                          !controller.outcomeConsent)
                  ? null
                  : (value) => _setConsent(context, controller, value),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    (controller.outcomeConsent
                            ? TonyoPalette.of(context).success
                            : TonyoPalette.of(context).secondary)
                        .withValues(alpha: .09),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                controller.outcomeConsent
                    ? context.tr(
                        "{value0} energy · {value1} cognitive outcomes active",
                        args: {
                          'value0': controller.observedEnergyOutcomeCount,
                          'value1': controller.cognitiveOutcomeCount,
                        },
                      )
                    : context.tr(
                        'Outcome use is off. Previously saved cloud outcomes are excluded; reset or account deletion removes them.',
                      ),
                key: const Key('outcome-consent-status'),
                style: const TextStyle(fontSize: 11),
              ),
            ),
            if (controller.outcomeError case final error?) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(error),
                style: TextStyle(
                  color: TonyoPalette.of(context).error,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Future<void> _setConsent(
    BuildContext context,
    AppController controller,
    bool value,
  ) async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Allow outcome learning?')),
          content: Text(
            context.tr(
              'Tonyo will create private training-eligible records from future energy check-ins, reaction tests, and optional completed-plan ratings. They stay under your user ID. Training is a separate action in Model preparation; this switch does not start training.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('Not now')),
            ),
            FilledButton(
              key: const Key('confirm-outcome-consent'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr('Allow future records')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await controller.setOutcomeConsent(value);
  }
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet();

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  String? _error;

  Future<void> _update(
    BuildContext context,
    Future<void> Function() save,
  ) async {
    setState(() => _error = null);
    try {
      await save();
    } on Object {
      if (!mounted) return;
      setState(
        () =>
            _error = 'Could not save notification settings. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Notifications'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Choose optional daily plan reminders. Open Tonyo each day to refresh them. Experimental forecasts are uncalibrated, so precise lower-energy and recovery alerts are disabled.',
              ),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TonyoPalette.of(context).primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.health_and_safety_outlined,
                    color: TonyoPalette.of(context).primary,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr(
                        'Wellness guidance only. Notification text never presents a diagnosis.',
                      ),
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              key: const Key('notification-master-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Allow notifications')),
              subtitle: Text(
                controller.notificationSchedulingSupported
                    ? context.tr(
                        'Permission is requested only when you turn this on.',
                      )
                    : context.tr(
                        'Scheduled notifications are not supported on this platform.',
                      ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              value: controller.notificationsEnabled,
              onChanged:
                  !controller.notificationSchedulingSupported ||
                      controller.isNotificationSyncing
                  ? null
                  : (value) => _update(context, () async {
                      await controller.setNotifications(value);
                    }),
            ),
            const Divider(),
            SwitchListTile(
              key: const Key('notification-coach-plan-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Daily plan reminders')),
              subtitle: Text(
                context.tr(
                  'A notification when each upcoming AI Coach block starts.',
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              value: controller.coachPlanNotificationsEnabled,
              onChanged:
                  controller.notificationSchedulingSupported &&
                      !controller.isNotificationSyncing
                  ? (value) => _update(
                      context,
                      () => controller.setCoachPlanNotifications(value),
                    )
                  : null,
            ),
            SwitchListTile(
              key: const Key('notification-study-log-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Study log reminders')),
              subtitle: Text(
                context.tr(
                  'Optional reminders at 18:00 for main sleep and 19:00 for Evening Energy, for the next 14 days. Save either at any time; reminders are skipped once that day’s entry is saved.',
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              value: controller.studyLogNotificationsEnabled,
              onChanged:
                  controller.notificationSchedulingSupported &&
                      !controller.isNotificationSyncing
                  ? (value) => _update(
                      context,
                      () => controller.setStudyLogNotifications(value),
                    )
                  : null,
            ),
            SwitchListTile(
              key: const Key('notification-crash-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Lower-energy heads-up')),
              subtitle: Text(
                context.tr(
                  'Unavailable: forecast timing has not been prospectively validated.',
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              value: false,
              onChanged: null,
            ),
            SwitchListTile(
              key: const Key('notification-recovery-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Recovery-window reminder')),
              subtitle: Text(
                context.tr(
                  'Unavailable: forecast timing has not been prospectively validated.',
                ),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
              value: false,
              onChanged: null,
            ),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  context.tr(_error!),
                  key: const Key('notification-settings-error'),
                  style: TextStyle(color: TonyoPalette.of(context).error),
                ),
              ),
              const SizedBox(height: 8),
            ],
            _NotificationStatus(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _ScreenTimeReportSheet extends StatelessWidget {
  const _ScreenTimeReportSheet();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final state = controller.screenTimeAuthorization;
    final canAuthorize = state == ScreenTimeAuthorizationState.notDetermined;
    final canView = state == ScreenTimeAuthorizationState.authorized;
    final syncAvailability = controller.screenTimeSyncAvailability;
    final autoSync = controller.screenTimeAutoSyncEnabled;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Screen Time'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Log hours manually, or connect Apple Screen Time to import daily totals automatically where available.',
              ),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              key: const Key('screen-time-auto-sync-toggle'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Auto-sync with Apple')),
              subtitle: Text(
                context.tr(
                  'Sync this device’s last 7 days when Tonyo opens and every 15 minutes while open. Daily totals are saved with your activity data and used in your scores.',
                ),
              ),
              value: autoSync,
              onChanged:
                  controller.isScreenTimeSyncAuthorizing ||
                      (!autoSync && !syncAvailability.canRequest)
                  ? null
                  : controller.setScreenTimeAutoSync,
            ),
            Text(
              context.tr(
                controller.isScreenTimeSyncAuthorizing
                    ? 'Requesting Apple data access…'
                    : syncAvailability.message,
              ),
              key: const Key('screen-time-auto-sync-status'),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'Requires iOS 26.4+ and an eligible EU device and Apple Account. Apple allows only one app at a time to hold this data access.',
              ),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 11,
              ),
            ),
            if (autoSync && controller.lastScreenTimeSync != null) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Last synced: {value0}',
                  args: {
                    'value0':
                        '${MaterialLocalizations.of(context).formatShortDate(controller.lastScreenTimeSync!)} ${TimeOfDay.fromDateTime(controller.lastScreenTimeSync!).format(context)}',
                  },
                ),
              ),
            ],
            if (controller.screenTimeSyncError != null) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(controller.screenTimeSyncError!),
                style: TextStyle(color: TonyoPalette.of(context).error),
              ),
            ],
            if (autoSync) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('screen-time-sync-now'),
                onPressed:
                    controller.isScreenTimeSyncing ||
                        controller.isScreenTimeSyncAuthorizing
                    ? null
                    : () =>
                          syncAvailability ==
                              ScreenTimeSyncAvailability.authorized
                          ? controller.syncScreenTimeIfDue(force: true)
                          : controller.setScreenTimeAutoSync(true),
                icon: const Icon(Icons.sync_rounded),
                label: Text(
                  context.tr(
                    controller.isScreenTimeSyncing
                        ? 'Syncing…'
                        : syncAvailability ==
                              ScreenTimeSyncAvailability.authorized
                        ? 'Sync now'
                        : 'Reconnect Apple Screen Time',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const _ScreenTimePrivacyRow(
              icon: Icons.edit_note_rounded,
              title: 'Manual input stays in control',
              detail:
                  'Hours you enter in Activity log override imported Apple totals for the same day. Turning off auto-sync stops new imports and keeps saved entries.',
            ),
            const _ScreenTimePrivacyRow(
              icon: Icons.lock_outline_rounded,
              title: 'Protected details stay with Apple',
              detail:
                  'Tonyo imports only daily totals, never app names, websites, categories, pickups, or notifications.',
            ),
            const _ScreenTimePrivacyRow(
              icon: Icons.cloud_off_outlined,
              title: 'No protected report data in Firebase',
              detail:
                  'The optional private report below is view-only and exports no data. Auto-sync separately saves daily totals using your existing data and cloud-sync choices.',
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('Private Screen Time report'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: TonyoPalette.of(context).secondary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(_screenTimeReportStatus(state)),
                    key: const Key('screen-time-report-status'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.tr(_screenTimeReportMessage(state)),
                    style: TextStyle(
                      color: TonyoPalette.of(context).muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      "{value0} manual screen-time {value1} saved",
                      args: {
                        'value0': controller.manualScreenTimeSignalCount,
                        'value1': controller.manualScreenTimeSignalCount == 1
                            ? 'signal'
                            : 'signals',
                      },
                    ),
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            if (controller.screenTimeError != null) ...[
              const SizedBox(height: 10),
              Text(
                context.tr(controller.screenTimeError!),
                style: TextStyle(
                  color: TonyoPalette.of(context).error,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('screen-time-report-button'),
                onPressed:
                    controller.isScreenTimeAuthorizing ||
                        (!canAuthorize && !canView)
                    ? null
                    : () async {
                        if (canAuthorize) {
                          final authorization = await controller
                              .authorizeScreenTimeReport();
                          if (authorization !=
                              ScreenTimeAuthorizationState.authorized) {
                            return;
                          }
                        }
                        await controller.showScreenTimeReport();
                      },
                icon: controller.isScreenTimeAuthorizing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        canView
                            ? Icons.bar_chart_rounded
                            : Icons.privacy_tip_outlined,
                      ),
                label: Text(
                  controller.isScreenTimeAuthorizing
                      ? context.tr('Requesting permission…')
                      : canView
                      ? context.tr('View today’s private report')
                      : canAuthorize
                      ? context.tr('Allow private report')
                      : context.tr('Private report unavailable'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _screenTimeReportStatus(ScreenTimeAuthorizationState state) =>
      switch (state) {
        ScreenTimeAuthorizationState.authorized => 'Private report ready',
        ScreenTimeAuthorizationState.notDetermined => 'Optional permission',
        ScreenTimeAuthorizationState.denied => 'Private report is off',
        ScreenTimeAuthorizationState.entitlementRequired =>
          'Apple entitlement pending',
        ScreenTimeAuthorizationState.error => 'Report status needs attention',
        ScreenTimeAuthorizationState.unavailable =>
          'Report unavailable on this platform',
      };

  static String _screenTimeReportMessage(
    ScreenTimeAuthorizationState state,
  ) => switch (state) {
    ScreenTimeAuthorizationState.authorized =>
      'Apple can render today’s aggregate inside its protected report sandbox.',
    ScreenTimeAuthorizationState.notDetermined =>
      'Permission is optional and does not replace manual screen-time logging.',
    ScreenTimeAuthorizationState.denied =>
      'Tonyo continues using only the manual hours you choose to enter.',
    ScreenTimeAuthorizationState.entitlementRequired =>
      'This report activates only after Apple approves Family Controls access for this app.',
    ScreenTimeAuthorizationState.error =>
      'Manual screen-time logging remains available while the report is unavailable.',
    ScreenTimeAuthorizationState.unavailable =>
      'Device Activity reports require a supported iPhone or iPad.',
  };
}

class _ScreenTimePrivacyRow extends StatelessWidget {
  const _ScreenTimePrivacyRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: TonyoPalette.of(context).secondary, size: 21),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(title),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                context.tr(detail),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HealthPermissionSheet extends StatelessWidget {
  const _HealthPermissionSheet();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Apple Health permissions'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Tonyo requests read access only. It never writes to Apple Health, and you choose each category in Apple’s permission sheet.',
              ),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'After you allow read access, available Health data syncs automatically. Manual logging stays available.',
              ),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            for (final permission in healthPermissions)
              _HealthPermissionRow(permission: permission),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TonyoPalette.of(context).secondary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    color: TonyoPalette.of(context).secondary,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr(
                        'For privacy, Apple does not tell apps which read categories you approved, denied, or later revoked. Your choices remain manageable in Settings.',
                      ),
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TonyoPalette.of(context).secondary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.edit_note_rounded,
                    color: TonyoPalette.of(context).secondary,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr(
                        'Manual sleep and activity logging stays available. Tonyo uses recent sleep, reaction time, HRV, and resting heart rate to build private personal baselines. New physiology inputs affect estimates only after enough of your own history exists.',
                      ),
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _HealthPermissionStatus(controller: controller),
            if (controller.healthAuthorized) ...[
              const SizedBox(height: 10),
              _ContinuousSyncStatus(controller: controller),
              const SizedBox(height: 8),
              _HeartSyncStatus(controller: controller),
              const SizedBox(height: 8),
              _SleepSyncStatus(controller: controller),
              const SizedBox(height: 8),
              _ActivitySyncStatus(controller: controller),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: controller.healthAuthorized
                    ? const Key('health-sync-button')
                    : const Key('health-connect-button'),
                onPressed:
                    !controller.healthAvailable ||
                        controller.isHealthAuthorizing ||
                        controller.isSyncing
                    ? null
                    : controller.healthAuthorized
                    ? controller.syncHealth
                    : controller.connectHealth,
                icon: controller.isHealthAuthorizing || controller.isSyncing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        controller.healthAuthorized
                            ? Icons.sync_rounded
                            : Icons.health_and_safety_outlined,
                      ),
                label: Text(
                  controller.isSyncing
                      ? context.tr('Syncing health data…')
                      : controller.healthAuthorized
                      ? context.tr('Sync now')
                      : context.tr('Review permissions'),
                ),
              ),
            ),
            if (controller.healthAvailable &&
                controller.healthAuthorization !=
                    HealthAuthorizationState.notDetermined) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('health-settings-button'),
                  onPressed: controller.openHealthSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(context.tr('Manage in Settings')),
                ),
              ),
            ],
            if (controller.healthAuthorized) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  key: const Key('health-disconnect-button'),
                  onPressed: () => _disconnect(context, controller),
                  child: Text(context.tr('Stop using Apple Health in Tonyo')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _disconnect(
    BuildContext context,
    AppController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Stop using Apple Health?')),
        content: Text(
          context.tr(
            'Tonyo will stop using Health data. Existing imported and manual entries stay saved. You can separately revoke categories in Settings.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('Stop connection')),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.disconnectHealth();
  }
}

class _HealthPermissionRow extends StatelessWidget {
  const _HealthPermissionRow({required this.permission});

  final HealthPermissionInfo permission;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _icon(permission.iconName),
          color: TonyoPalette.of(context).primary,
          size: 21,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(permission.title),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                context.tr(permission.detail),
                style: TextStyle(
                  color: TonyoPalette.of(context).muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static IconData _icon(String name) => switch (name) {
    'sleep' => Icons.bedtime_rounded,
    'heart' => Icons.monitor_heart_rounded,
    'workout' => Icons.fitness_center_rounded,
    'water' => Icons.water_drop_rounded,
    _ => Icons.health_and_safety_outlined,
  };
}

class _HealthPermissionStatus extends StatelessWidget {
  const _HealthPermissionStatus({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final (message, color) = controller.healthError != null
        ? (controller.healthError!, TonyoPalette.of(context).warning)
        : switch (controller.healthAuthorization) {
            HealthAuthorizationState.unavailable => (
              'Apple Health is unavailable on this platform. Manual logging works normally.',
              TonyoPalette.of(context).muted,
            ),
            HealthAuthorizationState.notDetermined => (
              'No Apple Health permission request has been made.',
              TonyoPalette.of(context).warning,
            ),
            HealthAuthorizationState.authorized => (
              controller.healthAuthorized
                  ? 'Your permission choices are saved in Apple Health. Tonyo can now import readable heart, sleep, workout, step, and hydration data.'
                  : 'Your permission choices are saved in Apple Health. Reconnect Tonyo to import readable health data.',
              TonyoPalette.of(context).success,
            ),
            HealthAuthorizationState.denied => (
              'The permission request was canceled or did not complete. You can try again or keep logging manually.',
              TonyoPalette.of(context).warning,
            ),
            HealthAuthorizationState.revoked => (
              'Tonyo’s Health connection is off. Saved and manual entries remain available.',
              TonyoPalette.of(context).warning,
            ),
            HealthAuthorizationState.error => (
              controller.healthError ??
                  'Apple Health permission status could not be checked.',
              TonyoPalette.of(context).warning,
            ),
          };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(context.tr(message), style: const TextStyle(fontSize: 11)),
    );
  }
}

class _ContinuousSyncStatus extends StatelessWidget {
  const _ContinuousSyncStatus({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final failed =
        controller.healthSyncStatus == HealthSyncStatus.failed ||
        controller.healthSyncStatus == HealthSyncStatus.partialFailure;
    final color = failed
        ? TonyoPalette.of(context).warning
        : TonyoPalette.of(context).success;
    final status = switch (controller.healthSyncStatus) {
      HealthSyncStatus.syncing => 'Refresh in progress',
      HealthSyncStatus.updated => 'New Health data imported',
      HealthSyncStatus.upToDate => 'Health inputs are up to date',
      HealthSyncStatus.partialFailure => 'Some Health sources need attention',
      HealthSyncStatus.failed => 'Automatic refresh needs attention',
      HealthSyncStatus.disabled => 'Automatic refresh is off',
      HealthSyncStatus.idle => 'Automatic refresh is ready',
    };
    final delivery = controller.healthBackgroundRefreshEnabled
        ? 'Checks every minute while open, plus HealthKit change notifications'
        : 'Checks every minute while Tonyo is open';
    return Container(
      key: const Key('continuous-health-sync-status'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.autorenew_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(status), style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                    "{value0} · scores update only when model inputs change.",
                    args: {'value0': context.tr(delivery)},
                  ),
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartSyncStatus extends StatelessWidget {
  const _HeartSyncStatus({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.healthSyncError != null;
    final latest = controller.latestHealthKitHeartRate;
    final color = failed
        ? TonyoPalette.of(context).warning
        : TonyoPalette.of(context).primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            failed ? Icons.info_outline_rounded : Icons.monitor_heart_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(controller.healthSyncSummary),
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 6),
                Text(
                  latest == null
                      ? context.tr(
                          'No Heart Rate samples imported yet. Check Heart Rate access in Apple Health, then tap Sync now.',
                        )
                      : context.tr(
                          'Latest Heart Rate: {value} bpm · recorded {time}',
                          args: {
                            'value': latest.value.round(),
                            'time': _timestamp(latest.timestamp),
                          },
                        ),
                  key: const Key('latest-health-heart-rate'),
                  style: const TextStyle(fontSize: 11),
                ),
                HeartDataDetails(
                  readings: controller.signals,
                  now: controller.currentTime,
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                    'Recent Heart Rate refreshes automatically. Sync now also checks the last 30 days.',
                  ),
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
                    fontSize: 10,
                  ),
                ),
                if (controller.lastSync != null && !controller.isSyncing) ...[
                  const SizedBox(height: 3),
                  Text(
                    context.tr(
                      "Last checked {value0}",
                      args: {'value0': _timestamp(controller.lastSync!)},
                    ),
                    style: TextStyle(
                      color: TonyoPalette.of(context).muted,
                      fontSize: 10,
                    ),
                  ),
                ],
                if (controller.lastHealthRejectedCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    context.tr(
                      "{value0} invalid {value1} ignored.",
                      args: {
                        'value0': controller.lastHealthRejectedCount,
                        'value1': controller.lastHealthRejectedCount == 1
                            ? 'sample was'
                            : 'samples were',
                      },
                    ),
                    style: TextStyle(
                      color: TonyoPalette.of(context).muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _timestamp(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} at $hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _SleepSyncStatus extends StatelessWidget {
  const _SleepSyncStatus({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.sleepSyncError != null;
    final color = failed
        ? TonyoPalette.of(context).warning
        : TonyoPalette.of(context).success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            failed ? Icons.info_outline_rounded : Icons.bedtime_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(controller.sleepSyncSummary),
                  style: const TextStyle(fontSize: 11),
                ),
                if (controller.lastSleepRejectedCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    context.tr(
                      "{value0} invalid sleep {value1} ignored.",
                      args: {
                        'value0': controller.lastSleepRejectedCount,
                        'value1': controller.lastSleepRejectedCount == 1
                            ? 'sample was'
                            : 'samples were',
                      },
                    ),
                    style: TextStyle(
                      color: TonyoPalette.of(context).muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivitySyncStatus extends StatelessWidget {
  const _ActivitySyncStatus({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.activitySyncError != null;
    final color = failed
        ? TonyoPalette.of(context).warning
        : TonyoPalette.of(context).success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            failed ? Icons.info_outline_rounded : Icons.fitness_center_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(controller.activitySyncSummary),
                  style: const TextStyle(fontSize: 11),
                ),
                if (controller.lastActivityRejectedCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    context.tr(
                      "{value0} invalid activity {value1} ignored.",
                      args: {
                        'value0': controller.lastActivityRejectedCount,
                        'value1': controller.lastActivityRejectedCount == 1
                            ? 'sample was'
                            : 'samples were',
                      },
                    ),
                    style: TextStyle(
                      color: TonyoPalette.of(context).muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationStatus extends StatelessWidget {
  const _NotificationStatus({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.notificationError;
    final next = controller.nextScheduledNotification;
    final status = controller.isNotificationSyncing
        ? 'Updating reminder schedule…'
        : error ??
              (controller.notificationPlan.state ==
                          NotificationPlanState.ready &&
                      next == null
                  ? 'No upcoming reminders remain.'
                  : _statusText(controller.notificationPlan.state));
    final detail = next == null
        ? status
        : '${controller.scheduledNotificationCount} scheduled · next ${_clock(next.scheduledAt)}';
    final color = error == null
        ? TonyoPalette.of(context).success
        : TonyoPalette.of(context).warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            error == null ? Icons.schedule_rounded : Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(detail),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusText(NotificationPlanState state) => switch (state) {
    NotificationPlanState.ready => 'Eligible reminders are scheduled.',
    NotificationPlanState.disabled => 'Notifications are off.',
    NotificationPlanState.missingForecast =>
      'No forecast is available, so nothing is scheduled.',
    NotificationPlanState.staleForecast =>
      'The forecast is stale, so alerts are suppressed.',
    NotificationPlanState.lowConfidence =>
      'Data coverage is limited, so forecast alerts are suppressed.',
    NotificationPlanState.uncalibratedForecast =>
      'Forecast timing is uncalibrated. Only eligible schedule reminders can be sent.',
    NotificationPlanState.noFutureWindows =>
      'No eligible upcoming reminders are available today.',
  };

  static String _clock(DateTime value) => formatHour(value);
}

class _CloudSyncRecoveryCard extends StatefulWidget {
  const _CloudSyncRecoveryCard({
    required this.controller,
    required this.savingBackup,
    required this.onSaveBackup,
  });

  final AppController controller;
  final bool savingBackup;
  final VoidCallback? onSaveBackup;

  @override
  State<_CloudSyncRecoveryCard> createState() => _CloudSyncRecoveryCardState();
}

class _CloudSyncRecoveryCardState extends State<_CloudSyncRecoveryCard> {
  bool _busy = false;
  String? _error;

  Future<void> _reviewConflicts() async {
    if (_busy || widget.controller.isCloudSyncing) return;
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SyncConflictScreen(controller: widget.controller),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    if (_busy || widget.controller.isCloudSyncing) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.retryCloudSync();
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              widget.controller.cloudSyncError ??
              'Could not finish syncing. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCloud() async {
    if (_busy || widget.controller.isCloudSyncing) return;
    final sessionRevision = widget.controller.sessionRevision;
    // Guard the confirmation as well as the read against repeated taps.
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('cloud-sync-replace-dialog'),
          scrollable: true,
          title: Text(context.tr('Use cloud version?')),
          content: Text(
            context.tr(
              'This replaces unsynced profile, activity, sleep, and check-in edits '
              'on this device with the version saved in your cloud account. '
              'Save a device backup first if you want to keep a copy of these edits.',
            ),
          ),
          actions: [
            TextButton(
              key: const Key('cloud-sync-replace-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Keep my edits')),
            ),
            FilledButton(
              key: const Key('cloud-sync-replace-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Use cloud version')),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          widget.controller.sessionRevision != sessionRevision) {
        return;
      }
      setState(() => _error = null);
      await widget.controller.useCloudInputs();
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not load the cloud version. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflict = widget.controller.cloudSyncConflict;
    final quotaReached =
        widget.controller.cloudSyncFailureKind == CloudSyncFailureKind.quota;
    final busy = _busy || widget.controller.isCloudSyncing;
    final error =
        _error ??
        widget.controller.cloudSyncError ??
        widget.controller.outcomeError;
    return TonyoCard(
      key: const Key('cloud-sync-recovery-card'),
      color: TonyoPalette.of(context).surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              conflict
                  ? context.tr('Cloud sync needs review')
                  : context.tr('Saved on this device · sync pending'),
              style: TextStyle(
                color: TonyoPalette.of(context).warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (!quotaReached)
            Text(
              conflict
                  ? context.tr(
                      'Another device changed the same data. Your edits remain saved '
                      'on this device. Review each conflict and choose which version to keep.',
                    )
                  : context.tr(
                      'Your latest changes are saved on this device. Retry when you’re '
                      'connected to sync them to your account.',
                    ),
              style: TextStyle(
                color: TonyoPalette.of(context).muted,
                fontSize: 11,
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                context.tr(error),
                style: TextStyle(color: TonyoPalette.of(context).warning),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Save a JSON backup of the data on this device, including unsynced '
              'changes. No internet is needed.',
            ),
            style: TextStyle(
              color: TonyoPalette.of(context).muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('cloud-sync-save-backup'),
            onPressed: widget.onSaveBackup,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: Text(
              widget.savingBackup
                  ? context.tr('Saving backup…')
                  : context.tr('Save device backup'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('cloud-sync-retry'),
            onPressed: busy ? null : _retry,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: Text(
              busy ? context.tr('Please wait…') : context.tr('Retry sync'),
            ),
          ),
          if (conflict) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('cloud-sync-review-conflicts'),
              onPressed: busy ? null : _reviewConflicts,
              icon: const Icon(Icons.compare_arrows_rounded),
              label: Text(context.tr('Review conflicts')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('cloud-sync-use-cloud'),
              onPressed: busy ? null : _useCloud,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(context.tr('Use cloud version')),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => TonyoCard(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    child: Column(
      children: [
        Text(
          context.tr(value),
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          context.tr(label),
          textAlign: TextAlign.center,
          style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 9),
        ),
      ],
    ),
  );
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.status,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String status;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final statusLabel = Text(
      context.tr("● {value0}", args: {'value0': context.tr(status)}),
      style: TextStyle(
        color: status == 'On' || status == 'Managed'
            ? TonyoPalette.of(context).success
            : TonyoPalette.of(context).muted,
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    );
    return TonyoCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MetricIcon(icon: icon, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(title),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      context.tr(detail),
                      style: TextStyle(
                        color: TonyoPalette.of(context).muted,
                        fontSize: 10,
                      ),
                    ),
                    if (large) ...[const SizedBox(height: 5), statusLabel],
                  ],
                ),
              ),
              if (!large) ...[const SizedBox(width: 8), statusLabel],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
    leading: Icon(icon, color: TonyoPalette.of(context).muted),
    title: Text(
      context.tr(title),
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      context.tr(subtitle),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 10),
    ),
    trailing: Icon(
      Icons.chevron_right_rounded,
      color: TonyoPalette.of(context).muted,
    ),
    onTap: onTap,
  );
}
