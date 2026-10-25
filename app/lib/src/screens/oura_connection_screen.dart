import 'package:flutter/material.dart';

import '../app.dart';
import '../app_controller.dart';
import '../l10n/app_localizations.dart';
import 'heart_metrics_screen.dart';

class OuraConnectionScreen extends StatelessWidget {
  const OuraConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Oura'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.favorite_border, size: 44),
          const SizedBox(height: 16),
          Text(
            context.tr('Oura heart metrics'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Connect Oura to import your nighttime HRV and resting heart rate from the last 30 days. You choose whether to allow access in Oura.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Apple Health can stay connected. Oura and Apple Health measurements are shown separately because their measurement methods differ.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'After connecting, Tonyo checks for updates when you open the app and every 15 minutes while it is open. Sync your ring in Oura first.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Imported readings are saved in Tonyo and included in your private account sync. Disconnecting stops future imports and keeps saved readings. Clear tracking history to remove them.',
            ),
          ),
          const SizedBox(height: 24),
          if (!controller.ouraAvailable)
            Text(
              context.tr('Oura connection is not available in this build yet.'),
            )
          else if (!controller.isCloudAuthenticated)
            Text(context.tr('Sign in to your Tonyo account to connect Oura.'))
          else if (!controller.canConnectOura)
            Text(
              context.tr('Review your privacy choices before connecting Oura.'),
            ),
          if (controller.ouraError case final error?) ...[
            Text(
              context.tr(error),
              key: const Key('oura-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          if (controller.ouraConnected) ...[
            Text(context.tr('Connected'), key: const Key('oura-connected')),
            if (controller.lastOuraSync case final at?)
              Text(
                context.tr(
                  'Last synced: {time}',
                  args: {
                    'time':
                        '${MaterialLocalizations.of(context).formatShortDate(at)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
                  },
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('oura-sync-button'),
              onPressed: controller.isOuraBusy || !controller.canConnectOura
                  ? null
                  : () => controller.syncOura(),
              icon: const Icon(Icons.sync),
              label: Text(
                context.tr(controller.isOuraBusy ? 'Syncing…' : 'Sync now'),
              ),
            ),
          ] else
            FilledButton.icon(
              key: const Key('oura-connect-button'),
              onPressed:
                  controller.isOuraBusy ||
                      !controller.canConnectOura ||
                      controller.ouraDisconnectPending
                  ? null
                  : controller.connectOura,
              icon: const Icon(Icons.link),
              label: Text(
                context.tr(
                  controller.isOuraBusy ? 'Connecting…' : 'Connect Oura',
                ),
              ),
            ),
          if (controller.ouraConnected || controller.ouraDisconnectPending)
            TextButton(
              key: const Key('oura-disconnect-button'),
              onPressed:
                  controller.isOuraBusy && controller.ouraDisconnectPending
                  ? null
                  : controller.disconnectOura,
              child: Text(
                context.tr(
                  controller.ouraDisconnectPending
                      ? 'Retry disconnect'
                      : 'Disconnect Oura',
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HeartMetricsScreen(),
              ),
            ),
            icon: const Icon(Icons.monitor_heart_outlined),
            label: Text(context.tr('Heart metrics')),
          ),
        ],
      ),
    );
  }
}
