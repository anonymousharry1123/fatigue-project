import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../app_controller.dart';
import '../health_service.dart';
import '../models.dart';
import '../notification_logic.dart';
import '../sleep_sync_logic.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'admin/admin_cohort_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final profile = controller.profile;
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
                backgroundColor: TonyoColors.primary.withValues(alpha: .22),
                child: Text(
                  profile.name.characters.first.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
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
                      '${profile.role} · ${profile.ageRange}',
                      style: const TextStyle(
                        color: TonyoColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    if (controller.accountEmail != null)
                      Text(
                        controller.accountEmail!,
                        style: const TextStyle(
                          color: TonyoColors.muted,
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
                        color: TonyoColors.mint.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        controller.isCloudAuthenticated
                            ? '● Private cloud sync active'
                            : '● Local demo profile',
                        style: const TextStyle(
                          color: TonyoColors.mint,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _editProfile(context, controller),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _ProfileStat(
                '${controller.score.energy}',
                'Est. energy',
                TonyoColors.mint,
              ),
              const SizedBox(width: 8),
              _ProfileStat(
                '${_latestSleep(controller)}h',
                'Avg sleep',
                TonyoColors.blue,
              ),
              const SizedBox(width: 8),
              _ProfileStat(
                '${(controller.score.confidence * 100).round()}%',
                'Confidence',
                TonyoColors.violet,
              ),
            ],
          ),
          const SectionHeader('Connected data sources'),
          _SourceCard(
            key: const Key('health-source-card'),
            icon: Icons.health_and_safety_rounded,
            color: TonyoColors.blue,
            title: 'Apple Health',
            detail: _healthSourceDetail(controller),
            status: _healthSourceStatus(controller),
            onTap: () => _healthPermissions(context),
          ),
          const SizedBox(height: 9),
          const _SourceCard(
            icon: Icons.smartphone_rounded,
            color: TonyoColors.violet,
            title: 'Screen Time',
            detail: 'Privacy-preserving · Version 0.28',
            status: 'Preview',
          ),
          const SizedBox(height: 9),
          _SourceCard(
            icon: Icons.storage_rounded,
            color: TonyoColors.mint,
            title: controller.isCloudAuthenticated
                ? 'Firebase Cloud Firestore'
                : 'Local app storage',
            detail: controller.isCloudAuthenticated
                ? controller.isCloudSyncing
                      ? 'Syncing private account data'
                      : controller.cloudSyncError == null
                      ? 'Offline cache enabled'
                      : 'Offline cache active · sync will retry'
                : controller.cloudEnabled
                ? 'Sign in to migrate local data'
                : 'Offline demo mode',
            status: controller.isCloudAuthenticated ? 'On' : 'Local',
          ),
          const SectionHeader('Settings'),
          if (controller.cloudEnabled)
            _SettingTile(
              icon: Icons.cloud_outlined,
              title: 'Cloud account',
              subtitle: controller.isCloudAuthenticated
                  ? 'Signed in as ${controller.accountEmail}'
                  : 'Sign in and migrate this device’s data',
              onTap: () => controller.isCloudAuthenticated
                  ? _signOut(context, controller)
                  : _signIn(context, controller),
            ),
          _SettingTile(
            icon: Icons.track_changes_rounded,
            title: 'Goals & schedule',
            subtitle: profile.goal,
            onTap: () => _editProfile(context, controller),
          ),
          _SettingTile(
            icon: Icons.notifications_outlined,
            title: 'Forecast alerts',
            subtitle: _notificationSubtitle(controller),
            onTap: () => _notifications(context),
          ),
          _SettingTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Model & data privacy',
            subtitle:
                '${controller.signals.length} signals · ${controller.isCloudAuthenticated ? 'private cloud + cache' : 'local cache'}',
            onTap: () => _privacy(context, controller),
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
          const SectionHeader('Developer'),
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
        ? 'On · no eligible forecast windows'
        : 'On · $count ${count == 1 ? 'alert' : 'alerts'} scheduled';
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
            : '${controller.healthKitHeartSignalCount} heart · ${controller.healthKitSleepNightCount} sleep nights · ${controller.healthKitWorkoutSignalCount + controller.healthKitHydrationSignalCount} activity signals',
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

  static void _healthPermissions(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TonyoColors.surface,
        builder: (_) => const _HealthPermissionSheet(),
      );

  static void _notifications(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: TonyoColors.surface,
        builder: (_) => const _NotificationSheet(),
      );

  static Future<void> _editProfile(
    BuildContext context,
    AppController controller,
  ) async {
    final name = TextEditingController(text: controller.profile.name);
    var role = controller.profile.role;
    var goal = controller.profile.goal;
    final updated = await showDialog<UserProfile>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: ['Student', 'Athlete', 'Student athlete']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => role = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: goal,
                  decoration: const InputDecoration(labelText: 'Goal'),
                  items:
                      [
                            'Improve focus',
                            'Improve recovery',
                            'Balance focus and training',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() => goal = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
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
                ),
              ),
              child: const Text('Save'),
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
          title: const Text('Version 0.5 preview'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  static Future<void> _signIn(
    BuildContext context,
    AppController controller,
  ) async {
    final email = TextEditingController(text: controller.accountEmail);
    final password = TextEditingController();
    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in to Tonyo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your existing local data is migrated only if this cloud account has no Tonyo data yet.',
              style: TextStyle(color: TonyoColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (email.text.trim(), password.text)),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    email.dispose();
    password.dispose();
    if (credentials == null) return;
    try {
      await controller.signIn(email: credentials.$1, password: credentials.$2);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign-in failed. Check your email and password.'),
          ),
        );
      }
    }
  }

  static Future<void> _signOut(
    BuildContext context,
    AppController controller,
  ) async {
    await controller.signOut();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Signed out. The offline cache remains on this device.',
          ),
        ),
      );
    }
  }

  static void _privacy(
    BuildContext context,
    AppController controller,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TonyoColors.surface,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Model & data privacy',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              controller.isCloudAuthenticated
                  ? 'Tonyo stores your profile, preferences, signals, and check-ins under your Firebase user ID. Firestore rules restrict access to that account. A local cache keeps the demo usable offline. Passwords are handled only by Firebase Authentication.'
                  : 'This build currently stores your profile, preferences, signals, and check-ins in the on-device offline cache. Passwords are never saved by Tonyo.',
              style: TextStyle(color: TonyoColors.muted),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy_rounded, color: TonyoColors.blue),
              title: const Text('Copy my data export'),
              onTap: () async {
                final export = await controller.exportAllData();
                await Clipboard.setData(ClipboardData(text: export));
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.restart_alt_rounded,
                color: TonyoColors.amber,
              ),
              title: const Text('Reset tracking data'),
              subtitle: const Text(
                'Clear check-ins, activity, sleep, and scores. Keep account.',
                style: TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Reset tracking data?'),
                    content: const Text(
                      'This clears your check-ins, signals (activity, sleep, reaction, etc.), and saved energy score snapshots so you can start a blank manual tracking period.\n\nYour account, profile, and login stay. This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Reset tracking'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                try {
                  await controller.clearTrackingData();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Tracking data cleared. You can start logging from blank.',
                        ),
                      ),
                    );
                  }
                } on Object {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Reset could not finish. Check your connection and retry.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: TonyoColors.coral,
              ),
              title: Text(
                controller.isCloudAuthenticated
                    ? 'Permanently delete account data'
                    : 'Delete local data',
              ),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Delete all Tonyo data?'),
                    content: Text(
                      controller.isCloudAuthenticated
                          ? 'This permanently deletes your Firestore data, Firebase account, and local cache. This cannot be undone.'
                          : 'This permanently deletes the Tonyo data cached on this device. This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Delete permanently'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                try {
                  await controller.deleteAccountData();
                  if (context.mounted) Navigator.pop(context);
                } on Object {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Deletion could not finish. Sign in again and retry.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _NotificationSheet extends StatelessWidget {
  const _NotificationSheet();

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
                    'Forecast alerts',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Opt in to private reminders based on fresh, higher-confidence forecast windows. Tonyo suppresses stale, uncertain, past, and dismissed guidance.',
              style: TextStyle(color: TonyoColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TonyoColors.blue.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.health_and_safety_outlined,
                    color: TonyoColors.blue,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Wellness guidance only. Notification text never presents a diagnosis.',
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
              title: const Text('Allow forecast alerts'),
              subtitle: Text(
                controller.notificationSchedulingSupported
                    ? 'Permission is requested only when you turn this on.'
                    : 'Scheduled alerts are not supported on this platform.',
                style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
              value: controller.notificationsEnabled,
              onChanged:
                  !controller.notificationSchedulingSupported ||
                      controller.isNotificationSyncing
                  ? null
                  : (value) async {
                      await controller.setNotifications(value);
                    },
            ),
            const Divider(),
            SwitchListTile(
              key: const Key('notification-crash-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Lower-energy heads-up'),
              subtitle: const Text(
                'A gentle reminder about 15 minutes before an eligible window.',
                style: TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
              value: controller.crashNotificationsEnabled,
              onChanged:
                  controller.notificationsEnabled &&
                      !controller.isNotificationSyncing
                  ? controller.setCrashNotifications
                  : null,
            ),
            SwitchListTile(
              key: const Key('notification-recovery-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Recovery-window reminder'),
              subtitle: const Text(
                'A check-in prompt when the forecast starts to recover.',
                style: TextStyle(color: TonyoColors.muted, fontSize: 11),
              ),
              value: controller.recoveryNotificationsEnabled,
              onChanged:
                  controller.notificationsEnabled &&
                      !controller.isNotificationSyncing
                  ? controller.setRecoveryNotifications
                  : null,
            ),
            const SizedBox(height: 8),
            _NotificationStatus(controller: controller),
          ],
        ),
      ),
    );
  }
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
                    'Apple Health permissions',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tonyo requests read access only. It never writes to Apple Health, and you choose each category in Apple’s permission sheet.',
              style: TextStyle(color: TonyoColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            for (final permission in healthPermissions)
              _HealthPermissionRow(permission: permission),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TonyoColors.violet.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    color: TonyoColors.violet,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'For privacy, Apple does not tell apps which read categories you approved, denied, or later revoked. Your choices remain manageable in Settings.',
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
                color: TonyoColors.mint.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.edit_note_rounded, color: TonyoColors.mint),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Manual sleep and activity logging stays available in every permission state. A manual exercise or hydration value corrects that day’s imported total; deleting it falls back to Apple Health. Existing manual entries are never removed.',
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
                      ? 'Syncing health data…'
                      : controller.healthAuthorized
                      ? 'Sync health data'
                      : 'Review permissions',
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
                  label: const Text('Manage in Settings'),
                ),
              ),
            ],
            if (controller.healthAuthorized) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  key: const Key('health-disconnect-button'),
                  onPressed: () => _disconnect(context, controller),
                  child: const Text('Stop using Apple Health in Tonyo'),
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
        title: const Text('Stop using Apple Health?'),
        content: const Text(
          'Tonyo will stop using Health data. Existing imported and manual entries stay saved. You can separately revoke categories in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stop connection'),
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
        Icon(_icon(permission.iconName), color: TonyoColors.blue, size: 21),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                permission.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                permission.detail,
                style: const TextStyle(color: TonyoColors.muted, fontSize: 11),
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
        ? (controller.healthError!, TonyoColors.amber)
        : switch (controller.healthAuthorization) {
            HealthAuthorizationState.unavailable => (
              'Apple Health is unavailable on this platform. Manual logging works normally.',
              TonyoColors.muted,
            ),
            HealthAuthorizationState.notDetermined => (
              'No Apple Health permission request has been made.',
              TonyoColors.amber,
            ),
            HealthAuthorizationState.authorized => (
              controller.healthAuthorized
                  ? 'Your permission choices are saved in Apple Health. Tonyo can now import readable heart, sleep, workout, and hydration data.'
                  : 'Your permission choices are saved in Apple Health. Reconnect Tonyo to import readable health data.',
              TonyoColors.mint,
            ),
            HealthAuthorizationState.denied => (
              'The permission request was canceled or did not complete. You can try again or keep logging manually.',
              TonyoColors.amber,
            ),
            HealthAuthorizationState.revoked => (
              'Tonyo’s Health connection is off. Saved and manual entries remain available.',
              TonyoColors.amber,
            ),
            HealthAuthorizationState.error => (
              controller.healthError ??
                  'Apple Health permission status could not be checked.',
              TonyoColors.amber,
            ),
          };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _HeartSyncStatus extends StatelessWidget {
  const _HeartSyncStatus({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.healthSyncError != null;
    final color = failed ? TonyoColors.amber : TonyoColors.blue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
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
                  controller.healthSyncSummary,
                  style: const TextStyle(fontSize: 11),
                ),
                if (controller.lastSync != null && !controller.isSyncing) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Last checked ${_timestamp(controller.lastSync!)} · 30-day window',
                    style: const TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
                if (controller.lastHealthRejectedCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${controller.lastHealthRejectedCount} invalid ${controller.lastHealthRejectedCount == 1 ? 'sample was' : 'samples were'} ignored.',
                    style: const TextStyle(
                      color: TonyoColors.muted,
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
    final color = failed ? TonyoColors.amber : TonyoColors.violet;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
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
                  controller.sleepSyncSummary,
                  style: const TextStyle(fontSize: 11),
                ),
                if (controller.lastSleepRejectedCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${controller.lastSleepRejectedCount} invalid sleep ${controller.lastSleepRejectedCount == 1 ? 'sample was' : 'samples were'} ignored.',
                    style: const TextStyle(
                      color: TonyoColors.muted,
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
    final color = failed ? TonyoColors.amber : TonyoColors.coral;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
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
                  controller.activitySyncSummary,
                  style: const TextStyle(fontSize: 11),
                ),
                if (controller.lastActivityRejectedCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${controller.lastActivityRejectedCount} invalid activity ${controller.lastActivityRejectedCount == 1 ? 'sample was' : 'samples were'} ignored.',
                    style: const TextStyle(
                      color: TonyoColors.muted,
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
    final status = error ?? _statusText(controller.notificationPlan.state);
    final detail = next == null
        ? status
        : '${controller.scheduledNotificationCount} scheduled · next ${_clock(next.scheduledAt)}';
    final color = error == null ? TonyoColors.mint : TonyoColors.amber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            error == null ? Icons.schedule_rounded : Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(detail, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  static String _statusText(NotificationPlanState state) => switch (state) {
    NotificationPlanState.ready => 'Eligible forecast alerts are scheduled.',
    NotificationPlanState.disabled => 'Forecast alerts are off.',
    NotificationPlanState.missingForecast =>
      'No forecast is available, so nothing is scheduled.',
    NotificationPlanState.staleForecast =>
      'The forecast is stale, so alerts are suppressed.',
    NotificationPlanState.lowConfidence =>
      'Forecast confidence is low, so alerts are suppressed.',
    NotificationPlanState.noFutureWindows =>
      'No eligible future windows are available today.',
  };

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: TonyoCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: TonyoColors.muted, fontSize: 9),
          ),
        ],
      ),
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
  Widget build(BuildContext context) => TonyoCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            MetricIcon(icon: icon, color: color),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: TonyoColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '● $status',
              style: TextStyle(
                color: status == 'On' || status == 'Managed'
                    ? TonyoColors.mint
                    : TonyoColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
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
    leading: Icon(icon, color: TonyoColors.muted),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, color: TonyoColors.muted),
    onTap: onTap,
  );
}
