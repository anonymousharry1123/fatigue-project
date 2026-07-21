import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../app_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

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
                      child: const Text(
                        '● Local profile active',
                        style: TextStyle(
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
                'Avg energy',
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
          const _SourceCard(
            icon: Icons.bedtime_rounded,
            color: TonyoColors.blue,
            title: 'Sleep tracking',
            detail: 'Health integration · Version 0.22',
            status: 'Preview',
          ),
          const SizedBox(height: 9),
          const _SourceCard(
            icon: Icons.monitor_heart_rounded,
            color: TonyoColors.coral,
            title: 'Wearable · Apple Watch',
            detail: 'Heart signals · Version 0.23',
            status: 'Preview',
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
          const _SourceCard(
            icon: Icons.storage_rounded,
            color: TonyoColors.mint,
            title: 'Local app storage',
            detail: 'Profile and demo state',
            status: 'On',
          ),
          const SectionHeader('Settings'),
          _SettingTile(
            icon: Icons.track_changes_rounded,
            title: 'Goals & schedule',
            subtitle: profile.goal,
            onTap: () => _editProfile(context, controller),
          ),
          _SettingTile(
            icon: Icons.notifications_outlined,
            title: 'Forecast alerts',
            subtitle: 'Preview only in Version 0.5.1',
            onTap: () =>
                _preview(context, 'Notifications arrive in Version 0.20.'),
          ),
          _SettingTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Model & data privacy',
            subtitle: '${controller.signals.length} local fixture signals',
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
        ],
      ),
    );
  }

  static String _latestSleep(AppController controller) {
    final matches = controller.signals.where(
      (item) => item.type == SignalType.sleep,
    );
    return matches.isEmpty ? '—' : matches.first.value.toStringAsFixed(1);
  }

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
            const Text(
              'Version 0.5.1 stores your account email, profile, onboarding status, fixtures, and check-ins locally. Passwords are never saved and no cloud upload is used.',
              style: TextStyle(color: TonyoColors.muted),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy_rounded, color: TonyoColors.blue),
              title: const Text('Copy local data export'),
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: controller.exportJson()),
                );
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: TonyoColors.coral,
              ),
              title: const Text('Delete local data'),
              onTap: () async {
                await controller.reset();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
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
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.status,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String status;
  @override
  Widget build(BuildContext context) => TonyoCard(
    padding: const EdgeInsets.all(13),
    child: Row(
      children: [
        MetricIcon(icon: icon, color: color),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(
                detail,
                style: const TextStyle(color: TonyoColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
        Text(
          '● $status',
          style: TextStyle(
            color: status == 'On' ? TonyoColors.mint : TonyoColors.muted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
